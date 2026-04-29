defmodule CloneEx.Decompressor do
  @moduledoc """
  Handles decompression of archived repositories.

  Supports both zstd (.tar.zst) and lz4 (.tar.lz4) compressed archives.
  """

  require Logger

  @doc """
  Decompresses an archive file to the specified output directory.

  ## Parameters
    * `archive_path` - Path to the compressed archive (.tar.zst or .tar.lz4)
    * `output_dir` - Optional output directory (defaults to current directory)

  ## Examples
      iex> CloneEx.Decompressor.decompress("repo.tar.zst")
      {:ok, "."}

      iex> CloneEx.Decompressor.decompress("repo.tar.lz4", "/tmp/restored")
      {:ok, "/tmp/restored"}
  """
  @spec decompress(Path.t(), Path.t() | nil) :: {:ok, Path.t()} | {:error, String.t()}
  def decompress(archive_path, output_dir \\ nil) do
    cond do
      String.ends_with?(archive_path, ".tar.zst") ->
        decompress_zstd(archive_path, output_dir)

      String.ends_with?(archive_path, ".tar.lz4") ->
        decompress_lz4(archive_path, output_dir)

      true ->
        {:error, "Unsupported format. Expected .tar.zst or .tar.lz4"}
    end
  end

  # Decompresses a zstd archive
  @spec decompress_zstd(Path.t(), Path.t() | nil) :: {:ok, Path.t()} | {:error, String.t()}
  defp decompress_zstd(archive_path, output_dir) do
    IO.puts("Decompressing zstd archive: #{archive_path}")

    if output_dir do
      decompress_to_directory(:zstd, archive_path, output_dir)
    else
      decompress_to_current(:zstd, archive_path)
    end
  end

  # Decompresses an lz4 archive
  @spec decompress_lz4(Path.t(), Path.t() | nil) :: {:ok, Path.t()} | {:error, String.t()}
  defp decompress_lz4(archive_path, output_dir) do
    IO.puts("Decompressing lz4 archive: #{archive_path}")

    if output_dir do
      decompress_to_directory(:lz4, archive_path, output_dir)
    else
      decompress_to_current(:lz4, archive_path)
    end
  end

  # Decompress to a specific directory
  @spec decompress_to_directory(atom(), Path.t(), Path.t()) ::
          {:ok, Path.t()} | {:error, String.t()}
  defp decompress_to_directory(algorithm, archive_path, output_dir) do
    File.mkdir_p!(output_dir)

    basename =
      archive_path
      |> Path.basename()
      |> String.replace_suffix(extension(algorithm), "")

    tar_path = Path.join(output_dir, basename)

    with :ok <- decompress_file(algorithm, archive_path, tar_path),
         :ok <- extract_tar(tar_path, output_dir),
         :ok <- File.rm(tar_path) do
      IO.puts("✓ Extracted to #{output_dir}")
      {:ok, output_dir}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Decompress to current directory (streaming)
  @spec decompress_to_current(atom(), Path.t()) :: {:ok, Path.t()} | {:error, String.t()}
  defp decompress_to_current(algorithm, archive_path) do
    case decompress_and_extract_streaming(algorithm, archive_path, ".") do
      :ok ->
        IO.puts("✓ Extracted to current directory")
        {:ok, "."}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Decompress a file using system command
  @spec decompress_file(atom(), Path.t(), Path.t()) :: :ok | {:error, String.t()}
  defp decompress_file(:zstd, input_path, output_path) do
    case System.cmd("zstd", ["-d", input_path, "-o", output_path], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, code} -> {:error, "zstd failed with exit #{code}: #{String.trim(output)}"}
    end
  end

  defp decompress_file(:lz4, input_path, output_path) do
    case System.cmd("lz4", ["-d", input_path, output_path], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, code} -> {:error, "lz4 failed with exit #{code}: #{String.trim(output)}"}
    end
  end

  # Extract tar archive to directory
  @spec extract_tar(Path.t(), Path.t()) :: :ok | {:error, String.t()}
  defp extract_tar(tar_path, output_dir) do
    case System.cmd("tar", ["-xf", tar_path, "-C", output_dir], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, code} -> {:error, "tar failed with exit #{code}: #{String.trim(output)}"}
    end
  end

  # Decompress and extract in one streaming operation (no intermediate file)
  @spec decompress_and_extract_streaming(atom(), Path.t(), Path.t()) ::
          :ok | {:error, String.t()}
  defp decompress_and_extract_streaming(:zstd, archive_path, output_dir) do
    # zstd -d -c archive.tar.zst | tar -xf - -C output_dir
    case System.cmd("sh", [
           "-c",
           "zstd -d -c '#{archive_path}' | tar -xf - -C '#{output_dir}'"
         ]) do
      {_output, 0} -> :ok
      {output, code} -> {:error, "Decompression failed with exit #{code}: #{String.trim(output)}"}
    end
  end

  defp decompress_and_extract_streaming(:lz4, archive_path, output_dir) do
    # lz4 -d -c archive.tar.lz4 | tar -xf - -C output_dir
    case System.cmd("sh", [
           "-c",
           "lz4 -d -c '#{archive_path}' | tar -xf - -C '#{output_dir}'"
         ]) do
      {_output, 0} -> :ok
      {output, code} -> {:error, "Decompression failed with exit #{code}: #{String.trim(output)}"}
    end
  end

  # Get file extension for algorithm
  @spec extension(atom()) :: String.t()
  defp extension(:zstd), do: ".tar.zst"
  defp extension(:lz4), do: ".tar.lz4"
end
