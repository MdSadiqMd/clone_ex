defmodule CloneEx.Telemetry do
  @moduledoc """
  Handles telemetry events from Broadway, GitCloner, and Compressor.

  All event handlers are wrapped in `try/rescue` to prevent telemetry handler
  crashes from propagating into the calling process (which would kill Broadway
  processors or batchers).
  """
  use GenServer
  require Logger
  alias CloneEx.{Buffer, Config}

  @doc "Starts the Telemetry handler as part of the supervision tree"
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    :ok =
      :telemetry.attach_many(
        "clone_ex-handler",
        Config.telemetry_events(),
        &__MODULE__.handle_event/4,
        nil
      )

    {:ok, state}
  end

  @doc false
  def handle_event(event, measurements, metadata, config) do
    try do
      do_handle_event(event, measurements, metadata, config)
    rescue
      e ->
        Logger.error("Telemetry handler crashed for #{inspect(event)}: #{Exception.message(e)}")
    end
  end

  defp do_handle_event([:clone_ex, :clone, :start], _measurements, metadata, _config) do
    IO.puts([
      IO.ANSI.yellow(),
      "  ⟳ ",
      IO.ANSI.reset(),
      "Cloning ",
      IO.ANSI.bright(),
      to_string(metadata.repo),
      IO.ANSI.reset(),
      "..."
    ])
  end

  defp do_handle_event([:clone_ex, :clone, :stop], measurements, metadata, _config) do
    Logger.debug(
      "Cloned #{metadata.repo} (#{Buffer.format_size(measurements.size_bytes)}) in #{measurements.duration_ms}ms"
    )
  end

  defp do_handle_event([:clone_ex, :clone, :error], _measurements, metadata, _config) do
    IO.puts([
      IO.ANSI.red(),
      "  ✗ ",
      IO.ANSI.reset(),
      "Clone failed for ",
      IO.ANSI.bright(),
      to_string(metadata.repo),
      IO.ANSI.reset(),
      ": ",
      inspect(metadata.reason)
    ])
  end

  defp do_handle_event([:clone_ex, :compress, :start], _measurements, metadata, _config) do
    IO.puts([
      IO.ANSI.cyan(),
      "  ⟳ ",
      IO.ANSI.reset(),
      "Compressing ",
      IO.ANSI.bright(),
      to_string(metadata.repo),
      IO.ANSI.reset(),
      "..."
    ])
  end

  defp do_handle_event([:clone_ex, :compress, :stop], measurements, metadata, _config) do
    # Guard against non-finite ratio values
    ratio_str =
      if is_number(measurements.ratio) and measurements.ratio > 0 do
        Float.round(measurements.ratio * 1.0, 1) |> to_string()
      else
        "N/A"
      end

    IO.puts([
      IO.ANSI.green(),
      "  ✓ ",
      IO.ANSI.bright(),
      String.pad_trailing(to_string(metadata.repo), 30),
      IO.ANSI.reset(),
      Buffer.format_size(measurements.original_bytes),
      " → ",
      IO.ANSI.cyan(),
      Buffer.format_size(measurements.compressed_bytes),
      IO.ANSI.reset(),
      " (",
      ratio_str,
      "x) ",
      IO.ANSI.light_black(),
      "[",
      format_duration(measurements.duration_ms),
      "]",
      IO.ANSI.reset()
    ])
  end

  defp do_handle_event([:clone_ex, :compress, :error], _measurements, metadata, _config) do
    IO.puts([
      IO.ANSI.red(),
      "  ✗ ",
      IO.ANSI.reset(),
      "Compression failed for ",
      IO.ANSI.bright(),
      to_string(metadata.repo),
      IO.ANSI.reset(),
      ": ",
      inspect(metadata.reason)
    ])
  end

  defp do_handle_event([:clone_ex, :pipeline, :error], _measurements, metadata, _config) do
    IO.puts([
      IO.ANSI.red(),
      "  ✗ ",
      IO.ANSI.reset(),
      "Pipeline failure for ",
      IO.ANSI.bright(),
      to_string(metadata.repo),
      IO.ANSI.reset(),
      ": ",
      inspect(metadata.reason)
    ])
  end

  defp format_duration(ms) when is_integer(ms) and ms < 1000, do: "#{ms}ms"

  defp format_duration(ms) when is_integer(ms) do
    s = div(ms, 1000)

    if s < 60 do
      "#{s}s"
    else
      m = div(s, 60)
      rem_s = rem(s, 60)
      "#{m}m #{rem_s}s"
    end
  end

  defp format_duration(_), do: "?ms"
end
