///|
pub fn stop_order(
  targets : Array[@identity.InstanceId],
  edges : Array[Edge],
) -> Array[@identity.InstanceId] raise DependencyCycle {
  let included : Map[@identity.InstanceId, Unit] = Map([])
  let pending = targets.copy()
  let predecessors : Map[@identity.InstanceId, Array[@identity.InstanceId]] = Map([],
  )
  for edge in edges {
    let before = predecessors.get_or_default(edge.after, [])
    before.push(edge.before)
    predecessors[edge.after] = before
  }
  let mut index = 0
  while index < pending.length() {
    let id = pending[index]
    index += 1
    if !included.contains(id) {
      included[id] = ()
      pending.append(predecessors.get_or_default(id, []))
    }
  }
  topological_order(included.keys().collect(), edges)
}
