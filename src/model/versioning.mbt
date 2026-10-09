///|
pub(all) enum VersionLifecycle {
  Supported
  Deprecated
}

///|
/// Format of `protocol_identity`.
///
/// - `V1` (`mmkp_1`): `mmkp_1:<warmup_iterations>:<confirmatory_samples>:<practical_delta_pct>`.
///   It ignored every other protocol field and is no longer produced.
/// - `V2` (`mmkp_2`): `mmkp_2:<16 hex digits>`, the 64-bit FNV-1a digest of
///   `protocol_canonical_encoding`, which covers every `RunProtocol` field.
pub(all) enum ProtocolVersion {
  V1
  V2
}

///|
pub fn ProtocolVersion::version(self : ProtocolVersion) -> Int {
  match self {
    V1 => 1
    V2 => 2
  }
}

///|
pub fn ProtocolVersion::implementation(self : ProtocolVersion) -> String {
  match self {
    V1 | V2 => "mmkp"
  }
}

///|
pub fn ProtocolVersion::lifecycle(self : ProtocolVersion) -> VersionLifecycle {
  match self {
    V1 => Deprecated
    V2 => Supported
  }
}

///|
pub fn ProtocolVersion::identifier(self : ProtocolVersion) -> String {
  self.implementation() + "_" + self.version().to_string()
}

///|
pub(all) enum ArtifactVersion {
  V1
}

///|
pub fn ArtifactVersion::version(self : ArtifactVersion) -> Int {
  match self {
    V1 => 1
  }
}

///|
pub fn ArtifactVersion::implementation(self : ArtifactVersion) -> String {
  match self {
    V1 => "mmka"
  }
}

///|
pub fn ArtifactVersion::lifecycle(self : ArtifactVersion) -> VersionLifecycle {
  match self {
    V1 => Supported
  }
}

///|
pub fn ArtifactVersion::identifier(self : ArtifactVersion) -> String {
  self.implementation() + "_" + self.version().to_string()
}

///|
pub(all) enum SchemaVersion {
  V1
  V2
}

///|
pub fn SchemaVersion::version(self : SchemaVersion) -> Int {
  match self {
    V1 => 1
    V2 => 2
  }
}

///|
pub fn SchemaVersion::implementation(self : SchemaVersion) -> String {
  match self {
    V1 | V2 => "mmks"
  }
}

///|
pub fn SchemaVersion::lifecycle(self : SchemaVersion) -> VersionLifecycle {
  match self {
    V1 => Deprecated
    V2 => Supported
  }
}

///|
pub fn SchemaVersion::identifier(self : SchemaVersion) -> String {
  self.implementation() + "_" + self.version().to_string()
}
