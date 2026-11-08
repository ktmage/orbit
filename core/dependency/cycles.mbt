///|
#derive(Eq, Debug)
pub(all) struct Edge {
  before : @identity.InstanceId
  after : @identity.InstanceId
}

///|
#derive(Debug)
pub(all) suberror DependencyCycle {
  DependencyCycle(Array[@identity.InstanceId])
}

///|
pub fn topological_order(
  nodes : Array[@identity.InstanceId],
  edges : Array[Edge],
) -> Array[@identity.InstanceId] raise DependencyCycle {
  let incoming : Map[@identity.InstanceId, Int32] = Map([])
  let outgoing : Map[@identity.InstanceId, Array[@identity.InstanceId]] = Map([])
  for id in nodes {
    incoming[id] = 0
  }
  for edge in edges {
    if incoming.contains(edge.before) && incoming.contains(edge.after) {
      let afters = outgoing.get_or_default(edge.before, [])
      if !afters.contains(edge.after) {
        afters.push(edge.after)
        outgoing[edge.before] = afters
        incoming[edge.after] = incoming[edge.after] + 1
      }
    }
  }
  let ready = incoming
    .iter()
    .filter(fn(entry) { entry.1 == 0 })
    .map(fn(entry) { entry.0 })
    .collect()
  ready.sort()
  let result = []
  let mut index = 0
  while index < ready.length() {
    let id = ready[index]
    index += 1
    result.push(id)
    let afters = outgoing.get_or_default(id, [])
    afters.sort()
    for after in afters {
      incoming[after] = incoming[after] - 1
      if incoming[after] == 0 {
        ready.push(after)
      }
    }
  }
  if result.length() != incoming.length() {
    let blocked = incoming
      .iter()
      .filter(fn(entry) { entry.1 > 0 })
      .map(fn(entry) { entry.0 })
      .collect()
    blocked.sort()
    raise DependencyCycle(find_cycle(blocked, outgoing))
  }
  result
}

///|
fn find_cycle(
  nodes : Array[@identity.InstanceId],
  outgoing : Map[@identity.InstanceId, Array[@identity.InstanceId]],
) -> Array[@identity.InstanceId] {
  let visited : Map[@identity.InstanceId, Unit] = Map([])
  for root in nodes {
    if visited.contains(root) {
      continue
    }
    let stack : Array[(@identity.InstanceId, Int32)] = [(root, 0)]
    let position : Map[@identity.InstanceId, Int32] = Map([(root, 0)])
    while stack.last() is Some((node, index)) {
      let children = outgoing.get_or_default(node, [])
      if index == children.length() {
        ignore(stack.pop())
        position.remove(node)
        visited[node] = ()
        continue
      }
      let child = children[index]
      stack[stack.length() - 1] = (node, index + 1)
      if position.get(child) is Some(start) {
        return stack
          .exact_view(start~)
          .iter()
          .map(fn(frame) { frame.0 })
          .collect()
      }
      if !visited.contains(child) {
        position[child] = stack.length()
        stack.push((child, 0))
      }
    }
  }
  abort("cyclic dependency graph has no cycle")
}

///|
pub fn DependencyGraph::validate(
  self : DependencyGraph,
  tree : ScopeTree,
  providers : ProviderIndex,
) -> Unit raise DependencyCycle {
  let edges = self.planned_edges(tree, providers)
  edges.append(self.ownership_edges(tree))
  ignore(topological_order(self.records.keys().collect(), edges))
}
