///|
/// Errors raised while resolving a local deployment profile.
pub(all) suberror DeployError {
  EmptyPath
  InvalidResourceLimit
  UnknownArgument(String)
  MissingArgument(String)
  InvalidProfile(String)
} derive(Debug, Eq)

///|
/// The two supported process roles.
pub(all) enum RunProfileKind {
  Node
  ControlPlane
} derive(Debug, Eq)

///|
/// The supported deployment target for this release.
pub(all) enum DeploymentTarget {
  LinuxNative
} derive(Debug, Eq)

///|
/// Network behavior selected by a run profile.
pub(all) enum NetworkMode {
  Reconnectable
  OfflineOnly
} derive(Debug, Eq)

///|
/// Bounded local resource settings for a process role.
pub(all) struct ResourceLimits {
  max_pending_events : Int
  max_log_entries : Int
  max_reconnect_attempts : Int
} derive(Debug, Eq)

///|
/// Creates positive resource limits.
pub fn ResourceLimits::new(
  max_pending_events~ : Int,
  max_log_entries~ : Int,
  max_reconnect_attempts~ : Int,
) -> ResourceLimits raise DeployError {
  if max_pending_events <= 0 ||
    max_log_entries <= 0 ||
    max_reconnect_attempts <= 0 {
    raise DeployError::InvalidResourceLimit
  }
  { max_pending_events, max_log_entries, max_reconnect_attempts, }
}

///|
/// A complete node or control-plane run profile.
pub(all) struct RunProfile {
  name : String
  kind : RunProfileKind
  target : DeploymentTarget
  network : NetworkMode
  data_dir : String
  config_path : String
  journal_dir : String
  diagnostics_dir : String
  resources : ResourceLimits
} derive(Debug, Eq)

///|
/// Returns the default node profile for a standard Linux user process.
pub fn RunProfile::node_default() -> RunProfile {
  {
    name: "node",
    kind: RunProfileKind::Node,
    target: DeploymentTarget::LinuxNative,
    network: NetworkMode::Reconnectable,
    data_dir: "/var/lib/edgeweaver/node",
    config_path: "/etc/edgeweaver/node.toml",
    journal_dir: "/var/lib/edgeweaver/node/events",
    diagnostics_dir: "/var/lib/edgeweaver/node/diagnostics",
    resources: {
      max_pending_events: 1024,
      max_log_entries: 256,
      max_reconnect_attempts: 8,
    },
  }
}

///|
/// Returns the default control-plane profile for a standard Linux user process.
pub fn RunProfile::control_plane_default() -> RunProfile {
  {
    name: "control-plane",
    kind: RunProfileKind::ControlPlane,
    target: DeploymentTarget::LinuxNative,
    network: NetworkMode::Reconnectable,
    data_dir: "/var/lib/edgeweaver/control-plane",
    config_path: "/etc/edgeweaver/control-plane.toml",
    journal_dir: "/var/lib/edgeweaver/control-plane/events",
    diagnostics_dir: "/var/lib/edgeweaver/control-plane/diagnostics",
    resources: {
      max_pending_events: 4096,
      max_log_entries: 512,
      max_reconnect_attempts: 8,
    },
  }
}

///|
/// Selects a default profile by process role.
pub fn RunProfile::for_kind(kind~ : RunProfileKind) -> RunProfile {
  match kind {
    RunProfileKind::Node => RunProfile::node_default()
    RunProfileKind::ControlPlane => RunProfile::control_plane_default()
  }
}

///|
/// Validates paths and resource limits before process startup.
pub fn RunProfile::validate(self : RunProfile) -> Unit raise DeployError {
  ensure_path(self.data_dir)
  ensure_path(self.config_path)
  ensure_path(self.journal_dir)
  ensure_path(self.diagnostics_dir)
  if self.resources.max_pending_events <= 0 ||
    self.resources.max_log_entries <= 0 ||
    self.resources.max_reconnect_attempts <= 0 {
    raise DeployError::InvalidResourceLimit
  }
}

///|
/// Startup overrides accepted by the command-line launcher.
pub(all) struct LaunchOptions {
  mut kind : RunProfileKind
  mut data_dir : String?
  mut config_path : String?
} derive(Debug, Eq)

///|
/// Creates launcher options for a profile role.
pub fn LaunchOptions::new(kind~ : RunProfileKind) -> LaunchOptions {
  { kind, data_dir: None, config_path: None, }
}

///|
/// Parses profile, data directory, and config path startup arguments.
pub fn LaunchOptions::parse(
  args~ : Array[String],
) -> LaunchOptions raise DeployError {
  let options = LaunchOptions::new(kind=RunProfileKind::Node)
  let mut index = 0
  while index < args.length() {
    match args[index] {
      "--profile" => {
        let value = next_argument(args, index, "--profile")
        options.kind = parse_profile(value)
        index = index + 2
      }
      "--data-dir" => {
        let value = next_argument(args, index, "--data-dir")
        options.data_dir = Some(value)
        index = index + 2
      }
      "--config" => {
        let value = next_argument(args, index, "--config")
        options.config_path = Some(value)
        index = index + 2
      }
      argument => raise DeployError::UnknownArgument(argument)
    }
  }
  options
}

///|
/// Resolves startup overrides into a validated run profile.
pub fn LaunchOptions::resolve(
  self : LaunchOptions,
) -> RunProfile raise DeployError {
  let base = RunProfile::for_kind(kind=self.kind)
  let data_dir = match self.data_dir {
    Some(path) => path
    None => base.data_dir
  }
  let config_path = match self.config_path {
    Some(path) => path
    None => base.config_path
  }
  let profile = {
    name: base.name,
    kind: base.kind,
    target: base.target,
    network: base.network,
    data_dir,
    config_path,
    journal_dir: data_dir + "/events",
    diagnostics_dir: data_dir + "/diagnostics",
    resources: base.resources,
  }
  profile.validate()
  profile
}

///|
fn next_argument(
  args : Array[String],
  index : Int,
  option : String,
) -> String raise DeployError {
  if index + 1 >= args.length() {
    raise DeployError::MissingArgument(option)
  }
  let value = args[index + 1]
  if value == "" {
    raise DeployError::EmptyPath
  }
  value
}

///|
fn parse_profile(value : String) -> RunProfileKind raise DeployError {
  match value {
    "node" => RunProfileKind::Node
    "control-plane" => RunProfileKind::ControlPlane
    _ => raise DeployError::InvalidProfile(value)
  }
}

///|
fn ensure_path(path : String) -> Unit raise DeployError {
  if path == "" {
    raise DeployError::EmptyPath
  }
}
