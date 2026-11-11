///|
priv struct Command {
  id : @identity.RegistrationId
  run : (String) -> String raise
}

///|
pub struct CommandRegistry {
  priv entries : Map[String, Command]
}

///|
pub struct Commands {
  priv registry : CommandRegistry
  priv context : @runtime.ServiceContext
}

///|
#derive(Debug)
pub(all) suberror CommandError {
  DuplicateCommand(String)
  UnknownCommand(String)
  InvalidPrefix
}

///|
pub extend CommandError with Debug::{to_repr}

///|
pub fn CommandRegistry::new() -> CommandRegistry {
  { entries: Map([]), }
}

///|
pub fn CommandRegistry::plugin(
  self : CommandRegistry,
  key : @service.ServiceKey[Commands],
) -> @runtime.Plugin[Unit] {
  @runtime.Plugin::new(
    (ctx, _) => ctx.provide_with(key, context => { registry: self, context, }),
    provides=[key.id()],
  )
}

///|
fn Commands::name(self : Commands, name : String) -> String raise {
  let metadata = self.context.metadata()
  match metadata {
    { "prefix": String(prefix), .. } => prefix + name
    { "prefix": _, .. } => raise InvalidPrefix
    _ => name
  }
}

///|
pub fn Commands::register(
  self : Commands,
  name : String,
  run : (String) -> String raise,
) -> (async () -> Unit) raise {
  let name = self.name(name)
  let (_, dispose) = self.context.effect(fn() raise {
    guard !self.registry.entries.contains(name) else {
      raise DuplicateCommand(name)
    }
    let id = @identity.RegistrationId::fresh()
    self.registry.entries[name] = { id, run, }
    (
      (),
      () => {
        if self.registry.entries.get(name) is Some(current) && current.id == id {
          self.registry.entries.remove(name)
        }
      },
    )
  })
  dispose
}

///|
pub fn Commands::execute(
  self : Commands,
  name : String,
  input : String,
) -> String raise {
  let name = self.name(name)
  guard self.registry.entries.get(name) is Some(command) else {
    raise UnknownCommand(name)
  }
  (command.run)(input)
}

///|
pub fn Commands::names(self : Commands) -> Array[String] raise {
  self.context.ensure()
  let names = self.registry.entries.keys().collect()
  names.sort()
  names
}
