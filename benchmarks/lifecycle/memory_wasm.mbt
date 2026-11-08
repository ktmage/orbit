///|
extern "wasm" fn memory_pages() -> UInt32 =
  #| (func (result i32) (memory.size))

///|
fn memory_bytes() -> Double {
  memory_pages().to_double() * 65536.0
}
