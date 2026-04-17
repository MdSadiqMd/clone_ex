defmodule CloneEx.Retry do
  @moduledoc """
  Generic retry logic with exponential backoff and jitter.

  Provides safe, composable retry mechanisms for transient failures with:
  - Exponential backoff with randomized jitter to prevent thundering herd
  - Support for permanent errors (no retry)
  - Exception handling (treated as transient errors)
  - Configurable delays and attempt limits

  ## Error Types
  - `{:ok, value}` - Success, no retry needed
  - `{:error, :permanent, reason}` - Permanent failure, no retry (e.g., auth error)
  - `{:error, reason}` - Transient failure, will retry (e.g., timeout, network)

  ## Examples
      # Simple retry with defaults (3 attempts, 1s base delay, 4x multiplier)
      iex> CloneEx.Retry.with_retry(fn ->
      ...>   if :rand.uniform() > 0.5, do: {:ok, :success}, else: {:error, :transient}
      ...> end)
      {:ok, :success}

      # Custom retry configuration
      iex> CloneEx.Retry.with_retry(fn ->
      ...>   {:error, :always_fails}
      ...> end, max_attempts: 2, base_delay_ms: 100)
      {:error, :always_fails}

      # Permanent errors skip retries immediately
      iex> CloneEx.Retry.with_retry(fn ->
      ...>   {:error, :permanent, :auth_failed}
      ...> end)
      {:error, :auth_failed}
  """

  require Logger
  alias CloneEx.Config

  @doc """
  Executes the given function with exponential backoff retries on transient failures.
  The function must return one of:
  - `{:ok, result}` - success, returns immediately
  - `{:error, :permanent, reason}` - permanent failure, no retry
  - `{:error, reason}` - transient failure, retry with backoff

  Exceptions raised by the function are caught and treated as transient errors.
  ## Options
    * `:max_attempts` - maximum number of attempts (default: 3)
    * `:base_delay_ms` - base delay in milliseconds (default: 1000)
    * `:multiplier` - backoff multiplier (default: 4, so 1s → 4s → 16s → ...)
    * `:jitter` - maximum jitter ratio (default: 0.2, meaning ±20%)

  ## Examples
      {:ok, result} = CloneEx.Retry.with_retry(
        fn -> do_something() end,
        max_attempts: 5,
        base_delay_ms: 500
      )

      {:error, reason} = CloneEx.Retry.with_retry(fn ->
        {:error, :permanent, :auth_failed}
      end)
  """
  @spec with_retry(
          (-> {:ok, value} | {:error, :permanent, reason} | {:error, reason}),
          keyword()
        ) :: {:ok, value} | {:error, reason}
        when value: var, reason: var
  def with_retry(fun, opts \\ []) when is_function(fun, 0) and is_list(opts) do
    max_attempts = Keyword.get(opts, :max_attempts, Config.default_max_retries())
    base_delay = Keyword.get(opts, :base_delay_ms, Config.default_retry_delay_ms())
    multiplier = Keyword.get(opts, :multiplier, Config.default_retry_multiplier())
    jitter = Keyword.get(opts, :jitter, Config.default_retry_jitter())

    do_retry(fun, 1, max_attempts, base_delay, multiplier, jitter)
  end

  defp do_retry(fun, attempt, max_attempts, current_delay, multiplier, jitter_ratio) do
    result =
      try do
        fun.()
      rescue
        e ->
          Logger.debug("Caught exception during retry attempt: #{Exception.message(e)}")
          {:error, e}
      end

    case result do
      {:ok, _} = success ->
        success

      {:error, :permanent, reason} ->
        Logger.debug("Permanent error on attempt #{attempt}: #{inspect(reason)}")
        {:error, reason}

      {:error, reason} ->
        if attempt < max_attempts do
          sleep_ms = apply_jitter(current_delay, jitter_ratio)

          Logger.debug(
            "Transient error on attempt #{attempt}/#{max_attempts}, " <>
              "retrying after #{sleep_ms}ms: #{inspect(reason)}"
          )

          Process.sleep(sleep_ms)

          next_delay = current_delay * multiplier
          do_retry(fun, attempt + 1, max_attempts, next_delay, multiplier, jitter_ratio)
        else
          Logger.warning("Failed after #{max_attempts} attempts: #{inspect(reason)}")
          {:error, reason}
        end
    end
  end

  @spec apply_jitter(pos_integer(), float()) :: non_neg_integer()
  defp apply_jitter(delay, ratio) when is_integer(delay) and delay > 0 and ratio >= 0 do
    variance = delay * ratio
    jitter = :rand.uniform() * variance * 2 - variance
    trunc(delay + jitter) |> max(0)
  end
end
