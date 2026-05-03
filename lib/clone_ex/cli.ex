defmodule CloneEx.CLI do
  @moduledoc """
  Escript entry point for CloneEx.

  Responsible for:
  1. Parsing and validating command-line arguments
  2. Resolving configuration from CLI flags and environment
  3. Executing the appropriate workflow (archive or dry-run)
  4. Displaying user-friendly output and error messages

  All validations use guard clauses where possible, and all option parsing
  uses `with/1` chains for clear error propagation.
  """

  alias CloneEx.{Buffer, Config, Log}

  @doc """
  Escript entry point. Called with command-line arguments.

  ## Return Value
  Never returns; always calls `System.halt(code)` with appropriate exit code:
  - 0: Success
  - 1: Failed to archive (some repos failed)
  - 2: Invalid arguments
  - 3: GitHub errors (not found, unauthorized)
  - 4: Unexpected errors
  """
  @spec main([String.t()]) :: no_return()
  def main(args) when is_list(args) do
    case parse_args(args) do
      {:help} ->
        print_help()
        System.halt(0)

      {:error, message} when is_binary(message) ->
        error_exit(message, 2)

      {:ok, opts} when is_list(opts) ->
        run(opts)
    end
  end

  @spec run(keyword()) :: no_return()
  defp run(opts) when is_list(opts) do
    case Application.ensure_all_started(:clone_ex) do
      {:ok, _apps} ->
        if opts[:dry_run] do
          run_dry(opts)
        else
          run_archive(opts)
        end

      {:error, reason} ->
        error_exit("Failed to start application: #{inspect(reason)}", 4)
    end
  end

  @spec run_dry(keyword()) :: no_return()
  defp run_dry(opts) when is_list(opts) do
    username = Keyword.fetch!(opts, :username)
    token = opts[:token]

    Log.info("Dry run: Fetching repos for #{username}...")

    case CloneEx.GitHubClient.list_repos(username, token: token) do
      {:ok, repos} when is_list(repos) ->
        Log.info("Found #{length(repos)} repositories.\n")
        Enum.each(repos, &print_repo/1)
        System.halt(0)

      {:error, :not_found} ->
        error_exit("User '#{username}' not found on GitHub", 3)

      {:error, :unauthorized} ->
        error_exit("Invalid GitHub token (unauthorized)", 3)

      {:error, reason} ->
        error_exit("Failed to fetch repos: #{inspect(reason)}", 4)
    end
  end

  @spec run_archive(keyword()) :: no_return()
  defp run_archive(opts) when is_list(opts) do
    IO.puts("#{IO.ANSI.bright()}CloneEx v#{CloneEx.version()}#{IO.ANSI.reset()}")

    case CloneEx.archive(opts) do
      {:ok, stats} when is_map(stats) ->
        print_summary(stats)
        exit_code = if stats.failed > 0, do: 1, else: 0
        System.halt(exit_code)

      {:error, :not_found} ->
        error_exit("User '#{Keyword.fetch!(opts, :username)}' not found on GitHub", 3)

      {:error, :unauthorized} ->
        error_exit("Invalid GitHub token (unauthorized)", 3)

      {:error, reason} ->
        error_exit("Archive failed: #{inspect(reason)}", 4)
    end
  end

  @spec print_repo(map()) :: :ok
  defp print_repo(repo) when is_map(repo) do
    size_str = Buffer.format_size((repo[:size_kb] || 0) * 1024)
    IO.puts("  - #{repo.name} (#{size_str})")
  end

  @spec print_summary(map()) :: :ok
  defp print_summary(stats) when is_map(stats) do
    IO.puts("\n#{IO.ANSI.bright()}✨ Archival Complete#{IO.ANSI.reset()}")
    IO.puts("  Total:      #{stats.total}")
    IO.puts("  Successful: #{IO.ANSI.green()}#{stats.successful}#{IO.ANSI.reset()}")

    if stats.failed > 0 do
      IO.puts("  Failed:     #{IO.ANSI.red()}#{stats.failed}#{IO.ANSI.reset()}")
    end

    IO.puts("")
  end

  @spec error_exit(String.t(), 1..4) :: no_return()
  defp error_exit(msg, code) when is_binary(msg) and code in [1, 2, 3, 4] do
    IO.puts(:stderr, "\n  #{IO.ANSI.red()}error:#{IO.ANSI.reset()} #{msg}")
    IO.puts(:stderr, "  Run with --help for usage.\n")
    System.halt(code)
  end

  @doc """
  Parses command-line arguments into an option list or error.

  Handles:
  - Help flag recognition
  - Unknown option detection
  - Required argument validation
  - Option normalization and validation

  Returns `{:help}`, `{:error, reason}`, or `{:ok, opts}`.
  """
  @spec parse_args([String.t()]) ::
          {:help} | {:error, String.t()} | {:ok, keyword()}
  def parse_args(args) when is_list(args) do
    {opts, _remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          username: :string,
          token: :string,
          buffer_size: :string,
          output_dir: :string,
          max_concurrency: :integer,
          compression_mode: :string,
          compression_level: :integer,
          skip_forks: :boolean,
          include_private: :boolean,
          clone_timeout: :integer,
          dry_run: :boolean,
          verbose: :boolean,
          help: :boolean
        ],
        aliases: [
          u: :username,
          t: :token,
          b: :buffer_size,
          o: :output_dir,
          c: :max_concurrency,
          m: :compression_mode,
          l: :compression_level,
          v: :verbose,
          h: :help
        ]
      )

    cond do
      opts[:help] ->
        {:help}

      invalid != [] ->
        flags = Enum.map_join(invalid, ", ", fn {k, _} -> k end)
        {:error, "Unknown options: #{flags}"}

      is_nil(opts[:username]) ->
        {:error, "Missing required flag: --username (-u)"}

      true ->
        validate_and_normalize(opts)
    end
  end

  @doc false
  @spec validate_and_normalize(keyword()) :: {:ok, keyword()} | {:error, String.t()}
  def validate_and_normalize(opts) when is_list(opts) do
    with {:ok, buffer_bytes} <- parse_buffer(opts[:buffer_size]),
         :ok <- validate_compression_mode(opts[:compression_mode]),
         :ok <- validate_compression_level(opts[:compression_level]) do
      # Resolve token: explicit flag > system env > application env
      token =
        opts[:token] ||
          System.get_env("GITHUB_TOKEN") ||
          Application.get_env(:clone_ex, :github_token)

      normalized =
        opts
        |> Keyword.put(:buffer_size, buffer_bytes)
        |> Keyword.put(:token, token)
        |> Keyword.put_new(:output_dir, "./archives")
        |> normalize_clone_timeout()
        |> normalize_compression_mode()

      {:ok, normalized}
    end
  end

  @spec normalize_clone_timeout(keyword()) :: keyword()
  defp normalize_clone_timeout(opts) when is_list(opts) do
    case opts[:clone_timeout] do
      nil ->
        Keyword.put_new(opts, :clone_timeout, Config.default_clone_timeout_ms())

      timeout_secs when is_integer(timeout_secs) and timeout_secs > 0 ->
        Keyword.put(opts, :clone_timeout, timeout_secs * 1000)

      _ ->
        opts
    end
  end

  @spec normalize_compression_mode(keyword()) :: keyword()
  defp normalize_compression_mode(opts) when is_list(opts) do
    case opts[:compression_mode] do
      nil ->
        opts

      mode_str when is_binary(mode_str) ->
        Keyword.put(opts, :compression_mode, String.to_atom(mode_str))

      _ ->
        opts
    end
  end

  @spec validate_compression_mode(any()) :: :ok | {:error, String.t()}
  defp validate_compression_mode(nil), do: :ok

  defp validate_compression_mode(mode) when mode in ["fast", "balanced", "high", "max"] do
    :ok
  end

  defp validate_compression_mode(mode) do
    {:error, "Invalid compression mode: #{mode}. Valid modes: fast, balanced, high, max"}
  end

  @spec parse_buffer(any()) :: {:ok, pos_integer()} | {:error, String.t()}
  defp parse_buffer(nil) do
    {:ok, Config.default_buffer_size_bytes()}
  end

  defp parse_buffer(size_str) when is_binary(size_str) do
    case Buffer.parse_size(size_str) do
      {:ok, bytes} when bytes > 0 ->
        {:ok, bytes}

      {:ok, _} ->
        {:error, "Buffer size must be greater than zero"}

      {:error, msg} ->
        {:error, msg}
    end
  end

  defp parse_buffer(other) do
    {:error, "Buffer size must be a string, got: #{inspect(other)}"}
  end

  @spec validate_compression_level(any()) :: :ok | {:error, String.t()}
  defp validate_compression_level(nil) do
    :ok
  end

  defp validate_compression_level(level) when is_integer(level) do
    min_level = Config.min_compression_level()
    max_level = Config.max_compression_level()

    if level >= min_level and level <= max_level do
      :ok
    else
      {:error,
       "Compression level must be between #{min_level} and #{max_level}, got: #{inspect(level)}"}
    end
  end

  defp validate_compression_level(level) do
    {:error, "Compression level must be an integer, got: #{inspect(level)}"}
  end

  @spec print_help() :: :ok
  defp print_help do
    IO.puts("""

      #{IO.ANSI.bright()}CloneEx v#{CloneEx.version()}#{IO.ANSI.reset()} — Broadway-powered GitHub repository archiver

      #{IO.ANSI.bright()}USAGE:#{IO.ANSI.reset()}
        clone_ex [OPTIONS]

      #{IO.ANSI.bright()}REQUIRED:#{IO.ANSI.reset()}
        -u, --username <NAME>         GitHub username to archive

      #{IO.ANSI.bright()}OPTIONS:#{IO.ANSI.reset()}
        -t, --token <TOKEN>           GitHub personal access token (or GITHUB_TOKEN env)
        -b, --buffer-size <SIZE>      Memory budget for concurrent clones (default: 1GB)
                                      Accepts: "512MB", "1GB", "2GB", etc.
        -o, --output-dir <PATH>       Output directory (default: ./archives)
        -c, --max-concurrency <N>     Max parallel clone+compress workers (default: 2×CPU cores)
        -m, --compression-mode <MODE> Compression preset (default: balanced)
                                      fast     - LZ4 (660 MB/s, 1.8x ratio)
                                      balanced - Zstd level 3 (350 MB/s, 2.8x ratio) [default]
                                      high     - Zstd level 9 (50 MB/s, 3.2x ratio)
                                      max      - Zstd level 19 (5 MB/s, 3.5x ratio)
        -l, --compression-level <N>   Zstd compression level 1-22 (overrides mode)
            --skip-forks              Skip forked repositories
            --include-private         Include private repos (requires token with repo scope)
            --clone-timeout <SECS>    Timeout per clone in seconds (default: 600)
            --dry-run                 List repos without cloning
        -v, --verbose                 Debug-level logging
        -h, --help                    Show this help

      #{IO.ANSI.bright()}EXAMPLES:#{IO.ANSI.reset()}
        # Default: balanced compression (zstd level 3)
        clone_ex -u octocat

        # Fast mode for local backups (lz4)
        clone_ex -u torvalds -m fast

        # High compression for long-term storage
        clone_ex -u torvalds -m high -b 4GB -c 12

        # Custom compression level
        clone_ex -u octocat -l 6

        # Dry run to see what would be archived
        clone_ex -u octocat --skip-forks --dry-run

      #{IO.ANSI.bright()}ENVIRONMENT:#{IO.ANSI.reset()}
        GITHUB_TOKEN                  Used when --token not provided

      #{IO.ANSI.bright()}COMPRESSION GUIDE:#{IO.ANSI.reset()}
        fast     - Best for: Local backups, fast networks (>2 Gbps)
        balanced - Best for: General use, typical internet speeds [RECOMMENDED]
        high     - Best for: Long-term storage, slow networks
        max      - Best for: Archival, when time doesn't matter
    """)
  end
end
