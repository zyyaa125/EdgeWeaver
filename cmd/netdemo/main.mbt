///|
suberror NetworkDemoError {
  InvalidArguments
  UnexpectedMessage
  UnexpectedAck
  PendingRecovery
  ReconnectExhausted
}

///|
fn main raise {
  let args = @env.args()
  if args.length() == 6 && args[1] == "serve" {
    let port = @string.parse_int(args[2].view())
    let sessions = @string.parse_int(args[4].view())
    let timeout_ms = @string.parse_int(args[5].view())
    if sessions <= 0 || timeout_ms <= 0 {
      raise NetworkDemoError::InvalidArguments
    }
    serve(port, args[3], sessions, timeout_ms)
  } else if args.length() == 4 && args[1] == "queue" {
    let count = @string.parse_int(args[3].view())
    if count <= 0 {
      raise NetworkDemoError::InvalidArguments
    }
    queue_events(args[2], count)
  } else if args.length() == 5 &&
    (args[1] == "send" || args[1] == "replay" || args[1] == "drain") {
    let port = @string.parse_int(args[2].view())
    let timeout_ms = @string.parse_int(args[4].view())
    if timeout_ms <= 0 {
      raise NetworkDemoError::InvalidArguments
    }
    if args[1] == "drain" {
      drain_events(port, args[3], timeout_ms)
    } else {
      send(args[1], port, args[3], timeout_ms)
    }
  } else {
    println(
      "usage: serve <port> <receipt-path> <sessions> <timeout-ms> | queue <checkpoint-path> <count> | send|replay|drain <port> <checkpoint-path> <timeout-ms>",
    )
    raise NetworkDemoError::InvalidArguments
  }
}

///|
fn frame(message : @edgeweaver.WireMessage) -> @edgeweaver.WireFrame {
  { version: @edgeweaver.ProtocolVersion::current(), message, }
}

///|
fn now(value : Int32) -> @edgeweaver.Timestamp raise {
  @edgeweaver.Timestamp::new(unix_seconds=value)
}

///|
fn serve(
  port : Int32,
  receipt_path : String,
  sessions : Int32,
  timeout_ms : Int32,
) -> Unit raise {
  let listener = @network.listen(port)
  let control = @edgeweaver.ControlPlane::new()
  println("control listening on 127.0.0.1:" + port.to_string())
  for _ in 0..<sessions {
    let socket = listener.accept(timeout_ms~)
    serve_session(socket, control, receipt_path)
    socket.close()
  }
  listener.close()
  println("control sessions=" + sessions.to_string())
}

