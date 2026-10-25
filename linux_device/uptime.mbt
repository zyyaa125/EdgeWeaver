///|
/// A read-only Linux user-space adapter for the host's `/proc/uptime` metric.
pub(all) struct LinuxUptimeAdapter {
  id : String
}

///|
/// Creates the fixed, read-only host uptime adapter.
pub fn LinuxUptimeAdapter::new() -> LinuxUptimeAdapter {
  { id: "linux-host", }
}

///|
extern "c" fn host_supported() -> Int32 = "edgeweaver_linux_host_supported"

///|
/// Reports whether this build targets Linux; collection can still fail if procfs is unavailable.
pub fn LinuxUptimeAdapter::supported() -> Bool {
  host_supported() == 1
}

///|
extern "c" fn read_uptime_seconds() -> Int32 = "edgeweaver_linux_read_uptime"

///|
extern "c" fn unix_now_seconds() -> Int32 = "edgeweaver_linux_unix_now"

///|
fn LinuxUptimeAdapter::observation_from_seconds(
  self : LinuxUptimeAdapter,
  node_id : @edgeweaver.NodeId,
  at : @edgeweaver.Timestamp,
  seconds : Int32,
) -> @edgeweaver.DeviceObservation raise @edgeweaver.AdapterError {
  if seconds < 0 {
    raise @edgeweaver.AdapterError::ReadUnavailable("proc_uptime")
  }
  @edgeweaver.DeviceObservation::new(
    node_id~,
    device_id=self.id,
    health=@edgeweaver.NodeHealth::Unknown,
    metric="uptime_seconds",
    value=seconds,
    unit="s",
    captured_at=at,
  )
}

///|
/// Reads the integer uptime in seconds from the Linux proc filesystem.
pub fn LinuxUptimeAdapter::collect(
  self : LinuxUptimeAdapter,
  node_id~ : @edgeweaver.NodeId,
  at~ : @edgeweaver.Timestamp,
) -> @edgeweaver.DeviceObservation raise @edgeweaver.AdapterError {
  self.observation_from_seconds(node_id, at, read_uptime_seconds())
}

///|
/// Captures the Linux wall clock and host uptime in one observation.
pub fn LinuxUptimeAdapter::collect_now(
  self : LinuxUptimeAdapter,
  node_id~ : @edgeweaver.NodeId,
) -> @edgeweaver.DeviceObservation raise @edgeweaver.AdapterError {
  let at = unix_now_seconds()
  if at < 0 {
    raise @edgeweaver.AdapterError::ReadUnavailable("system_clock")
  }
  self.collect(node_id~, at=@edgeweaver.Timestamp::{ unix_seconds: at, })
}
