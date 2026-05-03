defmodule CloneEx.Result do
  @moduledoc """
  Result type utilities for consistent, composable error handling.

  Provides helpers for working with `{:ok, value}` and `{:error, reason}` tuples,
  following Elixir conventions and enabling safe error propagation with `with/1`.

  ## Examples

      # Chain operations with automatic error propagation
      iex> with {:ok, data} <- fetch_data(),
      ...>      {:ok, processed} <- process(data) do
      ...>   {:ok, processed}
      ...> end

      # Use map to transform success values
      iex> {:ok, 10} |> CloneEx.Result.map(&(&1 * 2))
      {:ok, 20}

      # Use map_error to transform error values
      iex> {:error, :network} |> CloneEx.Result.map_error(&normalize_error/1)
      {:error, "Network error"}

      # Chain with flat_map for operations that return Results
      iex> {:ok, "path"} |> CloneEx.Result.flat_map(&File.read/1)
      {:ok, "file contents"} # or {:error, :enoent}
  """

  @doc """
  Transforms the success value in an `{:ok, value}` result, leaving errors unchanged.

  ## Examples
      iex> CloneEx.Result.map({:ok, 5}, &(&1 * 2))
      {:ok, 10}

      iex> CloneEx.Result.map({:error, :failed}, &(&1 * 2))
      {:error, :failed}
  """
  @spec map({:ok, value} | {:error, reason}, (value -> result)) ::
          {:ok, result} | {:error, reason}
        when value: var, reason: var, result: var
  def map(result, fun)

  def map({:ok, value}, fun) do
    {:ok, fun.(value)}
  end

  def map({:error, _} = error, _fun) do
    error
  end

  @doc """
  Transforms the error value in an `{:error, reason}` result, leaving successes unchanged.

  ## Examples
      iex> CloneEx.Result.map_error({:error, :failed}, &(: {:error, &1}))
      {:error, {:wrapped, :failed}}

      iex> CloneEx.Result.map_error({:ok, 10}, &(:never_called))
      {:ok, 10}
  """
  @spec map_error(
          {:ok, value} | {:error, reason},
          (reason -> new_reason)
        ) :: {:ok, value} | {:error, new_reason}
        when value: var, reason: var, new_reason: var
  def map_error(result, fun)

  def map_error({:ok, _} = ok, _fun) do
    ok
  end

  def map_error({:error, reason}, fun) do
    {:error, fun.(reason)}
  end

  @doc """
  Chains Results together, flattening nested Results (monadic bind).

  Useful when the function returns a Result itself.

  ## Examples
      iex> {:ok, "hello"} |> CloneEx.Result.flat_map(fn s ->
      ...>   if String.length(s) > 3, do: {:ok, String.upcase(s)}, else: {:error, :too_short}
      ...> end)
      {:ok, "HELLO"}

      iex> {:error, :not_found} |> CloneEx.Result.flat_map(&some_operation/1)
      {:error, :not_found}
  """
  @spec flat_map(
          {:ok, value} | {:error, reason},
          (value -> {:ok, result} | {:error, reason})
        ) :: {:ok, result} | {:error, reason}
        when value: var, reason: var, result: var
  def flat_map(result, fun)

  def flat_map({:ok, value}, fun) do
    fun.(value)
  end

  def flat_map({:error, _} = error, _fun) do
    error
  end

  @doc """
  Executes a function regardless of success or failure, preserving the original result.

  Useful for cleanup or logging side effects.

  ## Examples
      iex> {:ok, 42} |> CloneEx.Result.tap(fn _ -> nil end)
      {:ok, 42}
  """
  @spec tap(
          {:ok, value} | {:error, reason},
          (value -> any())
        ) :: {:ok, value} | {:error, reason}
        when value: var, reason: var
  def tap(result, fun)

  def tap({:ok, value} = ok, fun) do
    fun.(value)
    ok
  end

  def tap({:error, _} = error, _fun) do
    error
  end

  @doc """
  Unwraps a Result, returning the value or raising an error.

  Use sparingly — prefer pattern matching or `with/1` for better error handling.

  ## Examples
      iex> CloneEx.Result.unwrap!({:ok, 42})
      42

      iex> CloneEx.Result.unwrap!({:error, :not_found})
      ** (RuntimeError) Error: :not_found
  """
  @spec unwrap!({:ok, value} | {:error, any()}) :: value when value: var
  def unwrap!({:ok, value}) do
    value
  end

  def unwrap!({:error, reason}) do
    raise "Error: #{inspect(reason)}"
  end

  @doc """
  Unwraps a Result, returning the value or a default.

  ## Examples
      iex> CloneEx.Result.unwrap_or({:ok, 42}, 0)
      42

      iex> CloneEx.Result.unwrap_or({:error, :not_found}, 0)
      0
  """
  @spec unwrap_or({:ok, value} | {:error, any()}, default) :: value | default
        when value: var, default: var
  def unwrap_or(result, default)

  def unwrap_or({:ok, value}, _default) do
    value
  end

  def unwrap_or({:error, _}, default) do
    default
  end

  @doc """
  Applies a function to the error value if present, or the success value otherwise.

  ## Examples
      iex> CloneEx.Result.fold({:ok, 10}, fn _e -> 0 end, fn v -> v * 2 end)
      20

      iex> CloneEx.Result.fold({:error, :failed}, fn _e -> 0 end, fn _v -> 999 end)
      0
  """
  @spec fold(
          {:ok, value} | {:error, reason},
          (reason -> result),
          (value -> result)
        ) :: result
        when value: var, reason: var, result: var
  def fold(result, error_fn, ok_fn)

  def fold({:ok, value}, _error_fn, ok_fn) do
    ok_fn.(value)
  end

  def fold({:error, reason}, error_fn, _ok_fn) do
    error_fn.(reason)
  end
end
