defmodule CloneEx.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :clone_ex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      dialyzer: dialyzer(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Metadata
      name: "CloneEx",
      description:
        "Broadway-powered concurrent GitHub repository archiver with streaming Zstandard compression.",
      source_url: "https://github.com/MdSadiqMd/clone_ex"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {CloneEx.Application, []}
    ]
  end

  defp escript do
    [main_module: CloneEx.CLI]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ex_unit],
      flags: [:unmatched_returns, :error_handling, :no_opaque],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Pipeline orchestration (GenStage, backpressure, batching, partitioning)
      {:broadway, "~> 1.2"},

      # HTTP client middleware stack
      {:tesla, "~> 1.11"},

      # HTTP/2 connection pooling (Mint + NimblePool)
      {:finch, "~> 0.19"},

      # JSON codec for GitHub API responses
      {:jason, "~> 1.4"},

      # Compression: Uses system `tar` and `zstd` binaries instead of ezstd NIF
      # Rationale:
      #   - zstd -T0 provides multi-threaded compression (faster than single-threaded NIF)
      #   - No NIF compilation required (simpler deployment)
      #   - System binaries are battle-tested and widely available
      # Requirements: tar and zstd >= 1.4.0 must be installed on the system

      # Event dispatch for metrics and progress
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},

      # Dev/Test tooling
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
