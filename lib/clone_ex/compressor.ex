defmodule CloneEx.Compressor do
  @moduledoc """
  Handles compression pipelines for cloned repositories.

  ## Architecture Decision: System Binaries vs NIF

  This implementation uses system `tar` and `zstd` binaries instead of the
  originally planned ezstd NIF for the following reasons:

  1. **Multi-threaded compression**: `zstd -T0` uses all available CPU cores,
     significantly faster than single-threaded NIF streaming for large files.

  2. **Simpler deployment**: No NIF compilation required, works on any system
     with tar and zstd installed (standard on most Unix systems).

  3. **Proven stability**: System binaries are battle-tested and maintained
     by their respective communities.

  The two-step approach (tar then zstd) avoids shell injection vulnerabilities
  that arise from piping through `sh -c`, as all arguments are passed safely
  via lists to `System.cmd/3`.

  ## Compression Modes

  - **fast**: LZ4 compression (660 MB/s, 1.8x ratio) - for local backups
  - **balanced**: Zstd level 3 (350 MB/s, 2.8x ratio) - default, best overall
  - **high**: Zstd level 9 (50 MB/s, 3.2x ratio) - for long-term storage
  - **max**: Zstd level 19 (5 MB/s, 3.5x ratio) - maximum compression

  ## Requirements

  - `tar` command (GNU tar or BSD tar)
  - `zstd` command (version >= 1.4.0)
  - `lz4` command (optional, for fast mode)

  Install on macOS: `brew install zstd lz4`
  Install on Ubuntu/Debian: `apt-get install zstd lz4`
  """

  require Logger
  alias CloneEx.Utils

  # Compression mode presets
  @compression_modes %{
    fast: {:lz4, nil},
    balanced: {:zstd, 3},
    high: {:zstd, 9},
    max: {:zstd, 19}
  }

  @doc """
  Compresses a mirror directory into a compressed archive.

  The pipeline is:
    1. `tar cf temp.tar -C <dir> .` — create an uncompressed tarball
    2. Compress with selected algorithm (zstd or lz4)

  ## Options
    * `:compression_mode` - Preset mode: `:fast`, `:balanced`, `:high`, `:max` (default: `:balanced`)
    * `:compression_level` - Zstandard compression level 1–22 (overrides mode)

  ## Examples
      # Default: balanced (zstd level 3)
      iex> CloneEx.Compressor.compress("/tmp/repo.git", "/tmp/repo.tar.zst")
      {:ok, %{original_bytes: 1_000_000, compressed_bytes: 350_000, ratio: 2.86, duration_ms: 123}}

      # Fast mode (lz4)
      iex> CloneEx.Compressor.compress("/tmp/repo.git", "/tmp/repo.tar.lz4", compression_mode: :fast)
      {:ok, %{original_bytes: 1_000_000, compressed_bytes: 550_000, ratio: 1.82, duration_ms: 45}}

      # High compression (zstd level 9)
      iex> CloneEx.Compressor.compress("/tmp/repo.git", "/tmp/repo.tar.zst", compression_mode: :high)
      {:ok, %{original_bytes: 1_000_000, compressed_bytes: 310_000, ratio: 3.23, duration_ms: 456}}
  """
  @spec compress(Path.t(), Path.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def compress(mirror_path, output_path, opts \\ []) do
    {algorithm, level} = determine_compression(opts)

    if not File.dir?(mirror_path) do
      {:error, "Source directory does not exist: #{mirror_path}"}
    else
      :telemetry.execute([:clone_ex, :compress, :start], %{}, %{repo: Path.basename(mirror_path)})
      start_time = System.monotonic_time(:millisecond)
      original_bytes = Utils.dir_size(mirror_path)

      File.mkdir_p!(Path.dirname(output_path))

      # Two-step approach avoids shell injection (no `sh -c` interpolation).
      # Step 1: Create intermediate tar archive
      tar_path = output_path <> ".tmp.tar"

      try do
        case create_tar(mirror_path, tar_path) do
          :ok ->
            compress_result =
              case algorithm do
                :lz4 -> compress_lz4(tar_path, output_path)
                :zstd -> compress_zstd(tar_path, output_path, level)
              end

            case compress_result do
              :ok ->
                duration = System.monotonic_time(:millisecond) - start_time
                compressed_bytes = File.stat!(output_path).size

                ratio =
                  if compressed_bytes > 0,
                    do: Float.round(original_bytes / compressed_bytes, 2),
                    else: 0.0

                stats = %{
                  original_bytes: original_bytes,
                  compressed_bytes: compressed_bytes,
                  ratio: ratio,
                  duration_ms: duration,
                  algorithm: algorithm,
                  level: level
                }

                :telemetry.execute([:clone_ex, :compress, :stop], stats, %{
                  repo: Path.basename(mirror_path)
                })

                {:ok, stats}

              {:error, reason} ->
                emit_error(mirror_path, reason)
                {:error, reason}
            end

          {:error, reason} ->
            emit_error(mirror_path, reason)
            {:error, reason}
        end
      after
        # Always clean up intermediate tar file (if it still exists)
        # Note: zstd --rm flag removes the input file, so this may not exist
        if File.exists?(tar_path) do
          case File.rm(tar_path) do
            :ok ->
              :ok

            {:error, reason} ->
              Logger.warning("Failed to remove temp tar #{tar_path}: #{inspect(reason)}")
          end
        end
      end
    end
  end

  # Determines compression algorithm and level from options
  @spec determine_compression(keyword()) :: {:lz4 | :zstd, pos_integer() | nil}
  defp determine_compression(opts) do
    cond do
      # Explicit level overrides everything
      level = opts[:compression_level] ->
        {:zstd, level}

      # Mode preset
      mode = opts[:compression_mode] ->
        Map.get(@compression_modes, mode, @compression_modes.balanced)

      # Default: balanced (zstd level 3)
      true ->
        @compression_modes.balanced
    end
  end

  # Creates a tar archive using safe argument passing (no shell interpolation).
  # Uses system tar binary for maximum compatibility and performance.
  @spec create_tar(Path.t(), Path.t()) :: :ok | {:error, String.t()}
  defp create_tar(source_dir, tar_path) do
    case System.cmd("tar", ["cf", tar_path, "-C", source_dir, "."], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, code} -> {:error, "tar failed with exit #{code}: #{String.trim(output)}"}
    end
  end

  # Compresses a file with zstd using safe argument passing.
  # Uses multi-threaded compression (-T0) for maximum performance.
  @spec compress_zstd(Path.t(), Path.t(), pos_integer()) :: :ok | {:error, String.t()}
  defp compress_zstd(input_path, output_path, level) do
    args = [
      # Use all available CPU threads
      "-T0",
      # Compression level
      "-#{level}",
      # Input file
      input_path,
      # Output file
      "-o",
      output_path,
      # Remove input after compression (saves disk)
      "--rm",
      # Force overwrite
      "-f"
    ]

    case System.cmd("zstd", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, code} -> {:error, "zstd failed with exit #{code}: #{String.trim(output)}"}
    end
  end

  # Compresses a file with lz4 using safe argument passing.
  # LZ4 is the fastest compression algorithm, ideal for local backups.
  @spec compress_lz4(Path.t(), Path.t()) :: :ok | {:error, String.t()}
  defp compress_lz4(input_path, output_path) do
    args = [
      # Fast compression (level 1)
      "-1",
      # Input file
      input_path,
      # Output file
      output_path,
      # Force overwrite
      "-f",
      # Remove input after compression
      "--rm"
    ]

    case System.cmd("lz4", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, code} -> {:error, "lz4 failed with exit #{code}: #{String.trim(output)}"}
    end
  end

  defp emit_error(mirror_path, reason) do
    :telemetry.execute(
      [:clone_ex, :compress, :error],
      %{},
      %{repo: Path.basename(mirror_path), reason: reason}
    )
  end
end
