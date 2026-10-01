///|
fn sync_timestamp() -> @edgeweaver.Timestamp raise @edgeweaver.NodeError {
  @edgeweaver.Timestamp::new(unix_seconds=700)
}

///|
fn sync_event(
  message_id : String,
) -> @edgeweaver.MessageEnvelope raise @edgeweaver.ProtocolError {
  @edgeweaver.MessageEnvelope::new(
    version=@edgeweaver.ProtocolVersion::current(),
    message_id~,
    node_id=try! @edgeweaver.NodeId::new(value="node-sync"),
    created_at=try! sync_timestamp(),
    correlation_id=None,
    payload=@edgeweaver.MessagePayload::Telemetry("temperature=22"),
  )
}

///|
fn sync_store() -> @edgeweaver.LocalStore {
  let config = try! @edgeweaver.JournalConfig::new(
    capacity=8,
    full_policy=@edgeweaver.QueueFullPolicy::RejectNew,
  )
  @edgeweaver.LocalStore::new(config~)
}

///|
test "replay sends one duplicate message and deduplicates the rest" {
  let store = sync_store()
  let first = try! store.append_event(envelope=try! sync_event("event-dup"))
  let second = try! store.append_event(envelope=try! sync_event("event-dup"))
  let config = try! @edgeweaver.SyncConfig::new(batch_size=8, max_attempts=3)
  let mut calls = 0
  let report = try! @edgeweaver.replay_pending(
    store,
    config~,
    cursor=@edgeweaver.SyncCursor::start(),
    sender=_message => {
      calls = calls + 1
      @edgeweaver.SyncSendResult::Accepted
    },
  )
  assert_eq(report.inspected, 2)
  assert_eq(report.acknowledged, 1)
  assert_eq(report.deduplicated, 1)
  assert_eq(calls, 1)
  assert_eq(report.cursor.last_acked_sequence, second)
  assert_eq(store.pending_count(), 0)
  assert_eq(report.items[0].sequence, first)
  assert_eq(report.items[0].outcome, @edgeweaver.ReplayOutcome::Acknowledged)
  assert_eq(report.items[1].outcome, @edgeweaver.ReplayOutcome::Deduplicated)
}

///|
test "retryable replay keeps the event and later recovery advances cursor" {
  let store = sync_store()
  let sequence = try! store.append_event(
    envelope=try! sync_event("event-retry"),
  )
  let config = try! @edgeweaver.SyncConfig::new(batch_size=2, max_attempts=3)
  let first_report = try! @edgeweaver.replay_pending(
    store,
    config~,
    cursor=@edgeweaver.SyncCursor::start(),
    sender=_message => @edgeweaver.SyncSendResult::RetryableFailure("offline"),
  )
  assert_eq(first_report.retryable_failures, 1)
  assert_eq(first_report.cursor.last_acked_sequence, 0)
  assert_eq(first_report.items[0].attempts, 1)
  assert_eq(store.pending_count(), 1)

  let second_report = try! @edgeweaver.replay_pending(
    store,
    config~,
    cursor=first_report.cursor,
    sender=_message => @edgeweaver.SyncSendResult::Accepted,
  )
  assert_eq(second_report.acknowledged, 1)
  assert_eq(second_report.cursor.last_acked_sequence, sequence)
  assert_eq(second_report.items[0].attempts, 2)
  assert_eq(store.pending_count(), 0)
}

///|
test "remote duplicate acknowledgement is idempotent" {
  let store = sync_store()
  let sequence = try! store.append_event(
    envelope=try! sync_event("event-remote-dup"),
  )
  let config = try! @edgeweaver.SyncConfig::new(batch_size=1, max_attempts=1)
  let report = try! @edgeweaver.replay_pending(
    store,
    config~,
    cursor=@edgeweaver.SyncCursor::start(),
    sender=_message => @edgeweaver.SyncSendResult::Duplicate,
  )
  assert_eq(report.deduplicated, 1)
  assert_eq(report.acknowledged, 0)
  assert_eq(report.cursor.last_acked_sequence, sequence)
  assert_eq(store.pending_count(), 0)
}

///|
test "replay stops on exhausted attempts and validates limits" {
  try @edgeweaver.SyncConfig::new(batch_size=0, max_attempts=1) catch {
    @edgeweaver.SyncError::InvalidBatchSize => ()
    _ => fail("wrong sync error")
  } noraise {
    _ => fail("expected invalid batch size")
  }
  try @edgeweaver.SyncConfig::new(batch_size=1, max_attempts=0) catch {
    @edgeweaver.SyncError::InvalidMaxAttempts => ()
    _ => fail("wrong sync error")
  } noraise {
    _ => fail("expected invalid max attempts")
  }
  let store = sync_store()
  let sequence = try! store.append_event(
    envelope=try! sync_event("event-exhausted"),
  )
  let config = try! @edgeweaver.SyncConfig::new(batch_size=1, max_attempts=1)
  let first_report = try! @edgeweaver.replay_pending(
    store,
    config~,
    cursor=@edgeweaver.SyncCursor::start(),
    sender=_message => @edgeweaver.SyncSendResult::RetryableFailure("busy"),
  )
  assert_eq(first_report.items[0].attempts, 1)
  let second_report = try! @edgeweaver.replay_pending(
    store,
    config~,
    cursor=first_report.cursor,
    sender=_message => @edgeweaver.SyncSendResult::Accepted,
  )
  assert_eq(second_report.exhausted, 1)
  assert_eq(
    second_report.items[0].outcome,
    @edgeweaver.ReplayOutcome::Exhausted,
  )
  assert_eq(second_report.items[0].sequence, sequence)
  assert_eq(store.pending_count(), 1)
}
