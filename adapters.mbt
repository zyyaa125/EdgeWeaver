///|
/// Errors raised by device adapters and the simulator registry.
pub(all) suberror AdapterError {
  EmptyNodeId
  EmptyAdapterId
  EmptyUnit
  EmptyAction
  EmptyActionSet
  DuplicateAdapterId(String)
  UnknownSensor(String)
  UnknownActuator(String)
  ActionNotAllowed(String)
  InvalidTimestamp
} derive(Debug, Eq)

///|
/// A deterministic reading produced by a sensor adapter.
pub(all) struct SensorReading {
  sensor_id : String
  value : Int
  unit : String
  captured_at : Timestamp
} derive(Debug, Eq)

///|
/// A simulated sensor adapter with a fixed increment per read.
pub(all) struct SensorAdapter {
  id : String
  unit : String
  mut value : Int
  step : Int
} derive(Debug, Eq)

///|
/// Creates a deterministic sensor adapter.
pub fn SensorAdapter::new(
  id~ : String,
  unit~ : String,
  initial_value~ : Int,
  step~ : Int,
) -> SensorAdapter raise AdapterError {
  if id == "" {
    raise AdapterError::EmptyAdapterId
  }
  if unit == "" {
    raise AdapterError::EmptyUnit
  }
  { id, unit, value: initial_value, step, }
}

///|
/// Reads the current value and advances the deterministic simulator state.
pub fn SensorAdapter::read(
  self : SensorAdapter,
  at~ : Timestamp,
) -> SensorReading raise AdapterError {
  ensure_adapter_timestamp(at)
  let reading = {
    sensor_id: self.id,
    value: self.value,
    unit: self.unit,
    captured_at: at,
  }
  self.value = self.value + self.step
  reading
}

///|
/// The result of an actuator operation.
pub(all) struct ActuatorResult {
  actuator_id : String
  action : String
  state : String
  executed_at : Timestamp
} derive(Debug, Eq)

///|
/// A simulated actuator adapter with an explicit action allowlist.
pub(all) struct ActuatorAdapter {
  id : String
  allowed_actions : Array[String]
  mut state : String
} derive(Debug, Eq)

///|
/// Creates an actuator adapter with a non-empty action allowlist.
pub fn ActuatorAdapter::new(
  id~ : String,
  allowed_actions~ : Array[String],
  initial_state~ : String,
) -> ActuatorAdapter raise AdapterError {
  if id == "" {
    raise AdapterError::EmptyAdapterId
  }
  if allowed_actions.length() == 0 {
    raise AdapterError::EmptyActionSet
  }
  for action in allowed_actions {
    if action == "" {
      raise AdapterError::EmptyAction
    }
  }
  { id, allowed_actions: copy_strings(allowed_actions), state: initial_state, }
}

///|
/// Applies an allowed action and returns the new actuator state.
pub fn ActuatorAdapter::execute(
  self : ActuatorAdapter,
  action~ : String,
  at~ : Timestamp,
) -> ActuatorResult raise AdapterError {
  ensure_adapter_timestamp(at)
  if !contains_string(self.allowed_actions, action) {
    raise AdapterError::ActionNotAllowed(action)
  }
  self.state = action
  { actuator_id: self.id, action, state: self.state, executed_at: at, }
}

///|
/// A simulator snapshot containing all adapter state.
pub(all) struct DeviceSnapshot {
  node_id : NodeId
  sensors : Array[SensorAdapter]
  actuators : Array[ActuatorAdapter]
} derive(Debug, Eq)

///|
/// A node-local simulator that exposes sensor and actuator adapter APIs.
pub(all) struct DeviceSimulator {
  node_id : NodeId
  mut sensors : Array[SensorAdapter]
  mut actuators : Array[ActuatorAdapter]
} derive(Debug, Eq)

