///|
/// Prints one real Linux host uptime observation and its versioned event.
fn main raise {
  let node_id = @edgeweaver.NodeId::new(value="linux-demo-node")
  let adapter = @linux_device.LinuxUptimeAdapter::new()
  let observation = adapter.collect_now(node_id~)
  println(@json.to_json(observation).stringify())
  let envelope = observation.to_envelope(
    message_id="uptime-" + observation.captured_at.unix_seconds.to_string(),
  )
  println(@json.to_json(envelope).stringify())
}
