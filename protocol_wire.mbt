///|
/// Errors returned before a wire message reaches domain logic.
pub(all) suberror WireError {
  TooLarge
  InvalidData
  UnsupportedVersion
} derive(Debug, Eq)

///|
pub extend WireError with @debug.Debug::{to_repr}

///|
pub extend WireError with Eq::{not_equal, equal}

///|
/// Receiver acknowledgement status; only Accepted or Duplicate permits a
/// sender to remove a pending event.
pub(all) enum WireAckStatus {
  Accepted
  Duplicate
  Rejected(String)
} derive(Eq, ToJson, FromJson)

///|
pub extend WireAckStatus with ToJson::{to_json}

///|
pub extend WireAckStatus with @json.FromJson::{from_json}

///|
pub extend WireAckStatus with Eq::{not_equal, equal}

///|
/// Version 1 request/response kinds. Strings are values, never shell text.
/// Semantic validation follows JSON decoding before dispatch.
pub(all) enum WireMessage {
  Handshake(Array[TransportCapability])
  Enroll(String, Array[NodeCapability], Timestamp)
  Heartbeat(String, NodeHealth, Timestamp)
  ConfigUpdate(String, ConfigSnapshot)
  Command(String, String, String, Timestamp)
  EventReplay(MessageEnvelope)
  Receipt(String, WireAckStatus)
  ErrorResponse(String, String)
} derive(ToJson, FromJson)

///|
pub extend WireMessage with ToJson::{to_json}

///|
pub extend WireMessage with @json.FromJson::{from_json}

///|
/// One versioned JSON frame. The transport supplies an external length prefix.
pub(all) struct WireFrame {
  version : ProtocolVersion
  message : WireMessage
} derive(ToJson, FromJson)

///|
pub extend WireFrame with ToJson::{to_json}

///|
pub extend WireFrame with @json.FromJson::{from_json}

///|
/// The maximum UTF-8 JSON payload accepted by the native transport.
pub fn wire_max_bytes() -> Int32 {
  65536
}

///|
/// Encodes a validated version 1 frame for length-delimited transport.
pub fn encode_wire(frame : WireFrame) -> String raise WireError {
  validate_wire(frame)
  let encoded = @json.to_json(frame).stringify()
  if @utf8.encode(encoded).length() > wire_max_bytes() {
    raise WireError::TooLarge
  }
  encoded
}

///|
/// Decodes one complete UTF-8 JSON frame and rejects invalid semantics.
pub fn decode_wire(content : String) -> WireFrame raise WireError {
  if @utf8.encode(content).length() > wire_max_bytes() {
    raise WireError::TooLarge
  }
  let json = @json.parse(content) catch { _ => raise WireError::InvalidData }
  let frame : WireFrame = @json.from_json(json) catch {
    _ => raise WireError::InvalidData
  }
  validate_wire(frame)
  frame
}

///|
fn validate_wire(frame : WireFrame) -> Unit raise WireError {
  if frame.version != ProtocolVersion::current() {
    raise WireError::UnsupportedVersion
  }
  match frame.message {
    WireMessage::Handshake(capabilities) =>
      if capabilities.length() == 0 {
        raise WireError::InvalidData
      }
    WireMessage::Enroll(id, _, at) =>
      if id == "" || at.unix_seconds < 0 {
        raise WireError::InvalidData
      }
    WireMessage::Heartbeat(id, _, at) =>
      if id == "" || at.unix_seconds < 0 {
        raise WireError::InvalidData
      }
    WireMessage::ConfigUpdate(id, snapshot) =>
      if id == "" ||
        snapshot.version.value <= 0 ||
        snapshot.content == "" ||
        snapshot.created_at.unix_seconds < 0 {
        raise WireError::InvalidData
      }
    WireMessage::Command(node_id, command_id, action, expires_at) =>
      if node_id == "" ||
        command_id == "" ||
        action == "" ||
        expires_at.unix_seconds < 0 {
        raise WireError::InvalidData
      }
    WireMessage::EventReplay(envelope) => {
      if envelope.node_id.value == "" || envelope.created_at.unix_seconds < 0 {
        raise WireError::InvalidData
      }
      let _ = MessageEnvelope::new(
        version=envelope.version,
        message_id=envelope.message_id,
        node_id=envelope.node_id,
        created_at=envelope.created_at,
        correlation_id=envelope.correlation_id,
        payload=envelope.payload,
      ) catch {
        _ => raise WireError::InvalidData
      }
    }
    WireMessage::Receipt(message_id, status) => {
      if message_id == "" {
        raise WireError::InvalidData
      }
      match status {
        WireAckStatus::Rejected(reason) if reason == "" =>
          raise WireError::InvalidData
        _ => ()
      }
    }
    WireMessage::ErrorResponse(code, reason) =>
      if code == "" || reason == "" {
        raise WireError::InvalidData
      }
  }
}
