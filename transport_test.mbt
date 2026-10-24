///|
fn transport_time(
  seconds : Int32,
) -> @edgeweaver.Timestamp raise @edgeweaver.NodeError {
  @edgeweaver.Timestamp::new(unix_seconds=seconds)
}

///|
fn transport_event(
  message_id : String,
) -> @edgeweaver.MessageEnvelope raise @edgeweaver.ProtocolError {
  @edgeweaver.MessageEnvelope::new(
    version=@edgeweaver.ProtocolVersion::current(),
    message_id~,
    node_id=try! @edgeweaver.NodeId::new(value="node-transport"),
    created_at=try! transport_time(1),
    correlation_id=None,
    payload=@edgeweaver.MessagePayload::Telemetry("temperature=23"),
  )
}

///|
fn transport_store() -> @edgeweaver.LocalStore {
  let journal = try! @edgeweaver.JournalConfig::new(
    capacity=4,
    full_policy=@edgeweaver.QueueFullPolicy::RejectNew,
  )
  @edgeweaver.LocalStore::new(config=journal)
}

///|
test "transport negotiates capabilities and applies bounded backoff" {
  let policy = try! @edgeweaver.BackoffPolicy::new(
    base_delay=2,
    max_delay=8,
    max_attempts=3,
  )
  assert_eq(try! policy.delay_for(attempt=1), 2)
  assert_eq(try! policy.delay_for(attempt=2), 4)
  assert_eq(try! policy.delay_for(attempt=5), 8)
  let manager = try! @edgeweaver.TransportManager::new(
    protocol=@edgeweaver.ProtocolVersion::current(),
    capabilities=[
      @edgeweaver.TransportCapability::EventReplay,
      @edgeweaver.TransportCapability::Heartbeat,
    ],
    backoff=policy,
  )
  manager.begin_connect(at=try! transport_time(10))
  assert_eq(manager.state(), @edgeweaver.ConnectionState::Connecting)
  manager.disconnect(at=try! transport_time(10))
  match manager.next_retry_at() {
    Some(at) => assert_eq(at.unix_seconds, 12)
    None => fail("expected retry deadline")
  }
  try manager.begin_connect(at=try! transport_time(11)) catch {
    @edgeweaver.TransportError::RetryNotReady(at) =>
      assert_eq(at.unix_seconds, 12)
    _ => fail("wrong retry readiness error")
  } noraise {
    _ => fail("expected retry window rejection")
  }
  manager.begin_connect(at=try! transport_time(12))
  let link = try! manager.handshake(
    peer=@edgeweaver.CapabilityAdvertisement::new(
      protocol=@edgeweaver.ProtocolVersion::current(),
      capabilities=[
        @edgeweaver.TransportCapability::EventReplay,
        @edgeweaver.TransportCapability::Command,
      ],
    ),
  )
  assert_eq(link.protocol, @edgeweaver.ProtocolVersion::current())
  assert_eq(link.capabilities, [@edgeweaver.TransportCapability::EventReplay])
  assert_true(
    manager.has_capability(
      capability=@edgeweaver.TransportCapability::EventReplay,
    ),
  )
  assert_true(
    !manager.has_capability(capability=@edgeweaver.TransportCapability::Command),
  )
  assert_eq(manager.state(), @edgeweaver.ConnectionState::Connected)
}

