///|
pub(all) enum VersionLifecycle {
  Supported
  Deprecated
}

///|
pub(all) enum ProtocolVersion {
  V1
}

///|
pub fn ProtocolVersion::version(self : ProtocolVersion) -> Int {
  match self {
    V1 => 1
  }
}

///|
pub fn ProtocolVersion::implementation(self : ProtocolVersion) -> String {
  match self {
    V1 => "mmkp"
  }
}

///|
pub fn ProtocolVersion::lifecycle(self : ProtocolVersion) -> VersionLifecycle {
  match self {
    V1 => Supported
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
}

///|
pub fn SchemaVersion::version(self : SchemaVersion) -> Int {
  match self {
    V1 => 1
  }
}

///|
pub fn SchemaVersion::implementation(self : SchemaVersion) -> String {
  match self {
    V1 => "mmks"
  }
}

///|
pub fn SchemaVersion::lifecycle(self : SchemaVersion) -> VersionLifecycle {
  match self {
    V1 => Supported
  }
}

///|
pub fn SchemaVersion::identifier(self : SchemaVersion) -> String {
  self.implementation() + "_" + self.version().to_string()
}
