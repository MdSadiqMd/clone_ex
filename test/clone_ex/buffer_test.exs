defmodule CloneEx.BufferTest do
  use ExUnit.Case
  alias CloneEx.Buffer

  describe "parse_size/1" do
    test "parses GB" do
      assert Buffer.parse_size("1GB") == {:ok, 1_073_741_824}
      assert Buffer.parse_size("1.5GB") == {:ok, 1_610_612_736}
      assert Buffer.parse_size("2 gb") == {:ok, 2_147_483_648}
    end

    test "parses MB and KB" do
      assert Buffer.parse_size("512MB") == {:ok, 536_870_912}
      assert Buffer.parse_size("1.5MB") == {:ok, 1_572_864}
      assert Buffer.parse_size("100KB") == {:ok, 102_400}
    end

    test "parses bare integers" do
      assert Buffer.parse_size("1073741824") == {:ok, 1_073_741_824}
    end

    test "returns error for invalid formats" do
      assert {:error, _} = Buffer.parse_size("wat")
      assert {:error, _} = Buffer.parse_size("")
      assert {:error, _} = Buffer.parse_size("-5GB")
      assert {:error, _} = Buffer.parse_size("1.5.0GB")
    end
  end

  describe "format_size/1" do
    test "formats sizes correctly" do
      assert Buffer.format_size(1_073_741_824) == "1.00 GB"
      assert Buffer.format_size(536_870_912) == "512.00 MB"
      assert Buffer.format_size(1_572_864) == "1.50 MB"
      assert Buffer.format_size(1024) == "1.00 KB"
      assert Buffer.format_size(500) == "500 B"
    end
  end

  describe "calculate_concurrency/3" do
    test "calculates based on average size plus overhead" do
      repos = [%{size_kb: 100_000}, %{size_kb: 200_000}]
      # avg_repo_bytes = 150_000 KB = ~153 MB
      # per_slot_bytes = ~153 MB + 50 MB overhead = ~203 MB
      # buffer = 1 GB = 1024 MB
      # slots = trunc(1024 / 203) = 5
      assert Buffer.calculate_concurrency(1_073_741_824, repos, max_concurrency: 10) == 5
    end

    test "floors to minimum 1" do
      repos = [%{size_kb: 100_000}]
      assert Buffer.calculate_concurrency(100_000, repos, max_concurrency: 10) == 1
    end

    test "caps at max_concurrency" do
      repos = [%{size_kb: 1}]
      assert Buffer.calculate_concurrency(10_000_000_000, repos, max_concurrency: 4) == 4
    end

    test "returns max_concurrency for empty repos list" do
      assert Buffer.calculate_concurrency(1_073_741_824, [], max_concurrency: 10) == 10
    end

    test "raises ArgumentError for invalid buffer_bytes" do
      repos = [%{size_kb: 100_000}]

      assert_raise ArgumentError, ~r/buffer_bytes must be a positive integer/, fn ->
        Buffer.calculate_concurrency(0, repos, max_concurrency: 10)
      end

      assert_raise ArgumentError, ~r/buffer_bytes must be a positive integer/, fn ->
        Buffer.calculate_concurrency(-1000, repos, max_concurrency: 10)
      end

      assert_raise ArgumentError, ~r/buffer_bytes must be a positive integer/, fn ->
        Buffer.calculate_concurrency("not a number", repos, max_concurrency: 10)
      end
    end
  end
end
