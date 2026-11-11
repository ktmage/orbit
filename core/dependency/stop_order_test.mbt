///|
test "transitive consumers stop before providers and unrelated instances remain outside" {
  let provider = @identity.InstanceId::fresh()
  let middle = @identity.InstanceId::fresh()
  let consumer = @identity.InstanceId::fresh()
  let unrelated = @identity.InstanceId::fresh()
  let edges : Array[@dependency.Edge] = [
    { before: consumer, after: middle, },
    { before: middle, after: provider, },
  ]
  let order = @dependency.stop_order([provider], edges)
  assert_eq(order, [consumer, middle, provider])
  assert_false(order.contains(unrelated))
}

///|
test "a later provider that closes a dependency cycle is rejected" {
  let tree = @dependency.ScopeTree::new()
  let graph = @dependency.DependencyGraph::new()
  let providers = @dependency.ProviderIndex::new()
  let a = @identity.InstanceId::fresh()
  let b = @identity.InstanceId::fresh()
  let key_a = @identity.KeyId::fresh()
  let key_b = @identity.KeyId::fresh()
  graph.put(a, tree.root(), [{ key: key_b, required: true, }])
  providers.reserve(tree, tree.root(), a, [key_a])
  graph.validate(tree, providers)
  let proposed_graph = graph.copy()
  let proposed_providers = providers.copy()
  proposed_graph.put(b, tree.root(), [{ key: key_a, required: true, }])
  proposed_providers.reserve(tree, tree.root(), b, [key_b])
  let rejected = try {
    proposed_graph.validate(tree, proposed_providers)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  graph.validate(tree, providers)
  assert_eq(providers.get(tree, tree.root(), key_b), None)
}

///|
test "ownership and service edges jointly constrain shutdown" {
  let owner = @identity.InstanceId::fresh()
  let owned = @identity.InstanceId::fresh()
  let provider = @identity.InstanceId::fresh()
  let tree = @dependency.ScopeTree::new()
  let child = tree.add(tree.root(), owner={
    instance: owner,
    activation: @identity.ActivationId::fresh(),
  })
  let graph = @dependency.DependencyGraph::new()
  graph.put(owner, tree.root(), [])
  graph.put(owned, child, [])
  graph.select(owned, [
    { key: @identity.KeyId::fresh(), provider: Some(provider), },
  ])
  let edges = graph.selected_edges()
  edges.append(graph.ownership_edges(tree))
  assert_eq(@dependency.stop_order([owner], edges), [owned, owner])
  edges.push({ before: owner, after: owned, })
  let rejected = try {
    ignore(@dependency.stop_order([owner], edges))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "cycle diagnostics do not include a provider outside the cycle" {
  let a = @identity.InstanceId::fresh()
  let b = @identity.InstanceId::fresh()
  let provider = @identity.InstanceId::fresh()
  let cycle = try {
    ignore(
      @dependency.topological_order([a, b, provider], [
        { before: a, after: b, },
        { before: b, after: a, },
        { before: b, after: provider, },
      ]),
    )
    []
  } catch {
    @dependency.DependencyCycle(instances) => instances
  }
  assert_eq(cycle, [a, b])
}
