///| Global adapter registry for managing IM platform adapters.

///|
/// AdapterRegistry stores registered adapters and provides lookup by name.
pub(all) struct AdapterRegistry {
  adapters : Map[String, AnyAdapter] // platform_name -> adapter
}

///|
/// Create a new empty AdapterRegistry.
pub fn AdapterRegistry::new() -> AdapterRegistry {
  { adapters: Map([]) }
}

///|
/// Register an adapter by name.
pub fn AdapterRegistry::register(
  self : AdapterRegistry,
  name : String,
  adapter : AnyAdapter,
) -> Unit {
  self.adapters.set(name, adapter)
}

///|
/// Find adapter by platform name.
pub fn AdapterRegistry::find(
  self : AdapterRegistry,
  name : String,
) -> AnyAdapter? {
  self.adapters.get(name)
}

///|
/// Get all registered adapters.
pub fn AdapterRegistry::all(self : AdapterRegistry) -> Array[AnyAdapter] {
  let result : Array[AnyAdapter] = []
  for _name, adapter in self.adapters {
    result.push(adapter)
  }
  result
}

///|
/// List all registered platform names.
pub fn AdapterRegistry::list_names(self : AdapterRegistry) -> Array[String] {
  let result : Array[String] = []
  for name, _adapter in self.adapters {
    result.push(name)
  }
  result
}

///|
/// Check if a platform is registered.
pub fn AdapterRegistry::has(self : AdapterRegistry, name : String) -> Bool {
  self.adapters.contains(name)
}

///|
/// Get the number of registered adapters.
pub fn AdapterRegistry::size(self : AdapterRegistry) -> Int {
  self.adapters.length()
}
