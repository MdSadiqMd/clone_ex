defmodule CloneEx.RetryTest do
  use ExUnit.Case
  alias CloneEx.Retry

  test "succeeds on first try" do
    assert {:ok, 42} == Retry.with_retry(fn -> {:ok, 42} end)
  end

  test "succeeds on third try" do
    counter = :counters.new(1, [])

    assert {:ok, :done} ==
             Retry.with_retry(
               fn ->
                 :counters.add(counter, 1, 1)

                 if :counters.get(counter, 1) < 3 do
                   {:error, :not_yet}
                 else
                   {:ok, :done}
                 end
               end,
               base_delay_ms: 1,
               jitter: 0.0
             )

    assert :counters.get(counter, 1) == 3
  end

  test "exhausts all attempts" do
    assert {:error, :always_fails} ==
             Retry.with_retry(
               fn -> {:error, :always_fails} end,
               max_attempts: 3,
               base_delay_ms: 1,
               jitter: 0.0
             )
  end

  test "permanent error skips retries" do
    counter = :counters.new(1, [])

    assert {:error, :fatal} ==
             Retry.with_retry(
               fn ->
                 :counters.add(counter, 1, 1)
                 {:error, :permanent, :fatal}
               end,
               base_delay_ms: 1,
               jitter: 0.0
             )

    assert :counters.get(counter, 1) == 1
  end

  test "handles exceptions by wrapping and retrying" do
    counter = :counters.new(1, [])

    assert {:error, %RuntimeError{message: "boom"}} =
             Retry.with_retry(
               fn ->
                 :counters.add(counter, 1, 1)
                 raise "boom"
               end,
               max_attempts: 2,
               base_delay_ms: 1,
               jitter: 0.0
             )

    assert :counters.get(counter, 1) == 2
  end
end
