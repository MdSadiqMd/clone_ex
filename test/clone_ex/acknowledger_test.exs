defmodule CloneEx.AcknowledgerTest do
  use ExUnit.Case, async: true
  alias CloneEx.Acknowledger

  describe "init/2" do
    test "returns an ack_ref tuple with atomics" do
      {:ok, {ref, pid}} = Acknowledger.init(5, self())
      assert is_reference(ref)
      assert pid == self()
    end

    test "zero total sends completion immediately" do
      {:ok, _ack_ref} = Acknowledger.init(0, self())
      assert_receive {:pipeline_complete, %{successful: 0, failed: 0, total: 0}}
    end
  end

  describe "ack/3 — basic flow" do
    test "fires completion after all successful" do
      {:ok, ack_ref} = Acknowledger.init(3, self())

      # Ack 2 — not done yet
      Acknowledger.ack(ack_ref, [make_msg(), make_msg()], [])
      refute_receive {:pipeline_complete, _}, 10

      # Ack remaining 1
      Acknowledger.ack(ack_ref, [make_msg()], [])
      assert_receive {:pipeline_complete, %{successful: 3, failed: 0, total: 3}}
    end

    test "fires completion with mixed success and failure" do
      {:ok, ack_ref} = Acknowledger.init(3, self())

      Acknowledger.ack(ack_ref, [make_msg(), make_msg()], [])
      Acknowledger.ack(ack_ref, [], [make_msg()])

      assert_receive {:pipeline_complete, %{successful: 2, failed: 1, total: 3}}
    end

    test "fires completion with all failures" do
      {:ok, ack_ref} = Acknowledger.init(2, self())

      Acknowledger.ack(ack_ref, [], [make_msg(), make_msg()])
      assert_receive {:pipeline_complete, %{successful: 0, failed: 2, total: 2}}
    end

    test "single message total" do
      {:ok, ack_ref} = Acknowledger.init(1, self())

      Acknowledger.ack(ack_ref, [make_msg()], [])
      assert_receive {:pipeline_complete, %{successful: 1, failed: 0, total: 1}}
    end
  end

  describe "ack/3 — exactly-once delivery" do
    test "completion message sent only once under concurrent acks" do
      {:ok, ack_ref} = Acknowledger.init(100, self())

      # Simulate 100 concurrent ack calls, each acking 1 message
      tasks =
        for _i <- 1..100 do
          Task.async(fn ->
            Acknowledger.ack(ack_ref, [make_msg()], [])
          end)
        end

      Task.await_many(tasks, 5000)

      # Should receive exactly one completion message
      assert_receive {:pipeline_complete, %{successful: 100, failed: 0, total: 100}}
      refute_receive {:pipeline_complete, _}, 50
    end
  end

  describe "counts/1" do
    test "returns current counter state" do
      {:ok, ack_ref} = Acknowledger.init(5, self())
      Acknowledger.ack(ack_ref, [make_msg(), make_msg()], [make_msg()])

      counts = Acknowledger.counts(ack_ref)
      assert counts.successful == 2
      assert counts.failed == 1
      assert counts.total == 5
    end
  end

  describe "configure/3" do
    test "passes through ack_ref unchanged" do
      {:ok, ack_ref} = Acknowledger.init(1, self())
      assert {:ok, ^ack_ref} = Acknowledger.configure(ack_ref, nil, [])
    end
  end

  # Helper: creates a minimal struct that has the shape Broadway expects for counting
  defp make_msg, do: %{data: :stub}
end