///|
test "transport rejects incompatible handshake and exhausts retries" {
  let policy = try! @edgeweaver.BackoffPolicy::new(
    base_delay=1,
    max_delay=2,
    max_attempts=2,
  )
  let manager = try! @edgeweaver.TransportManager::new(
    protocol=@edgeweaver.ProtocolVersion::current(),
    capabilities=[@edgeweaver.TransportCapability::EventReplay],
    backoff=policy,
  )
  manager.begin_connect(at=try! transport_time(1))
  let unsupported = try! @edgeweaver.ProtocolVersion::new(major=2, minor=0)
  try
    manager.handshake(
      peer=@edgeweaver.CapabilityAdvertisement::new(protocol=unsupported, capabilities=[
        @edgeweaver.TransportCapability::EventReplay,
      ]),
    )
  catch {
    @edgeweaver.TransportError::UnsupportedProtocol(version) => {
      assert_eq(version.major, 2)
      assert_eq(version.minor, 0)
    }
    _ => fail("wrong protocol handshake error")
  } noraise {
    _ => fail("expected unsupported peer protocol")
  }
  try
    manager.handshake(
      peer=@edgeweaver.CapabilityAdvertisement::new(
        protocol=@edgeweaver.ProtocolVersion::current(),
        capabilities=[@edgeweaver.TransportCapability::Heartbeat],
      ),
    )
  catch {
    @edgeweaver.TransportError::NoSharedCapability => ()
    _ => fail("wrong capability handshake error")
  } noraise {
    _ => fail("expected missing shared capability")
  }

  manager.disconnect(at=try! transport_time(1))
  manager.begin_connect(at=try! transport_time(2))
  manager.disconnect(at=try! transport_time(2))
  try manager.begin_connect(at=try! transport_time(4)) catch {
    @edgeweaver.TransportError::RetryExhausted => ()
    _ => fail("wrong retry exhaustion error")
  } noraise {
    _ => fail("expected retry exhaustion")
  }
}

///|
test "transport gates event replay until handshake capability is ready" {
  let policy = try! @edgeweaver.BackoffPolicy::new(
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
    backoff=policy,
  )
  let store = transport_store()
  let _ = try! store.append_event(
    envelope=try! transport_event("event-transport"),
  )
  let sync_config = try! @edgeweaver.SyncConfig::new(
    batch_size=2,
    max_attempts=2,
  )
  try
    manager.replay_pending(store, config=sync_config, sender=_message => {
      @edgeweaver.SyncSendResult::Accepted
    })
  catch {
    @edgeweaver.TransportError::SyncNotReady => ()
    _ => fail("wrong pre-handshake sync error")
  } noraise {
    _ => fail("expected sync gating before handshake")
  }
  manager.begin_connect(at=try! transport_time(10))
  let _ = try! manager.handshake(
    peer=@edgeweaver.CapabilityAdvertisement::new(
      protocol=@edgeweaver.ProtocolVersion::current(),
      capabilities=[@edgeweaver.TransportCapability::Heartbeat],
    ),
  )
  try
    manager.replay_pending(store, config=sync_config, sender=_message => {
      @edgeweaver.SyncSendResult::Accepted
    })
  catch {
    @edgeweaver.TransportError::SyncNotReady => ()
    _ => fail("wrong capability sync error")
  } noraise {
    _ => fail("expected event replay capability gating")
  }

  manager.disconnect(at=try! transport_time(10))
  manager.begin_connect(at=try! transport_time(11))
  let _ = try! manager.handshake(
    peer=@edgeweaver.CapabilityAdvertisement::new(
      protocol=@edgeweaver.ProtocolVersion::current(),
      capabilities=[@edgeweaver.TransportCapability::EventReplay],
    ),
  )
  let report = try! manager.replay_pending(store, config=sync_config, sender=_message => {
    @edgeweaver.SyncSendResult::Accepted
  })
  assert_eq(report.acknowledged, 1)
  assert_eq(manager.sync_cursor().last_acked_sequence, 1)
}

///|
test "transport validates backoff configuration" {
  try
    @edgeweaver.BackoffPolicy::new(base_delay=0, max_delay=1, max_attempts=1)
  catch {
    @edgeweaver.TransportError::InvalidBaseDelay => ()
    _ => fail("wrong base delay error")
  } noraise {
    _ => fail("expected invalid base delay")
  }
  try
    @edgeweaver.BackoffPolicy::new(base_delay=3, max_delay=2, max_attempts=1)
  catch {
    @edgeweaver.TransportError::InvalidMaxDelay => ()
    _ => fail("wrong max delay error")
  } noraise {
    _ => fail("expected invalid max delay")
  }
  try
    @edgeweaver.BackoffPolicy::new(base_delay=1, max_delay=2, max_attempts=0)
  catch {
    @edgeweaver.TransportError::InvalidAttemptLimit => ()
    _ => fail("wrong attempt limit error")
  } noraise {
    _ => fail("expected invalid attempt limit")
  }
}

