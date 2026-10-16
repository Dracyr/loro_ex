defmodule LoroEx.HistoryTest do
  use ExUnit.Case, async: true

  # What a host needs to keep a readable history in the oplog itself: dated
  # changes, a note each change carries, and a way to read both back.

  defp last_change(doc) do
    {peer, counter} = last_id(doc)
    LoroEx.get_change(doc, peer, counter)
  end

  defp last_id(doc) do
    peer = LoroEx.peer_id(doc)
    {peer, LoroEx.len_ops(doc) - 1}
  end

  describe "set_record_timestamp/2" do
    @tag :nif
    test "changes are undated by default and dated once it is on" do
      doc = LoroEx.new(1)
      :ok = LoroEx.map_set(doc, "m", "a", "1")
      assert {:ok, %{timestamp: 0}} = last_change(doc)

      :ok = LoroEx.set_record_timestamp(doc, true)
      :ok = LoroEx.set_change_merge_interval(doc, 0)
      :ok = LoroEx.map_set(doc, "m", "b", "2")
      assert {:ok, %{timestamp: ts}} = last_change(doc)
      assert ts > 1_700_000_000
    end
  end

  describe "set_commit_note/2" do
    @tag :nif
    test "every commit carries the note until it is cleared" do
      doc = LoroEx.new(2)
      :ok = LoroEx.set_commit_note(doc, ~s({"by":"agent:a1"}))
      :ok = LoroEx.map_set(doc, "m", "a", "1")
      :ok = LoroEx.map_set(doc, "m", "b", "2")
      assert {:ok, %{message: ~s({"by":"agent:a1"})}} = last_change(doc)
      # Identical notes let the op's many commits merge into one change.
      assert LoroEx.len_changes(doc) == 1

      :ok = LoroEx.set_commit_note(doc, nil)
      :ok = LoroEx.map_set(doc, "m", "c", "3")
      assert {:ok, %{message: nil}} = last_change(doc)
      assert LoroEx.len_changes(doc) == 2
    end

    @tag :nif
    test "a different note starts a new change" do
      doc = LoroEx.new(3)
      :ok = LoroEx.set_commit_note(doc, "one")
      :ok = LoroEx.map_set(doc, "m", "a", "1")
      :ok = LoroEx.set_commit_note(doc, "two")
      :ok = LoroEx.map_set(doc, "m", "b", "2")
      assert LoroEx.len_changes(doc) == 2
      assert {:ok, %{message: "two"}} = last_change(doc)
    end

    @tag :nif
    test "an imported change keeps its author's note, not ours" do
      a = LoroEx.new(4)
      :ok = LoroEx.set_commit_note(a, "theirs")
      :ok = LoroEx.map_set(a, "m", "a", "1")
      b = LoroEx.new(5)
      :ok = LoroEx.set_commit_note(b, "ours")
      :ok = LoroEx.apply_update(b, LoroEx.export_snapshot(a))
      assert {:ok, %{message: "theirs"}} = LoroEx.get_change(b, 4, 0)
    end
  end

  describe "get_change/3" do
    @tag :nif
    test "an id no change covers is an error" do
      doc = LoroEx.new(6)
      assert {:error, {_reason, _detail}} = LoroEx.get_change(doc, 6, 0)
    end
  end
end
