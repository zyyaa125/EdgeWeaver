///|
/// Errors raised while constructing or updating a node model.
pub(all) suberror NodeError {
  EmptyNodeId
  InvalidTimestamp
  InvalidTransition(String)
  InvalidHealthUpdate
} derive(Debug, Eq)

///|
/// Lifecycle states for an EdgeWeaver node.
pub(all) enum NodeLifecycle {
  New
  Enrolled
  Online
  Offline
  Retired
} derive(Debug, Eq)

///|
/// Health states reported by a node or an operator.
pub(all) enum NodeHealth {
  Unknown
  Healthy
  Degraded
  Unhealthy
} derive(Debug, Eq)

///|
/// Capabilities that a node can advertise to the control plane.
pub(all) enum NodeCapability {
  Telemetry
  CommandExecution
  PersistentStorage
} derive(Debug, Eq)

///|
/// A stable identifier for one edge node.
pub(all) struct NodeId {
  value : String
} derive(Debug, Eq)

///|
/// Creates a non-empty node identifier.
pub fn NodeId::new(value~ : String) -> NodeId raise NodeError {
  if value == "" {
    raise NodeError::EmptyNodeId
  }
  { value, }
}

///|
/// A non-negative Unix timestamp measured in seconds.
pub(all) struct Timestamp {
  unix_seconds : Int
} derive(Debug, Eq)

///|
/// Creates a validated timestamp.
pub fn Timestamp::new(unix_seconds~ : Int) -> Timestamp raise NodeError {
  if unix_seconds < 0 {
    raise NodeError::InvalidTimestamp
  }
  { unix_seconds, }
}

///|
/// Identity, capabilities, lifecycle, health, and observation time for a node.
pub(all) struct Node {
  id : NodeId
  capabilities : Array[NodeCapability]
  lifecycle : NodeLifecycle
  health : NodeHealth
  created_at : Timestamp
  updated_at : Timestamp
} derive(Debug, Eq)

///|
/// Creates a node in the New lifecycle with unknown health.
pub fn Node::new(
  id~ : String,
  capabilities~ : Array[NodeCapability],
  created_at~ : Timestamp,
) -> Node raise NodeError {
  {
    id: NodeId::new(value=id),
    capabilities,
    lifecycle: NodeLifecycle::New,
    health: NodeHealth::Unknown,
    created_at,
    updated_at: created_at,
  }
}

///|
/// Reports whether the node advertises a capability.
pub fn Node::supports(self : Node, capability~ : NodeCapability) -> Bool {
  for item in self.capabilities {
    if item == capability {
      return true
    }
  }
  false
}

///|
/// Applies a legal lifecycle transition at a monotonic timestamp.
pub fn Node::transition(
  self : Node,
  target~ : NodeLifecycle,
  at~ : Timestamp,
) -> Node raise NodeError {
  if at.unix_seconds < self.updated_at.unix_seconds {
    raise NodeError::InvalidTimestamp
  }
  if !can_transition(self.lifecycle, target) {
    raise NodeError::InvalidTransition("lifecycle transition is not allowed")
  }
  {
    id: self.id,
    capabilities: self.capabilities,
    lifecycle: target,
    health: self.health,
    created_at: self.created_at,
    updated_at: at,
  }
}

///|
/// Records a health observation at a monotonic timestamp.
pub fn Node::record_health(
  self : Node,
  health~ : NodeHealth,
  at~ : Timestamp,
) -> Node raise NodeError {
  if self.lifecycle == NodeLifecycle::Retired {
    raise NodeError::InvalidHealthUpdate
  }
  if at.unix_seconds < self.updated_at.unix_seconds {
    raise NodeError::InvalidTimestamp
  }
  {
    id: self.id,
    capabilities: self.capabilities,
    lifecycle: self.lifecycle,
    health,
    created_at: self.created_at,
    updated_at: at,
  }
}

///|
fn can_transition(from : NodeLifecycle, to : NodeLifecycle) -> Bool {
  match (from, to) {
    (NodeLifecycle::New, NodeLifecycle::Enrolled) => true
    (NodeLifecycle::New, NodeLifecycle::Retired) => true
    (NodeLifecycle::Enrolled, NodeLifecycle::Online) => true
    (NodeLifecycle::Enrolled, NodeLifecycle::Offline) => true
    (NodeLifecycle::Enrolled, NodeLifecycle::Retired) => true
    (NodeLifecycle::Online, NodeLifecycle::Offline) => true
    (NodeLifecycle::Online, NodeLifecycle::Retired) => true
    (NodeLifecycle::Offline, NodeLifecycle::Online) => true
    (NodeLifecycle::Offline, NodeLifecycle::Retired) => true
    _ => false
  }
}
