defmodule CloneEx.Acknowledger do
  @moduledoc """
  A custom Broadway acknowledger using `:atomics` for lock-free counter updates.

  Traditional Agent-based acknowledgers serialize all ack calls through a single
  GenServer mailbox. Under high concurrency this becomes a bottleneck and introduces
  race conditions with `Agent.cast` (fire-and-forget).

  This implementation uses `:atomics` (lock-free atomic integers backed by the
  BEAM's native atomics) for the success/fail counters, and a compare-and-swap
  loop to guarantee the completion message is sent **exactly once**.

  ## Memory layout (atomics)
    - Index 1: successful count
    - Index 2: failed count
    - Index 3: total count
    - Index 4: completion flag (0 = pending, 1 = sent)
  """
  @behaviour Broadway.Acknowledger

  require Logger

  @idx_successful 1
  @idx_failed 2
  @idx_total 3
  @idx_done 4

  @doc """
  Initializes the acknowledger and returns a reference.

  The reference is a tuple `{atomics_ref, caller_pid}` that is stored as the
  `ack_ref` in each `Broadway.Message`.
  """
  @spec init(non_neg_integer(), pid()) :: {:ok, {:atomics.atomics_ref(), pid()}}
  def init(total, caller_pid) when is_integer(total) and total >= 0 and is_pid(caller_pid) do
    ref = :atomics.new(4, signed: true)
    :atomics.put(ref, @idx_total, total)
    :atomics.put(ref, @idx_done, 0)

    ack_ref = {ref, caller_pid}

    # Handle edge case: zero repos → fire completion immediately
    if total == 0 do
      send(caller_pid, {:pipeline_complete, %{successful: 0, failed: 0, total: 0}})
    end

    {:ok, ack_ref}
  end

  @doc """
  Called by Broadway after messages are acknowledged.

  Uses `:atomics.add_get/3` for lock-free counter increments, then checks
  whether the total has been reached. A CAS on the done-flag ensures the
  completion message is sent exactly once even under concurrent ack calls.
  """
  @impl true
  def ack({atomics_ref, caller_pid}, successful, failed) do
    succ_count = length(successful)
    fail_count = length(failed)

    # Atomic increments — no lock, no serialization
    new_succ =
      if succ_count > 0,
        do: :atomics.add_get(atomics_ref, @idx_successful, succ_count),
        else: :atomics.get(atomics_ref, @idx_successful)

    new_fail =
      if fail_count > 0,
        do: :atomics.add_get(atomics_ref, @idx_failed, fail_count),
        else: :atomics.get(atomics_ref, @idx_failed)

    total = :atomics.get(atomics_ref, @idx_total)

    if new_succ + new_fail >= total do
      # CAS: only one caller wins the race to set done = 1
      case :atomics.compare_exchange(atomics_ref, @idx_done, 0, 1) do
        :ok ->
          send(
            caller_pid,
            {:pipeline_complete,
             %{
               successful: new_succ,
               failed: new_fail,
               total: total
             }}
          )

        _ ->
          # Another ack call already sent the completion message
          :ok
      end
    end
  end

  @impl true
  def configure(ack_ref, _ack_data, _options) do
    {:ok, ack_ref}
  end

  @spec counts({:atomics.atomics_ref(), any()}) :: %{
          failed: integer(),
          successful: integer(),
          total: integer()
        }
  @doc """
  Returns the current counts (for observability / debugging).
  """
  @spec counts({reference(), pid()}) :: %{
          successful: non_neg_integer(),
          failed: non_neg_integer(),
          total: non_neg_integer()
        }
  def counts({atomics_ref, _caller_pid}) do
    %{
      successful: :atomics.get(atomics_ref, @idx_successful),
      failed: :atomics.get(atomics_ref, @idx_failed),
      total: :atomics.get(atomics_ref, @idx_total)
    }
  end
end
