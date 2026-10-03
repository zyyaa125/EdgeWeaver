///|
fn observability_time(
  seconds : Int,
) -> @edgeweaver.Timestamp raise @edgeweaver.NodeError {
  @edgeweaver.Timestamp::new(unix_seconds=seconds)
}

///|
fn observability_node() -> @edgeweaver.Node {
  let node = try! @edgeweaver.Node::new(
    id="node-diagnostics",
    capabilities=[
      @edgeweaver.NodeCapability::Telemetry,
      @edgeweaver.NodeCapability::CommandExecution,
      @edgeweaver.NodeCapability::PersistentStorage,
    ],
    created_at=try! observability_time(1),
  )
  let enrolled = try! node.transition(
    target=@edgeweaver.NodeLifecycle::Enrolled,
    at=try! observability_time(2),
  )
  let online = try! enrolled.transition(
    target=@edgeweaver.NodeLifecycle::Online,
    at=try! observability_time(3),
  )
  try! online.record_health(
    health=@edgeweaver.NodeHealth::Healthy,
    at=try! observability_time(4),
  )
}

///|
fn observability_store() -> @edgeweaver.LocalStore {
  let config = try! @edgeweaver.JournalConfig::new(
    capacity=1,
    full_policy=@edgeweaver.QueueFullPolicy::DropOldest,
  )
  let store = @edgeweaver.LocalStore::new(config~)
  let first = try! @edgeweaver.MessageEnvelope::new(
    version=@edgeweaver.ProtocolVersion::current(),
    message_id="diagnostic-event-1",
    node_id=try! @edgeweaver.NodeId::new(value="node-diagnostics"),
    created_at=try! observability_time(5),
    correlation_id=None,
    payload=@edgeweaver.MessagePayload::Telemetry("temperature=24"),
  )
  let second = try! @edgeweaver.MessageEnvelope::new(
    version=@edgeweaver.ProtocolVersion::current(),
    message_id="diagnostic-event-2",
    node_id=try! @edgeweaver.NodeId::new(value="node-diagnostics"),
    created_at=try! observability_time(6),
    correlation_id=None,
    payload=@edgeweaver.MessagePayload::Telemetry("temperature=25"),
  )
  let _ = try! store.append_event(envelope=first)
  let _ = try! store.append_event(envelope=second)
  store
}

///|
fn observability_transport() -> @edgeweaver.TransportManager {
  let backoff = try! @edgeweaver.BackoffPolicy::new(
    base_delay=1,
    max_delay=4,
    max_attempts=2,
  )
  let manager = try! @edgeweaver.TransportManager::new(
    protocol=@edgeweaver.ProtocolVersion::current(),
    capabilities=[
      @edgeweaver.TransportCapability::EventReplay,
      @edgeweaver.TransportCapability::Heartbeat,
    ],
    backoff~,
  )
  let _ = try! manager.begin_connect(at=try! observability_time(7))
  let _ = try! manager.handshake(
    peer=@edgeweaver.CapabilityAdvertisement::new(
      protocol=@edgeweaver.ProtocolVersion::current(),
      capabilities=[
        @edgeweaver.TransportCapability::EventReplay,
        @edgeweaver.TransportCapability::Heartbeat,
      ],
    ),
  )
  manager
}

///|
test "diagnostics retain a bounded structured log and latest statuses" {
  let collector = try! @edgeweaver.DiagnosticsCollector::new(max_logs=2)
  collector.record_event(
    at=try! observability_time(1),
    level=@edgeweaver.LogLevel::Debug,
    component="node",
    message="started",
  )
  collector.record_event(
    at=try! observability_time(2),
    level=@edgeweaver.LogLevel::Warn,
    component="transport",
    message="link delayed",
  )
  collector.record_sync_failure(
    at=try! observability_time(3),
    message="peer unavailable",
  )
  collector.record_policy_decision(
    at=try! observability_time(4),
    decision=@edgeweaver.PolicyDecision::SafeDefault,
  )
  let events = collector.events()
  assert_eq(events.length(), 2)
  assert_eq(events[0].component, "sync")
  assert_eq(events[0].level, @edgeweaver.LogLevel::Error)
  assert_eq(events[1].component, "policy")
  assert_eq(collector.sync_failures, 1)
  assert_eq(collector.last_sync_error, Some("peer unavailable"))
  assert_eq(
    collector.last_policy_decision,
    @edgeweaver.PolicyDecision::SafeDefault,
  )
}

///|
test "diagnostic snapshot exposes queue connection policy and execution status" {
  let node = observability_node()
  let store = observability_store()
  let transport = observability_transport()
  let allowlist = try! @edgeweaver.CommandAllowlist::new(actions=[
    @edgeweaver.AllowedAction::Execute("restart"),
  ])
  let executor = @edgeweaver.EdgeExecutor::new(node~, allowlist~)
  let collector = try! @edgeweaver.DiagnosticsCollector::new(max_logs=4)
  collector.record_sync_failure(
    at=try! observability_time(8),
    message="replay deferred",
  )
  collector.record_policy_decision(
    at=try! observability_time(9),
    decision=@edgeweaver.PolicyDecision::Execute(
      "restart-on-outage",
      @edgeweaver.CommandAction::Execute("restart"),
    ),
  )
  let snapshot = try! collector.snapshot(
    node~,
    store~,
    transport~,
    executor~,
    at=try! observability_time(10),
  )
  assert_eq(snapshot.node_id.value, "node-diagnostics")
  assert_eq(snapshot.lifecycle, @edgeweaver.NodeLifecycle::Online)
  assert_eq(snapshot.health, @edgeweaver.NodeHealth::Healthy)
  assert_eq(snapshot.pending_events, 1)
  assert_eq(snapshot.dropped_events, 1)
  assert_eq(snapshot.sync_failures, 1)
  assert_eq(snapshot.last_sync_error, Some("replay deferred"))
  assert_eq(snapshot.connection_state, @edgeweaver.ConnectionState::Connected)
  assert_eq(snapshot.negotiated_capabilities, [
    @edgeweaver.TransportCapability::EventReplay,
    @edgeweaver.TransportCapability::Heartbeat,
  ])
  assert_eq(
    snapshot.policy_decision,
    @edgeweaver.PolicyDecision::Execute(
      "restart-on-outage",
      @edgeweaver.CommandAction::Execute("restart"),
    ),
  )
  assert_eq(snapshot.execution_records, 0)
  assert_eq(snapshot.events.length(), 2)
}

///|
test "diagnostics validate limits and required event fields" {
  try @edgeweaver.DiagnosticsCollector::new(max_logs=0) catch {
    @edgeweaver.DiagnosticsError::InvalidLogLimit => ()
    _ => fail("wrong diagnostics limit error")
  } noraise {
    _ => fail("expected invalid diagnostics limit")
  }
  let collector = try! @edgeweaver.DiagnosticsCollector::new(max_logs=1)
  try
    collector.record_event(
      at=try! observability_time(1),
      level=@edgeweaver.LogLevel::Info,
      component="",
      message="message",
    )
  catch {
    @edgeweaver.DiagnosticsError::EmptyComponent => ()
    _ => fail("wrong diagnostics component error")
  } noraise {
    _ => fail("expected empty component rejection")
  }
  try
    collector.record_sync_failure(at=try! observability_time(1), message="")
  catch {
    @edgeweaver.DiagnosticsError::EmptyMessage => ()
    _ => fail("wrong diagnostics message error")
  } noraise {
    _ => fail("expected empty message rejection")
  }
}
