defmodule CloneEx.CompressorTest do
  use ExUnit.Case
  alias CloneEx.Compressor

  @test_base "/tmp/clone_ex_compressor_test"
  @source_dir Path.join(@test_base, "source")
  @output_path Path.join(@test_base, "out/test.tar.zst")

  setup do
    has_zstd = System.find_executable("zstd") != nil

    if has_zstd do
      File.rm_rf!(@test_base)
      File.mkdir_p!(@source_dir)

      content = String.duplicate("The quick brown fox jumps over the lazy dog.\n", 10_000)
      File.write!(Path.join(@source_dir, "file1.txt"), content)
      File.write!(Path.join(@source_dir, "file2.txt"), content)

      on_exit(fn -> File.rm_rf!(@test_base) end)
    end

    {:ok, has_zstd: has_zstd}
  end

  @tag :external
  test "compress/3 successfully creates a valid zstd tarball", %{has_zstd: has_zstd} do
    unless has_zstd do
      IO.puts("    [skipped] zstd binary not found")
      assert true
    else
      assert {:ok, stats} = Compressor.compress(@source_dir, @output_path, compression_level: 3)

      assert File.exists?(@output_path)
      assert stats.original_bytes > 0
      assert stats.compressed_bytes > 0
      assert stats.ratio > 1.0
      assert stats.duration_ms >= 0

      # Round-trip verification
      tar_path = Path.join(@test_base, "out/test.tar")
      {_, 0} = System.cmd("zstd", ["-d", @output_path, "-o", tar_path])
      {tar_out, 0} = System.cmd("tar", ["-tf", tar_path])
      assert String.contains?(tar_out, "file1.txt")
      assert String.contains?(tar_out, "file2.txt")
    end
  end

  test "compress/3 returns error on invalid source" do
    assert {:error, msg} =
             Compressor.compress("/path/does/not/exist", @output_path, compression_level: 3)

    assert String.contains?(msg, "Source directory does not exist")
  end

  @tag :external
  test "compress/3 cleans up intermediate tar file on success", %{has_zstd: has_zstd} do
    unless has_zstd do
      IO.puts("    [skipped] zstd binary not found")
      assert true
    else
      {:ok, _stats} = Compressor.compress(@source_dir, @output_path, compression_level: 1)
      refute File.exists?(@output_path <> ".tmp.tar")
    end
  end
end
