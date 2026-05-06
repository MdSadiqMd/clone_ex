defmodule CloneEx do
  @moduledoc """
  Broadway-powered concurrent GitHub repository archiver with streaming Zstandard compression.

  Top-level orchestrator that ties together the GitHub API client, git cloner,
  compressor, and Broadway pipeline to mirror and archive all repositories
  under a GitHub username into lossless `.tar.zst` archives.
  """

  require Logger
  alias CloneEx.{GitHubClient, Buffer, Acknowledger, Pipeline, Config}

  @version "0.1.0"

  @doc "Returns the current version string."
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Main entry point for starting an archival run.

  Fetches the repository list, calculates dynamic concurrency based on buffer
  size, starts the Broadway pipeline, and blocks until all repos are processed.

  The pipeline is monitored — if it crashes, this function returns an error
  instead of hanging forever.

  ## Options
    * `:username` - GitHub username (required)
    * `:token` - GitHub personal access token
    * `:output_dir` - output directory (default: `"./archives"`)
    * `:buffer_size` - memory budget in bytes (default: 1 GB)
    * `:max_concurrency` - max parallel workers
    * `:skip_forks` - skip forked repos (default: false)
    * `:include_private` - include private repos (default: false)
    * `:compression_level` - zstd level 1–22
    * `:clone_timeout` - per-clone timeout in ms
    * `:pipeline_timeout` - overall timeout in ms (default: 1 hour)
  """
  @spec archive(keyword()) :: {:ok, map()} | {:error, term()}
  def archive(opts) do
    username = opts[:username]
    token = opts[:token]
    output_dir = opts[:output_dir] || "./archives"
    buffer_size = opts[:buffer_size] || Config.default_buffer_size_bytes()
    pipeline_timeout = opts[:pipeline_timeout] || Config.default_pipeline_timeout_ms()

    Logger.info("Fetching repositories for #{username}...")

    case GitHubClient.list_repos(username, token: token) do
      {:ok, repos} ->
        Logger.info("Found #{length(repos)} repositories")

        repos = maybe_filter(repos, opts)

        if repos == [] do
          Logger.info("No repositories to archive after filtering.")
          {:ok, %{total: 0, successful: 0, failed: 0}}
        else
          run_pipeline(repos, username, output_dir, buffer_size, pipeline_timeout, opts)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_pipeline(repos, username, output_dir, buffer_size, pipeline_timeout, opts) do
    concurrency = Buffer.calculate_concurrency(buffer_size, repos, opts)

    Logger.info(
      "Concurrency: #{concurrency} workers (buffer budget: #{Buffer.format_size(buffer_size)})"
    )

    {:ok, ack_ref} = Acknowledger.init(length(repos), self())

    # Use a unique name to allow concurrent archive/1 calls
    pipeline_name = :"CloneEx.Pipeline.#{System.unique_integer([:positive])}"

    {:ok, pipeline_pid} =
      Pipeline.start_link(
        name: pipeline_name,
        repos: repos,
        concurrency: concurrency,
        output_dir: output_dir,
        username: username,
        caller: self(),
        ack_ref: ack_ref,
        compress_opts: Keyword.take(opts, [:compression_level, :compression_mode]),
        clone_opts: Keyword.take(opts, [:clone_timeout, :max_retries, :retry_delay_ms])
      )

    # Monitor the pipeline so we detect crashes instead of hanging forever
    mon_ref = Process.monitor(pipeline_pid)

    receive do
      {:pipeline_complete, stats} ->
        Process.demonitor(mon_ref, [:flush])
        {:ok, stats}

      {:DOWN, ^mon_ref, :process, ^pipeline_pid, reason} ->
        Logger.error("Broadway pipeline crashed: #{inspect(reason)}")
        {:error, {:pipeline_crashed, reason}}
    after
      pipeline_timeout ->
        Process.demonitor(mon_ref, [:flush])
        Logger.error("Pipeline timed out after #{pipeline_timeout}ms")
        # Attempt graceful shutdown
        if Process.alive?(pipeline_pid), do: Broadway.stop(pipeline_name)
        {:error, :pipeline_timeout}
    end
  end

  defp maybe_filter(repos, opts) do
    repos
    |> then(fn r -> if opts[:skip_forks], do: Enum.reject(r, & &1.fork), else: r end)
    |> then(fn r -> if !opts[:include_private], do: Enum.reject(r, & &1.private), else: r end)
  end
end
