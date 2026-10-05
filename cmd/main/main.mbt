///|
/// Runs a node-to-control-plane offline event round trip.
fn main {
  let created_at = try! @edgeweaver.Timestamp::new(unix_seconds=100)
  let node = try! @edgeweaver.Node::new(
    id="node-demo",
    capabilities=[
      @edgeweaver.NodeCapability::Telemetry,
      @edgeweaver.NodeCapability::PersistentStorage,
    ],
    created_at~,
  )
  let control_plane = @edgeweaver.ControlPlane::new()
  let _ = try! control_plane.enroll(
    request=try! @edgeweaver.EnrollmentRequest::new(
      version=@edgeweaver.ProtocolVersion::current(),
      node_id=node.id.value,
      capabilities=node.capabilities,
      at=created_at,
    ),
  )
  let online = try! control_plane.receive_heartbeat(
    heartbeat=try! @edgeweaver.Heartbeat::new(
      version=@edgeweaver.ProtocolVersion::current(),
      node_id=node.id.value,
      health=@edgeweaver.NodeHealth::Healthy,
      at=try! @edgeweaver.Timestamp::new(unix_seconds=101),
    ),
  )

  let journal_config = try! @edgeweaver.JournalConfig::new(
    capacity=8,
    full_policy=@edgeweaver.QueueFullPolicy::RejectNew,
  )
  let store = @edgeweaver.LocalStore::new(config=journal_config)
  let _ = try! store.append_event(
    envelope=try! @edgeweaver.MessageEnvelope::new(
      version=@edgeweaver.ProtocolVersion::current(),
      message_id="demo-telemetry-001",
      node_id=node.id,
      created_at=try! @edgeweaver.Timestamp::new(unix_seconds=102),
      correlation_id=None,
      payload=@edgeweaver.MessagePayload::Telemetry("temperature=24"),
    ),
  )

  let backoff = try! @edgeweaver.BackoffPolicy::new(
    base_delay=1,
    max_delay=4,
    max_attempts=3,
  )
  let transport = try! @edgeweaver.TransportManager::new(
    protocol=@edgeweaver.ProtocolVersion::current(),
    capabilities=[
      @edgeweaver.TransportCapability::EventReplay,
      @edgeweaver.TransportCapability::Heartbeat,
    ],
    backoff~,
  )
  let _ = try! transport.begin_connect(
    at=try! @edgeweaver.Timestamp::new(unix_seconds=103),
  )
  let _ = try! transport.handshake(
    peer=@edgeweaver.CapabilityAdvertisement::new(
      protocol=@edgeweaver.ProtocolVersion::current(),
      capabilities=[
        @edgeweaver.TransportCapability::EventReplay,
        @edgeweaver.TransportCapability::Heartbeat,
      ],
    ),
  )
  let sync_config = try! @edgeweaver.SyncConfig::new(
    batch_size=4,
    max_attempts=3,
  )
  let report = try! transport.replay_pending(store, config=sync_config, sender=_message => {
    @edgeweaver.SyncSendResult::Accepted
  })

  println("EdgeWeaver node/control-plane demo")
  println("enrolled node: " + online.id.value)
  println("acknowledged events: " + report.acknowledged.to_string())
  println("pending events: " + store.pending_count().to_string())
}
