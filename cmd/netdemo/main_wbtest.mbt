///|
test "offline queue keeps stable message IDs and ordered sequences" {
  let store = @edgeweaver.LocalStore::new(
    config=try! @edgeweaver.JournalConfig::new(
      capacity=3,
      full_policy=@edgeweaver.QueueFullPolicy::RejectNew,
    ),
  )
  append_demo_event(store)
  append_demo_event(store)
  append_demo_event(store)
  let restored = try! @edgeweaver.LocalStore::restore(
    checkpoint=store.checkpoint(),
  )
  assert_eq(restored.pending_count(), 3)
  for index in 0..<3 {
    let entry = restored.pending_events()[index]
    assert_eq(entry.sequence, index + 1)
    assert_eq(
      entry.envelope.message_id,
      "network-event-" + (index + 1).to_string(),
    )
  }
}