///|
fn serve_session(
  socket : @network.Socket,
  control : @edgeweaver.ControlPlane,
  receipt_path : String,
) -> Unit raise {
  let hello = socket.receive()
  match hello.message {
    @edgeweaver.WireMessage::Handshake(capabilities) => {
      let mut replay = false
      let mut heartbeat = false
      for capability in capabilities {
        if capability == @edgeweaver.TransportCapability::EventReplay {
          replay = true
        }
        if capability == @edgeweaver.TransportCapability::Heartbeat {
          heartbeat = true
        }
      }
      if !replay || !heartbeat {
        socket.send(
          frame(
            @edgeweaver.WireMessage::ErrorResponse(
              "capability", "EventReplay and Heartbeat required",
            ),
          ),
        )
        raise NetworkDemoError::UnexpectedMessage
      }
      socket.send(
        frame(
          @edgeweaver.WireMessage::Handshake([
            @edgeweaver.TransportCapability::EventReplay,
            @edgeweaver.TransportCapability::Heartbeat,
          ]),
        ),
      )
    }
    _ => raise NetworkDemoError::UnexpectedMessage
  }
  let enrollment = socket.receive()
  let node_id = match enrollment.message {
    @edgeweaver.WireMessage::Enroll(id, capabilities, at) => {
      match control.lookup(node_id=@edgeweaver.NodeId::new(value=id)) {
        Some(_) => ()
        None => {
          let _ = control.enroll(
            request=@edgeweaver.EnrollmentRequest::new(
              version=enrollment.version,
              node_id=id,
              capabilities~,
              at~,
            ),
          )
        }
      }
      id
    }
    _ => raise NetworkDemoError::UnexpectedMessage
  }
  socket.send(
    frame(
      @edgeweaver.WireMessage::Receipt(
        "enroll:" + node_id,
        @edgeweaver.WireAckStatus::Accepted,
      ),
    ),
  )
  let heartbeat = socket.receive()
  match heartbeat.message {
    @edgeweaver.WireMessage::Heartbeat(id, health, at) if id == node_id => {
      let _ = control.receive_heartbeat(
        heartbeat=@edgeweaver.Heartbeat::new(
          version=heartbeat.version,
          node_id=id,
          health~,
          at~,
        ),
      )
    }
    _ => raise NetworkDemoError::UnexpectedMessage
  }
  socket.send(
    frame(
      @edgeweaver.WireMessage::Receipt(
        "heartbeat:" + node_id,
        @edgeweaver.WireAckStatus::Accepted,
      ),
    ),
  )
  let event = socket.receive()
  match event.message {
    @edgeweaver.WireMessage::EventReplay(envelope) if envelope.node_id.value ==
      node_id =>
      match @disk.receive_once(receipt_path, envelope) {
        @edgeweaver.SyncSendResult::Accepted =>
          socket.send(
            frame(
              @edgeweaver.WireMessage::Receipt(
                envelope.message_id,
                @edgeweaver.WireAckStatus::Accepted,
              ),
            ),
          )
        @edgeweaver.SyncSendResult::Duplicate =>
          socket.send(
            frame(
              @edgeweaver.WireMessage::Receipt(
                envelope.message_id,
                @edgeweaver.WireAckStatus::Duplicate,
              ),
            ),
          )
        _ =>
          socket.send(
            frame(
              @edgeweaver.WireMessage::ErrorResponse(
                "storage", "durable receipt unavailable",
              ),
            ),
          )
      }
    _ => raise NetworkDemoError::UnexpectedMessage
  }
}

///|
fn expect_receipt(
  socket : @network.Socket,
  expected_id : String,
) -> @edgeweaver.WireAckStatus raise {
  let response = socket.receive()
  match response.message {
    @edgeweaver.WireMessage::Receipt(message_id, status) if message_id ==
      expected_id => status
    _ => raise NetworkDemoError::UnexpectedAck
  }
}

///|
fn send(
  mode : String,
  port : Int32,
  path : String,
  timeout_ms : Int32,
) -> Unit raise {
  let store = if mode == "send" {
    let current = load_or_new_store(path)
    if current.pending_count() != 0 {
      raise NetworkDemoError::PendingRecovery
    }
    append_demo_event(current)
    @disk.save_checkpoint(path, current)
    current
  } else {
    @disk.load_checkpoint(path)
  }
  if store.pending_count() != 1 {
    raise NetworkDemoError::PendingRecovery
  }
  let entry = store.pending_events()[0]
  let status = exchange_one(port, timeout_ms, entry.envelope)
  if mode == "send" {
    if status != @edgeweaver.WireAckStatus::Accepted {
      raise NetworkDemoError::UnexpectedAck
    }
    println(
      "remote accepted; local pending=" + store.pending_count().to_string(),
    )
  } else {
    match status {
      @edgeweaver.WireAckStatus::Accepted
      | @edgeweaver.WireAckStatus::Duplicate => ()
      _ => raise NetworkDemoError::UnexpectedAck
    }
    store.acknowledge(sequence=entry.sequence)
    @disk.save_checkpoint(path, store)
    let outcome = match status {
      @edgeweaver.WireAckStatus::Duplicate => "duplicate"
      _ => "accepted"
    }
    println(
      "remote " +
      outcome +
      "; local pending=" +
      store.pending_count().to_string(),
    )
  }
}

///|
fn load_or_new_store(path : String) -> @edgeweaver.LocalStore raise {
  match @disk.load_checkpoint_if_exists(path) {
    Some(existing) => existing
    None =>
      @edgeweaver.LocalStore::new(
        config=@edgeweaver.JournalConfig::new(
          capacity=4,
          full_policy=@edgeweaver.QueueFullPolicy::RejectNew,
        ),
      )
  }
}

