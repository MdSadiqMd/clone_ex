defmodule CloneEx.Utils do
  @moduledoc """
  Shared utility functions used across CloneEx modules.
  """

  @doc """
  Calculates the total size of a directory in bytes using the system `du` command.
  Falls back to a pure-Elixir recursive walk if `du` is unavailable.

  Returns `0` if the path does not exist or cannot be read.
  """
  @spec dir_size(Path.t()) :: non_neg_integer()
  def dir_size(path) do
    case System.cmd("du", ["-sk", path], stderr_to_stdout: true) do
      {output, 0} ->
        [kb | _] = String.split(output, "\t")
        String.to_integer(kb) * 1024

      _ ->
        dir_size_elixir(path)
    end
  end

  @doc """
  Pure-Elixir directory size calculation. Slower than `du` but portable.

  Recursively walks the directory tree and sums file sizes.
  """
  @spec dir_size_elixir(Path.t()) :: non_neg_integer()
  def dir_size_elixir(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, size: size}} ->
        size

      {:ok, %File.Stat{type: :directory}} ->
        case File.ls(path) do
          {:ok, entries} ->
            entries
            |> Enum.reduce(0, fn entry, acc ->
              acc + dir_size_elixir(Path.join(path, entry))
            end)

          {:error, _} ->
            0
        end

      _ ->
        0
    end
  end
end
