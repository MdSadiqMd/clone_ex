defmodule CloneEx.GitCloner do
  @moduledoc """
  Handles cloning git repositories using `git clone --mirror`.

  Uses `Task.Supervisor` for structured concurrency — all spawned tasks are
  supervised, ensuring clean shutdown (no orphaned `git` OS processes) when
  the application stops or the pipeline is terminated.
  """

  require Logger
  alias CloneEx.{Retry, Utils}

  @doc """
  Clones a git repository into a destination path using `--mirror`.

  Wraps the clone in `CloneEx.Retry.with_retry/2` with exponential backoff.
  Permanent errors (auth failures, repo not found) are not retried.

  ## Options
    * `:timeout` - timeout for the clone operation in milliseconds (default: 600_000)
    * `:max_retries` - maximum number of retry attempts (default: 3)
    * `:retry_delay_ms` - base delay for backoff (default: 1_000)
  """
  @spec clone_mirror(String.t(), Path.t(), keyword()) :: {:ok, Path.t()} | {:error, String.t()}
  def clone_mirror(url, dest_path, opts \\ []) do
    retry_opts = [
      max_attempts: Keyword.get(opts, :max_retries, 3),
      base_delay_ms: Keyword.get(opts, :retry_delay_ms, 1000)
    ]

    Retry.with_retry(
      fn ->
        # Clean up any partial clone from a previous attempt
        _ = if File.dir?(dest_path), do: File.rm_rf!(dest_path)
        do_clone(url, dest_path, opts)
      end,
      retry_opts
    )
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
        type = classify_error(code, output)

        :telemetry.execute(
          [:clone_ex, :clone, :error],
          %{exit_code: code},
          %{repo: repo_name, reason: output}
        )

        error_msg = "git exit #{code}: #{String.trim(output)}"

        if type == :permanent do
          {:error, :permanent, error_msg}
        else
          {:error, error_msg}
        end

      nil ->
        :telemetry.execute(
          [:clone_ex, :clone, :error],
          %{exit_code: nil},
          %{repo: repo_name, reason: "timeout"}
        )

        {:error, "clone timed out after #{timeout}ms"}
    end
  end

  @doc """
  Classifies a git error as `:permanent` (no point retrying) or `:retriable`.

  Exit code 128 is used by git for many error types. We inspect the output
  to distinguish auth/not-found errors (permanent) from network flakes (retriable).
  """
  @spec classify_error(integer(), String.t()) :: :permanent | :retriable
  def classify_error(128, output) do
    lower = String.downcase(output)

    cond do
      String.contains?(lower, "not found") -> :permanent
      String.contains?(lower, "fatal: could not read username") -> :permanent
      String.contains?(lower, "fatal: authentication failed") -> :permanent
      String.contains?(lower, "does not exist") -> :permanent
      # Typical network flakes also return 128, treat the rest as retriable
      true -> :retriable
    end
  end

  def classify_error(_code, _output), do: :retriable
end
