///|
fn store_time(
  seconds : Int,
) -> @edgeweaver.Timestamp raise @edgeweaver.NodeError {
  @edgeweaver.Timestamp::new(unix_seconds=seconds)
}

///|
fn store_node() -> @edgeweaver.Node raise @edgeweaver.NodeError {
  @edgeweaver.Node::new(
    id="node-store",
    capabilities=[@edgeweaver.NodeCapability::PersistentStorage],
    created_at=try! store_time(500),
  )
}

///|
fn store_event(
  message_id : String,
) -> @edgeweaver.MessageEnvelope raise @edgeweaver.ProtocolError {
  @edgeweaver.MessageEnvelope::new(
    version=@edgeweaver.ProtocolVersion::current(),
    message_id~,
    node_id=try! @edgeweaver.NodeId::new(value="node-store"),
    created_at=try! store_time(500),
    correlation_id=None,
    payload=@edgeweaver.MessagePayload::Telemetry("temperature=20"),
  )
}

///|
test "checkpoint restores local state and pending journal" {
  let config = try! @edgeweaver.ConfigVersion::new(value=1)
  let snapshot = try! @edgeweaver.ConfigSnapshot::new(
    version=config,
    content="mode=active",
    created_at=try! store_time(501),
  )
  let node = try! store_node()
  let journal_config = try! @edgeweaver.JournalConfig::new(
    capacity=2,
    full_policy=@edgeweaver.QueueFullPolicy::DropOldest,
  )
  let store = @edgeweaver.LocalStore::new(config=journal_config)
  store.save_state(snapshot={
    node,
    config: Some(snapshot),
    saved_at: try! store_time(502),
  })
  let first = try! store.append_event(envelope=try! store_event("event-001"))
  let second = try! store.append_event(envelope=try! store_event("event-002"))
  store.record_attempt(sequence=first)
  store.acknowledge(sequence=first)
  let third = try! store.append_event(envelope=try! store_event("event-003"))
  let checkpoint = store.checkpoint()
  let restored = try! @edgeweaver.LocalStore::restore(checkpoint~)
  assert_eq(restored.pending_count(), 2)
  assert_eq(restored.dropped_count(), 0)
  assert_eq(restored.pending_events()[0].sequence, second)
  assert_eq(restored.pending_events()[1].sequence, third)
  match restored.state() {
    Some(value) => {
      assert_eq(value.node.id.value, "node-store")
      assert_true(value.config is Some(_))
    }
    None => fail("expected restored state snapshot")
  }
  assert_eq(restored.journal_entries()[0].attempts, 1)
  assert_eq(
    restored.journal_entries()[0].status,
    @edgeweaver.JournalStatus::Acknowledged,
  )
  restored.record_attempt(sequence=second)
  assert_eq(checkpoint.journal[1].attempts, 0)
}

///|
test "drop-oldest policy bounds pending events and records drops" {
  let journal_config = try! @edgeweaver.JournalConfig::new(
    capacity=2,
    full_policy=@edgeweaver.QueueFullPolicy::DropOldest,
  )
  let store = @edgeweaver.LocalStore::new(config=journal_config)
  let first = try! store.append_event(envelope=try! store_event("event-101"))
  let second = try! store.append_event(envelope=try! store_event("event-102"))
  let third = try! store.append_event(envelope=try! store_event("event-103"))
  assert_eq(store.dropped_count(), 1)
  assert_eq(store.pending_count(), 2)
  assert_eq(store.pending_events()[0].sequence, second)
  assert_eq(store.pending_events()[1].sequence, third)
  try store.record_attempt(sequence=first) catch {
    @edgeweaver.StoreError::EventNotFound(sequence) =>
      assert_eq(sequence, first)
    _ => fail("wrong store error")
  } noraise {
    _ => fail("expected dropped event to be unavailable")
  }
}

///|
test "reject-new policy preserves the full queue" {
  let journal_config = try! @edgeweaver.JournalConfig::new(
    capacity=1,
    full_policy=@edgeweaver.QueueFullPolicy::RejectNew,
  )
  let store = @edgeweaver.LocalStore::new(config=journal_config)
  let first = try! store.append_event(envelope=try! store_event("event-201"))
  assert_eq(first, 1)
  try store.append_event(envelope=try! store_event("event-202")) catch {
    @edgeweaver.StoreError::QueueFull => ()
    _ => fail("wrong store error")
  } noraise {
    _ => fail("expected queue capacity rejection")
  }
  assert_eq(store.pending_count(), 1)
  assert_eq(store.dropped_count(), 0)
}

///|
test "store acknowledges idempotently and validates configuration" {
  try
    @edgeweaver.JournalConfig::new(
      capacity=0,
      full_policy=@edgeweaver.QueueFullPolicy::RejectNew,
    )
  catch {
    @edgeweaver.StoreError::InvalidCapacity => ()
    _ => fail("wrong store error")
  } noraise {
    _ => fail("expected invalid capacity rejection")
  }
  let journal_config = try! @edgeweaver.JournalConfig::new(
    capacity=1,
    full_policy=@edgeweaver.QueueFullPolicy::RejectNew,
  )
  let store = @edgeweaver.LocalStore::new(config=journal_config)
  let sequence = try! store.append_event(envelope=try! store_event("event-301"))
  store.acknowledge(sequence~)
  store.acknowledge(sequence~)
  assert_eq(store.pending_count(), 0)
  try store.acknowledge(sequence=999) catch {
    @edgeweaver.StoreError::EventNotFound(value) => assert_eq(value, 999)
    _ => fail("wrong store error")
  } noraise {
    _ => fail("expected unknown event rejection")
  }
}
