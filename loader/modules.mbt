///|
#derive(Eq, Debug)
pub(all) struct ModuleRef {
  source : String
  revision : String
}

///|
pub extend ModuleRef with Eq::{equal, not_equal}

///|
pub extend ModuleRef with Debug::{to_repr}

///|
pub(all) struct ModuleEntry {
  id : String
  module_ref : ModuleRef
  config : Json
  enabled : Bool
}

///|
pub struct Resolver {
  priv resolve : async (ModuleRef) -> @runtime.Plugin[Json]
}

///|
pub fn Resolver::new(
  resolve : async (ModuleRef) -> @runtime.Plugin[Json],
) -> Resolver {
  { resolve, }
}

///|
pub async fn Loader::reload(
  self : Loader,
  entries : Array[ModuleEntry],
  resolver : Resolver,
) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  guard !self.closed else { raise Closed }
  let prepared : Map[(String, String), @runtime.Plugin[Json]] = Map([])
  let target : Array[Entry] = []
  for entry in entries {
    let key = (entry.module_ref.source, entry.module_ref.revision)
    let cached = match prepared.get(key) {
      Some(plugin) => Some(plugin)
      None => self.modules.get(key)
    }
    let plugin = match cached {
      Some(plugin) => plugin
      None => (resolver.resolve)(entry.module_ref)
    }
    prepared[key] = plugin
    target.push(
      Entry::new(entry.id, plugin, entry.config, enabled=entry.enabled),
    )
  }
  self.validate(target)
  @async.protect_from_cancel(() => self.commit(target))
  self.modules.clear()
  for key, plugin in prepared {
    self.modules[key] = plugin
  }
}
