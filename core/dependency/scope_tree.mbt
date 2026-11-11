///|
#derive(Eq, Debug)
pub(all) struct Owner {
  instance : @identity.InstanceId
  activation : @identity.ActivationId
}

///|
priv struct ScopeRecord {
  parent : @identity.ScopeId?
  owner : Owner?
  mut closing : Bool
  isolation : Map[@identity.KeyId, @identity.RealmId]
  intercepts : Array[(@identity.KeyId, Json)]
  event_scope : @identity.ScopeId
  shadow : @identity.RealmId?
}

///|
pub struct ScopeTree {
  priv root : @identity.ScopeId
  priv records : Map[@identity.ScopeId, ScopeRecord]
  priv realm : @identity.RealmId
}

///|
#derive(Debug)
pub(all) suberror ScopeError {
  UnknownScope(@identity.ScopeId)
  ClosedScope(@identity.ScopeId)
}

///|
pub fn ScopeTree::new() -> ScopeTree {
  let root = @identity.ScopeId::fresh()
  {
    root,
    realm: @identity.RealmId::fresh(),
    records: Map([
      (
        root,
        {
          parent: None,
          owner: None,
          closing: false,
          isolation: Map([]),
          intercepts: [],
          event_scope: root,
          shadow: None,
        },
      ),
    ]),
  }
}

///|
pub fn ScopeTree::root(self : ScopeTree) -> @identity.ScopeId {
  self.root
}

///|
pub fn ScopeTree::add(
  self : ScopeTree,
  parent : @identity.ScopeId,
  owner? : Owner,
  isolation~ : Array[(@identity.KeyId, @identity.RealmId)] = [],
  intercepts~ : Array[(@identity.KeyId, Json)] = [],
  isolate_events~ : Bool = false,
  shadow~ : Bool = false,
) -> @identity.ScopeId raise ScopeError {
  guard self.records.contains(parent) else { raise UnknownScope(parent) }
  guard !self.is_closing(parent) else { raise ClosedScope(parent) }
  let id = @identity.ScopeId::fresh()
  let inherited = self.records[parent]
  self.records[id] = {
    parent: Some(parent),
    owner,
    closing: false,
    isolation: Map::from_iter(isolation.iter()),
    intercepts: intercepts.copy(),
    event_scope: if isolate_events {
      id
    } else {
      inherited.event_scope
    },
    shadow: if shadow {
      Some(@identity.RealmId::fresh())
    } else {
      None
    },
  }
  id
}

///|
pub fn ScopeTree::realm(
  self : ScopeTree,
  scope : @identity.ScopeId,
  key : @identity.KeyId,
) -> @identity.RealmId {
  self.realms(scope, key)[0]
}

///|
pub fn ScopeTree::realms(
  self : ScopeTree,
  scope : @identity.ScopeId,
  key : @identity.KeyId,
) -> Array[@identity.RealmId] {
  let realms = []
  for id in self.ancestors(scope) {
    if self.records[id].isolation.get(key) is Some(realm) {
      realms.push(realm)
      return realms
    }
    if self.records[id].shadow is Some(realm) {
      realms.push(realm)
    }
  }
  realms.push(self.realm)
  realms
}

///|
pub fn ScopeTree::interceptions(
  self : ScopeTree,
  scope : @identity.ScopeId,
  key : @identity.KeyId,
) -> Array[Json] {
  let values = []
  for id in self.ancestors(scope).rev_iter() {
    for (candidate, value) in self.records[id].intercepts {
      if candidate == key {
        values.push(value)
      }
    }
  }
  values
}

///|
pub fn ScopeTree::event_scope(
  self : ScopeTree,
  scope : @identity.ScopeId,
) -> @identity.ScopeId {
  match self.records.get(scope) {
    Some(record) => record.event_scope
    None => scope
  }
}

///|
pub fn ScopeTree::contains(self : ScopeTree, scope : @identity.ScopeId) -> Bool {
  self.records.contains(scope)
}

///|
pub fn ScopeTree::parent(
  self : ScopeTree,
  scope : @identity.ScopeId,
) -> @identity.ScopeId? {
  match self.records.get(scope) {
    Some(record) => record.parent
    None => None
  }
}

///|
pub fn ScopeTree::owner(self : ScopeTree, scope : @identity.ScopeId) -> Owner? {
  match self.records.get(scope) {
    Some(record) => record.owner
    None => None
  }
}

///|
pub fn ScopeTree::ancestors(
  self : ScopeTree,
  scope : @identity.ScopeId,
) -> Array[@identity.ScopeId] {
  let result = []
  let mut cursor = Some(scope)
  while cursor is Some(id) {
    guard self.records.get(id) is Some(record) else { break }
    result.push(id)
    cursor = record.parent
  }
  result
}

///|
pub fn ScopeTree::is_within(
  self : ScopeTree,
  scope : @identity.ScopeId,
  ancestor : @identity.ScopeId,
) -> Bool {
  self.ancestors(scope).contains(ancestor)
}

///|
pub fn ScopeTree::is_closing(
  self : ScopeTree,
  scope : @identity.ScopeId,
) -> Bool {
  self.ancestors(scope).any(fn(id) { self.records[id].closing })
}

///|
pub fn ScopeTree::close(
  self : ScopeTree,
  scope : @identity.ScopeId,
) -> Unit raise ScopeError {
  guard self.records.get(scope) is Some(record) else {
    raise UnknownScope(scope)
  }
  record.closing = true
}

///|
pub fn ScopeTree::descendants(
  self : ScopeTree,
  scope : @identity.ScopeId,
) -> Array[@identity.ScopeId] {
  let result = self.records
    .keys()
    .filter(fn(id) { self.is_within(id, scope) })
    .collect()
  result.sort()
  result
}

///|
pub fn ScopeTree::forget(self : ScopeTree, scope : @identity.ScopeId) -> Unit {
  for id in self.descendants(scope) {
    self.records.remove(id)
  }
}
