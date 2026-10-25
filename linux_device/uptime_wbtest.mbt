///|
test "linux uptime adapter uses the shared observation contract" {
  let adapter = LinuxUptimeAdapter::new()
  let node_id = try! @edgeweaver.NodeId::new(value="node-host")
  let at = try! @edgeweaver.Timestamp::new(unix_seconds=42)
  let synthetic = try! adapter.observation_from_seconds(node_id, at, 123)
  assert_eq(synthetic.device_id, "linux-host")
  assert_eq(synthetic.health, @edgeweaver.NodeHealth::Unknown)
  assert_eq(synthetic.metric, "uptime_seconds")
  assert_eq(synthetic.value, 123)
  assert_eq(synthetic.unit, "s")
  try adapter.observation_from_seconds(node_id, at, -1) catch {
    @edgeweaver.AdapterError::ReadUnavailable(source) =>
      assert_eq(source, "proc_uptime")
    _ => fail("wrong read error")
  } noraise {
    _ => fail("unavailable reading accepted")
  }
  if LinuxUptimeAdapter::supported() {
    let actual = try! adapter.collect(node_id~, at~)
    assert_eq(actual.captured_at, at)
    assert_true(actual.value >= 0)
    let current = try! adapter.collect_now(node_id~)
    assert_true(current.captured_at.unix_seconds > 0)
  } else {
    try adapter.collect(node_id~, at~) catch {
      @edgeweaver.AdapterError::ReadUnavailable(_) => ()
      _ => fail("wrong unsupported-host error")
    } noraise {
      _ => fail("non-Linux uptime read succeeded")
    }
  }
}
