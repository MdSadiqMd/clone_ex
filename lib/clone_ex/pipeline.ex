defmodule CloneEx.Pipeline do
  @moduledoc """
  Broadway pipeline that orchestrates the concurrent cloning and compression
  of repositories.

  Each message flows through two stages:
    1. **Processor** — clones the repo into a temp directory via `GitCloner`
    2. **Batcher `:archive`** — compresses the clone into a `.tar.zst` archive

  Failed messages (clone errors, compression errors) are cleaned up and logged
  in `handle_failed/2`.
  """
  use Broadway
  require Logger
  alias CloneEx.{TempDir, GitCloner, Compressor}

  @doc """
  Starts the Broadway pipeline with dynamic naming.

  ## Required config keys
    * `:name` - unique pipeline name (atom)
    * `:repos` - list of repository maps
    * `:caller` - pid of orchestrating process
    * `:ack_ref` - initialized Acknowledger reference
    * `:concurrency` - number of concurrent processors/batchers
    * `:output_dir` - base directory for final archives
    * `:username` - GitHub username
    * `:clone_opts` - options for GitCloner
    * `:compress_opts` - options for Compressor
  """
  def start_link(config) do
    concurrency = config[:concurrency] || 4
    pipeline_name = config[:name] || __MODULE__

    Broadway.start_link(__MODULE__,
      name: pipeline_name,
      context: config,
      producer: [
        module:
          {CloneEx.RepoProducer,
           [
             repos: config[:repos],
             caller: config[:caller],
             ack_ref: config[:ack_ref]
           ]},
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: concurrency,
          max_demand: 2,
          min_demand: 1
        ]
      ],
      batchers: [
        archive: [
          concurrency: concurrency,
          batch_size: 1,
          batch_timeout: 600_000
        ]
      ]
    )
  end

  @impl true
  def handle_message(_processor, message, context) do
    repo = message.data
    clone_opts = context[:clone_opts] || []

    # 1. Create a unique temp directory
    tmp_base = context[:output_dir] || "/tmp/clone_ex"

    case TempDir.create(tmp_base) do
      {:ok, tmp_dir} ->
        dest_path = Path.join(tmp_dir, "#{repo.name}.git")

        # 2. Clone the mirror
        case GitCloner.clone_mirror(repo.clone_url, dest_path, clone_opts) do
          {:ok, mirror_path} ->
            # 3. Success → attach paths and route to batcher
            message
            |> Broadway.Message.put_data(%{
              repo: repo,
              mirror_path: mirror_path,
              tmp_dir: tmp_dir
            })
            |> Broadway.Message.put_batcher(:archive)

          {:error, reason} ->
            TempDir.cleanup(tmp_dir)
            Broadway.Message.failed(message, {:clone_failed, reason})
        end

      {:error, reason} ->
        Broadway.Message.failed(message, {:temp_dir_failed, reason})
    end
  end

  @impl true
  def handle_batch(:archive, messages, _batch_info, context) do
    output_base = context[:output_dir] || "/tmp/clone_ex"
    username = context[:username]
    compress_opts = context[:compress_opts] || []

    # Determine file extension based on compression mode
    extension =
      case compress_opts[:compression_mode] do
        :fast -> ".tar.lz4"
        _ -> ".tar.zst"
      end

    Enum.map(messages, fn msg ->
      %{repo: repo, mirror_path: mirror_path, tmp_dir: tmp_dir} = msg.data

      user_dir = Path.join(output_base, username)
      output_path = Path.join(user_dir, "#{repo.name}#{extension}")

      File.mkdir_p!(user_dir)

      case Compressor.compress(mirror_path, output_path, compress_opts) do
        {:ok, _stats} ->
          TempDir.cleanup(tmp_dir)
          msg

        {:error, reason} ->
          TempDir.cleanup(tmp_dir)
          Broadway.Message.failed(msg, {:compress_failed, reason})
      end
    end)
  end

  @impl true
  def handle_failed(messages, _context) do
    Enum.each(messages, fn msg ->
      # Ensure temp dir is cleaned up on any failure path
      case msg.data do
        %{tmp_dir: tmp_dir} when is_binary(tmp_dir) ->
          TempDir.cleanup(tmp_dir)

        _ ->
          :ok
      end

      repo_name = extract_repo_name(msg.data)
      Logger.warning("Pipeline failure for #{repo_name}: #{inspect(msg.status)}")

      :telemetry.execute([:clone_ex, :pipeline, :error], %{}, %{
        repo: repo_name,
        reason: msg.status
      })
    end)

    messages
  end

  defp extract_repo_name(%{repo: %{name: name}}), do: name
  defp extract_repo_name(%{name: name}), do: name
  defp extract_repo_name(_), do: "unknown"
end
