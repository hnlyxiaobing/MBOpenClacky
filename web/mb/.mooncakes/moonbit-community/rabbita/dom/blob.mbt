///|
#cfg(target="js")
type Blob

///|
#cfg(target="js")
pub extern "js" fn Blob::get_size(self : Self) -> Int = "(self) => self.size"

///|
#cfg(target="js")
pub extern "js" fn Blob::get_type(self : Self) -> String = "(self) => self.type"

///|
#cfg(target="js")
pub extern "js" fn Blob::slice(
  self : Self,
  start : Int,
  end_? : @js.Optional[Int],
) -> Blob = "(self, start, end) => self.slice(start, end)"

///|
#cfg(target="js")
extern "js" fn Blob::text_ffi(self : Self) -> @js.Promise = "(self) => self.text()"

///|
#cfg(target="js")
pub async fn Blob::text(self : Self) -> String {
  self.text_ffi().wait().cast()
}

///|
#cfg(target="js")
extern "js" fn Blob::bytes_ffi(self : Self) -> @js.Promise =
  #| (self) => self.arrayBuffer().then((buffer) => new Uint8Array(buffer))

///|
#cfg(target="js")
pub async fn Blob::bytes(self : Self) -> Bytes {
  self.bytes_ffi().wait().cast()
}
