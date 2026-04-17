defmodule CloneEx.Log do
  @moduledoc """
  Structured logging utilities for CloneEx.

  Provides a consistent interface for logging with proper tags, metadata,
  and colored output for CLI applications. All functions automatically include
  application context and timestamps.

  ## Usage
    CloneEx.Log.info("Starting pipeline", repo: "torvalds/linux")
    CloneEx.Log.debug("Attempting retry", attempt: 2, delay_ms: 1000)
    CloneEx.Log.warn("High memory usage", used_bytes: 512_000_000)
    CloneEx.Log.error("Clone failed", reason: :enoent, url: url)
  """

  require Logger

  alias CloneEx.Buffer

  @doc """
  Logs an info message with optional metadata.

  Outputs with cyan color for CLI visibility.
  """
  @spec info(String.t(), keyword()) :: :ok
  def info(message, metadata \\ []) do
    Logger.info(colorize(:cyan, message), metadata)
    :ok
  end

  @doc """
  Logs a debug message with optional metadata.

  Only visible when logger level is :debug.
  """
  @spec debug(String.t(), keyword()) :: :ok
  def debug(message, metadata \\ []) do
    Logger.debug(message, metadata)
    :ok
  end

  @doc """
  Logs a warning message with optional metadata.

  Outputs with yellow color for CLI visibility.
  """
  @spec warn(String.t(), keyword()) :: :ok
  def warn(message, metadata \\ []) do
    Logger.warning(colorize(:yellow, message), metadata)
    :ok
  end

  @doc """
  Logs an error message with optional metadata.

  Outputs with red color for CLI visibility.
  """
  @spec error(String.t(), keyword()) :: :ok
  def error(message, metadata \\ []) do
    Logger.error(colorize(:red, message), metadata)
    :ok
  end

  @doc """
  Logs a success message with optional metadata.

  Outputs with green color for CLI visibility.
  """
  @spec success(String.t(), keyword()) :: :ok
  def success(message, metadata \\ []) do
    Logger.info(colorize(:green, message), metadata)
    :ok
  end

  @doc """
  Logs progress information with formatted data sizes and durations.

  Useful for reporting on clone/compression progress.

  ## Examples
      CloneEx.Log.progress("Clone complete",
        original_bytes: 1_000_000_000,
        duration_ms: 45_000
      )
  """
  @spec progress(String.t(), keyword()) :: :ok
  def progress(message, metrics \\ []) do
    formatted_metrics =
      metrics
      |> Enum.map(fn
        {:original_bytes, bytes} -> "original: #{Buffer.format_size(bytes)}"
        {:compressed_bytes, bytes} -> "compressed: #{Buffer.format_size(bytes)}"
        {:ratio, ratio} -> "ratio: #{Float.round(ratio, 2)}x"
        {:duration_ms, ms} -> "#{ms}ms"
        {key, val} -> "#{key}: #{val}"
      end)
      |> Enum.join(" | ")

    info("#{message} (#{formatted_metrics})")
  end

  @doc """
  Logs a series of debug measurements (typically from telemetry).

  Formats bytes and times nicely.
  """
  @spec measurements(String.t(), map()) :: :ok
  def measurements(prefix, meas_map) when is_map(meas_map) do
    formatted =
      meas_map
      |> Enum.map(fn
        {_k, v} when is_float(v) -> Float.round(v, 2) |> to_string()
        {_k, v} when is_integer(v) and v > 100_000_000 -> Buffer.format_size(v)
        {_k, v} -> to_string(v)
      end)
      |> Enum.join(" ")

    debug("#{prefix}: #{formatted}")
  end

  @spec colorize(atom(), String.t()) :: String.t()
  defp colorize(color, text) do
    ansi = ansi_color(color)
    reset = IO.ANSI.reset()
    "#{ansi}#{text}#{reset}"
  end

  @spec ansi_color(atom()) :: String.t()
  defp ansi_color(:cyan), do: IO.ANSI.cyan()
  defp ansi_color(:yellow), do: IO.ANSI.yellow()
  defp ansi_color(:red), do: IO.ANSI.red()
  defp ansi_color(:green), do: IO.ANSI.green()
end
