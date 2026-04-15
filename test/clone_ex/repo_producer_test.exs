defmodule CloneEx.RepoProducerTest do
  use ExUnit.Case, async: true
  alias CloneEx.RepoProducer

  setup do
    # We need a valid ack_ref for message construction
    {:ok, ack_ref} = CloneEx.Acknowledger.init(10, self())
    %{ack_ref: ack_ref}
  end

  describe "init/1" do
    test "initializes with repos as a queue", %{ack_ref: ack_ref} do
      repos = [%{name: "a"}, %{name: "b"}, %{name: "c"}]

      assert {:producer, state} =
               RepoProducer.init(repos: repos, caller: self(), ack_ref: ack_ref)

      assert :queue.len(state.queue) == 3
    end

    test "initializes with empty repos", %{ack_ref: ack_ref} do
      assert {:producer, state} =
               RepoProducer.init(repos: [], caller: self(), ack_ref: ack_ref)

      assert :queue.is_empty(state.queue)
    end
  end

  describe "handle_demand/2" do
    test "returns requested number of messages when available", %{ack_ref: ack_ref} do
      repos = [%{name: "a"}, %{name: "b"}, %{name: "c"}]
      {:producer, state} = RepoProducer.init(repos: repos, caller: self(), ack_ref: ack_ref)

      {:noreply, messages, new_state} = RepoProducer.handle_demand(2, state)

      assert length(messages) == 2
      assert hd(messages).data.name == "a"
      assert List.last(messages).data.name == "b"
      assert :queue.len(new_state.queue) == 1
    end

    test "returns all remaining when demand exceeds queue size", %{ack_ref: ack_ref} do
      repos = [%{name: "a"}, %{name: "b"}]
      {:producer, state} = RepoProducer.init(repos: repos, caller: self(), ack_ref: ack_ref)

      {:noreply, messages, new_state} = RepoProducer.handle_demand(10, state)

      assert length(messages) == 2
      assert :queue.is_empty(new_state.queue)
    end

    test "returns empty list when queue is exhausted", %{ack_ref: ack_ref} do
      {:producer, state} = RepoProducer.init(repos: [], caller: self(), ack_ref: ack_ref)

      {:noreply, messages, _new_state} = RepoProducer.handle_demand(5, state)
      assert messages == []
    end

    test "messages have correct Broadway.Message structure", %{ack_ref: ack_ref} do
      repos = [%{name: "torvalds"}]
      {:producer, state} = RepoProducer.init(repos: repos, caller: self(), ack_ref: ack_ref)

      {:noreply, [msg], _state} = RepoProducer.handle_demand(1, state)

      assert %Broadway.Message{} = msg
      assert msg.data == %{name: "torvalds"}
      assert {CloneEx.Acknowledger, ^ack_ref, nil} = msg.acknowledger
    end
  end
end
