defmodule Issho.Authority.Window do
  @moduledoc false
  # A document's latest revisions, rebuildable inside its authority for
  # `content_at/3`: a form that publishes exactly the revision a person
  # saw a moment ago. In memory only; the store keeps the state and the
  # receipts (`Issho.Authority.Ledger`).
  #
  # Two checkpoints of the engine's state, and the accepted events since
  # the older one, newest first. Every @every revisions the newer
  # checkpoint becomes the older, the current state the newer, and the
  # events before the older go. Once it has turned, the window reaches
  # @every to 2 * @every revisions back, a rebuild replays fewer than
  # @every events, and turning replays nothing: a checkpoint is a state the
  # authority already had, and shares all but what changed since with the
  # current one.
  #
  #   * older revision <= newer revision <= the current revision;
  #   * `events` are the accepted events after the older revision.

  @every 128

  @enforce_keys [:older, :newer]
  defstruct [:older, :newer, events: []]

  @type checkpoint :: {non_neg_integer(), term()}
  @type t :: %__MODULE__{older: checkpoint(), newer: checkpoint(), events: [map()]}

  # The window of a document as loaded: from its revision on, or from
  # where a history saved with it begins (an upgrade's, or an older
  # Issho's "initial" and "journal"), when that is shorter than @every,
  # so a rebuild still replays fewer than @every events. A longer one is
  # dropped, not replayed: replaying it is the cost this replaces.
  @spec load(map()) :: t()
  def load(%{"revision" => revision, "journal" => [_ | _] = journal} = document)
      when is_map_key(document, "initial") and length(journal) < @every do
    base = revision - length(journal)

    # An event's revision is its place in the journal, as when it was read.
    events =
      journal
      |> Enum.with_index(base + 1)
      |> Enum.map(fn {event, revision} -> Map.put(event, "revision", revision) end)

    %__MODULE__{
      older: {base, document["initial"]},
      newer: {base, document["initial"]},
      events: Enum.reverse(events)
    }
  end

  def load(document), do: new(document["revision"], document["state"])

  @spec new(non_neg_integer(), term()) :: t()
  def new(revision, state), do: %__MODULE__{older: {revision, state}, newer: {revision, state}}

  # The window after an event the store saved, with the state after it.
  @spec push(t(), map(), term()) :: t()
  def push(%__MODULE__{newer: {newer, _state}} = window, %{"revision" => revision} = event, state)
      when revision - newer >= @every do
    kept = Enum.take_while(window.events, &(&1["revision"] > newer))
    %__MODULE__{older: window.newer, newer: {revision, state}, events: [event | kept]}
  end

  def push(window, event, _state), do: %{window | events: [event | window.events]}

  # How to rebuild a revision no later than the current one: the latest
  # checkpoint at or before it, and the events after that checkpoint up
  # to it, oldest first. `:error` before the window.
  @spec plan(t(), non_neg_integer()) :: {:ok, term(), [map()]} | :error
  def plan(%__MODULE__{older: {older, _state}}, revision) when revision < older, do: :error

  def plan(%__MODULE__{newer: {newer, _state}} = window, revision) do
    {from, state} = if revision >= newer, do: window.newer, else: window.older

    events =
      window.events
      |> Enum.drop_while(&(&1["revision"] > revision))
      |> Enum.take_while(&(&1["revision"] > from))
      |> Enum.reverse()

    {:ok, state, events}
  end

  # The whole window as one replay, from the older checkpoint to the
  # current revision: `Issho.Test.replays?/2`.
  @spec all(t()) :: {term(), [map()]}
  def all(%__MODULE__{older: {_revision, state}, events: events}),
    do: {state, Enum.reverse(events)}
end
