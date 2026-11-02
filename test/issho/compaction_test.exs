defmodule Issho.CompactionTest do
  # An idle document whose engine compacts is saved without what only its
  # past needed, as a new epoch that continues the last: the same content,
  # revision and receipts, and a transaction made before it still applies.
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Issho.{Authority, Config, Documents, Store, Transaction}

  defmodule Policy do
    @moduledoc false
    @behaviour Issho.Policy
    @impl true
    def authorize(_identity, _room, _action), do: :ok
    @impl true
    def document(_identity, _id), do: {:error, :not_found}
  end

  defmodule Trash do
    @moduledoc false
    # The map engine with a heap of trash beside it, which only its past
    # needed: "throw" adds to it, and compact/2 empties it. Its content is
    # the map. It tells its :observer when it is asked to compact, and its
    # :compact option makes it compact wrong or raise.
    @behaviour Issho.Engine

    alias Issho.Engine.Map, as: MapEngine

    def name, do: "trash"
    def version, do: 1
    def init(_initial, _opts), do: {:ok, %{"map" => %{}, "trash" => []}}
    def validate(state, _opts), do: {:ok, state["map"]}

    def apply(state, ops, opts) do
      Enum.reduce_while(ops, {:ok, state}, fn
        %{"op" => "throw", "bytes" => bytes}, {:ok, acc} ->
          {:cont, {:ok, Map.update!(acc, "trash", &[String.duplicate("x", bytes) | &1])}}

        op, {:ok, acc} ->
          case MapEngine.apply(acc["map"], [op], opts) do
            {:ok, map} -> {:cont, {:ok, %{acc | "map" => map}}}
            error -> {:halt, error}
          end
      end)
    end

    def compact(state, opts) do
      send(Keyword.fetch!(opts, :observer), :compact)

      case opts[:compact] do
        :raise -> raise "compaction failed"
        :wrong -> {:ok, %{state | "trash" => [], "map" => Map.put(state["map"], "lost", true)}}
        nil -> {:ok, %{state | "trash" => []}}
      end
    end
  end

  @ttl 100

  setup do
    instance = Issho.Test.start!(policy: Policy, ttl: @ttl)
    %{instance: instance, store: Module.concat(instance, "Store")}
  end

  defp spec(opts) do
    {engine, opts} = Keyword.pop(opts, :engine, Trash)
    {store, opts} = Keyword.pop(opts, :store)
    spec = %{engine: engine, opts: [observer: self()] ++ opts}
    if store, do: Map.put(spec, :store, store), else: spec
  end

  defp open(instance, opts \\ []) do
    id = "notes:" <> Transaction.id()
    {id, join(instance, id, opts)}
  end

  defp join(instance, id, opts) do
    {:ok, pid} = Documents.open(instance, id, nil, spec: spec(opts))
    {:ok, _snapshot, _engine} = Authority.join(pid, self())
    pid
  end

  # The last session leaves; the document goes after the TTL.
  defp leave(pid) do
    ref = Process.monitor(pid)
    Authority.leave(pid, self())
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
  end

  defp rejoin(instance, id, pid, opts \\ []) do
    await_gone(instance, id, pid)
    join(instance, id, opts)
  end

  defp await_gone(instance, id, pid) do
    if Documents.whereis(instance, id) == pid do
      Process.sleep(1)
      await_gone(instance, id, pid)
    end
  end

  defp commit(pid, ops) do
    {:ok, %{"epoch" => epoch, "revision" => revision}} = Authority.snapshot(pid)
    t = %{"id" => Transaction.id(), "epoch" => epoch, "base_revision" => revision, "ops" => ops}
    {:ok, receipt} = Authority.commit(pid, t, "user:ada")
    {t, receipt}
  end

  defp throw_away(bytes), do: %{"op" => "throw", "bytes" => bytes}
  defp set(key, value), do: %{"op" => "set", "path" => [key], "value" => value}

  defp content(pid) do
    {:ok, %{"content" => content}} = Authority.content(pid)
    content
  end

  defp telemetry do
    ref = make_ref()
    test = self()

    :telemetry.attach(
      ref,
      [:issho, :document, :compact],
      fn _event, measurements, metadata, _ -> send(test, {:compact, measurements, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(ref) end)
  end

  test "an idle document is saved without its trash, as an epoch that continues the last",
       %{instance: instance, store: store} do
    telemetry()
    {id, pid} = open(instance)
    commit(pid, [set("title", "Plan")])
    commit(pid, [throw_away(100_000)])
    {:ok, before} = Store.Memory.load(store, id)

    leave(pid)

    {:ok, stored} = Store.Memory.load(store, id)
    assert stored["continues"] == before["epoch"]
    assert is_binary(stored["epoch"]) and stored["epoch"] != before["epoch"]
    assert stored["state"] == %{"map" => %{"title" => "Plan"}, "trash" => []}
    assert Store.Memory.content(store, id) == %{"title" => "Plan"}

    for key <- ["revision", "receipts", "horizon", "engine", "engine_version"],
        do: assert(stored[key] == before[key])

    assert_received {:compact, %{bytes_before: bytes_before, bytes_after: bytes_after},
                     %{instance: ^instance, document: ^id, result: :ok}}

    assert bytes_before - bytes_after >= 100_000

    pid = rejoin(instance, id, pid)

    assert {:ok, %{"epoch" => epoch, "continues" => continues, "revision" => 2}} =
             Authority.snapshot(pid)

    assert {epoch, continues} == {stored["epoch"], before["epoch"]}
  end

  test "a transaction made before the compaction applies after it, and goes out on the new epoch",
       %{instance: instance} do
    {id, pid} = open(instance)
    commit(pid, [throw_away(100_000)])
    {:ok, %{"epoch" => old, "revision" => seen}} = Authority.snapshot(pid)
    leave(pid)

    pid = rejoin(instance, id, pid)
    {:ok, %{"epoch" => new}} = Authority.snapshot(pid)
    assert new != old
    Phoenix.PubSub.subscribe(Config.get(instance).pubsub, Authority.topic(id))

    offline = %{
      "id" => Transaction.id(),
      "epoch" => old,
      "base_revision" => seen,
      "ops" => [set("title", "Offline")]
    }

    assert {:ok, %{"revision" => revision, "version" => version}} =
             Authority.commit(pid, offline, "user:ada")

    assert revision == seen + 1
    assert version == Issho.Version.new(new, revision)
    assert_receive {Issho, :transaction, ^id, %{"epoch" => ^new, "revision" => ^revision}}
    assert content(pid) == %{"title" => "Offline"}
  end

  test "a retry of a transaction accepted before the compaction gets its revision, and applies once",
       %{instance: instance} do
    {id, pid} = open(instance)
    {:ok, %{"epoch" => old}} = Authority.snapshot(pid)

    {t, %{"revision" => revision}} =
      commit(pid, [%{"op" => "increment", "path" => ["n"], "by" => 1}])

    commit(pid, [throw_away(100_000)])
    leave(pid)

    pid = rejoin(instance, id, pid)
    assert {:ok, %{"continues" => ^old}} = Authority.snapshot(pid)

    assert {:ok, %{"revision" => ^revision, "duplicate" => true, "version" => version}} =
             Authority.commit(pid, t, "user:ada")

    assert version == Issho.Version.new(old, revision)
    assert content(pid) == %{"n" => 1}
  end

  test "an if_revision transaction of the epoch before is stale, and counts the changes since",
       %{instance: instance} do
    {id, pid} = open(instance)
    commit(pid, [throw_away(100_000)])
    {:ok, %{"epoch" => old, "revision" => seen}} = Authority.snapshot(pid)
    leave(pid)

    pid = rejoin(instance, id, pid)
    assert {:ok, %{"continues" => ^old}} = Authority.snapshot(pid)
    commit(pid, [set("a", 1)])
    commit(pid, [set("b", 2)])

    conditional = %{
      "id" => Transaction.id(),
      "epoch" => old,
      "base_revision" => seen,
      "if_revision" => seen,
      "ops" => [set("title", "Late")]
    }

    assert {:error, {:stale, %{"count" => 2, "changes" => changes, "complete" => true}}} =
             Authority.commit(pid, conditional, "user:ada")

    assert Enum.map(changes, & &1["revision"]) == [seen + 1, seen + 2]
    assert content(pid) == %{"a" => 1, "b" => 2}
  end

  test "a document that a session has open does not compact", %{instance: instance, store: store} do
    {id, pid} = open(instance)
    commit(pid, [throw_away(100_000)])
    {:ok, %{"epoch" => epoch}} = Authority.snapshot(pid)

    Process.sleep(@ttl * 3)
    assert Process.alive?(pid)
    refute_received :compact
    assert {:ok, %{"epoch" => ^epoch}} = Store.Memory.load(store, id)

    leave(pid)
    assert_received :compact
    assert {:ok, %{"continues" => ^epoch}} = Store.Memory.load(store, id)
  end

  test "a compaction that saves less than 64 KB, or less than a quarter of the state, is not saved",
       %{instance: instance, store: store} do
    telemetry()

    for ops <- [
          [throw_away(10_000)],
          [set("text", String.duplicate("y", 400_000)), throw_away(100_000)]
        ] do
      {id, pid} = open(instance)
      commit(pid, ops)
      {:ok, before} = Store.Memory.load(store, id)

      leave(pid)

      assert_received :compact
      assert_received {:compact, %{}, %{document: ^id, result: :skipped}}
      assert Store.Memory.load(store, id) == {:ok, before}
    end
  end

  test "a compaction whose content differs is not saved, and is logged",
       %{instance: instance, store: store} do
    {id, pid} = open(instance, compact: :wrong)
    commit(pid, [throw_away(100_000)])
    {:ok, before} = Store.Memory.load(store, id)

    log = capture_log(fn -> leave(pid) end)

    assert log =~ id
    assert log =~ "content"
    assert Store.Memory.load(store, id) == {:ok, before}
  end

  test "an engine that raises compacting leaves the document as it was, and stops",
       %{instance: instance, store: store} do
    telemetry()
    {id, pid} = open(instance, compact: :raise)
    commit(pid, [throw_away(100_000)])
    {:ok, before} = Store.Memory.load(store, id)

    log = capture_log(fn -> leave(pid) end)

    assert log =~ "compaction failed"
    assert_received {:compact, %{}, %{document: ^id, result: :error}}
    assert Store.Memory.load(store, id) == {:ok, before}
  end

  test "a document never compacts with compact: false, without a store, or with an engine that cannot",
       %{instance: instance} do
    telemetry()
    pubsub = Config.get(instance).pubsub
    uncompacted = Issho.Test.start!(policy: Policy, pubsub: pubsub, ttl: @ttl, compact: false)
    {_id, pid} = open(uncompacted)
    commit(pid, [throw_away(100_000)])
    leave(pid)
    refute_received :compact

    {_id, pid} = open(instance, store: :none)
    commit(pid, [throw_away(100_000)])
    leave(pid)
    refute_received :compact

    {_id, pid} = open(instance, engine: Issho.Engine.Map)
    commit(pid, [set("text", String.duplicate("y", 100_000))])
    commit(pid, [%{"op" => "delete", "path" => ["text"]}])
    leave(pid)
    refute_received {:compact, _measurements, _metadata}
  end

  test ":compact is true or false" do
    assert_raise ArgumentError, ~r/:compact is true or false/, fn ->
      Issho.start_link(
        name: :compact_test,
        pubsub: :p,
        policy: Policy,
        secret_key_base: "k",
        compact: :sometimes
      )
    end
  end
end
