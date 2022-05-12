# Zig Ring Buffer

A Ring Buffer (or Circular Buffer) struct template in Zig with Reader and Writer interface and optional thread safety.

## Examples

```zig
const RingBuffer = @import("ring_buffer.zig").RingBuffer;

// How to init a ring buffer

// By default, RingBuffer handles bytes (u8)
var buf: [50]u8 = undefined;
var rb1 = RingBuffer(.{}).init(&buf);
var rb2 = RingBuffer(.{ .thread_safe = true }).init(&buf);

// You can also specify an other type
var buf2: [10]?i17 = undefined;
var rb3 = RingBuffer(.{ .ContainedType = ?i17 }).init(&buf2);

// Init with an owned allocated buffer
const alloc = std.heap.page_allocator;
var rb4 = RingBuffer(.{}).init(try alloc.alloc(u8, 60));
defer alloc.free(rb4.buffer);

// How to use the ring buffer

// u8 ring buffers benefit from the reader/writer interface
const reader = rb4.reader();
const writer = rb4.writer();
try writer.print("This is a {}\n", .{ "test" });
var buf3: [4]u8 = undefined;
_ = try reader.readAll(&buf3)
// buf3 now contains "This"

// Pushing and popping individual values
try rb3.push(null);
try rb3.push(727);
_ = try rb3.pop(); // 727
```