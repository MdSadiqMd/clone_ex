defmodule CloneEx.TempDir do
  @moduledoc """
  Manages temporary directories for clones.

  Each `create/1` call generates a cryptographically random subdirectory under
  `<base_path>/.tmp/`. Cleanup is explicit via `cleanup/1` or `cleanup_all/1` —
  there is no implicit process-dictionary tracking, since Broadway processors
  and batchers run in different processes.

  ## Examples

      # Create a temporary directory
      iex> {:ok, path} = CloneEx.TempDir.create("/tmp/myapp")
      iex> File.dir?(path)
      true

      # Clean up when done
      iex> :ok = CloneEx.TempDir.cleanup(path)
      iex> File.dir?(path)
      false

      # Clean up all temp directories
      iex> CloneEx.TempDir.cleanup_all("/tmp/myapp")
      :ok
  """

  require Logger

  @doc """
  Creates a unique temporary directory under the given base path.

  Uses cryptographically random UUIDs with collision detection to ensure
  uniqueness even under high concurrency.

  ## Example
      {:ok, "/output/.tmp/a1b2c3d4e5f6g7h8"} = TempDir.create("/output")
  """
  @spec create(Path.t()) :: {:ok, Path.t()} | {:error, String.t()}
  def create(base_path) do
    tmp_base = Path.join(base_path, ".tmp")
    create_with_retry(tmp_base, 3)
  end

  @spec create_with_retry(Path.t(), non_neg_integer()) ::
          {:ok, Path.t()} | {:error, String.t()}
  defp create_with_retry(tmp_base, attempts) when attempts > 0 do
    uuid = :crypto.strong_rand_bytes(8) |> Base.encode32(case: :lower, padding: false)
    tmp_dir = Path.join(tmp_base, uuid)

    case File.mkdir_p(tmp_dir) do
      :ok ->
        # Verify directory was actually created (not pre-existing)
        # Check if directory is empty - a newly created dir should be empty
        case File.ls(tmp_dir) do
          {:ok, []} ->
            {:ok, tmp_dir}

          {:ok, _files} ->
            # Directory has files, likely a collision - retry
            Logger.debug("Temp dir collision detected (non-empty), retrying...")
            create_with_retry(tmp_base, attempts - 1)

          {:error, _} ->
            # Can't list directory but mkdir succeeded - proceed anyway
            {:ok, tmp_dir}
        end

      {:error, reason} ->
        {:error, "Failed to create temp dir #{tmp_dir}: #{inspect(reason)}"}
    end
  end

  defp create_with_retry(_tmp_base, 0) do
    {:error, "Failed to create unique temp dir after multiple attempts"}
  end

  @doc """
  Removes a single temporary directory and all its contents.
  Returns `:ok` even if the path does not exist (idempotent).
  """
  @spec cleanup(Path.t()) :: :ok
  def cleanup(path) do
    case File.rm_rf(path) do
      {:ok, _} ->
        :ok

      {:error, reason, failed_file} ->
        Logger.error("Failed to clean up temp dir #{failed_file}: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Removes all temporary directories under the base path's `.tmp/` subdirectory.
  """
  @spec cleanup_all(Path.t()) :: :ok
  def cleanup_all(base_path) do
    tmp_base = Path.join(base_path, ".tmp")
    cleanup(tmp_base)
  end
end
