///|
pub struct Runtime {
  priv id : @identity.RuntimeId
  priv driver : @lifecycle.Driver
  priv queue : ControlQueue
  priv scopes : @dependency.ScopeTree
  priv providers : @dependency.ProviderIndex
  priv dependencies : @dependency.DependencyGraph
  priv services : @service.ServiceBindings
  priv events : @event.EventDispatcher
  priv instances : Map[@identity.InstanceId, Instance]
  priv changes : Array[Change]
  priv observers : Array[Observer]
  priv mut sequence : Int64
  priv observer_errors : Array[Error]
}

///|
pub struct Scope {
  priv runtime : Runtime
  priv id : @identity.ScopeId
  priv managed : Bool
}

///|
pub struct Handle {
  priv runtime : Runtime
  priv instance : Instance
  priv managed : Bool
}

///|
pub fn Runtime::new(driver : @lifecycle.Driver) -> Runtime {
  let id = @identity.RuntimeId::fresh()
  {
    id,
    driver,
    queue: ControlQueue::new(),
    scopes: @dependency.ScopeTree::new(),
    providers: @dependency.ProviderIndex::new(),
    dependencies: @dependency.DependencyGraph::new(),
    services: @service.ServiceBindings::new(id),
    events: @event.EventDispatcher::new(),
    instances: Map([]),
    changes: [],
    observers: [],
    sequence: 0L,
    observer_errors: [],
  }
}

///|
pub fn Runtime::id(self : Runtime) -> @identity.RuntimeId {
  self.id
}

///|
pub fn Runtime::root(self : Runtime) -> Scope {
  { runtime: self, id: self.scopes.root(), managed: false, }
}

///|
pub fn Scope::id(self : Scope) -> @identity.ScopeId {
  self.id
}

///|
pub fn Handle::id(self : Handle) -> @identity.InstanceId {
  self.instance.id
}

///|
pub fn Scope::child(self : Scope) -> Scope raise {
  guard !self.managed else {
    raise ContractViolation("use Context.child_scope for owned scopes")
  }
  {
    runtime: self.runtime,
    id: self.runtime.scopes.add(self.id),
    managed: false,
  }
}

///|
pub fn Runtime::observe_operation(
  self : Runtime,
  operation : Operation,
) -> Operation raise {
  guard operation.cell.runtime == self.id else {
    raise ContractViolation("operation belongs to another runtime")
  }
  { cell: operation.cell, managed: false, }
}

///|
pub fn[C] Scope::install(
  self : Scope,
  plugin : Plugin[C],
  config : C,
) -> (Handle, Operation) raise {
  let definition = plugin.bind(config)
  let id = @identity.InstanceId::fresh()
  self.runtime.validate_definition(self.id, id, definition)
  let operation = Operation::new(self.runtime.id, self.managed)
  let instance : Instance = {
    id,
    scope: self.id,
    definition,
    state: Waiting,
    activation: None,
    desired: true,
    fatal: None,
    failures: [],
    missing: [],
    change: None,
    latest: Some(operation.id()),
  }
  self.runtime.commit(fn() {
    self.runtime.instances[id] = instance
    self.runtime.providers.reserve(
      self.runtime.scopes,
      self.id,
      id,
      definition.provides,
    ) catch {
      _ => abort("validated reservation failed")
    }
    self.runtime.dependencies.put(id, self.id, definition.requires)
    let change = self.runtime.new_change([id], operation)
    instance.change = Some(change)
    self.runtime.prepare_change(change)
    self.runtime.changes.push(change)
  })
  ({ runtime: self.runtime, instance, managed: self.managed, }, operation)
}

///|
fn Runtime::new_change(
  self : Runtime,
  roots : Array[@identity.InstanceId],
  operation : Operation,
) -> Change {
  let affected = self.stop_order(roots)
  {
    operation,
    roots: roots.copy(),
    affected,
    stop_targets: [],
    replacements: Map([]),
    expected_definition: None,
    removals: [],
    closing_scopes: [],
    reset_failures: [],
    attempt_failures: [],
    phase: Queued,
  }
}

///|
fn Runtime::stop_order(
  self : Runtime,
  roots : Array[@identity.InstanceId],
) -> Array[@identity.InstanceId] {
  let edges = self.dependencies.selected_edges()
  edges.append(self.dependencies.ownership_edges(self.scopes))
  @dependency.stop_order(roots, edges) catch {
    _ => abort("accepted graph became cyclic")
  }
}
