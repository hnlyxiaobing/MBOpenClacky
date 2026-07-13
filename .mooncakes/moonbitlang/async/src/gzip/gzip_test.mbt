// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
#cfg(target="native")
async fn node_gzip(mode : String, input : Bytes) -> Bytes {
  @async.with_task_group() <| group => {
    let (stdin, we_write) = @process.write_to_process()
    let runner = group.spawn(() => {
      @process.collect_output("node", ["src/gzip/node_gzip.js", mode], stdin~)
    })
    group.spawn_bg() <| () => {
      defer we_write.close()
      we_write.write(input)
    }
    let (code, stdout, stderr) = runner.wait()
    @debug.assert_eq(code, 0)
    @debug.assert_eq(stderr.binary().length(), 0)
    stdout.binary()
  }
}

///|
#cfg(target="native")
async fn encode_with_moonbit(input : Bytes) -> Bytes {
  let (r, w) = @io.pipe()
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      defer w.close()
      @gzip.Encoder(w)..write(input).end()
    }
    defer r.close()
    r.read_all().binary()
  }
}

///|
#cfg(target="native")
async fn decode_with_moonbit(input : Bytes) -> Bytes {
  let (r, w) = @io.pipe()
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      defer w.close()
      w.write(input)
    }
    defer r.close()
    @gzip.Decoder(r).read_all().binary()
  }
}

///|
#cfg(target="native")
async fn assert_node_compatibility(input : Bytes) -> Unit {
  let node_encoded = node_gzip("compress", input)
  assert_true(decode_with_moonbit(node_encoded) == input)

  let moonbit_encoded = encode_with_moonbit(input)
  assert_true(node_gzip("decompress", moonbit_encoded) == input)
}

///|
async test "encode decode roundtrip" {
  @async.with_task_group() <| root => {
    let source_chunks = ["hello ", "gzip ", "world"]
    let (compressed_r, compressed_w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer compressed_w.close()
      let encoder = @gzip.Encoder(
        compressed_w,
        mtime=123456789U,
        operating_system=b'\x03',
      )
      for chunk in source_chunks {
        encoder.write(chunk)
        @async.sleep(10)
      }
      encoder.end()
    }

    let decoder = @gzip.Decoder(compressed_r)
    @debug.debug_inspect(decoder.read_all().text(), content="hello gzip world")
    compressed_r.close()
  }
}

///|
async test "encoder uses valid blocks across large writes" {
  @async.with_task_group() <| root => {
    let payload = Bytes::makei(70000, i => (i % 251).to_byte())
    let (compressed_r, compressed_w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer compressed_w.close()
      let encoder = @gzip.Encoder(compressed_w)
      encoder.write(payload)
      encoder.end()
    }

    let decoder = @gzip.Decoder(compressed_r)
    @debug.debug_inspect(decoder.read_all().binary() == payload, content="true")
    compressed_r.close()
  }
}

///|
async test "encoder emits output when flushed" {
  let log : Array[String] = []
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      log.push("start init")
      let encoder = @gzip.Encoder(w)
      log.push("encoder ready")
      log.push("write plain ab")
      encoder.write("ab")
      encoder.flush()
      @async.sleep(60)
      log.push("write plain cd")
      encoder.write("cd")
      encoder.flush()
      @async.sleep(60)
      log.push("end")
      encoder.end()
    }
    root.spawn_bg() <| () => {
      defer r.close()
      while r.read_some() is Some(chunk) {
        log.push("receive compressed \{chunk.length()}")
      }
    }
  }
  json_inspect(log, content=[
    "start init", "encoder ready", "write plain ab", "receive compressed 13", "write plain cd",
    "receive compressed 3", "end", "receive compressed 10",
  ])
}

