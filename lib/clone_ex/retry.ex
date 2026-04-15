defmodule CloneEx.Retry do
  @moduledoc """
  Generic retry logic with exponential backoff and jitter.

  ## Examples

      # Simple retry with defaults (3 attempts, 1s base delay)
      iex> CloneEx.Retry.with_retry(fn ->
      ...>   if :rand.uniform() > 0.5, do: {:ok, :success}, else: {:error, :transient}
      ...> end)
      {:ok, :success}

      # Custom retry configuration
      iex> CloneEx.Retry.with_retry(fn ->
      ...>   {:error, :always_fails}
      ...> end, max_attempts: 2, base_delay_ms: 100)
      {:error, :always_fails}

      # Permanent errors skip retries
      iex> CloneEx.Retry.with_retry(fn ->
      ...>   {:error, :permanent, :auth_failed}
      ...> end)
      {:error, :auth_failed}
  """

  @doc """
  Executes the given function with exponential backoff retries.

  The function must return `{:ok, result}`, `{:error, :permanent, reason}`,
  or `{:error, reason}` (which will be retried).
  If the function raises an exception, it is caught and treated as a retriable error.

  ## Options
    * `:max_attempts` - maximum number of attempts (default: 3)
    * `:base_delay_ms` - base delay in milliseconds (default: 1000)
    * `:multiplier` - backoff multiplier (default: 4)
    * `:jitter` - maximum jitter ratio (default: 0.2, meaning ±20%)
  """
  @spec with_retry((-> {:ok, any()} | {:error, :permanent, any()} | {:error, any()}), keyword()) ::
          {:ok, any()} | {:error, any()}
  def with_retry(fun, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    base_delay = Keyword.get(opts, :base_delay_ms, 1000)
    multiplier = Keyword.get(opts, :multiplier, 4)
    jitter = Keyword.get(opts, :jitter, 0.2)

    do_retry(fun, 1, max_attempts, base_delay, multiplier, jitter)
  end

  defp do_retry(fun, attempt, max_attempts, current_delay, multiplier, jitter_ratio) do
    result =
      try do
        fun.()
      rescue
        e -> {:error, e}
      end

    case result do
      {:ok, _} = success ->
        success

      {:error, :permanent, reason} ->
        {:error, reason}

      {:error, reason} ->
        if attempt < max_attempts do
          sleep_ms = apply_jitter(current_delay, jitter_ratio)
          Process.sleep(sleep_ms)

          next_delay = current_delay * multiplier
          do_retry(fun, attempt + 1, max_attempts, next_delay, multiplier, jitter_ratio)
        else
          {:error, reason}
        end
    end
  end

  defp apply_jitter(delay, ratio) do
    variance = delay * ratio
    jitter = :rand.uniform() * variance * 2 - variance
    trunc(delay + jitter) |> max(0)
  end
end
