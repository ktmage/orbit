///|
extern "js" fn memory_bytes() -> Double =
  #| () => { if (globalThis.gc) globalThis.gc(); return process.memoryUsage().heapUsed; }