///|
async test "decoder yields plain chunks lazily across delayed chunks" {
  let log : Array[String] = []
  @async.with_task_group() <| root => {
    let (compressed_r, compressed_w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer compressed_w.close()
      compressed_w.write(b"\u{1f}\u{8b}\u{08}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{ff}")
      @async.sleep(20)
      log.push("write plain ab")
      compressed_w.write(b"\u{00}\u{02}\u{00}\u{fd}\u{ff}ab")
      @async.sleep(200)
      log.push("write plain cd")
      compressed_w.write(b"\u{00}\u{02}\u{00}\u{fd}\u{ff}cd")
      @async.sleep(200)
      log.push("write plain ef")
      compressed_w.write(b"\u{00}\u{02}\u{00}\u{fd}\u{ff}ef")
      @async.sleep(200)
      log.push("finish")
      compressed_w.write(b"\u{01}\u{00}\u{00}\u{ff}\u{ff}")
      compressed_w.write(b"\u{ef}\u{39}\u{8e}\u{4b}\u{06}\u{00}\u{00}\u{00}")
    }
    let decoder = @gzip.Decoder(compressed_r)
    match decoder.read_some(max_len=2) {
      Some(chunk) => log.push("read plain \{@utf8.decode(chunk)}")
      None => assert_true(false)
    }
    match decoder.read_some(max_len=2) {
      Some(chunk) => log.push("read plain \{@utf8.decode(chunk)}")
      None => assert_true(false)
    }
    match decoder.read_some(max_len=2) {
      Some(chunk) => log.push("read plain \{@utf8.decode(chunk)}")
      None => assert_true(false)
    }
    debug_inspect(decoder.read_some(max_len=2), content="None")
  }
  json_inspect(log, content=[
    "write plain ab", "read plain ab", "write plain cd", "read plain cd", "write plain ef",
    "read plain ef", "finish",
  ])
}

///|
async test "decoder supports reads smaller than writer chunks" {
  @async.with_task_group() <| root => {
    let (compressed_r, compressed_w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer compressed_w.close()
      compressed_w.write(b"\u{1f}\u{8b}\u{08}\u{00}\u{00}\u{00}\u{00}\u{00}\u{00}\u{ff}")
      compressed_w.write(b"\u{00}\u{04}\u{00}\u{fb}\u{ff}abcd")
      @async.sleep(200)
      compressed_w.write(b"\u{00}\u{04}\u{00}\u{fb}\u{ff}efgh")
      compressed_w.write(b"\u{01}\u{00}\u{00}\u{ff}\u{ff}")
      compressed_w.write(b"\u{50}\u{2a}\u{ef}\u{ae}\u{08}\u{00}\u{00}\u{00}")
    }
    let decoder = @gzip.Decoder(compressed_r)
    debug_inspect(
      decoder.read_some(max_len=2),
      content=(
        #|Some(<Bytes: [0x61, 0x62]>)
      ),
    )
    debug_inspect(
      decoder.read_some(max_len=2),
      content=(
        #|Some(<Bytes: [0x63, 0x64]>)
      ),
    )
    debug_inspect(
      decoder.read_some(max_len=2),
      content=(
        #|Some(<Bytes: [0x65, 0x66]>)
      ),
    )
    debug_inspect(
      decoder.read_some(max_len=2),
      content=(
        #|Some(<Bytes: [0x67, 0x68]>)
      ),
    )
    debug_inspect(decoder.read_some(max_len=2), content="None")
  }
}

///|
#cfg(target="native")
async test "node compatibility on source text file" {
  let input = @fs.read_file("src/internal/gzip_internal/decoder.mbt").binary()
  assert_node_compatibility(input)
}

///|
#cfg(target="native")
async test "node compatibility on generated binary data" {
  let input = Bytes::makei(65536 + 257, i => ((i * 73 + 19) & 0xff).to_byte())
  assert_node_compatibility(input)
}

///|
#cfg(not(target="native"))
let _unused : Unit = {
  ignore(@fs.unimplemented)
  ignore(@process.unimplemented)
}
