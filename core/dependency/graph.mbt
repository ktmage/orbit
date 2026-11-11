///|
priv struct DependencyRecord {
  scope : @identity.ScopeId
  mut requirements : Array[Requirement]
  mut selections : Array[Selection]
}

///|
pub struct DependencyGraph {
  priv records : Map[@identity.InstanceId, DependencyRecord]
  priv consumers : Map[@identity.InstanceId, Array[@identity.InstanceId]]
  priv waiting : Map[@identity.KeyId, Array[@identity.InstanceId]]
}

///|
pub fn DependencyGraph::new() -> DependencyGraph {
  { records: Map([]), consumers: Map([]), waiting: Map([]), }
}

///|
pub fn DependencyGraph::put(
  self : DependencyGraph,
  instance : @identity.InstanceId,
  scope : @identity.ScopeId,
  requirements : Array[Requirement],
) -> Unit {
  self.remove(instance)
  self.records[instance] = {
    scope,
    requirements: requirements.copy(),
    selections: [],
  }
}

///|
fn DependencyGraph::remove_selections(
  self : DependencyGraph,
  instance : @identity.InstanceId,
) -> Unit {
  guard self.records.get(instance) is Some(record) else { return }
  for selection in record.selections {
    match selection.provider {
      Some(provider) =>
        if self.consumers.get(provider) is Some(consumers) {
          let remaining = consumers.filter(fn(id) { id != instance })
          if remaining.is_empty() {
            self.consumers.remove(provider)
          } else {
            self.consumers[provider] = remaining
          }
        }
      None =>
        if self.waiting.get(selection.key) is Some(waiting) {
          let remaining = waiting.filter(fn(id) { id != instance })
          if remaining.is_empty() {
            self.waiting.remove(selection.key)
          } else {
            self.waiting[selection.key] = remaining
          }
        }
    }
  }
}

///|
pub fn DependencyGraph::select(
  self : DependencyGraph,
  instance : @identity.InstanceId,
  selections : Array[Selection],
) -> Unit {
  guard self.records.get(instance) is Some(record) else { return }
  self.remove_selections(instance)
  record.selections = selections.copy()
  for selection in selections {
    match selection.provider {
      Some(provider) => {
        let consumers = self.consumers.get_or_default(provider, [])
        if !consumers.contains(instance) {
          consumers.push(instance)
        }
        self.consumers[provider] = consumers
      }
      None => {
        let waiting = self.waiting.get_or_default(selection.key, [])
        if !waiting.contains(instance) {
          waiting.push(instance)
        }
        self.waiting[selection.key] = waiting
      }
    }
  }
}

///|
pub fn DependencyGraph::remove(
  self : DependencyGraph,
  instance : @identity.InstanceId,
) -> Unit {
  self.remove_selections(instance)
  self.records.remove(instance)
}

///|
pub fn DependencyGraph::consumers_of(
  self : DependencyGraph,
  provider : @identity.InstanceId,
) -> Array[@identity.InstanceId] {
  self.consumers.get_or_default(provider, []).copy()
}

///|
pub fn DependencyGraph::waiting_for(
  self : DependencyGraph,
  key : @identity.KeyId,
) -> Array[@identity.InstanceId] {
  self.waiting.get_or_default(key, []).copy()
}

///|
pub fn DependencyGraph::affected_by(
  self : DependencyGraph,
  tree : ScopeTree,
  scope : @identity.ScopeId,
  key : @identity.KeyId,
) -> Array[@identity.InstanceId] {
  self.records
  .iter()
  .filter(fn(entry) {
    tree.realms(entry.1.scope, key).contains(tree.realm(scope, key)) &&
    entry.1.requirements.any(fn(r) { r.key == key })
  })
  .map(fn(entry) { entry.0 })
  .collect()
}

///|
pub fn DependencyGraph::selected_edges(self : DependencyGraph) -> Array[Edge] {
  let result = []
  for instance, record in self.records {
    for selection in record.selections {
      if selection.provider is Some(provider) {
        result.push({ before: instance, after: provider, })
      }
    }
  }
  result
}

///|
pub fn DependencyGraph::planned_edges(
  self : DependencyGraph,
  tree : ScopeTree,
  providers : ProviderIndex,
) -> Array[Edge] {
  let result = []
  for instance, record in self.records {
    let resolution = resolve(
      tree,
      providers,
      record.scope,
      record.requirements,
      fn(_, _) { true },
    )
    for selection in resolution.selections {
      if selection.provider is Some(provider) {
        result.push({ before: instance, after: provider, })
      }
    }
  }
  result
}

///|
pub fn DependencyGraph::ownership_edges(
  self : DependencyGraph,
  tree : ScopeTree,
) -> Array[Edge] {
  let result = []
  for instance, record in self.records {
    for scope in tree.ancestors(record.scope) {
      if tree.owner(scope) is Some(owner) {
        result.push({ before: instance, after: owner.instance, })
      }
    }
  }
  result
}

///|
pub fn DependencyGraph::copy(self : DependencyGraph) -> DependencyGraph {
  let result = DependencyGraph::new()
  for instance, record in self.records {
    result.put(instance, record.scope, record.requirements)
    result.select(instance, record.selections)
  }
  result
}

///|
pub fn DependencyGraph::plan(
  self : DependencyGraph,
  instance : @identity.InstanceId,
  scope : @identity.ScopeId,
  requirements : Array[Requirement],
) -> Unit {
  match self.records.get(instance) {
    Some(record) => record.requirements = requirements.copy()
    None => self.put(instance, scope, requirements)
  }
}
