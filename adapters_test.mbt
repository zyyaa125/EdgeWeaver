///|
fn adapter_time(
  seconds : Int,
) -> @edgeweaver.Timestamp raise @edgeweaver.NodeError {
  @edgeweaver.Timestamp::new(unix_seconds=seconds)
}

///|
test "device simulator reads sensors and drives actuators deterministically" {
  let node_id = try! @edgeweaver.NodeId::new(value="node-simulator")
  let sensor = try! @edgeweaver.SensorAdapter::new(
    id="temperature",
    unit="celsius",
    initial_value=20,
    step=2,
  )
  let actuator = try! @edgeweaver.ActuatorAdapter::new(
    id="fan",
    allowed_actions=["on", "off"],
    initial_state="off",
  )
  let simulator = try! @edgeweaver.DeviceSimulator::new(
    node_id~,
    sensors=[sensor],
    actuators=[actuator],
  )
  let first = try! simulator.read_sensor(
    sensor_id="temperature",
    at=try! adapter_time(10),
  )
  let second = try! simulator.read_sensor(
    sensor_id="temperature",
    at=try! adapter_time(11),
  )
  assert_eq(first.value, 20)
  assert_eq(second.value, 22)
  assert_eq(first.unit, "celsius")
  let all = try! simulator.read_all(at=try! adapter_time(12))
  assert_eq(all.length(), 1)
  assert_eq(all[0].value, 24)
  let turned_on = try! simulator.execute_actuator(
    actuator_id="fan",
    action="on",
    at=try! adapter_time(13),
  )
  assert_eq(turned_on.state, "on")
  assert_eq(turned_on.action, "on")

  let snapshot = simulator.snapshot()
  let _ = try! simulator.execute_actuator(
    actuator_id="fan",
    action="off",
    at=try! adapter_time(14),
  )
  let restored = @edgeweaver.DeviceSimulator::restore(snapshot~)
  let restored_reading = try! restored.read_sensor(
    sensor_id="temperature",
    at=try! adapter_time(15),
  )
  assert_eq(restored_reading.value, 26)
  let restored_action = try! restored.execute_actuator(
    actuator_id="fan",
    action="off",
    at=try! adapter_time(16),
  )
  assert_eq(restored_action.state, "off")
}

///|
test "adapter registry rejects invalid and unknown devices" {
  try
    @edgeweaver.SensorAdapter::new(
      id="",
      unit="celsius",
      initial_value=0,
      step=1,
    )
  catch {
    @edgeweaver.AdapterError::EmptyAdapterId => ()
    _ => fail("wrong sensor identity error")
  } noraise {
    _ => fail("expected empty sensor identity rejection")
  }
  try
    @edgeweaver.ActuatorAdapter::new(
      id="relay",
      allowed_actions=[],
      initial_state="off",
    )
  catch {
    @edgeweaver.AdapterError::EmptyActionSet => ()
    _ => fail("wrong actuator action set error")
  } noraise {
    _ => fail("expected empty actuator action set rejection")
  }
  try
    @edgeweaver.ActuatorAdapter::new(
      id="relay",
      allowed_actions=[""],
      initial_state="off",
    )
  catch {
    @edgeweaver.AdapterError::EmptyAction => ()
    _ => fail("wrong actuator action error")
  } noraise {
    _ => fail("expected empty actuator action rejection")
  }

  let node_id = try! @edgeweaver.NodeId::new(value="node-invalid")
  let sensor = try! @edgeweaver.SensorAdapter::new(
    id="shared",
    unit="unit",
    initial_value=1,
    step=1,
  )
  let actuator = try! @edgeweaver.ActuatorAdapter::new(
    id="shared",
    allowed_actions=["on"],
    initial_state="off",
  )
  try
    @edgeweaver.DeviceSimulator::new(node_id~, sensors=[sensor], actuators=[
      actuator,
    ])
  catch {
    @edgeweaver.AdapterError::DuplicateAdapterId(id) => assert_eq(id, "shared")
    _ => fail("wrong duplicate adapter error")
  } noraise {
    _ => fail("expected duplicate adapter rejection")
  }
}

///|
test "device simulator reports unknown devices and forbidden actions" {
  let node_id = try! @edgeweaver.NodeId::new(value="node-errors")
  let sensor = try! @edgeweaver.SensorAdapter::new(
    id="pressure",
    unit="kpa",
    initial_value=100,
    step=0,
  )
  let actuator = try! @edgeweaver.ActuatorAdapter::new(
    id="pump",
    allowed_actions=["start"],
    initial_state="stopped",
  )
  let simulator = try! @edgeweaver.DeviceSimulator::new(
    node_id~,
    sensors=[sensor],
    actuators=[actuator],
  )
  try
    simulator.read_sensor(sensor_id="missing", at=try! adapter_time(1))
  catch {
    @edgeweaver.AdapterError::UnknownSensor(id) => assert_eq(id, "missing")
    _ => fail("wrong unknown sensor error")
  } noraise {
    _ => fail("expected unknown sensor rejection")
  }
  try
    simulator.execute_actuator(
      actuator_id="missing",
      action="start",
      at=try! adapter_time(1),
    )
  catch {
    @edgeweaver.AdapterError::UnknownActuator(id) => assert_eq(id, "missing")
    _ => fail("wrong unknown actuator error")
  } noraise {
    _ => fail("expected unknown actuator rejection")
  }
  try
    simulator.execute_actuator(
      actuator_id="pump",
      action="stop",
      at=try! adapter_time(1),
    )
  catch {
    @edgeweaver.AdapterError::ActionNotAllowed(action) =>
      assert_eq(action, "stop")
    _ => fail("wrong actuator action error")
  } noraise {
    _ => fail("expected forbidden actuator action rejection")
  }
}
