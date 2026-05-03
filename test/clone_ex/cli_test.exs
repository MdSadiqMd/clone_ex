defmodule CloneEx.CLITest do
  use ExUnit.Case, async: true
  alias CloneEx.CLI

  describe "parse_args/1 — flag parsing" do
    test "parses all standard flags" do
      args = [
        "--username",
        "octocat",
        "--token",
        "ghp_test123",
        "--buffer-size",
        "2GB",
        "--output-dir",
        "/tmp/out",
        "--max-concurrency",
        "8",
        "--compression-level",
        "3",
        "--skip-forks",
        "--include-private",
        "--clone-timeout",
        "120"
      ]

      assert {:ok, opts} = CLI.parse_args(args)
      assert opts[:username] == "octocat"
      assert opts[:token] == "ghp_test123"
      assert opts[:buffer_size] == 2_147_483_648
      assert opts[:output_dir] == "/tmp/out"
      assert opts[:max_concurrency] == 8
      assert opts[:compression_level] == 3
      assert opts[:skip_forks] == true
      assert opts[:include_private] == true
      assert opts[:clone_timeout] == 120_000
    end

    test "parses short aliases" do
      args = ["-u", "test", "-t", "tok", "-b", "512MB", "-o", "/out", "-c", "4", "-l", "1"]
      assert {:ok, opts} = CLI.parse_args(args)
      assert opts[:username] == "test"
      assert opts[:buffer_size] == 536_870_912
      assert opts[:compression_level] == 1
    end

    test "returns :help when --help present" do
      assert {:help} = CLI.parse_args(["--help"])
      assert {:help} = CLI.parse_args(["-h"])
      # --help takes precedence even with other flags
      assert {:help} = CLI.parse_args(["--help", "-u", "test"])
    end

    test "errors on missing username" do
      assert {:error, msg} = CLI.parse_args([])
      assert msg =~ "Missing required flag: --username"
    end

    test "errors on unknown flags" do
      assert {:error, msg} = CLI.parse_args(["-u", "test", "--bogus-flag", "val"])
      assert msg =~ "Unknown options"
    end
  end

  describe "parse_args/1 — validation & normalization" do
    test "defaults buffer_size to 1GB when not specified" do
      assert {:ok, opts} = CLI.parse_args(["-u", "test"])
      assert opts[:buffer_size] == 1_073_741_824
    end

    test "defaults to balanced compression mode (zstd level 3)" do
      assert {:ok, opts} = CLI.parse_args(["-u", "test"])
      # No explicit compression_level or mode means balanced mode will be used
      assert opts[:compression_level] == nil
      assert opts[:compression_mode] == nil
    end

    test "accepts compression mode" do
      assert {:ok, opts} = CLI.parse_args(["-u", "test", "-m", "fast"])
      assert opts[:compression_mode] == :fast

      assert {:ok, opts} = CLI.parse_args(["-u", "test", "--compression-mode", "high"])
      assert opts[:compression_mode] == :high
    end

    test "validates compression mode" do
      assert {:error, msg} = CLI.parse_args(["-u", "test", "-m", "invalid"])
      assert msg =~ "Invalid compression mode"
    end

    test "defaults output_dir to ./archives" do
      assert {:ok, opts} = CLI.parse_args(["-u", "test"])
      assert opts[:output_dir] == "./archives"
    end

    test "defaults clone_timeout to 600_000ms" do
      assert {:ok, opts} = CLI.parse_args(["-u", "test"])
      assert opts[:clone_timeout] == 600_000
    end

    test "rejects invalid buffer size" do
      assert {:error, msg} = CLI.parse_args(["-u", "test", "-b", "wat"])
      assert msg =~ "Cannot parse size"
    end

    test "rejects compression level out of range — too high" do
      assert {:error, msg} = CLI.parse_args(["-u", "test", "-l", "25"])
      assert msg =~ "Compression level must be between 1 and 22"
    end

    test "rejects compression level out of range — too low" do
      assert {:error, msg} = CLI.parse_args(["-u", "test", "-l", "0"])
      assert msg =~ "Compression level must be between 1 and 22"
    end

    test "parses various buffer size formats" do
      assert {:ok, opts} = CLI.parse_args(["-u", "t", "-b", "1GB"])
      assert opts[:buffer_size] == 1_073_741_824

      assert {:ok, opts} = CLI.parse_args(["-u", "t", "-b", "512MB"])
      assert opts[:buffer_size] == 536_870_912

      assert {:ok, opts} = CLI.parse_args(["-u", "t", "-b", "100KB"])
      assert opts[:buffer_size] == 102_400
    end

    test "token from flag takes precedence over env" do
      # Set env token
      Application.put_env(:clone_ex, :github_token, "env_token")

      assert {:ok, opts} = CLI.parse_args(["-u", "test", "-t", "flag_token"])
      assert opts[:token] == "flag_token"

      # Cleanup
      Application.delete_env(:clone_ex, :github_token)
    end

    test "falls back to env token when flag not provided" do
      Application.put_env(:clone_ex, :github_token, "env_token")

      assert {:ok, opts} = CLI.parse_args(["-u", "test"])
      assert opts[:token] == "env_token"

      Application.delete_env(:clone_ex, :github_token)
    end
  end
end
