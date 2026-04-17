defmodule CloneEx.Config do
  @moduledoc """
  Centralized configuration for CloneEx.

  Contains all constants, default values, timeouts, and limits used throughout
  the application. Consolidating these here makes tuning and maintenance easier
  and prevents magic numbers scattered across modules.

  ## Constants

  ### Size Units
  - `kb/0` - Kilobyte in bytes (1_024)
  - `mb/0` - Megabyte in bytes (1_048_576)
  - `gb/0` - Gigabyte in bytes (1_073_741_824)

  ### Timeouts (milliseconds)
  - `default_clone_timeout_ms/0` - Per-clone operation timeout (600_000 ms = 10 min)
  - `default_pipeline_timeout_ms/0` - Overall pipeline timeout (3_600_000 ms = 1 hour)
  - `github_api_timeout_ms/0` - GitHub API request timeout (30_000 ms = 30 sec)

  ### Retries
  - `default_max_retries/0` - Maximum retry attempts (3)
  - `default_retry_delay_ms/0` - Base delay for exponential backoff (1_000 ms)
  - `default_retry_multiplier/0` - Backoff multiplier per attempt (4)
  - `default_retry_jitter/0` - Random jitter ratio (0.2 = ±20%)

  ### Buffers and Concurrency
  - `default_buffer_size_bytes/0` - Memory budget for concurrent operations (1 GB)
  - `min_buffer_size_bytes/0` - Minimum allowed buffer (256 MB)
  - `max_concurrency_limit/0` - Hard limit on concurrent workers (64)
  - `estimated_clone_size_per_worker_bytes/0` - Conservative estimate (334 MB)
  - `github_api_concurrency/0` - Concurrent page fetches (4)

  ### Compression
  - `default_compression_mode/0` - Default compression mode (:balanced)
  - `default_compression_level/0` - Default zstd level (3)
  - `max_compression_level/0` - Maximum zstd level (22)
  - `min_compression_level/0` - Minimum zstd level (1)
  - `compression_modes/0` - Supported compression modes

  ### GitHub API
  - `github_api_base_url/0` - GitHub API endpoint
  - `github_api_version/0` - GitHub API version header
  - `github_api_per_page/0` - Repos per page (30)
  - `github_api_max_pages/0` - Maximum pages to fetch (100)

  ### Files and Paths
  - `temp_dir_suffix/0` - Suffix for temporary directories (".tmp")
  - `archive_file_extension/0` - Compressed archive extension (".tar.zst")

  ### Telemetry
  - `telemetry_events/0` - List of all telemetry events
  """

  @doc "Returns one kilobyte in bytes."
  @spec kb() :: pos_integer()
  def kb, do: 1024

  @doc "Returns one megabyte in bytes."
  @spec mb() :: pos_integer()
  def mb, do: 1024 * kb()

  @doc "Returns one gigabyte in bytes."
  @spec gb() :: pos_integer()
  def gb, do: 1024 * mb()

  @doc "Default timeout for a single clone operation (10 minutes)."
  @spec default_clone_timeout_ms() :: pos_integer()
  def default_clone_timeout_ms, do: 600_000

  @doc "Default timeout for the entire pipeline (1 hour)."
  @spec default_pipeline_timeout_ms() :: pos_integer()
  def default_pipeline_timeout_ms, do: 3_600_000

  @doc "GitHub API request timeout (30 seconds)."
  @spec github_api_timeout_ms() :: pos_integer()
  def github_api_timeout_ms, do: 30_000

  @doc "Default maximum number of retry attempts."
  @spec default_max_retries() :: pos_integer()
  def default_max_retries, do: 3

  @doc "Base delay for exponential backoff in milliseconds."
  @spec default_retry_delay_ms() :: pos_integer()
  def default_retry_delay_ms, do: 1_000

  @doc "Multiplier for exponential backoff (delay * multiplier per attempt)."
  @spec default_retry_multiplier() :: pos_integer()
  def default_retry_multiplier, do: 4

  @doc "Jitter ratio for randomizing delays (e.g., 0.2 = ±20%)."
  @spec default_retry_jitter() :: float()
  def default_retry_jitter, do: 0.2

  @doc "Default memory budget for concurrent operations (1 GB)."
  @spec default_buffer_size_bytes() :: pos_integer()
  def default_buffer_size_bytes, do: 1 * gb()

  @doc "Minimum allowed buffer size (256 MB)."
  @spec min_buffer_size_bytes() :: pos_integer()
  def min_buffer_size_bytes, do: 256 * mb()

  @doc "Hard limit on concurrent workers."
  @spec max_concurrency_limit() :: pos_integer()
  def max_concurrency_limit, do: 64

  @doc "Conservative estimate of clone size per worker in bytes (334 MB)."
  @spec estimated_clone_size_per_worker_bytes() :: pos_integer()
  def estimated_clone_size_per_worker_bytes, do: trunc(334 * mb())

  @doc "Number of concurrent GitHub API page fetches."
  @spec github_api_concurrency() :: pos_integer()
  def github_api_concurrency, do: 4

  @doc "Default compression mode."
  @spec default_compression_mode() :: atom()
  def default_compression_mode, do: :balanced

  @doc "Default zstandard compression level."
  @spec default_compression_level() :: 0..22
  def default_compression_level, do: 3

  @doc "Maximum zstandard compression level."
  @spec max_compression_level() :: 1..22
  def max_compression_level, do: 22

  @doc "Minimum zstandard compression level."
  @spec min_compression_level() :: 1..22
  def min_compression_level, do: 1

  @doc """
  Returns compression mode presets.

  Each preset maps to `{algorithm, level}` tuples used by Compressor.
  """
  @spec compression_modes() :: %{
          fast: {atom(), nil},
          balanced: {atom(), 1..22},
          high: {atom(), 1..22},
          max: {atom(), 1..22}
        }
  def compression_modes do
    %{
      fast: {:lz4, nil},
      balanced: {:zstd, 3},
      high: {:zstd, 9},
      max: {:zstd, 19}
    }
  end

  @doc "GitHub REST API base URL."
  @spec github_api_base_url() :: String.t()
  def github_api_base_url, do: "https://api.github.com"

  @doc "GitHub API version string."
  @spec github_api_version() :: String.t()
  def github_api_version, do: "2022-11-28"

  @doc "Default number of repositories per API page."
  @spec github_api_per_page() :: 1..100
  def github_api_per_page, do: 30

  @doc "Maximum number of pages to fetch from GitHub API."
  @spec github_api_max_pages() :: pos_integer()
  def github_api_max_pages, do: 100

  @doc "Suffix for temporary directories."
  @spec temp_dir_suffix() :: String.t()
  def temp_dir_suffix, do: ".tmp"

  @doc "File extension for compressed archives."
  @spec archive_file_extension() :: String.t()
  def archive_file_extension, do: ".tar.zst"

  @doc "Returns all telemetry event names used by CloneEx."
  @spec telemetry_events() :: [list(atom())]
  def telemetry_events do
    [
      [:clone_ex, :clone, :start],
      [:clone_ex, :clone, :stop],
      [:clone_ex, :clone, :error],
      [:clone_ex, :compress, :start],
      [:clone_ex, :compress, :stop],
      [:clone_ex, :compress, :error],
      [:clone_ex, :pipeline, :error]
    ]
  end
end
