defmodule CloneEx.PipelineTest do
  use ExUnit.Case
  alias CloneEx.Pipeline

  @test_base "/tmp/clone_ex_pipeline_test"

  setup do
    File.rm_rf!(@test_base)
    on_exit(fn -> File.rm_rf!(@test_base) end)
    :ok
  end

  test "pipeline orchestrates end-to-end — clone failure path" do
    repos = [%{name: "repo1", clone_url: "https://invalid.test/repo1.git", size_kb: 100}]

    # Initialize acknowledger
    {:ok, ack_ref} = CloneEx.Acknowledger.init(1, self())

    # Use unique name to prevent test conflicts
    pipeline_name = :"CloneEx.Pipeline.Test.#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Pipeline.start_link(
               name: pipeline_name,
               repos: repos,
               caller: self(),
               ack_ref: ack_ref,
               output_dir: @test_base,
               concurrency: 1,
               username: "testuser",
               clone_opts: [max_retries: 1, retry_delay_ms: 10, timeout: 5_000]
             )

    # GitCloner will fail (invalid URL), failure should reach the acknowledger
    assert_receive {:pipeline_complete, %{failed: 1, successful: 0, total: 1}}, 30_000

    # Brief wait for Broadway cleanup lifecycle
    Process.sleep(200)

    # Verify temp dir cleanup on failure
    tmp_path = Path.join(@test_base, ".tmp")

    if File.dir?(tmp_path) do
      assert File.ls!(tmp_path) == []
    end
  end

  test "pipeline handles multiple repos with failures" do
    repos = [
      %{name: "repo1", clone_url: "https://invalid.test/repo1.git", size_kb: 50},
      %{name: "repo2", clone_url: "https://invalid.test/repo2.git", size_kb: 50}
    ]

    {:ok, ack_ref} = CloneEx.Acknowledger.init(2, self())
    pipeline_name = :"CloneEx.Pipeline.Test.#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Pipeline.start_link(
               name: pipeline_name,
               repos: repos,
               caller: self(),
               ack_ref: ack_ref,
               output_dir: @test_base,
               concurrency: 2,
               username: "testuser",
               clone_opts: [max_retries: 1, retry_delay_ms: 10, timeout: 5_000]
             )

    assert_receive {:pipeline_complete, %{failed: 2, successful: 0, total: 2}}, 30_000
  end
end
