defmodule CloneEx.UtilsTest do
  use ExUnit.Case, async: true
  alias CloneEx.Utils

  @test_base "/tmp/clone_ex_utils_test"

  setup do
    File.rm_rf!(@test_base)
    File.mkdir_p!(@test_base)
    on_exit(fn -> File.rm_rf!(@test_base) end)
    :ok
  end

  describe "dir_size/1" do
    test "returns size of a directory with files" do
      File.write!(Path.join(@test_base, "a.txt"), String.duplicate("x", 4096))
      File.write!(Path.join(@test_base, "b.txt"), String.duplicate("y", 2048))

      size = Utils.dir_size(@test_base)
      # du reports in 1K blocks, so size should be at least 6KB
      assert size >= 6 * 1024
    end

    test "returns 0 for nonexistent path" do
      assert Utils.dir_size("/tmp/nonexistent_dir_#{:rand.uniform(999_999)}") == 0
    end
  end

  describe "dir_size_elixir/1" do
    test "calculates size via pure Elixir" do
      content = String.duplicate("z", 1000)
      File.write!(Path.join(@test_base, "file.txt"), content)

      size = Utils.dir_size_elixir(@test_base)
      assert size == 1000
    end

    test "handles nested directories" do
      nested = Path.join(@test_base, "sub")
      File.mkdir_p!(nested)
      File.write!(Path.join(nested, "deep.txt"), "deep content")

      size = Utils.dir_size_elixir(@test_base)
      assert size == byte_size("deep content")
    end

    test "returns 0 for nonexistent path" do
      assert Utils.dir_size_elixir("/tmp/nope_#{:rand.uniform(999_999)}") == 0
    end
  end
end
