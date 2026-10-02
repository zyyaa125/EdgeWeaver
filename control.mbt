///|
/// Errors raised by the node enrollment and heartbeat flow.
pub(all) suberror ControlError {
  EmptyNodeId
  InvalidTimestamp
  UnsupportedProtocol(ProtocolVersion)
  DuplicateNode(NodeId)
  UnknownNode(NodeId)
  NodeNotEnrolled(NodeId)
  RetiredNode(NodeId)
  StaleHeartbeat
} derive(Debug, Eq)

///|
/// A request to register one node with the control plane.
pub(all) struct EnrollmentRequest {
  version : ProtocolVersion
  node_id : String
  capabilities : Array[NodeCapability]
  at : Timestamp
} derive(Debug, Eq)

///|
/// Creates an enrollment request with a non-empty identity.
pub fn EnrollmentRequest::new(
  version~ : ProtocolVersion,
  node_id~ : String,
  capabilities~ : Array[NodeCapability],
  at~ : Timestamp,
) -> EnrollmentRequest raise ControlError {
  if node_id == "" {
    raise ControlError::EmptyNodeId
  }
  { version, node_id, capabilities, at, }
}

///|
/// A liveness and health observation sent by an enrolled node.
pub(all) struct Heartbeat {
  version : ProtocolVersion
  node_id : String
  health : NodeHealth
  at : Timestamp
} derive(Debug, Eq)

///|
/// Creates a heartbeat with a non-empty node identity.
pub fn Heartbeat::new(
  version~ : ProtocolVersion,
  node_id~ : String,
  health~ : NodeHealth,
  at~ : Timestamp,
) -> Heartbeat raise ControlError {
  if node_id == "" {
    raise ControlError::EmptyNodeId
  }
  { version, node_id, health, at, }
}

///|
/// In-memory control-plane registry for enrolled nodes.
pub(all) struct ControlPlane {
  mut nodes : Array[Node]
} derive(Debug, Eq)

///|
/// Creates an empty control-plane registry.
pub fn ControlPlane::new() -> ControlPlane {
  { nodes: [], }
}

///|
/// Registers a node and places it in the Enrolled lifecycle state.
pub fn ControlPlane::enroll(
  self : ControlPlane,
  request~ : EnrollmentRequest,
) -> Node raise ControlError {
  ensure_supported(request.version)
  ensure_timestamp(request.at)
  if request.node_id == "" {
    raise ControlError::EmptyNodeId
  }
  let node_id : NodeId = { value: request.node_id, }
  for node in self.nodes {
    if node.id == node_id {
      raise ControlError::DuplicateNode(node_id)
    }
  }
  let node = {
    id: node_id,
    capabilities: request.capabilities,
    lifecycle: NodeLifecycle::Enrolled,
    health: NodeHealth::Unknown,
    created_at: request.at,
    updated_at: request.at,
  }
  self.nodes.push(node)
  node
}

///|
/// Applies a heartbeat and moves an enrolled or offline node online.
pub fn ControlPlane::receive_heartbeat(
  self : ControlPlane,
  heartbeat~ : Heartbeat,
) -> Node raise ControlError {
  ensure_supported(heartbeat.version)
  ensure_timestamp(heartbeat.at)
  let node_id = control_node_id(heartbeat.node_id)
  let index = self.find_index(node_id~)
  match index {
    None => raise ControlError::UnknownNode(node_id)
    Some(index) => {
      let current = self.nodes[index]
      if current.lifecycle == NodeLifecycle::Retired {
        raise ControlError::RetiredNode(node_id)
      }
      if heartbeat.at.unix_seconds < current.updated_at.unix_seconds {
        raise ControlError::StaleHeartbeat
      }
      let lifecycle = match current.lifecycle {
        NodeLifecycle::Enrolled => NodeLifecycle::Online
        NodeLifecycle::Offline => NodeLifecycle::Online
        NodeLifecycle::Online => NodeLifecycle::Online
        NodeLifecycle::New => raise ControlError::NodeNotEnrolled(node_id)
        NodeLifecycle::Retired => raise ControlError::RetiredNode(node_id)
      }
      let updated = {
        id: current.id,
        capabilities: current.capabilities,
        lifecycle,
        health: heartbeat.health,
        created_at: current.created_at,
        updated_at: heartbeat.at,
      }
      self.nodes[index] = updated
      updated
    }
  }
}

///|
/// Marks an enrolled node offline after a missed heartbeat window.
pub fn ControlPlane::mark_offline(
  self : ControlPlane,
  node_id~ : NodeId,
  at~ : Timestamp,
) -> Node raise ControlError {
  ensure_timestamp(at)
  let index = self.find_index(node_id~)
  match index {
    None => raise ControlError::UnknownNode(node_id)
    Some(index) => {
      let current = self.nodes[index]
      if current.lifecycle == NodeLifecycle::Retired {
        raise ControlError::RetiredNode(node_id)
      }
      if at.unix_seconds < current.updated_at.unix_seconds {
        raise ControlError::StaleHeartbeat
      }
      let updated = {
        id: current.id,
        capabilities: current.capabilities,
        lifecycle: match current.lifecycle {
          NodeLifecycle::Enrolled => NodeLifecycle::Offline
          NodeLifecycle::Online => NodeLifecycle::Offline
          NodeLifecycle::Offline => NodeLifecycle::Offline
          NodeLifecycle::New => raise ControlError::NodeNotEnrolled(node_id)
          NodeLifecycle::Retired => raise ControlError::RetiredNode(node_id)
        },
        health: current.health,
        created_at: current.created_at,
        updated_at: at,
      }
      self.nodes[index] = updated
      updated
    }
  }
}

///|
/// Looks up an enrolled node by its stable identity.
pub fn ControlPlane::lookup(self : ControlPlane, node_id~ : NodeId) -> Node? {
  for node in self.nodes {
    if node.id == node_id {
      return Some(node)
    }
  }
  None
}

///|
fn ensure_supported(version : ProtocolVersion) -> Unit raise ControlError {
  if version != ProtocolVersion::current() {
    raise ControlError::UnsupportedProtocol(version)
  }
}

///|
fn ensure_timestamp(at : Timestamp) -> Unit raise ControlError {
  if at.unix_seconds < 0 {
    raise ControlError::InvalidTimestamp
  }
}

///|
fn control_node_id(value : String) -> NodeId raise ControlError {
  if value == "" {
    raise ControlError::EmptyNodeId
  }
  { value, }
}

///|
fn ControlPlane::find_index(self : ControlPlane, node_id~ : NodeId) -> Int? {
  for index in 0..<self.nodes.length() {
    if self.nodes[index].id == node_id {
      return Some(index)
    }
  }
  None
}
