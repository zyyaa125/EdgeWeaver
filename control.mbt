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
  StaleConfig(ConfigVersion)
  DuplicateCommand(CommandId)
  UnknownCommand(CommandId)
  CommandTargetMismatch(CommandId)
  CommandTransition(CommandError)
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
/// A versioned configuration accepted for one node.
pub(all) struct ConfigDelivery {
  node_id : NodeId
  snapshot : ConfigSnapshot
  delivered_at : Timestamp
} derive(Debug, Eq)

///|
/// A lifecycle update requested for a tracked command.
pub(all) enum CommandUpdate {
  Accept
  Start
  Succeed(String)
  Fail(String)
  Reject(String)
  Expire
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
  mut configs : Array[ConfigDelivery]
  mut commands : Array[Command]
} derive(Debug, Eq)

///|
/// Creates an empty control-plane registry.
pub fn ControlPlane::new() -> ControlPlane {
  { nodes: [], configs: [], commands: [], }
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
/// Accepts a newer configuration version for a registered node.
pub fn ControlPlane::deliver_config(
  self : ControlPlane,
  node_id~ : NodeId,
  snapshot~ : ConfigSnapshot,
  at~ : Timestamp,
) -> ConfigDelivery raise ControlError {
  ensure_node_id(node_id)
  ensure_timestamp(at)
  match self.find_index(node_id~) {
    None => raise ControlError::UnknownNode(node_id)
    Some(index) =>
      if self.nodes[index].lifecycle == NodeLifecycle::Retired {
        raise ControlError::RetiredNode(node_id)
      }
  }
  match self.find_config_index(node_id~) {
    Some(index) => {
      let current = self.configs[index]
      if !snapshot.supersedes(previous=current.snapshot) {
        raise ControlError::StaleConfig(current.snapshot.version)
      }
      let delivery = { node_id, snapshot, delivered_at: at, }
      self.configs[index] = delivery
      delivery
    }
    None => {
      let delivery = { node_id, snapshot, delivered_at: at, }
      self.configs.push(delivery)
      delivery
    }
  }
}

///|
/// Returns the latest configuration accepted for a node.
pub fn ControlPlane::config(
  self : ControlPlane,
  node_id~ : NodeId,
) -> ConfigDelivery? {
  match self.find_config_index(node_id~) {
    Some(index) => Some(self.configs[index])
    None => None
  }
}

///|
/// Delivers a command to its declared node target.
pub fn ControlPlane::deliver_command(
  self : ControlPlane,
  node_id~ : NodeId,
  command~ : Command,
) -> Command raise ControlError {
  ensure_node_id(node_id)
  if command.node_id != node_id {
    raise ControlError::CommandTargetMismatch(command.id)
  }
  match self.find_index(node_id~) {
    None => raise ControlError::UnknownNode(node_id)
    Some(index) =>
      if self.nodes[index].lifecycle == NodeLifecycle::Retired {
        raise ControlError::RetiredNode(node_id)
      }
  }
  for existing in self.commands {
    if existing.id == command.id {
      raise ControlError::DuplicateCommand(command.id)
    }
  }
  self.commands.push(command)
  command
}

///|
/// Returns a command tracked by its idempotency key.
pub fn ControlPlane::command(
  self : ControlPlane,
  command_id~ : CommandId,
) -> Command? {
  match self.find_command_index(command_id~) {
    Some(index) => Some(self.commands[index])
    None => None
  }
}

///|
/// Applies one lifecycle update and retains the resulting command state.
pub fn ControlPlane::update_command(
  self : ControlPlane,
  command_id~ : CommandId,
  update~ : CommandUpdate,
  at~ : Timestamp,
) -> Command raise ControlError {
  ensure_timestamp(at)
  let index = match self.find_command_index(command_id~) {
    Some(index) => index
    None => raise ControlError::UnknownCommand(command_id)
  }
  let current = self.commands[index]
  let updated = match update {
    CommandUpdate::Accept =>
      current.accept(at~) catch {
        error => raise ControlError::CommandTransition(error)
      }
    CommandUpdate::Start =>
      current.start(at~) catch {
        error => raise ControlError::CommandTransition(error)
      }
    CommandUpdate::Succeed(message) =>
      current.succeed(at~, message~) catch {
        error => raise ControlError::CommandTransition(error)
      }
    CommandUpdate::Fail(message) =>
      current.fail(at~, message~) catch {
        error => raise ControlError::CommandTransition(error)
      }
    CommandUpdate::Reject(reason) =>
      current.reject(at~, reason~) catch {
        error => raise ControlError::CommandTransition(error)
      }
    CommandUpdate::Expire =>
      current.expire(at~) catch {
        error => raise ControlError::CommandTransition(error)
      }
  }
  self.commands[index] = updated
  updated
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
fn ensure_node_id(node_id : NodeId) -> Unit raise ControlError {
  if node_id.value == "" {
    raise ControlError::EmptyNodeId
  }
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

///|
fn ControlPlane::find_config_index(
  self : ControlPlane,
  node_id~ : NodeId,
) -> Int? {
  for index in 0..<self.configs.length() {
    if self.configs[index].node_id == node_id {
      return Some(index)
    }
  }
  None
}

///|
fn ControlPlane::find_command_index(
  self : ControlPlane,
  command_id~ : CommandId,
) -> Int? {
  for index in 0..<self.commands.length() {
    if self.commands[index].id == command_id {
      return Some(index)
    }
  }
  None
}
