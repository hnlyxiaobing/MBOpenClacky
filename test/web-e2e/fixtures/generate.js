const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

function makeChunk(type, data) {
  const typeBytes = Buffer.from(type);
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const crcInput = Buffer.concat([typeBytes, data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(crcInput));
  return Buffer.concat([len, typeBytes, data, crc]);
}

function crc32(buf) {
  let crc = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) {
    crc ^= buf[i];
    for (let j = 0; j < 8; j++) {
      crc = (crc >>> 1) ^ (crc & 1 ? 0xEDB88320 : 0);
    }
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

const width = 4, height = 4;
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(width, 0);
ihdr.writeUInt32BE(height, 4);
ihdr[8] = 8;  // bit depth
ihdr[9] = 2;  // color type: RGB
ihdr[10] = 0; // compression
ihdr[11] = 0; // filter
ihdr[12] = 0; // interlace

const rawRows = [];
for (let y = 0; y < height; y++) {
  const row = Buffer.alloc(1 + width * 3);
  row[0] = 0; // filter: none
  for (let x = 0; x < width; x++) {
    row[1 + x * 3] = 255;     // R
    row[1 + x * 3 + 1] = 0;   // G
    row[1 + x * 3 + 2] = 0;   // B
  }
  rawRows.push(row);
}
const idatData = zlib.deflateSync(Buffer.concat(rawRows));

const png = Buffer.concat([
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  makeChunk('IHDR', ihdr),
  makeChunk('IDAT', idatData),
  makeChunk('IEND', Buffer.alloc(0)),
]);

fs.writeFileSync(path.join(__dirname, 'red.png'), png);
console.log('Generated red.png:', png.length, 'bytes');
