defmodule Issho.Authority do
  @moduledoc """
  The one process that orders a document's changes, across every node of
  a cluster.

  It loads the document from the store (or builds it from the initial
  content your policy gives), and for each transaction:

    1. checks the envelope (`Issho.Transaction`) and its receipt: a retry
       of an accepted transaction gets its revision again, and changes
       nothing; and a transaction only on the revision it saw
       (`"if_revision"`) that someone changed since is refused as stale;
    2. applies the operations with the document's engine, all or none;
    3. validates the result (`c:Issho.Engine.validate/2`);
    4. saves the document and its content, comparing the stored version;
    5. only then answers the author and broadcasts the transaction.

  A store that answers `{:error, :conflict}` means another process saved
  meanwhile (a node that lost touch with the cluster): this one stops, and
  the next open loads the newer document.

  When no session has used the document for the instance's `:ttl` (30
  seconds), the authority stops; the document stays in the store.

  Start an authority with `Issho.Documents.open/3`, not directly.

  ## The stored document

  The authority saves the engine's state inside Issho's envelope:

      %{
        "engine" => "kotoba",
        "engine_version" => 3,
        "epoch" => "9a0b…",
        "revision" => 1649,
        "state" => …,           # the engine's state at "revision"
        "initial" => …,         # the engine's state at "base"
        "base" => 1521,         # the journal starts after this revision
        "journal" => [event],   # each transaction accepted since "base", oldest first
        "receipts" => %{id => %{"digest" => …, "revision" => …, "author" => …}},
        "horizon" => 649,       # each transaction accepted after it has a receipt
        "continues" => "77c1…"  # after a compaction, the epoch this one continues
      }

  The journal holds `"revision"` minus `"base"` events. `content_at/4`
  replays them from `"initial"`, each with its author, to rebuild any
  revision from `"base"` to `"revision"` of the current epoch, so a form
  can publish exactly the revision a person saw. Any other revision is
  `{:error, :unknown_revision}`. The current revision needs no replay,
  because the authority keeps its content.

  Three options of the instance bound what a document keeps. Each is off
  by default, and the document then keeps what Issho 0.5.0 keeps.

    * `:journal` is how many transactions the journal keeps. Once the
      journal is a quarter longer, the authority replays its oldest
      transactions onto `"initial"` before the save and moves `"base"` on,
      at most one more apply a commit. If that replay fails, the authority
      logs it, keeps the journal, and commits all the same. A document
      saved with a journal more than a quarter longer opens with its
      journal starting at its current revision, with no replay.
    * `:history` is how many receipts the document keeps. A retry of one
      of those transactions gets its revision again. A transaction with no
      receipt that was made on a revision before `"horizon"` may be one
      whose receipt is gone, so the authority refuses it as
      `{:error, :expired}` rather than apply it twice. An `"if_revision"`
      one is stale, with the exact count of changes since and those whose
      receipts are kept.
    * `:compact` saves an idle document without what only its past needed
      (a text's deleted characters), when its engine compacts
      (`c:Issho.Engine.compact/2`). Before the authority stops, it saves
      the compacted state as a new epoch whose `"continues"` names the
      last, with the same content, revision, receipts and horizon, and a
      journal that starts over from the compacted state. It does so only
      when that saves at least a quarter of the state and 64 KB, and only
      when the compacted state gives the same content. A transaction made
      on the epoch the document continues still applies, unless it is an
      `"if_revision"` one, which is stale. A transaction made on an epoch
      before that is refused as `:epoch_mismatch`, unless the document has
      its receipt: a retry gets its receipt from any epoch. Telemetry
      `[:issho, :document, :compact]` reports each attempt.

  A document saved without a journal opens with one that starts at its
  current revision.

  ## Issho 0.5.0 reads what this saves

  Each key Issho 0.5.0 stores keeps its meaning, and `"horizon"` and
  `"continues"` are new. 0.5.0 loads a document this version saves,
  commits to it, and rebuilds the revisions its journal holds, so a deploy
  can roll back. Two gaps remain. 0.5.0 ignores `"horizon"`, so after a
  rollback, a retry of a transaction whose receipt `:history` dropped is
  applied a second time. 0.5.0 also ignores `"continues"`, so it refuses a
  transaction made on the epoch a compacted document continues, as it
  refuses any other epoch's.
  """

  use GenServer, restart: :temporary

  alias Issho.Authority.{Journal, Ledger}
  alias Issho.{Config, Engine, Transaction}

  require Logger

  @read_timeout 5_000

  # A compaction is worth a new epoch when it saves at least this share
  # of the state, and at least this many bytes.
  @compact_share 4
  @compact_bytes 65_536

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @doc """
  Adds a session (a channel, an agent) that uses the document; the
  authority stays while one does. Returns the document as a browser
  receives it, and the document's engine.
  """
  @spec join(GenServer.server(), pid()) :: {:ok, map(), module()}
  def join(server, pid), do: GenServer.call(server, {:join, pid})

  @doc "Takes back a session that no longer uses the document, as if its process had ended."
  @spec leave(GenServer.server(), pid()) :: :ok
  def leave(server, pid), do: GenServer.cast(server, {:leave, pid})

  @doc """
  The document as a browser receives it: epoch, revision and the engine's
  snapshot. `{:error, :timeout}` or `{:error, :unavailable}` when the
  authority does not answer, rather than an exit.
  """
  @spec snapshot(GenServer.server()) :: {:ok, map()} | {:error, :timeout | :unavailable}
  def snapshot(server), do: read(server, :snapshot)

  @doc """
  Commits a transaction of an author: its identity (`Issho.Identity`), or
  only its key. The key is what the journal and the receipts keep; the
  identity, when given, is what the document's hook gets as `:by` (who
  made the change: a person, an agent and whom it acts for, a service).
  Gives `{:ok, %{"id" => id, "revision" => revision, "version" => token}}`
  (`Issho.Version`), with `"duplicate" => true` for a retry, or
  `{:error, reason}` (`{:error, {:stale, details}}` for a change only on
  a revision someone changed since: `Issho.Transaction`).
  """
  @spec commit(GenServer.server(), Transaction.t(), String.t() | Issho.Identity.t()) ::
          {:ok, map()} | {:error, term()}
  def commit(server, transaction, %Issho.Identity{} = by),
    do: GenServer.call(server, {:commit, transaction, by}, 15_000)

  def commit(server, transaction, author) when is_binary(author),
    do: commit(server, transaction, Issho.Identity.service(author))

  @doc "Which of these transaction ids the author already has accepted, after a reconnect."
  @spec accepted(GenServer.server(), [String.t()], String.t()) :: [String.t()]
  def accepted(server, ids, author), do: GenServer.call(server, {:accepted, ids, author})

  @doc """
  The content of the current revision, with its epoch and revision.
  `{:error, :timeout}` or `{:error, :unavailable}` when the authority does
  not answer, rather than an exit.
  """
  @spec content(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def content(server), do: read(server, :content)

  @doc """
  The content of an accepted revision of the epoch. `{:error, :timeout}`
  when the authority does not answer within the `:timeout` option, in
  milliseconds (5,000), and `{:error, :unavailable}` when it is gone,
  rather than an exit.
  """
  @spec content_at(GenServer.server(), String.t(), non_neg_integer(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def content_at(server, epoch, revision, opts \\ []),
    do: read(server, {:content_at, epoch, revision}, Keyword.get(opts, :timeout, @read_timeout))

  @doc false
  # Issho.Test.replays?/2: content_at/3 answers the current revision without a replay.
  @spec replayed(GenServer.server(), String.t(), non_neg_integer()) ::
          {:ok, term()} | {:error, term()}
  def replayed(server, epoch, revision), do: read(server, {:replayed, epoch, revision})

  # commit/3 and join/2 exit instead: that ends the channel, and the
  # browser's rejoin resends its pending transactions, which receipts keep
  # from applying twice. A read has no such retry, and its caller (a
  # LiveView publishing what a person saw) outlives a slow authority.
  defp read(server, request, timeout \\ @read_timeout) do
    GenServer.call(server, request, timeout)
  catch
    :exit, {:timeout, _call} -> {:error, :timeout}
    :exit, _reason -> {:error, :unavailable}
  end

  @doc false
  @spec topic(String.t()) :: String.t()
  def topic(document_id), do: "issho:document:" <> document_id

  # Server

  @impl true
  def init(opts) do
    config = Config.get(Keyword.fetch!(opts, :instance))
    id = Keyword.fetch!(opts, :document_id)
    spec = Keyword.fetch!(opts, :spec)
    engine = Map.fetch!(spec, :engine)
    engine_opts = Map.get(spec, :opts, [])
    {store, context} = store(Map.get(spec, :store), config.store)

    with {:ok, loaded} <- store.load(context, id),
         {stored, spec} = initial(loaded, spec),
         {:ok, document} <- document(stored, engine, spec, engine_opts),
         document = document |> Ledger.load(config.history) |> Journal.load(config.journal),
         {:ok, content} <- Engine.validate(engine, document["state"], engine_opts),
         :ok <- first_save(stored, store, context, id, document, content) do
      {:ok,
       %{
         config: config,
         id: id,
         engine: engine,
         opts: engine_opts,
         store: store,
         context: context,
         hook: Map.get(spec, :on_transaction),
         events: Map.get(spec, :events),
         document: document,
         content: content,
         members: %{},
         timer: Process.send_after(self(), :expire, config.ttl)
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  # A store that has the content but no document yet (your app's own
  # table, before anyone opened it together) gives the initial content.
  defp initial({:initial, content}, spec), do: {nil, Map.put(spec, :initial, content)}
  defp initial(stored, spec), do: {stored, spec}

  defp document(nil, engine, spec, opts) do
    with {:ok, state} <- engine.init(Map.get(spec, :initial), opts) do
      {:ok,
       %{
         "engine" => engine.name(),
         "engine_version" => engine.version(),
         "epoch" => Transaction.id(),
         "revision" => 0,
         "state" => state,
         "initial" => state,
         "journal" => [],
         "receipts" => %{}
       }}
    end
  end

  defp document(%{"engine" => name, "engine_version" => version} = stored, engine, _spec, _opts)
       when is_binary(name) do
    cond do
      name == engine.name() and version == engine.version() -> {:ok, stored}
      Engine.upgrades?(engine) -> upgrade(engine, stored)
      true -> {:error, {:engine_mismatch, name, version}}
    end
  end

  defp document(stored, engine, _spec, _opts) do
    if Engine.upgrades?(engine),
      do: upgrade(engine, stored),
      else: {:error, :unsupported_document}
  end

  # A stored document of another engine version, or from before Issho (a
  # library's own format): the engine's upgrade/1 gives its state, epoch
  # and revision, and its journal and receipts if it kept them.
  defp upgrade(engine, stored) do
    case engine.upgrade(stored) do
      {:ok, %{"state" => state, "epoch" => epoch, "revision" => revision} = upgraded}
      when is_binary(epoch) and is_integer(revision) ->
        {initial, journal} = history(upgraded, state)

        {:ok,
         %{
           "engine" => engine.name(),
           "engine_version" => engine.version(),
           "epoch" => epoch,
           "revision" => revision,
           "state" => state,
           "initial" => initial,
           "base" => revision - length(journal),
           "journal" => journal,
           "receipts" => Map.get(upgraded, "receipts", %{})
         }}

      {:error, _reason} = error ->
        error

      other ->
        raise ArgumentError, "#{inspect(engine)}.upgrade/1 returned #{inspect(other)}"
    end
  end

  # The journal an upgraded document kept, from the state it began with;
  # without one, its journal begins at the revision it has.
  defp history(%{"initial" => initial, "journal" => journal}, _state) when is_list(journal),
    do: {initial, journal}

  defp history(_upgraded, state), do: {state, []}

  defp store(:none, _default), do: {Issho.Store.None, nil}
  defp store({module, _context} = store, _default) when is_atom(module), do: store
  defp store(nil, {module, _context} = store) when is_atom(module), do: store

  defp store(nil, nil),
    do:
      raise(ArgumentError, "Issho needs a :store for documents, or `store: :none` in their spec")

  defp first_save(nil, store, context, id, document, content),
    do: store.save(context, id, nil, document, content)

  defp first_save(_stored, _store, _context, _id, _document, _content), do: :ok

  @impl true
  def handle_call({:join, pid}, _from, state) do
    state =
      if Map.has_key?(state.members, pid),
        do: state,
        else: %{state | members: Map.put(state.members, pid, Process.monitor(pid))}

    {:reply, {:ok, snapshot_of(state), state.engine}, cancel_timer(state)}
  end

  def handle_call(:snapshot, _from, state), do: {:reply, {:ok, snapshot_of(state)}, state}

  def handle_call(:content, _from, state) do
    %{"epoch" => epoch, "revision" => revision} = state.document

    {:reply, {:ok, %{"epoch" => epoch, "revision" => revision, "content" => state.content}},
     state}
  end

  def handle_call({:content_at, epoch, revision}, _from, state) do
    {:reply, content_at_revision(state, epoch, revision), state}
  end

  def handle_call({:replayed, epoch, revision}, _from, state) do
    {:reply, replayed_content(state, epoch, revision), state}
  end

  def handle_call({:accepted, ids, author}, _from, state),
    do: {:reply, Ledger.accepted(state.document, ids, author), state}

  def handle_call({:commit, transaction, %Issho.Identity{} = by}, _from, state) do
    started = System.monotonic_time()
    author = by.key
    result = commit_transaction(state, transaction, by)

    :telemetry.execute(
      [:issho, :transaction, :commit],
      %{duration: System.monotonic_time() - started},
      %{instance: state.config.name, document: state.id, author: author, result: elem(result, 0)}
    )

    case result do
      {:ok, reply, state} -> {:reply, {:ok, reply}, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
      {:stop, reason, state} -> {:stop, :normal, {:error, reason}, state}
    end
  end

  defp commit_transaction(state, transaction, by) do
    document = state.document
    author = by.key

    with :ok <- check(document, transaction, author),
         digest = Transaction.digest(transaction, author),
         :new <- Ledger.check(document, transaction, digest),
         :ok <- unchanged(document, transaction),
         {:ok, engine_state} <-
           state.engine.apply(document["state"], transaction["ops"], [
             {:author, author} | state.opts
           ]),
         {:ok, content} <- Engine.validate(state.engine, engine_state, state.opts),
         revision = document["revision"] + 1,
         :ok <- hook(state, transaction, by, engine_state, revision) do
      # Of the document's epoch, whichever its author made it on (the one
      # this continues): every browser applies it.
      event =
        transaction
        |> Map.take(["id", "base_revision", "ops"])
        |> Map.merge(%{"epoch" => document["epoch"], "revision" => revision, "author" => author})

      next =
        document
        |> Map.merge(%{"state" => engine_state, "revision" => revision})
        |> Journal.append(event)
        |> fold(state)
        |> Ledger.record(
          transaction["id"],
          %{"digest" => digest, "revision" => revision, "author" => author},
          state.config.history
        )

      persist(state, next, content, event, by)
    else
      # Its version is of the epoch it was made on, which may be one this
      # document continues.
      {:duplicate, revision} ->
        {:ok,
         %{
           "id" => transaction["id"],
           "revision" => revision,
           "version" => Issho.Version.new(transaction["epoch"], revision),
           "duplicate" => true
         }, state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  # Past the instance's :journal, the oldest events fold into "initial",
  # before the save, so the stored document stays bounded. A fold that
  # fails (an engine that does not apply a transaction again as it did)
  # leaves the journal as it was: the commit goes on.
  defp fold(document, state) do
    case Journal.fold(document, state.config.journal, &replay(state, &1, &2)) do
      {:ok, folded} ->
        folded

      {:error, reason} ->
        Logger.error("Issho: #{state.id} kept its journal unfolded: #{inspect(reason)}")
        document
    end
  end

  # The document's transaction hook, once per accepted transaction, before
  # it is saved: the app can save it in its own tables, or refuse it.
  defp hook(%{hook: nil}, _transaction, _by, _after, _revision), do: :ok

  defp hook(state, transaction, by, after_state, revision) do
    context = %{
      instance: state.config.name,
      document: state.id,
      author: by.key,
      by: by,
      revision: revision,
      before: state.document["state"],
      after: after_state
    }

    case state.hook.(transaction["ops"], context) do
      :ok -> :ok
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
      other -> raise ArgumentError, "an :on_transaction hook returned #{inspect(other)}"
    end
  rescue
    error ->
      Logger.error(
        "Issho: the :on_transaction hook of #{state.id} raised: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      {:error, :hook_failed}
  end

  # The document's own events of a transaction, once it is saved: what its
  # spec's `:events` says happened (`{name, data}`), in the room.
  defp emit(%{events: nil}, _event, _by, _after), do: :ok

  defp emit(state, event, by, after_state) do
    context = %{
      document: state.id,
      author: by.key,
      by: by,
      revision: event["revision"],
      before: state.document["state"],
      after: after_state
    }

    for {name, data} <- state.events.(event["ops"], context) do
      event = %Issho.Event{
        name: name,
        room: Issho.Policy.room(state.id),
        document: state.id,
        by: by,
        data: data,
        at: DateTime.utc_now()
      }

      Issho.Events.broadcast(state.config.pubsub, event)
      Issho.Inbox.deliver(state.config, event)
    end

    :ok
  rescue
    error ->
      Logger.error(
        "Issho: the :events of #{state.id} raised: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )
  end

  # The envelope's to refuse, but for a transaction of another epoch.
  defp check(document, transaction, author) do
    case Transaction.check(transaction, epoch(document, transaction), document["revision"]) do
      {:error, :epoch_mismatch} -> other_epoch(document, transaction, author)
      result -> result
    end
  end

  # A retry of a transaction the document applied, made on any epoch, gets
  # its receipt; a conditional one is stale, as one from an older revision
  # is; anything else is refused.
  defp other_epoch(document, transaction, author) do
    case Ledger.check(document, transaction, Transaction.digest(transaction, author)) do
      {:duplicate, _revision} = duplicate ->
        duplicate

      _other ->
        if Transaction.conditional?(transaction),
          do: stale(document, transaction),
          else: {:error, :epoch_mismatch}
    end
  end

  # The epoch a transaction is checked on: the document's, or the one it
  # continues for an unconditional transaction made before a compaction.
  defp epoch(%{"continues" => continued} = document, %{"epoch" => continued} = transaction) do
    if Transaction.conditional?(transaction), do: document["epoch"], else: continued
  end

  defp epoch(document, _transaction), do: document["epoch"]

  # Only on the revision it saw: still the document's.
  defp unchanged(%{"revision" => revision}, %{"if_revision" => revision}), do: :ok

  defp unchanged(document, transaction) do
    if Transaction.conditional?(transaction), do: stale(document, transaction), else: :ok
  end

  @changes 20

  # The document's version now, and what changed since the author saw it:
  # each change's revision and author (never its operations), the latest
  # @changes whose receipts it keeps. Revisions are dense, and go on across
  # a compaction, so the count is exact; nil for another epoch.
  defp stale(document, %{"epoch" => epoch, "if_revision" => seen}) do
    line? = epoch == document["epoch"] or (is_binary(epoch) and epoch == document["continues"])
    count = if line? and seen <= document["revision"], do: document["revision"] - seen
    changes = if count, do: Ledger.since(document, seen, @changes), else: []

    {:error,
     {:stale,
      %{
        "version" => Issho.Version.of(document),
        "epoch" => document["epoch"],
        "revision" => document["revision"],
        "count" => count,
        "changes" => changes,
        "complete" => count == length(changes)
      }}}
  end

  defp persist(state, next, content, event, by) do
    expected = {state.document["epoch"], state.document["revision"]}

    result =
      if :erlang.external_size(next) <= state.config.max_document_bytes,
        do: state.store.save(state.context, state.id, expected, next, content),
        else: {:error, :document_too_large}

    case result do
      :ok ->
        Phoenix.PubSub.broadcast(
          state.config.pubsub,
          topic(state.id),
          {Issho, :transaction, state.id, event}
        )

        Issho.Events.broadcast(state.config.pubsub, %Issho.Event{
          name: "document.changed",
          room: Issho.Policy.room(state.id),
          document: state.id,
          by: by,
          data: %{revision: event["revision"]},
          at: DateTime.utc_now()
        })

        emit(state, event, by, next["state"])

        {:ok,
         %{
           "id" => event["id"],
           "revision" => event["revision"],
           "version" => Issho.Version.new(next["epoch"], event["revision"])
         }, %{state | document: next, content: content}}

      {:error, :conflict} ->
        Logger.warning("Issho: a newer #{state.id} was saved elsewhere; this authority stops")
        {:stop, :stale_authority, state}

      {:error, :document_too_large} ->
        {:error, :document_too_large, state}

      {:error, reason} ->
        {:error, {:storage, reason}, state}
    end
  end

  defp content_at_revision(
         %{document: %{"epoch" => epoch, "revision" => revision}} = state,
         epoch,
         revision
       ),
       do: {:ok, state.content}

  defp content_at_revision(state, epoch, revision), do: replayed_content(state, epoch, revision)

  defp replayed_content(state, epoch, revision) do
    with {:ok, initial, events} <- Journal.rebuild(state.document, epoch, revision),
         {:ok, engine_state} <- replay(state, initial, events),
         do: Engine.validate(state.engine, engine_state, state.opts)
  end

  # Each transaction as it was accepted, with its author: an engine may
  # limit the operations of one. An engine that raises gives an error,
  # and the document goes on.
  defp replay(state, engine_state, events) do
    Enum.reduce_while(events, {:ok, engine_state}, fn event, {:ok, acc} ->
      case state.engine.apply(acc, event["ops"], [{:author, event["author"]} | state.opts]) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  rescue
    error ->
      Logger.error(
        "Issho: replaying the journal of #{state.id} raised: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      {:error, :replay_failed}
  end

  defp snapshot_of(state) do
    state.document
    |> Map.take(["engine", "epoch", "continues", "revision"])
    |> Map.merge(%{
      "id" => state.id,
      "state" => Engine.snapshot(state.engine, state.document["state"])
    })
  end

  @impl true
  def handle_cast({:leave, pid}, state) do
    case Map.pop(state.members, pid) do
      {nil, _members} ->
        {:noreply, state}

      {ref, members} ->
        Process.demonitor(ref, [:flush])
        {:noreply, member_gone(%{state | members: members})}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state),
    do: {:noreply, member_gone(%{state | members: Map.delete(state.members, pid)})}

  def handle_info(:expire, %{members: members} = state) when map_size(members) == 0 do
    if compacts?(state), do: compact(state)
    {:stop, :normal, state}
  end

  def handle_info(:expire, state), do: {:noreply, state}

  defp compacts?(state) do
    state.config.compact and state.store != Issho.Store.None and Engine.compacts?(state.engine)
  end

  # The idle document, saved as a new epoch that continues this one,
  # without what only its past needed. No session has it open, so no page
  # holds pending work on this epoch but one that was away, whose
  # transactions still apply. At most once an idle period: the authority
  # stops right after.
  defp compact(state) do
    started = System.monotonic_time()
    {result, sizes} = compaction(state)

    :telemetry.execute(
      [:issho, :document, :compact],
      Map.put(sizes, :duration, System.monotonic_time() - started),
      %{instance: state.config.name, document: state.id, result: result}
    )
  end

  defp compaction(%{document: document} = state) do
    case state.engine.compact(document["state"], state.opts) do
      {:ok, compacted} ->
        sizes = %{
          bytes_before: :erlang.external_size(document["state"]),
          bytes_after: :erlang.external_size(compacted)
        }

        {save_compacted(state, compacted, sizes), sizes}

      {:error, reason} ->
        Logger.warning("Issho: #{state.id} did not compact: #{inspect(reason)}")
        {:error, %{}}
    end
  rescue
    error ->
      Logger.error(
        "Issho: compacting #{state.id} raised: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      {:error, %{}}
  end

  # A store that answers :conflict has a newer document (saved from
  # another node), or no longer takes this one: not an error.
  defp save_compacted(%{document: document} = state, compacted, sizes) do
    kept = state.content

    next =
      document
      |> Map.merge(%{
        "epoch" => Transaction.id(),
        "continues" => document["epoch"],
        "state" => compacted
      })
      |> Journal.restart()

    expected = {document["epoch"], document["revision"]}

    with :ok <- worth(sizes),
         {:ok, ^kept} <- Engine.validate(state.engine, compacted, state.opts),
         :ok <- state.store.save(state.context, state.id, expected, next, kept) do
      :ok
    else
      :too_little ->
        :skipped

      {:error, :conflict} ->
        :skipped

      {:ok, _content} ->
        Logger.error("Issho: #{state.id} compacted to other content; it is kept as it was")
        :error

      {:error, reason} ->
        Logger.error("Issho: #{state.id} was not saved compacted: #{inspect(reason)}")
        :error
    end
  end

  defp worth(%{bytes_before: before, bytes_after: compacted}) do
    if before - compacted >= max(div(before, @compact_share), @compact_bytes),
      do: :ok,
      else: :too_little
  end

  # The last session gone: the document goes after the TTL, unless one comes.
  defp member_gone(%{members: members} = state) when map_size(members) == 0,
    do: %{state | timer: Process.send_after(self(), :expire, state.config.ttl)}

  defp member_gone(state), do: state

  defp cancel_timer(%{timer: nil} = state), do: state

  defp cancel_timer(state) do
    Process.cancel_timer(state.timer)
    %{state | timer: nil}
  end
end
