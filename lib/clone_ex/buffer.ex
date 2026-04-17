defmodule CloneEx.Buffer do
  @moduledoc """
  Utilities for parsing buffer sizes and calculating dynamic concurrency based on
  available memory and repository sizes.

  ## Examples

      # Parse human-readable sizes
      iex> CloneEx.Buffer.parse_size("1GB")
      {:ok, 1_073_741_824}

      iex> CloneEx.Buffer.parse_size("512MB")
      {:ok, 536_870_912}

      # Format bytes to human-readable
      iex> CloneEx.Buffer.format_size(1_073_741_824)
      "1.00 GB"

      # Calculate optimal concurrency
      iex> repos = [%{size_kb: 100_000}, %{size_kb: 200_000}]
      iex> CloneEx.Buffer.calculate_concurrency(1_073_741_824, repos, max_concurrency: 10)
      5
  """

  @kb 1024
  @mb 1024 * 1024
  @gb 1024 * 1024 * 1024

  @doc """
  Parses a human-readable size string into bytes.
  Accepts strings like "1GB", "512MB", "1.5GB", "100KB", or bare numbers.

  Returns `{:error, ...}` for negative numbers, empty strings, and unparseable input.
  """
  @spec parse_size(String.t()) :: {:ok, pos_integer()} | {:error, String.t()}
  def parse_size(size_str) when is_binary(size_str) do
    size_str = String.trim(size_str)

    cond do
      size_str == "" ->
        {:error, "Cannot parse size: empty string"}

      String.match?(size_str, ~r/^[0-9]+$/) ->
        value = String.to_integer(size_str)

        if value >= 0,
          do: {:ok, value},
          else: {:error, "Cannot parse size: negative value"}

      String.match?(size_str, ~r/^([0-9]+\.?[0-9]*)\s*GB$/i) ->
        parse_with_multiplier(size_str, ~r/^([0-9]+\.?[0-9]*)\s*GB$/i, @gb)

      String.match?(size_str, ~r/^([0-9]+\.?[0-9]*)\s*MB$/i) ->
        parse_with_multiplier(size_str, ~r/^([0-9]+\.?[0-9]*)\s*MB$/i, @mb)

      String.match?(size_str, ~r/^([0-9]+\.?[0-9]*)\s*KB$/i) ->
        parse_with_multiplier(size_str, ~r/^([0-9]+\.?[0-9]*)\s*KB$/i, @kb)

      true ->
        {:error, "Cannot parse size: #{size_str}. Expected format: 1GB, 512MB, 100KB, etc."}
    end
  end

  @spec parse_with_multiplier(String.t(), Regex.t(), pos_integer()) ::
          {:ok, pos_integer()} | {:error, String.t()}
  defp parse_with_multiplier(str, regex, multiplier) do
    case Regex.run(regex, str) do
      [_, num_str] ->
        try do
          num =
            if String.contains?(num_str, ".") do
              String.to_float(num_str)
            else
              String.to_integer(num_str) * 1.0
            end

          if num < 0 do
            {:error, "Cannot parse size: negative value"}
          else
            {:ok, trunc(num * multiplier)}
          end
        rescue
          ArgumentError -> {:error, "Invalid numeric format: #{num_str}"}
        end

      _ ->
        {:error, "Invalid numeric format in #{str}"}
    end
  end

  @doc """
  Formats an integer byte count into a human-readable string.

  ## Examples
      iex> CloneEx.Buffer.format_size(1_073_741_824)
      "1.00 GB"
      iex> CloneEx.Buffer.format_size(500)
      "500 B"
  """
  @spec format_size(non_neg_integer()) :: String.t()
  def format_size(bytes) when is_integer(bytes) and bytes >= 0 do
    cond do
      bytes >= @gb -> "#{:erlang.float_to_binary(bytes / @gb, decimals: 2)} GB"
      bytes >= @mb -> "#{:erlang.float_to_binary(bytes / @mb, decimals: 2)} MB"
      bytes >= @kb -> "#{:erlang.float_to_binary(bytes / @kb, decimals: 2)} KB"
      true -> "#{bytes} B"
    end
  end

  # Overhead per repository slot: 50 MB for git metadata, packfile index, etc.
  @overhead_per_repo_bytes 50_000_000

  @doc """
  Calculates the optimal number of concurrent processors based on buffer size
  and repository metadata.

  ## Formula
  `min(floor(buffer / avg_estimate), max_concurrency) |> max(1)`
  where `avg_estimate = mean(repo.size_kb * 1024) + overhead_per_repo`

  ## Examples
      iex> repos = [%{size_kb: 100_000}, %{size_kb: 200_000}]
      iex> CloneEx.Buffer.calculate_concurrency(1_073_741_824, repos, max_concurrency: 10)
      5

      iex> CloneEx.Buffer.calculate_concurrency(1_073_741_824, [], max_concurrency: 8)
      8
  """
  @spec calculate_concurrency(pos_integer(), [map()], keyword()) :: pos_integer()
  def calculate_concurrency(buffer_bytes, repos, opts \\ [])

  def calculate_concurrency(buffer_bytes, repos, opts)
      when is_integer(buffer_bytes) and buffer_bytes > 0 do
    max_concurrency = opts[:max_concurrency] || System.schedulers_online() * 2
    overhead_bytes = @overhead_per_repo_bytes

    if repos == [] do
      max_concurrency
    else
      total_bytes =
        Enum.reduce(repos, 0, fn repo, acc ->
          acc + (repo[:size_kb] || repo.size_kb) * 1024
        end)

      avg_repo_bytes = div(total_bytes, length(repos))
      per_slot_bytes = avg_repo_bytes + overhead_bytes

      buffer_bytes
      |> div(per_slot_bytes)
      |> max(1)
      |> min(max_concurrency)
    end
  end

  def calculate_concurrency(buffer_bytes, _repos, _opts) do
    raise ArgumentError,
          "buffer_bytes must be a positive integer, got: #{inspect(buffer_bytes)}"
  end
end
