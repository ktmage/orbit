///|
pub struct Loader {
  priv scope : @runtime.Scope
  priv records : Map[String, Record]
  priv mutex : @async.Mutex
  priv mut committed : Array[Entry]
  priv mut dirty : Bool
  priv mut closed : Bool
  priv modules : Map[(String, String), @runtime.Plugin[Json]]
}

///|
pub fn Loader::new(scope : @runtime.Scope) -> Loader {
  {
    scope,
    records: Map([]),
    mutex: @async.Mutex::Mutex(),
    committed: [],
    dirty: false,
    closed: false,
    modules: Map([]),
  }
}

///|
pub fn Loader::snapshots(self : Loader) -> Array[EntrySnapshot] {
  let ids = self.records.keys().collect()
  ids.sort()
  ids.map(fn(id) {
    let record = self.records[id]
    {
      id,
      enabled: record.entry.enabled,
      instance: record.handle.map(handle => handle.snapshot()),
    }
  })
}

///|
pub async fn Loader::reconcile(self : Loader, entries : Array[Entry]) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  guard !self.closed else { raise Closed }
  self.validate(entries)
  @async.protect_from_cancel(() => self.commit(entries))
}

///|
fn Loader::validate(_self : Loader, entries : Array[Entry]) -> Unit raise {
  let ids : Map[String, Unit] = Map([])
  for entry in entries {
    guard !entry.id.is_empty() && !ids.contains(entry.id) else {
      raise InvalidEntry(entry.id)
    }
    ids[entry.id] = ()
    entry.plugin.validate(entry.config)
  }
}

///|
async fn Loader::commit(self : Loader, entries : Array[Entry]) -> Unit {
  if self.dirty {
    self.apply(self.committed) catch {
      cause => raise RecoveryFailed(cause)
    }
    self.dirty = false
  }
  self.dirty = true
  self.apply(entries) catch {
    cause => {
      let rollback = try {
        self.apply(self.committed)
        self.dirty = false
        None
      } catch {
        error => Some(error)
      }
      raise ReconcileFailed(cause, rollback)
    }
  }
  self.committed = entries.copy()
  self.dirty = false
}

///|
async fn await_operation(id : String, operation : @runtime.Operation) -> Unit {
  let result = operation.wait()
  guard result is @runtime.Succeeded(_) else { raise ApplyFailed(id, result) }
}

///|
async fn Record::settle(self : Record) -> Unit {
  guard self.handle is Some(handle) else { return }
  if handle.snapshot().failures.any(fn(failure) {
      failure.phase == @runtime.Stop
    }) {
    await_operation(self.entry.id, handle.retry_stop())
  }
  if handle.snapshot().state == @runtime.Removed {
    self.handle = None
  }
}

///|
async fn Loader::apply(self : Loader, entries : Array[Entry]) -> Unit {
  let desired : Map[String, Entry] = Map::from_iter(
    entries.iter().map(entry => (entry.id, entry)),
  )
  let previous_ids = self.records.keys().collect()
  previous_ids.sort()
  for id in previous_ids {
    let record = self.records[id]
    record.settle()
    if desired.get(id) is None ||
      desired.get(id) is Some({ enabled: false, .. }) {
      if record.handle is Some(handle) {
        await_operation(id, handle.remove())
        record.handle = None
      }
      if desired.get(id) is None {
        self.records.remove(id)
      }
    }
  }
  for entry in entries {
    let record = self.records.get_or_default(entry.id, { entry, handle: None, })
    self.records[entry.id] = record
    if !entry.enabled {
      record.entry = entry
      continue
    }
    match record.handle {
      None => {
        let (handle, operation) = self.scope.install(entry.plugin, entry.config)
        record.entry = entry
        record.handle = Some(handle)
        await_operation(entry.id, operation)
      }
      Some(handle) =>
        if !record.entry.equivalent(entry) ||
          handle.snapshot().state == @runtime.Failed {
          let operation = handle.replace(entry.plugin, entry.config)
          record.entry = entry
          await_operation(entry.id, operation)
        }
    }
  }
}

///|
pub async fn Loader::close(self : Loader) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  if self.closed {
    return
  }
  @async.protect_from_cancel(() => self.commit([]))
  self.modules.clear()
  self.closed = true
}
