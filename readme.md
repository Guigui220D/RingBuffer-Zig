# Zig Ring Buffer

A Ring Buffer (or Circular Buffer) struct template in Zig with Reader and Writer interface and thread safety.

## Examples

```zig
const RingBuffer = @import("ring_buffer.zig").RingBuffer;

// How to init a ring buffer

// By default, RingBuffer handles bytes (u8)
var buf1: [50]u8 = undefined;
var rb1 = RingBuffer(.{}).init(&buf1);

// You can also specify an other type
var buf2: [10]?i17 = undefined;
var rb2 = RingBuffer(.{ .T = ?i17 }).init(&buf2);

// Init with an owned allocated buffer
const alloc = std.heap.page_allocator;
var rb3 = RingBuffer(.{}).init(try alloc.alloc(u8, 60));
defer alloc.free(rb3.buffer);

// How to use the ring buffer

// u8 ring buffers benefit from the reader/writer interface
const reader = rb3.reader();
const writer = rb3.writer();
try writer.print("This is a {}\n", .{ "test" });
var buf3: [4]u8 = undefined;
_ = try reader.readAll(&buf3)
// buf3 now contains "This"

// Pushing and popping individual values
try rb2.push(null);
try rb2.push(727);
_ = try rb2.pop(); // 727
```