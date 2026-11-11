///|
test "an unpublished child provider does not hide a published ancestor" {
  let tree = @dependency.ScopeTree::new()
  let child = tree.add(tree.root(), shadow=true)
  let sibling = tree.add(tree.root(), shadow=true)
  let key = @identity.KeyId::fresh()
  let parent_provider = @identity.InstanceId::fresh()
  let child_provider = @identity.InstanceId::fresh()
  let index = @dependency.ProviderIndex::new()
  index.reserve(tree, tree.root(), parent_provider, [key])
  index.reserve(tree, child, child_provider, [key])
  let requirements : Array[@dependency.Requirement] = [{ key, required: true, }]
  let initial = @dependency.resolve(tree, index, child, requirements, fn(
    id,
    _,
  ) {
    id == parent_provider
  })
  assert_eq(initial.selections[0].provider, Some(parent_provider))
  let ready = @dependency.resolve(tree, index, child, requirements, fn(_, _) {
    true
  })
  assert_eq(ready.selections[0].provider, Some(child_provider))
  let separate = @dependency.resolve(tree, index, sibling, requirements, fn(
    _,
    _,
  ) {
    true
  })
  assert_eq(separate.selections[0].provider, Some(parent_provider))
}

///|
test "missing optional services do not prevent starting" {
  let tree = @dependency.ScopeTree::new()
  let optional = @identity.KeyId::fresh()
  let required = @identity.KeyId::fresh()
  let result = @dependency.resolve(
    tree,
    @dependency.ProviderIndex::new(),
    tree.root(),
    [{ key: optional, required: false, }, { key: required, required: true, }],
    fn(_, _) { true },
  )
  assert_eq(result.missing, [required])
  assert_eq(result.selections.length(), 2)
}

///|
test "a conflicting replacement preserves every previous reservation" {
  let index = @dependency.ProviderIndex::new()
  let tree = @dependency.ScopeTree::new()
  let scope = tree.root()
  let first = @identity.InstanceId::fresh()
  let second = @identity.InstanceId::fresh()
  let a = @identity.KeyId::fresh()
  let b = @identity.KeyId::fresh()
  let c = @identity.KeyId::fresh()
  index.reserve(tree, scope, first, [a])
  index.reserve(tree, scope, second, [b])
  let rejected = try {
    index.reserve(tree, scope, first, [c, b])
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(index.get(tree, scope, a), Some(first))
  assert_eq(index.get(tree, scope, b), Some(second))
  assert_eq(index.get(tree, scope, c), None)
}

///|
test "closing an ancestor prevents creating a descendant scope" {
  let tree = @dependency.ScopeTree::new()
  let child = tree.add(tree.root(), shadow=true)
  tree.close(tree.root())
  assert_true(tree.is_closing(child))
  let rejected = try {
    ignore(tree.add(child))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "a newly introduced shadow provider includes existing ancestor consumers" {
  let tree = @dependency.ScopeTree::new()
  let child = tree.add(tree.root(), shadow=true)
  let sibling = tree.add(tree.root(), shadow=true)
  let graph = @dependency.DependencyGraph::new()
  let consumer = @identity.InstanceId::fresh()
  let other = @identity.InstanceId::fresh()
  let provider = @identity.InstanceId::fresh()
  let key = @identity.KeyId::fresh()
  graph.put(consumer, child, [{ key, required: false, }])
  graph.put(other, sibling, [{ key, required: true, }])
  graph.select(consumer, [{ key, provider: Some(provider), }])
  assert_eq(graph.affected_by(tree, child, key), [consumer])
  graph.select(consumer, [{ key, provider: None, }])
  assert_eq(graph.consumers_of(provider), [])
  assert_eq(graph.waiting_for(key), [consumer])
  graph.remove(consumer)
  assert_eq(graph.waiting_for(key), [])
}
