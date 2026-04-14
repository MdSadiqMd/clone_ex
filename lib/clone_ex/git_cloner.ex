defmodule CloneEx.GitCloner do
  @moduledoc """
  Handles cloning git repositories using `git clone --mirror`.

  Uses `Task.Supervisor` for structured concurrency — all spawned tasks are
  supervised, ensuring clean shutdown (no orphaned `git` OS processes) when
  the application stops or the pipeline is terminated.
  """

  require Logger
  alias CloneEx.Utils

  @doc """
  Clones a git repository into a destination path using `--mirror`.

  Permanent errors (auth failures, repo not found) are not retried.

  ## Options
    * `:timeout` - timeout for the clone operation in milliseconds (default: 600_000)
  """
  @spec clone_mirror(String.t(), Path.t(), keyword()) :: {:ok, Path.t()} | {:error, String.t()}
  def clone_mirror(url, dest_path, opts \\ []) do
      fn ->
        # Clean up any partial clone from a previous attempt
        _ = if File.dir?(dest_path), do: File.rm_rf!(dest_path)
        do_clone(url, dest_path, opts)
      end
  end

  defp do_clone(url, dest_path, opts) do
    timeout = Keyword.get(opts, :timeout, 600_000)
    File.mkdir_p!(Path.dirname(dest_path))

    repo_name = Path.basename(dest_path)
    :telemetry.execute([:clone_ex, :clone, :start], %{}, %{repo: repo_name, url: url})
    start_time = System.monotonic_time(:millisecond)

    # Use Task.Supervisor for structured concurrency.
    # On application shutdown, the supervisor will terminate all running tasks,
    # which sends SIGTERM to the child git processes — no orphans.
    task =
      Task.Supervisor.async_nolink(CloneEx.TaskSupervisor, fn ->
        System.cmd(
          "git",
          [
            "clone",
            "--mirror",
            "--quiet",
            "--",
            url,
            dest_path
          ],
          stderr_to_stdout: true,
          env: [{"GIT_TERMINAL_PROMPT", "0"}]
        )
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {_output, 0}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        size = Utils.dir_size(dest_path)

        :telemetry.execute(
          [:clone_ex, :clone, :stop],
          %{duration_ms: duration, size_bytes: size},
          %{repo: repo_name}
        )

        {:ok, dest_path}

      {:ok, {output, code}} ->
        :telemetry.execute(
          [:clone_ex, :clone, :error],
          %{exit_code: code},
          %{repo: repo_name, reason: output}
        )
      nil ->
        :telemetry.execute(
          [:clone_ex, :clone, :error],
          %{exit_code: nil},
          %{repo: repo_name, reason: "timeout"}
        )

        {:error, "clone timed out after #{timeout}ms"}
    end
  end
end
