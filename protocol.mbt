///|
/// A protocol version carried by every EdgeWeaver message.
pub(all) struct ProtocolVersion {
  major : Int
  minor : Int
} derive(Debug, Eq)

///|
/// Errors raised while validating a protocol message.
pub(all) suberror ProtocolError {
  InvalidVersion
  UnsupportedVersion(ProtocolVersion)
  EmptyMessageId
  EmptyCorrelationId
  EmptyPayload
} derive(Debug, Eq)

///|
/// Creates a non-negative protocol version.
pub fn ProtocolVersion::new(
  major~ : Int,
  minor~ : Int,
) -> ProtocolVersion raise ProtocolError {
  if major < 0 || minor < 0 {
    raise ProtocolError::InvalidVersion
  }
  { major, minor, }
}

///|
/// Returns the only protocol version currently accepted by this release.
pub fn ProtocolVersion::current() -> ProtocolVersion {
  { major: 1, minor: 0, }
}

///|
/// Rejects versions that this release cannot interpret.
pub fn ProtocolVersion::ensure_supported(
  self : ProtocolVersion,
) -> Unit raise ProtocolError {
  if self != ProtocolVersion::current() {
    raise ProtocolError::UnsupportedVersion(self)
  }
}

///|
/// The payload categories carried by the common message envelope.
pub(all) enum MessagePayload {
  Telemetry(String)
  Command(String)
  CommandResult(String)
} derive(Debug, Eq)

///|
/// A versioned message shared by telemetry and control-plane flows.
pub(all) struct MessageEnvelope {
  version : ProtocolVersion
  message_id : String
  node_id : NodeId
  created_at : Timestamp
  correlation_id : String?
  payload : MessagePayload
} derive(Debug, Eq)

///|
/// Creates a validated versioned message envelope.
pub fn MessageEnvelope::new(
  version~ : ProtocolVersion,
  message_id~ : String,
  node_id~ : NodeId,
  created_at~ : Timestamp,
  correlation_id~ : String?,
  payload~ : MessagePayload,
) -> MessageEnvelope raise ProtocolError {
  version.ensure_supported()
  if message_id == "" {
    raise ProtocolError::EmptyMessageId
  }
  match correlation_id {
    Some(value) if value == "" => raise ProtocolError::EmptyCorrelationId
    _ => ()
  }
  match payload {
    Telemetry(value) if value == "" => raise ProtocolError::EmptyPayload
    Command(value) if value == "" => raise ProtocolError::EmptyPayload
    CommandResult(value) if value == "" => raise ProtocolError::EmptyPayload
    _ => ()
  }
  { version, message_id, node_id, created_at, correlation_id, payload, }
}
