///|
test "simulator collection uses the shared observation and event envelope" {
  let node_id = try! @edgeweaver.NodeId::new(value="node-example")
  let sensor = try! @edgeweaver.SensorAdapter::new(
    id="temperature",
    unit="celsius",
    initial_value=20,
    step=2,
  )
  let simulator = try! @edgeweaver.DeviceSimulator::new(
    node_id~,
    sensors=[sensor],
    actuators=[],
  )
  let at = try! @edgeweaver.Timestamp::new(unix_seconds=10)
  let observation = try! simulator.collect_sensor(sensor_id="temperature", at~)
  assert_eq(observation.node_id, node_id)
  assert_eq(observation.device_id, "temperature")
  assert_eq(observation.health, @edgeweaver.NodeHealth::Healthy)
  assert_eq(observation.metric, "value")
  assert_eq(observation.value, 20)
  let next = try! simulator.collect_sensor(sensor_id="temperature", at~)
  assert_eq(next.value, 22)
  let event = try! observation.to_envelope(message_id="reading-1")
  assert_eq(event.node_id, node_id)
  match event.payload {
    @edgeweaver.MessagePayload::Telemetry(value) => {
      let decoded : @edgeweaver.DeviceObservation = try! @json.from_json(
        try! @json.parse(value),
      )
      assert_eq(decoded, observation)
    }
    _ => fail("expected structured telemetry")
  }
}

///|
test "observation contract rejects incomplete identity metric and time" {
  let node_id = try! @edgeweaver.NodeId::new(value="node-example")
  let at = try! @edgeweaver.Timestamp::new(unix_seconds=10)
  try
    @edgeweaver.DeviceObservation::new(
      node_id~,
      device_id="",
      health=@edgeweaver.NodeHealth::Unknown,
      metric="value",
      value=1,
      unit="s",
      captured_at=at,
    )
  catch {
    @edgeweaver.AdapterError::EmptyDeviceId => ()
    _ => fail("wrong identity error")
  } noraise {
    _ => fail("empty device identity accepted")
  }
  try
    @edgeweaver.DeviceObservation::new(
      node_id~,
      device_id="device",
      health=@edgeweaver.NodeHealth::Unknown,
      metric="",
      value=1,
      unit="s",
      captured_at=at,
    )
  catch {
    @edgeweaver.AdapterError::EmptyMetric => ()
    _ => fail("wrong metric error")
  } noraise {
    _ => fail("empty metric accepted")
  }
  try
    @edgeweaver.DeviceObservation::new(
      node_id~,
      device_id="device",
      health=@edgeweaver.NodeHealth::Unknown,
      metric="uptime_seconds",
      value=1,
      unit="s",
      captured_at=@edgeweaver.Timestamp::{ unix_seconds: -1, },
    )
  catch {
    @edgeweaver.AdapterError::InvalidTimestamp => ()
    _ => fail("wrong timestamp error")
  } noraise {
    _ => fail("invalid observation time accepted")
  }
}