///|
fn append_demo_event(store : @edgeweaver.LocalStore) -> Unit raise {
  let sequence = store.checkpoint().next_sequence
  let _ = store.append_event(
    envelope=@edgeweaver.MessageEnvelope::new(
      version=@edgeweaver.ProtocolVersion::current(),
      message_id="network-event-" + sequence.to_string(),
      node_id=@edgeweaver.NodeId::new(value="network-node"),
      created_at=now(102),
      correlation_id=None,
      payload=@edgeweaver.MessagePayload::Telemetry(
        "sample=" + sequence.to_string(),
      ),
    ),
  )
}

///|
fn queue_events(path : String, count : Int32) -> Unit raise {
  let store = load_or_new_store(path)
  for _ in 0..<count {
    append_demo_event(store)
    @disk.save_checkpoint(path, store)
  }
  println("queued pending=" + store.pending_count().to_string())
}

///|
fn drain_events(port : Int32, path : String, timeout_ms : Int32) -> Unit raise {
  let store = @disk.load_checkpoint(path)
  let backoff = @edgeweaver.BackoffPolicy::new(
    base_delay=1,
    max_delay=4,
    max_attempts=3,
  )
  let mut failures = 0
  let mut sent = 0
  while store.pending_count() > 0 {
    let entry = store.pending_events()[0]
    let mut retryable = false
    let status = exchange_one(port, timeout_ms, entry.envelope) catch {
      @network.NetworkError::ConnectFailed
      | @network.NetworkError::ReadFailed
      | @network.NetworkError::WriteFailed => {
        retryable = true
        @edgeweaver.WireAckStatus::Rejected("transport unavailable")
      }
      error => raise error
    }
    if retryable {
      failures = failures + 1
      if failures >= backoff.max_attempts {
        raise NetworkDemoError::ReconnectExhausted
      }
      @network.pause(backoff.delay_for(attempt=failures) * 1000)
      continue
    }
    failures = 0
    match status {
      @edgeweaver.WireAckStatus::Accepted
      | @edgeweaver.WireAckStatus::Duplicate => ()
      _ => raise NetworkDemoError::UnexpectedAck
    }
    store.acknowledge(sequence=entry.sequence)
    @disk.save_checkpoint(path, store)
    sent = sent + 1
  }
  println("drained=" + sent.to_string() + "; pending=0")
}

///|
fn exchange_one(
  port : Int32,
  timeout_ms : Int32,
  envelope : @edgeweaver.MessageEnvelope,
) -> @edgeweaver.WireAckStatus raise {
  let socket = @network.connect(port, timeout_ms~)
  socket.send(
    frame(
      @edgeweaver.WireMessage::Handshake([
        @edgeweaver.TransportCapability::EventReplay,
        @edgeweaver.TransportCapability::Heartbeat,
      ]),
    ),
  )
  match socket.receive().message {
    @edgeweaver.WireMessage::Handshake(_) => ()
    _ => raise NetworkDemoError::UnexpectedMessage
  }
  socket.send(
    frame(
      @edgeweaver.WireMessage::Enroll(
        "network-node",
        [@edgeweaver.NodeCapability::Telemetry],
        now(100),
      ),
    ),
  )
  match expect_receipt(socket, "enroll:network-node") {
    @edgeweaver.WireAckStatus::Accepted => ()
    _ => raise NetworkDemoError::UnexpectedAck
  }
  socket.send(
    frame(
      @edgeweaver.WireMessage::Heartbeat(
        "network-node",
        @edgeweaver.NodeHealth::Healthy,
        now(101),
      ),
    ),
  )
  match expect_receipt(socket, "heartbeat:network-node") {
    @edgeweaver.WireAckStatus::Accepted => ()
    _ => raise NetworkDemoError::UnexpectedAck
  }
  socket.send(frame(@edgeweaver.WireMessage::EventReplay(envelope)))
  let status = expect_receipt(socket, envelope.message_id)
  socket.close()
  status
}
