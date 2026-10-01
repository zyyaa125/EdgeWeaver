///|
/// Errors raised while constructing configuration snapshots.
pub(all) suberror ConfigError {
  InvalidVersion
  EmptyContent
} derive(Debug, Eq)

///|
/// A positive, monotonically comparable configuration version.
pub(all) struct ConfigVersion {
  value : Int
} derive(Debug, Eq)

///|
/// Creates a positive configuration version.
pub fn ConfigVersion::new(value~ : Int) -> ConfigVersion raise ConfigError {
  if value <= 0 {
    raise ConfigError::InvalidVersion
  }
  { value, }
}

///|
/// An immutable configuration snapshot that can be referenced by a command.
pub(all) struct ConfigSnapshot {
  version : ConfigVersion
  content : String
  created_at : Timestamp
} derive(Debug, Eq)

///|
/// Creates a configuration snapshot with non-empty content.
pub fn ConfigSnapshot::new(
  version~ : ConfigVersion,
  content~ : String,
  created_at~ : Timestamp,
) -> ConfigSnapshot raise ConfigError {
  if content == "" {
    raise ConfigError::EmptyContent
  }
  { version, content, created_at, }
}

///|
/// Reports whether this snapshot is newer than the supplied snapshot.
pub fn ConfigSnapshot::supersedes(
  self : ConfigSnapshot,
  previous~ : ConfigSnapshot,
) -> Bool {
  self.version.value > previous.version.value
}
