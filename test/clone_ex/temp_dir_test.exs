defmodule CloneEx.TempDirTest do
  use ExUnit.Case
  alias CloneEx.TempDir

  @test_base "/tmp/clone_ex_test"

  setup do
    on_exit(fn -> File.rm_rf!(@test_base) end)
    :ok
  end

  test "create/1 makes a directory that exists" do
    assert {:ok, path} = TempDir.create(@test_base)
    assert File.dir?(path)
    assert String.contains?(path, ".tmp/")
  end

  test "two creates yield different paths" do
    assert {:ok, p1} = TempDir.create(@test_base)
    assert {:ok, p2} = TempDir.create(@test_base)
    assert p1 != p2
  end

  test "cleanup/1 removes the directory" do
    assert {:ok, path} = TempDir.create(@test_base)
    File.write!(Path.join(path, "test.txt"), "data")
    assert :ok == TempDir.cleanup(path)
    refute File.dir?(path)
  end

  test "cleanup_all/1 removes everything under .tmp" do
    assert {:ok, _p1} = TempDir.create(@test_base)
    assert {:ok, _p2} = TempDir.create(@test_base)
    assert :ok == TempDir.cleanup_all(@test_base)
    refute File.dir?(Path.join(@test_base, ".tmp"))
  end

  test "cleanup on nonexistent path doesn't crash" do
    assert :ok ==
             TempDir.cleanup(
               "/tmp/nonexistent_dir_xyz_" <> Base.encode16(:crypto.strong_rand_bytes(4))
             )
  end
end