///|
/// Creates a simulator and rejects duplicate adapter identities.
pub fn DeviceSimulator::new(
  node_id~ : NodeId,
  sensors~ : Array[SensorAdapter],
  actuators~ : Array[ActuatorAdapter],
) -> DeviceSimulator raise AdapterError {
  if node_id.value == "" {
    raise AdapterError::EmptyNodeId
  }
  let ids : Array[String] = []
  for sensor in sensors {
    if contains_string(ids, sensor.id) {
      raise AdapterError::DuplicateAdapterId(sensor.id)
    }
    ids.push(sensor.id)
  }
  for actuator in actuators {
    if contains_string(ids, actuator.id) {
      raise AdapterError::DuplicateAdapterId(actuator.id)
    }
    ids.push(actuator.id)
  }
  {
    node_id,
    sensors: copy_sensors(sensors),
    actuators: copy_actuators(actuators),
  }
}

///|
/// Reads one registered sensor.
pub fn DeviceSimulator::read_sensor(
  self : DeviceSimulator,
  sensor_id~ : String,
  at~ : Timestamp,
) -> SensorReading raise AdapterError {
  for index in 0..<self.sensors.length() {
    if self.sensors[index].id == sensor_id {
      return self.sensors[index].read(at~)
    }
  }
  raise AdapterError::UnknownSensor(sensor_id)
}

///|
/// Reads all registered sensors in registration order.
pub fn DeviceSimulator::read_all(
  self : DeviceSimulator,
  at~ : Timestamp,
) -> Array[SensorReading] raise AdapterError {
  let readings : Array[SensorReading] = []
  for index in 0..<self.sensors.length() {
    readings.push(self.sensors[index].read(at~))
  }
  readings
}

///|
/// Executes one action on a registered actuator.
pub fn DeviceSimulator::execute_actuator(
  self : DeviceSimulator,
  actuator_id~ : String,
  action~ : String,
  at~ : Timestamp,
) -> ActuatorResult raise AdapterError {
  for index in 0..<self.actuators.length() {
    if self.actuators[index].id == actuator_id {
      return self.actuators[index].execute(action~, at~)
    }
  }
  raise AdapterError::UnknownActuator(actuator_id)
}

///|
/// Captures simulator state for deterministic restart tests.
pub fn DeviceSimulator::snapshot(self : DeviceSimulator) -> DeviceSnapshot {
  {
    node_id: self.node_id,
    sensors: copy_sensors(self.sensors),
    actuators: copy_actuators(self.actuators),
  }
}

///|
/// Restores a simulator from a previously captured snapshot.
pub fn DeviceSimulator::restore(snapshot~ : DeviceSnapshot) -> DeviceSimulator {
  {
    node_id: snapshot.node_id,
    sensors: copy_sensors(snapshot.sensors),
    actuators: copy_actuators(snapshot.actuators),
  }
}

///|
fn ensure_adapter_timestamp(at : Timestamp) -> Unit raise AdapterError {
  if at.unix_seconds < 0 {
    raise AdapterError::InvalidTimestamp
  }
}

///|
fn contains_string(values : Array[String], value : String) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}

///|
fn copy_strings(values : Array[String]) -> Array[String] {
  let copy : Array[String] = []
  for value in values {
    copy.push(value)
  }
  copy
}

///|
fn copy_sensors(values : Array[SensorAdapter]) -> Array[SensorAdapter] {
  let copy : Array[SensorAdapter] = []
  for sensor in values {
    copy.push({
      id: sensor.id,
      unit: sensor.unit,
      value: sensor.value,
      step: sensor.step,
    })
  }
  copy
}

///|
fn copy_actuators(values : Array[ActuatorAdapter]) -> Array[ActuatorAdapter] {
  let copy : Array[ActuatorAdapter] = []
  for actuator in values {
    copy.push({
      id: actuator.id,
      allowed_actions: copy_strings(actuator.allowed_actions),
      state: actuator.state,
    })
  }
  copy
}
