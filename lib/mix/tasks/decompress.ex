defmodule Mix.Tasks.Decompress do
  @moduledoc """
  Decompresses CloneEx archives.

  ## Usage

      mix decompress <archive_path> [output_dir]

  ## Examples

      # Decompress to current directory
      mix decompress repo.tar.zst

      # Decompress to specific directory
      mix decompress repo.tar.lz4 /tmp/restored

  ## Supported Formats

    * .tar.zst (Zstandard compression)
    * .tar.lz4 (LZ4 compression)
  """

  use Mix.Task

  @shortdoc "Decompresses .tar.zst or .tar.lz4 archives"

  @impl Mix.Task
  def run(args) do
    case args do
      [archive_path] ->
        decompress(archive_path, nil)

      [archive_path, output_dir] ->
        decompress(archive_path, output_dir)

      _ ->
        Mix.shell().error("""
        Usage: mix decompress <archive_path> [output_dir]

        Examples:
          mix decompress repo.tar.zst
          mix decompress repo.tar.lz4 /tmp/restored
        """)

        exit({:shutdown, 1})
    end
  end

  defp decompress(archive_path, output_dir) do
    unless File.exists?(archive_path) do
      Mix.shell().error("Error: Archive not found: #{archive_path}")
      exit({:shutdown, 1})
    end

    case CloneEx.Decompressor.decompress(archive_path, output_dir) do
      {:ok, _path} ->
        :ok

      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
        exit({:shutdown, 1})
    end
  end
end
