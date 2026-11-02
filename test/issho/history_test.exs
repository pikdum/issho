defmodule Issho.HistoryTest do
  # A document keeps the receipts of its latest transactions (the
  # instance's :history), not of every one: a transaction it can no longer
  # tell from one it applied is refused, :expired, and never applied twice.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Issho.{Authority, Documents, Store, Transaction}

  defmodule Policy do
    @moduledoc false
    @behaviour Issho.Policy
    @impl true
    def authorize(_identity, _room, _action), do: :ok
    @impl true
    def document(_identity, _id), do: {:ok, %{engine: Issho.Engine.Map, initial: %{}}}
  end

  setup do
    unique = System.unique_integer([:positive])
    store = start_supervised!({Store.Memory, name: :"Issho.HistoryTest.Store#{unique}"})
    pubsub = :"Issho.HistoryTest.PubSub#{unique}"
    start_supervised!({Phoenix.PubSub, name: pubsub})

    instances =
      Map.new([20, 27], fn keep ->
        {keep,
         Issho.Test.start!(
           policy: Policy,
           pubsub: pubsub,
           history: keep,
           store: {Store.Memory, store},
           ttl: 60_000
         )}
      end)

    %{instance: instances[20], instances: instances, store: store}
  end

  # Each transaction counts, under its own id, how many times it applied.
  defp tx(epoch, base) do
    id = Transaction.id()

    %{
      "id" => id,
      "epoch" => epoch,
      "base_revision" => base,
      "ops" => [%{"op" => "increment", "path" => ["n", id], "by" => 1}]
    }
  end

  defp tx(pid) do
    {:ok, %{"epoch" => epoch, "revision" => revision}} = Authority.snapshot(pid)
    tx(epoch, revision)
  end

  defp applied(pid, transaction) do
    {:ok, %{"state" => state}} = Authority.snapshot(pid)
    get_in(state, ["n", transaction["id"]])
  end

  defp advance(pid, n) do
    for _ <- 1..n, do: {:ok, _} = Authority.commit(pid, tx(pid), "user:ken")
    :ok
  end

  defp open(instance) do
    id = "doc:" <> Transaction.id()
    {:ok, pid} = Documents.open(instance, id)
    {id, pid}
  end

  defp reopen(instance, id, pid) do
    :ok = GenServer.stop(pid)
    await_gone(instance, id, pid)
    {:ok, again} = Documents.open(instance, id)
    again
  end

  defp await_gone(instance, id, pid) do
    if Documents.whereis(instance, id) == pid do
      Process.sleep(1)
      await_gone(instance, id, pid)
    end
  end

  test "a retry older than the latest :history transactions is refused, and applied once",
       %{instance: instance} do
    {_id, pid} = open(instance)
    t = tx(pid)
    assert {:ok, %{"revision" => 1}} = Authority.commit(pid, t, "user:ada")
    advance(pid, 5)
    assert {:ok, %{"revision" => 1, "duplicate" => true}} = Authority.commit(pid, t, "user:ada")

    advance(pid, 25)
    assert {:error, :expired} = Authority.commit(pid, t, "user:ada")
    assert applied(pid, t) == 1
  end

  test "a transaction sent late applies once when made on one of the latest :history revisions",
       %{instance: instance} do
    {_id, pid} = open(instance)
    advance(pid, 10)
    recent = tx(pid)
    {:ok, %{"epoch" => epoch}} = Authority.snapshot(pid)
    old = tx(epoch, 4)
    advance(pid, 20)

    assert {:ok, %{"revision" => 31}} = Authority.commit(pid, recent, "user:ada")
    assert {:ok, %{"duplicate" => true}} = Authority.commit(pid, recent, "user:ada")
    assert applied(pid, recent) == 1

    # Made before them, it cannot be told from one whose receipt is gone.
    assert {:error, :expired} = Authority.commit(pid, old, "user:ada")
    assert applied(pid, old) == nil
  end

  test "a stale transaction counts every change since, though their receipts are gone",
       %{instance: instance} do
    {_id, pid} = open(instance)
    {:ok, %{"epoch" => epoch}} = Authority.snapshot(pid)
    advance(pid, 30)
    conditional = Map.put(tx(epoch, 0), "if_revision", 0)

    assert {:error, {:stale, %{"count" => 30, "changes" => changes, "complete" => false}}} =
             Authority.commit(pid, conditional, "user:ada")

    assert Enum.map(changes, & &1["revision"]) == Enum.to_list(11..30)
  end

  test "the store keeps the latest receipts, and a reopened document still knows its horizon",
       %{instance: instance, store: store} do
    {id, pid} = open(instance)
    old = tx(pid)
    {:ok, _} = Authority.commit(pid, old, "user:ada")
    advance(pid, 99)
    recent = tx(pid)
    {:ok, %{"revision" => 101}} = Authority.commit(pid, recent, "user:ada")

    {:ok, stored} = Store.Memory.load(store, id)
    assert map_size(stored["receipts"]) in 20..25

    pid = reopen(instance, id, pid)
    assert {:error, :expired} = Authority.commit(pid, old, "user:ada")

    assert {:ok, %{"revision" => 101, "duplicate" => true}} =
             Authority.commit(pid, recent, "user:ada")

    assert applied(pid, old) == 1
  end

  test "a document opened with a larger :history still refuses what a smaller one forgot",
       %{instances: instances} do
    {id, pid} = open(instances[20])
    advance(pid, 75)
    t = tx(pid)
    {:ok, %{"revision" => 76}} = Authority.commit(pid, t, "user:ada")
    advance(pid, 25)
    :ok = GenServer.stop(pid)

    {:ok, pid} = Documents.open(instances[27], id)
    assert {:error, :expired} = Authority.commit(pid, t, "user:ada")
    assert applied(pid, t) == 1
  end

  test "a document saved with every receipt opens with the latest, and saves only those",
       %{instance: instance, store: store} do
    id = "doc:" <> Transaction.id()

    transactions =
      for revision <- 1..40, do: {revision, %{tx("e1", revision - 1) | "id" => "t#{revision}"}}

    receipts =
      Map.new(transactions, fn {revision, t} ->
        {t["id"],
         %{
           "digest" => Transaction.digest(t, "user:ada"),
           "revision" => revision,
           "author" => "user:ada"
         }}
      end)

    stored = %{
      "engine" => "map",
      "engine_version" => 2,
      "epoch" => "e1",
      "revision" => 40,
      "state" => %{},
      "initial" => %{},
      "journal" => [],
      "receipts" => receipts
    }

    :ok = Store.Memory.save(store, id, nil, stored, %{})
    {:ok, pid} = Documents.open(instance, id)
    found = Map.new(transactions)

    assert {:ok, %{"revision" => 35, "duplicate" => true}} =
             Authority.commit(pid, found[35], "user:ada")

    assert {:error, :expired} = Authority.commit(pid, found[5], "user:ada")

    {:ok, _} = Authority.commit(pid, tx(pid), "user:ada")
    {:ok, saved} = Store.Memory.load(store, id)
    assert map_size(saved["receipts"]) in 20..25
  end

  test ":history is a number of transactions, at least 20" do
    assert_raise ArgumentError, ~r/:history is a number of transactions, at least 20/, fn ->
      Issho.start_link(
        name: :history_test,
        pubsub: :p,
        policy: Policy,
        secret_key_base: "k",
        history: 5
      )
    end
  end

  # Of the transactions made, some are sent at once and some later (an
  # offline tab), mostly on a recent revision, some up to three times
  # :history behind, and any is sent again (a lost reply, a reconnect), now
  # and then across a restart of the document's authority.
  defp step do
    behind = frequency([{4, integer(0..2)}, {2, integer(0..30)}, {1, integer(0..80)}])

    frequency([
      {4, tuple({constant(:send), behind})},
      {2, tuple({constant(:hold), behind})},
      {4, tuple({constant(:retry), non_negative_integer()})},
      {1, constant(:restart)}
    ])
  end

  property "a transaction applies at most once, and is refused only when older than :history",
           %{instances: instances, store: store} do
    check all(
            keep <- member_of(Map.keys(instances)),
            steps <- resize(list_of(step(), min_length: 200, max_length: 400), 400),
            max_runs: 30
          ) do
      instance = instances[keep]
      {id, pid} = open(instance)
      {:ok, %{"epoch" => epoch}} = Authority.snapshot(pid)
      start = %{instance: instance, id: id, epoch: epoch, keep: keep, pid: pid, revision: 0}

      model = Enum.reduce(steps, Map.put(start, :made, []), &run/2)

      {:ok, %{"state" => state, "revision" => revision}} = Authority.snapshot(model.pid)
      assert revision == model.revision
      assert revision == Enum.count(model.made, & &1.applied)
      assert state |> Map.get("n", %{}) |> Map.values() |> Enum.all?(&(&1 == 1))

      {:ok, stored} = Store.Memory.load(store, id)
      assert map_size(stored["receipts"]) <= keep + div(keep, 4)
    end
  end

  defp run({:send, behind}, model) do
    made = %{tx: tx(model.epoch, max(model.revision - behind, 0)), applied: nil}
    {made, model} = deliver(made, model)
    %{model | made: model.made ++ [made]}
  end

  defp run({:hold, behind}, model) do
    made = %{tx: tx(model.epoch, max(model.revision - behind, 0)), applied: nil}
    %{model | made: model.made ++ [made]}
  end

  defp run({:retry, _n}, %{made: []} = model), do: model

  defp run({:retry, n}, model) do
    index = rem(n, length(model.made))
    {made, model} = deliver(Enum.at(model.made, index), model)
    %{model | made: List.replace_at(model.made, index, made)}
  end

  defp run(:restart, model), do: %{model | pid: reopen(model.instance, model.id, model.pid)}

  # What the authority may answer, given what the transaction is: its
  # receipt is kept while it is one of the latest :history, and a
  # transaction made on one of the latest :history revisions without a
  # receipt is new.
  defp deliver(%{tx: t, applied: applied} = made, model) do
    latest = model.revision - model.keep

    case {Authority.commit(model.pid, t, "user:ada"), applied} do
      {{:ok, %{"duplicate" => true, "revision" => revision}}, revision} ->
        {made, model}

      {{:ok, %{"revision" => revision} = receipt}, nil} ->
        refute Map.has_key?(receipt, "duplicate")
        assert revision == model.revision + 1
        {%{made | applied: revision}, %{model | revision: revision}}

      {{:error, :expired}, nil} ->
        assert t["base_revision"] < latest
        {made, model}

      {{:error, :expired}, revision} ->
        assert revision <= latest
        {made, model}

      {other, applied} ->
        flunk("#{inspect(other)} for a transaction applied at #{inspect(applied)}")
    end
  end
end
