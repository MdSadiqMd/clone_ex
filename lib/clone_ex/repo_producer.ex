defmodule CloneEx.RepoProducer do
  @moduledoc """
  A custom GenStage producer that emits a predefined list of repositories on demand.
  """
  use GenStage

  @doc """
  Initializes the producer.

  ## Options
    * `:repos` - list of repository maps to produce (required)
    * `:caller` - process to notify (required)
    * `:ack_ref` - initialized Acknowledger reference (required)
  """
  @impl true
  def init(opts) do
    repos = Keyword.fetch!(opts, :repos)
    # caller defaults to self() but is not actually used in handling demand,
    # it's just kept in state in the original design if needed
    caller = Keyword.get(opts, :caller, self())
    ack_ref = Keyword.fetch!(opts, :ack_ref)

    queue = :queue.from_list(repos)
    {:producer, %{queue: queue, caller: caller, ack_ref: ack_ref}}
  end

  @impl true
  def handle_demand(demand, state) when demand > 0 do
    {messages, remaining_queue} = dequeue(demand, state.queue, [])

    broadway_messages = build_broadway_messages(messages, state.ack_ref)

    {:noreply, broadway_messages, %{state | queue: remaining_queue}}
  end

  defp dequeue(0, queue, acc), do: {Enum.reverse(acc), queue}

  defp dequeue(n, queue, acc) do
    case :queue.out(queue) do
      {{:value, item}, rest} -> dequeue(n - 1, rest, [item | acc])
      {:empty, queue} -> {Enum.reverse(acc), queue}
    end
  end

  defp build_broadway_messages(items, ack_ref) do
    Enum.map(items, fn repo ->
      %Broadway.Message{
        data: repo,
        acknowledger: {CloneEx.Acknowledger, ack_ref, nil}
      }
    end)
  end
end
