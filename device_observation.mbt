///|
/// A backend-independent result of collecting one device metric.
pub(all) struct DeviceObservation {
  node_id : NodeId
  device_id : String
  health : NodeHealth
  metric : String
  value : Int32
  unit : String
  captured_at : Timestamp
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend DeviceObservation with @debug.Debug::{to_repr}

///|
pub extend DeviceObservation with Eq::{not_equal, equal}

///|
pub extend DeviceObservation with ToJson::{to_json}

///|
pub extend DeviceObservation with @json.FromJson::{from_json}

///|
/// Validates identity, metric, unit and collection time for any adapter.
pub fn DeviceObservation::new(
  node_id~ : NodeId,
  device_id~ : String,
  health~ : NodeHealth,
  metric~ : String,
  value~ : Int32,
  unit~ : String,
  captured_at~ : Timestamp,
) -> DeviceObservation raise AdapterError {
  if node_id.value == "" {
    raise AdapterError::EmptyNodeId
  }
  if device_id == "" {
    raise AdapterError::EmptyDeviceId
  }
  if metric == "" {
    raise AdapterError::EmptyMetric
  }
  if unit == "" {
    raise AdapterError::EmptyUnit
  }
  ensure_adapter_timestamp(captured_at)
  { node_id, device_id, health, metric, value, unit, captured_at, }
}

///|
/// Encodes the structured observation as a versioned telemetry event.
pub fn DeviceObservation::to_envelope(
  self : DeviceObservation,
  message_id~ : String,
) -> MessageEnvelope raise ProtocolError {
  MessageEnvelope::new(
    version=ProtocolVersion::current(),
    message_id~,
    node_id=self.node_id,
    created_at=self.captured_at,
    correlation_id=None,
    payload=MessagePayload::Telemetry(@json.to_json(self).stringify()),
  )
}
