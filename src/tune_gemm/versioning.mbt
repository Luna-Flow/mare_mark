///|
pub(all) enum TuningSchemaVersion {
  V1
}

///|
pub fn TuningSchemaVersion::version(self : TuningSchemaVersion) -> Int {
  match self {
    V1 => 1
  }
}

///|
pub fn TuningSchemaVersion::implementation(
  self : TuningSchemaVersion,
) -> String {
  match self {
    V1 => "mmkts"
  }
}

///|
pub fn TuningSchemaVersion::lifecycle(
  self : TuningSchemaVersion,
) -> @model.VersionLifecycle {
  match self {
    V1 => @model.VersionLifecycle::Supported
  }
}

///|
pub fn TuningSchemaVersion::identifier(self : TuningSchemaVersion) -> String {
  self.implementation() + "_" + self.version().to_string()
}
