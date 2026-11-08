///|
fn Runtime::refresh(self : Runtime) -> Unit {
  let mut advanced = true
  while advanced {
    advanced = false
    let earlier : Array[Change] = []
    for change in self.changes.copy() {
      if change.phase is Done {
        continue
      }
      if change.phase is Queued {
        self.prepare_change(change)
      }
      if change.phase is Queued &&
        !earlier.any(fn(previous) {
          previous.affected.any(fn(id) { change.affected.contains(id) })
        }) {
        self.activate_change(change)
        advanced = true
      }
      earlier.push(change)
    }
    let edges = self.dependencies.selected_edges()
    edges.append(self.dependencies.ownership_edges(self.scopes))
    for instance in self.instances.values().collect() {
      guard instance.activation is Some(activation) && !activation.normal_valid else {
        continue
      }
      let blocked = edges.any(fn(edge) {
        edge.after == instance.id &&
        (match self.instances.get(edge.before) {
          Some(record) => record.activation is Some(_)
          None => false
        })
      })
      if next_action(
          instance.state,
          has_activation=true,
          stopping=activation.stopping || activation.stop_error is Some(_),
          stop_requested=true,
          blocked_by_consumers=blocked,
          registered=instance.desired,
          failed=instance.fatal is Some(_),
          may_start=false,
          missing=false,
        )
        is StopInstance {
        self.begin_stop(instance, activation)
        advanced = true
      }
    }
    for change in self.changes.copy() {
      if change.phase is Ending &&
        change.stop_targets.all(fn(id) {
          match self.instances.get(id) {
            Some(instance) => instance.activation is None
            None => true
          }
        }) {
        self.apply_change(change)
        advanced = true
      }
    }
    let nodes = self.instances.keys().collect()
    let start_order = @dependency.topological_order(
      nodes,
      self.dependencies.planned_edges(self.scopes, self.planned_providers()),
    ) catch {
      _ => nodes
    }
    for id in start_order.rev_iter() {
      guard self.instances.get(id) is Some(instance) else { continue }
      let may_start = match instance.change {
        Some(change) => change.phase is Settling
        None => true
      }
      if !instance.desired || self.scopes.is_closing(instance.scope) {
        continue
      }
      let resolution = self.resolve(instance)
      if instance.activation is None && instance.missing != resolution.missing {
        instance.missing = resolution.missing.copy()
        self.notify(instance)
      }
      let initializing_provider = instance.definition.requires.any(fn(
        requirement,
      ) {
        @dependency.resolve(
          self.scopes,
          self.providers,
          instance.scope,
          [requirement],
          fn(_, _) { true },
        ).selections.any(fn(selection) {
          match selection.provider {
            Some(provider) =>
              match self.instances.get(provider) {
                Some(record) =>
                  record.state == Starting &&
                  (match (instance.change, record.change) {
                    (Some(consumer_change), Some(provider_change)) =>
                      consumer_change.operation.id() ==
                      provider_change.operation.id()
                    _ => false
                  })
                None => false
              }
            None => false
          }
        })
      })
      match
        next_action(
          instance.state,
          has_activation=instance.activation is Some(_),
          stopping=false,
          stop_requested=false,
          blocked_by_consumers=false,
          registered=instance.desired,
          failed=instance.fatal is Some(_),
          may_start=may_start && !initializing_provider,
          missing=!resolution.missing.is_empty(),
        ) {
        StartInstance => {
          self.begin_start(instance, resolution)
          advanced = true
        }
        WaitForServices => {
          instance.state = Waiting
          self.notify(instance)
          advanced = true
        }
        NoAction | StopInstance => ()
      }
    }
    for instance in self.instances.values().collect() {
      if instance.activation is Some(activation) &&
        activation.published &&
        self.resolve(instance).selections != activation.selections {
        match instance.change {
          Some(change) if change.phase is Settling => {
            let affected = self.stop_order([instance.id])
            for id in affected {
              if !change.affected.contains(id) {
                change.affected.push(id)
              }
              if !change.stop_targets.contains(id) {
                change.stop_targets.push(id)
              }
            }
            change.phase = Ending
            self.supersede(change, affected, cancel_queued=false)
            self.stop_change_targets(change)
            advanced = true
          }
          None => {
            let change = self.new_change(
              [instance.id],
              Operation::new(self.id, false),
            )
            self.changes.push(change)
            advanced = true
          }
          _ => ()
        }
      }
    }
    for change in self.changes.copy() {
      if change.phase is Settling &&
        change.affected.all(fn(id) {
          match self.instances.get(id) {
            Some(instance) =>
              instance.state != Starting && instance.state != Stopping
            None => true
          }
        }) {
        self.finish_change(change)
        advanced = true
      }
    }
    self.changes.retain(fn(change) { !(change.phase is Done) })
  }
}
