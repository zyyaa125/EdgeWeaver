///|
suberror RecoveryError {
  InvalidArguments
  UnexpectedReplay
}

///|
fn main raise {
  let args = @env.args()
  if args.length() != 3 || args[2] == "" {
    println("usage: moon run cmd/recovery -- write|replay <checkpoint-path>")
    raise RecoveryError::InvalidArguments
  }
  match args[1] {
    "write" => write_pending_events(args[2])
    "replay" => replay_after_restart(args[2])
    _ => {
      println("usage: moon run cmd/recovery -- write|replay <checkpoint-path>")
      raise RecoveryError::InvalidArguments
    }
  }
}

///|
fn write_pending_events(path : String) -> Unit raise {
  let config = @edgeweaver.JournalConfig::new(
    capacity=4,
    full_policy=@edgeweaver.QueueFullPolicy::RejectNew,
  )
  let store = @edgeweaver.LocalStore::new(config~)
  let node_id = @edgeweaver.NodeId::new(value="recovery-node")
  let created_at = @edgeweaver.Timestamp::new(unix_seconds=100)
  let enrolled = @edgeweaver.Node::new(
    id=node_id.value,
    capabilities=[@edgeweaver.NodeCapability::PersistentStorage],
    created_at~,
  ).transition(
    target=@edgeweaver.NodeLifecycle::Enrolled,
    at=@edgeweaver.Timestamp::new(unix_seconds=101),
  )
  let online = enrolled
    .transition(
      target=@edgeweaver.NodeLifecycle::Online,
      at=@edgeweaver.Timestamp::new(unix_seconds=102),
    )
    .record_health(
      health=@edgeweaver.NodeHealth::Healthy,
      at=@edgeweaver.Timestamp::new(unix_seconds=103),
    )
  store.save_state(snapshot={
    node: online,
    config: Some(
      @edgeweaver.ConfigSnapshot::new(
        version=@edgeweaver.ConfigVersion::new(value=1),
        content="sampling=5s",
        created_at=@edgeweaver.Timestamp::new(unix_seconds=104),
      ),
    ),
    saved_at: @edgeweaver.Timestamp::new(unix_seconds=105),
  })
  let envelope = @edgeweaver.MessageEnvelope::new(
    version=@edgeweaver.ProtocolVersion::current(),
    message_id="recovery-event-001",
    node_id~,
    created_at=@edgeweaver.Timestamp::new(unix_seconds=100),
    correlation_id=None,
    payload=@edgeweaver.MessagePayload::Telemetry("temperature=24"),
  )
  let _ = store.append_event(envelope~)
  @disk.save_checkpoint(path, store)
  if @disk.receive_once(path + ".receipt", envelope) !=
    @edgeweaver.SyncSendResult::Accepted {
    raise RecoveryError::UnexpectedReplay
  }
  println(
    "checkpoint written; receiver accepted; local pending=\{store.pending_count()}",
  )
}

///|
fn replay_after_restart(path : String) -> Unit raise {
  let store = @disk.load_checkpoint(path)
  match store.state() {
    Some(snapshot) if snapshot.node.id.value == "recovery-node" &&
      snapshot.node.lifecycle == @edgeweaver.NodeLifecycle::Online &&
      snapshot.config != None => ()
    _ => raise RecoveryError::UnexpectedReplay
  }
  let config = @edgeweaver.SyncConfig::new(batch_size=4, max_attempts=3)
  let mut sent = 0
  let report = @edgeweaver.replay_pending(
    store,
    config~,
    cursor=@edgeweaver.SyncCursor::start(),
    sender=message => {
      sent = sent + 1
      @disk.receive_once(path + ".receipt", message)
    },
  )
  if report.acknowledged != 0 ||
    report.deduplicated != 1 ||
    sent != 1 ||
    store.pending_count() != 0 {
    raise RecoveryError::UnexpectedReplay
  }
  @disk.save_checkpoint(path, store)
  let persisted = @disk.load_checkpoint(path)
  if persisted.pending_count() != 0 {
    raise RecoveryError::UnexpectedReplay
  }
  println(
    "restarted; acknowledged=\{report.acknowledged}; deduplicated=\{report.deduplicated}; sent=\{sent}; pending=\{persisted.pending_count()}",
  )
}
