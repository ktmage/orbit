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
}

///|
pub struct ScopeTree {
  priv root : @identity.ScopeId
  priv records : Map[@identity.ScopeId, ScopeRecord]
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
    records: Map([(root, { parent: None, owner: None, closing: false, })]),
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
) -> @identity.ScopeId raise ScopeError {
  guard self.records.contains(parent) else { raise UnknownScope(parent) }
  guard !self.is_closing(parent) else { raise ClosedScope(parent) }
  let id = @identity.ScopeId::fresh()
  self.records[id] = { parent: Some(parent), owner, closing: false, }
  id
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
