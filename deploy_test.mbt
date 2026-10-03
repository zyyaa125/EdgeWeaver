///|
test "default profiles cover node and control plane roles" {
  let node = @edgeweaver.RunProfile::node_default()
  assert_eq(node.kind, @edgeweaver.RunProfileKind::Node)
  assert_eq(node.target, @edgeweaver.DeploymentTarget::LinuxNative)
  assert_eq(node.network, @edgeweaver.NetworkMode::Reconnectable)
  assert_eq(node.data_dir, "/var/lib/edgeweaver/node")
  assert_eq(node.resources.max_pending_events, 1024)
  try! node.validate()

  let control_plane = @edgeweaver.RunProfile::control_plane_default()
  assert_eq(control_plane.kind, @edgeweaver.RunProfileKind::ControlPlane)
  assert_eq(control_plane.data_dir, "/var/lib/edgeweaver/control-plane")
  assert_eq(control_plane.resources.max_pending_events, 4096)
  try! control_plane.validate()
}

///|
test "launch options resolve role and storage overrides" {
  let options = try! @edgeweaver.LaunchOptions::parse(args=[
    "--profile", "control-plane", "--data-dir", "/srv/edgeweaver/control", "--config",
    "/etc/edgeweaver/custom.toml",
  ])
  let profile = try! options.resolve()
  assert_eq(profile.kind, @edgeweaver.RunProfileKind::ControlPlane)
  assert_eq(profile.data_dir, "/srv/edgeweaver/control")
  assert_eq(profile.config_path, "/etc/edgeweaver/custom.toml")
  assert_eq(profile.journal_dir, "/srv/edgeweaver/control/events")
  assert_eq(profile.diagnostics_dir, "/srv/edgeweaver/control/diagnostics")
}

///|
test "launch parser rejects malformed startup arguments" {
  try @edgeweaver.LaunchOptions::parse(args=["--profile"]) catch {
    @edgeweaver.DeployError::MissingArgument(option) =>
      assert_eq(option, "--profile")
    _ => fail("wrong missing argument error")
  } noraise {
    _ => fail("expected missing profile argument")
  }
  try @edgeweaver.LaunchOptions::parse(args=["--profile", "worker"]) catch {
    @edgeweaver.DeployError::InvalidProfile(profile) =>
      assert_eq(profile, "worker")
    _ => fail("wrong profile error")
  } noraise {
    _ => fail("expected invalid profile rejection")
  }
  try @edgeweaver.LaunchOptions::parse(args=["--unknown"]) catch {
    @edgeweaver.DeployError::UnknownArgument(argument) =>
      assert_eq(argument, "--unknown")
    _ => fail("wrong unknown argument error")
  } noraise {
    _ => fail("expected unknown argument rejection")
  }
  try @edgeweaver.LaunchOptions::parse(args=["--data-dir", ""]) catch {
    @edgeweaver.DeployError::EmptyPath => ()
    _ => fail("wrong empty path error")
  } noraise {
    _ => fail("expected empty path rejection")
  }
}

///|
test "resource limits reject zero and negative values" {
  try
    @edgeweaver.ResourceLimits::new(
      max_pending_events=0,
      max_log_entries=1,
      max_reconnect_attempts=1,
    )
  catch {
    @edgeweaver.DeployError::InvalidResourceLimit => ()
    _ => fail("wrong resource limit error")
  } noraise {
    _ => fail("expected invalid resource limit rejection")
  }
  try
    @edgeweaver.ResourceLimits::new(
      max_pending_events=1,
      max_log_entries=-1,
      max_reconnect_attempts=1,
    )
  catch {
    @edgeweaver.DeployError::InvalidResourceLimit => ()
    _ => fail("wrong negative resource limit error")
  } noraise {
    _ => fail("expected negative resource limit rejection")
  }
}