///|
test "injected transport preserves pending event on alien receipt and timeout" {
  let manager = try! @edgeweaver.TransportManager::new(
    protocol=@edgeweaver.ProtocolVersion::current(),
    capabilities=[@edgeweaver.TransportCapability::EventReplay],
    backoff=try! @edgeweaver.BackoffPolicy::new(
      base_delay=1,
      max_delay=4,
      max_attempts=3,
    ),
  )
  let mut response = 0
  let adapter = @edgeweaver.TransportAdapter::{
    connect: () => @edgeweaver.TransportIoResult::Ready,
    close: () => (),
    exchange: _advertisement => {
      @edgeweaver.TransportHandshakeResult::Peer(
        @edgeweaver.CapabilityAdvertisement::new(
          protocol=@edgeweaver.ProtocolVersion::current(),
          capabilities=[@edgeweaver.TransportCapability::EventReplay],
        ),
      )
    },
    send_batch: _batch => {
      response = response + 1
      if response == 1 {
        @edgeweaver.TransportBatchResult::Receipts([
          {
            message_id: "wrong-id",
            result: @edgeweaver.SyncSendResult::Accepted,
          },
        ])
      } else if response == 2 {
        @edgeweaver.TransportBatchResult::Timeout
      } else {
        @edgeweaver.TransportBatchResult::Receipts([
          {
            message_id: "event-adapter",
            result: @edgeweaver.SyncSendResult::Duplicate,
          },
        ])
      }
    },
  }
  let _ = try! manager.connect_with(adapter~, at=try! transport_time(10))
  let store = transport_store()
  let _ = try! store.append_event(
    envelope=try! transport_event("event-adapter"),
  )
  let config = try! @edgeweaver.SyncConfig::new(batch_size=1, max_attempts=3)
  let first = try! manager.replay_with(store, config~, adapter~)
  assert_eq(first.retryable_failures, 1)
  assert_eq(store.pending_count(), 1)
  let second = try! manager.replay_with(store, config~, adapter~)
  assert_eq(second.retryable_failures, 1)
  assert_eq(store.pending_count(), 1)
  let third = try! manager.replay_with(store, config~, adapter~)
  assert_eq(third.deduplicated, 1)
  assert_eq(store.pending_count(), 0)
}

///|
test "injected handshake rejects incompatible version and backs off" {
  let manager = try! @edgeweaver.TransportManager::new(
    protocol=@edgeweaver.ProtocolVersion::current(),
    capabilities=[@edgeweaver.TransportCapability::EventReplay],
    backoff=try! @edgeweaver.BackoffPolicy::new(
      base_delay=2,
      max_delay=4,
      max_attempts=2,
    ),
  )
  let mut closes = 0
  let adapter = @edgeweaver.TransportAdapter::{
    connect: () => @edgeweaver.TransportIoResult::Ready,
    close: () => closes = closes + 1,
    exchange: _advertisement => {
      @edgeweaver.TransportHandshakeResult::Peer(
        @edgeweaver.CapabilityAdvertisement::new(
          protocol=try! @edgeweaver.ProtocolVersion::new(major=2, minor=0),
          capabilities=[@edgeweaver.TransportCapability::EventReplay],
        ),
      )
    },
    send_batch: _batch => @edgeweaver.TransportBatchResult::Timeout,
  }
  try manager.connect_with(adapter~, at=try! transport_time(5)) catch {
    @edgeweaver.TransportError::UnsupportedProtocol(_) => ()
    _ => fail("wrong handshake failure")
  } noraise {
    _ => fail("incompatible peer accepted")
  }
  assert_eq(closes, 1)
  assert_eq(manager.state(), @edgeweaver.ConnectionState::Backoff)
  try manager.begin_connect(at=try! transport_time(6)) catch {
    @edgeweaver.TransportError::RetryNotReady(_) => ()
    _ => fail("wrong retry window")
  } noraise {
    _ => fail("retry started before deadline")
  }
}
