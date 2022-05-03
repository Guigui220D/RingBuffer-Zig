const std = @import("std"); 

pub const RingBufferOptions = struct {
    ContainedType: type = u8,
    thread_safe: bool = false,
};

pub fn RingBuffer(comptime options: RingBufferOptions) type {
    const T = options.ContainedType;
    const MutexT = if (options.thread_safe) std.Thread.Mutex else std.Thread.Mutex.Dummy;

    return struct {
        mutex: MutexT,
        buffer: []T,
        head: usize = 0,
        tail: usize = 0,
        used: usize = 0,

        const Rb = @This();

        pub fn init(buf: []T) Rb {
            return .{
                .mutex = .{},
                .buffer = buf
            };
        }

        pub const WriteError = error{RingBufferFull};

        pub const Writer = std.io.Writer(*Rb, WriteError, writeFn);
        pub fn writer(self: *Rb) Writer {
            return .{ .context = self };
        }
        fn writeFn(self: *Rb, m: []const u8) WriteError!usize {
            if (T != u8)
                @compileError("Writer and Reader interfaces only support u8");

            if (m.len == 0)
                return 0;

            self.mutex.lock();
            defer self.mutex.unlock();


            const free_space = self.buffer.len - self.used;
            if (free_space == 0)
                return error.RingBufferFull;

            const writable = std.math.min(m.len, free_space);
            // Write as much as we can
            if (self.head > self.tail) {
                // the available space is not contiguous
                const before_wrap = self.buffer.len - self.head;

                if (before_wrap >= writable) {
                    // things fit without wrapping
                    std.mem.copy(u8, self.buffer[self.head..], m);
                    self.head += writable;
                } else {
                    // we have to wrap
                    std.mem.copy(u8, self.buffer[self.head..], m[0..before_wrap]);
                    std.mem.copy(u8, self.buffer[0..self.tail], m[before_wrap..writable]);
                    self.head = writable - before_wrap;
                }
            } else {
                if (self.head == self.tail) {
                    std.debug.assert(self.used == 0);
                    self.head = 0;
                    self.tail = 0;
                }
                // the available space is contiguous
                std.mem.copy(u8, self.buffer[self.head..], m[0..writable]); // copy what fits
                self.head += writable;
            }

            self.used += writable;
            return writable;
        }

        pub fn push(self: *Rb, value: T) WriteError!void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.used == self.buffer.len)
                return error.RingBufferFull;

            if (self.head == self.buffer.len)
                self.head = 0;
            
            self.buffer[self.head] = value;
            self.head += 1;
            self.used += 1;
        }

        pub const ReadError = error{RingBufferEmpty};

        pub const Reader = std.io.Reader(*Rb, error{}, readFn);
        pub fn reader(self: *Rb) Reader {
            return .{ .context = self };
        }
        fn readFn(self: *Rb, b: []u8) error{}!usize {
            if (T != u8)
                @compileError("Writer and Reader interfaces only support u8");

            if (b.len == 0)
                return 0;

            self.mutex.lock();
            defer self.mutex.unlock();


            const used_space = self.used;
            if (used_space == 0)
                return 0;

            const readable = std.math.min(used_space, b.len);
            // Read as much as we can
            if (self.head > self.tail) {
                // the readable data is contiguous
                std.mem.copy(u8, b, self.buffer[self.tail..(self.tail + readable)]);
                self.tail += readable;
            } else {
                // the readable data is not contiguous
                const before_wrap = self.buffer.len - self.tail;
                
                if (before_wrap >= readable) {
                    // things can be read without wrapping
                    std.mem.copy(u8, b, self.buffer[self.tail..(self.tail + readable)]);
                    self.tail += readable;
                } else {
                    const after_wrap = readable - before_wrap;
                    std.debug.assert(after_wrap <= self.head);

                    // the reading has to wrap
                    std.mem.copy(u8, b[0..before_wrap], self.buffer[self.tail..]);
                    std.mem.copy(u8, b[before_wrap..readable], self.buffer[0..after_wrap]);
                    self.tail = readable - before_wrap;
                }
            }

            self.used -= readable;
            return readable;
        }

        pub fn pop(self: *Rb) ReadError!T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.used == 0)
                return error.RingBufferEmpty;
            
            if (self.tail == self.buffer.len)
                self.tail = 0;

            const value = self.buffer[self.tail];
            self.tail += 1;
            self.used -= 1;

            return value;
        }

        pub fn getUsedSpace(self: *Rb) usize {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.used;
        }

        pub fn getFreeSpace(self: *Rb) usize {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.buffer.len - self.used;
        }

        // TODO: implement interfaces for other contained types than u8

        //NOT THREAD SAFE
        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            opt: std.fmt.FormatOptions,
            w: anytype
        ) !void {
            _ = opt;
            _ = fmt;

            if (T != u8)
                @compileError("Format only implemented for u8 as of now");

            try w.writeAll("\n[");
            for (self.buffer) |byte| {
                try w.print("{x:0>2} ", .{byte});
            }
            try w.writeAll("]\n");
            if (self.head < self.tail) {
                var i: usize = 0;
                try w.writeByte(' ');
                while (i < self.head) : (i += 1) {
                    try w.writeAll("---");
                }
                try w.writeAll("-H ");
                i += 1;
                while (i < self.tail) : (i += 1) {
                    try w.writeAll("   ");
                }
                try w.writeAll(" t-");
                i += 1;
                while (i < self.buffer.len) : (i += 1) {
                    try w.writeAll("---");
                }
            } else if (self.head > self.tail) {
                var i: usize = 0;
                try w.writeByte(' ');
                while (i < self.tail) : (i += 1) {
                    try w.writeAll("   ");
                }
                try w.writeAll(" t-");
                i += 1;
                while (i < self.head) : (i += 1) {
                    try w.writeAll("---");
                }
                try w.writeAll("-H ");
            } else if (self.head == self.tail) {
                try w.writeByte(' ');
                for (self.buffer) |_, i| {
                    if (i == self.head) {
                        try w.writeAll(if (self.used == 0) " ^ " else "-^-");
                    } else {
                        try w.writeAll(if (self.used == 0) "   " else "---");
                    }
                }
            }
            try w.writeByte('\n');
        }
    };
}

test "RingBuffer: writing" {
    // Note: this is NOT how you use a ring buffer
    const tst = std.testing;

    var buf: [10]u8 = undefined;
    var rb = RingBuffer(.{}).init(&buf);
    const w = rb.writer();

    _ = try w.write("0123456789");

    try tst.expectEqualStrings("0123456789", &buf);
    try tst.expectEqual(@as(usize, 10), rb.used);
    try tst.expectEqual(@as(usize, 0), rb.getFreeSpace());

    //std.debug.print("{}\n", .{rb});

    rb = RingBuffer(.{}){ .buffer = &buf, .head = 4, .tail = 3, .used = 1, .mutex = .{} };

    _ = try w.write("abcdefgh");
    _ = try w.write("ijklmnopq");
    try tst.expectError(error.RingBufferFull, w.write("stuvwxyz"));

    try tst.expectEqualStrings("ghi3abcdef", &buf);

    rb = RingBuffer(.{}){ .buffer = &buf, .head = 2, .tail = 3, .used = 9, .mutex = .{} };

    try w.writeByte('_');

    try tst.expectEqualStrings("gh_3abcdef", &buf);
}

test "RingBuffer: full buffer read" {
    // Note: this is NOT how you use a ring buffer
    const tst = std.testing;

    var buf: [10]u8 = undefined;
    var rb = RingBuffer(.{}).init(&buf);
    const w = rb.writer();
    const r = rb.reader();

    // test the scenario where the tail is at the start

    _ = try w.write("0123456789");

    try tst.expectEqualStrings("0123456789", &buf);
    try tst.expectEqual(@as(usize, 10), rb.used);
    try tst.expectEqual(@as(usize, 0), rb.getFreeSpace());

    //std.debug.print("{}", .{rb});

    {
        var rd_buf: [10]u8 = undefined;
        const len = try r.readAll(rd_buf[0..10]);
        try tst.expectEqual(len, 10);
        try tst.expectEqualStrings("0123456789", &rd_buf);
    }

    //std.debug.print("{}", .{rb});

    // Now, for something more tricky, a scenario where the head and tail are the same and are not at the beginning of the array

    _ = try w.write("0123456");
    _ = try r.read(buf[0..5]);
    _ = try w.write("01234567");

    //std.debug.print("{}", .{rb});

    {
        var rd_buf: [10]u8 = undefined;
        const len = try r.readAll(rd_buf[0..9]);
        try tst.expectEqual(len, 9);
        rd_buf[9] = 'a'; // fill
        try tst.expectEqualStrings("560123456a", &rd_buf);
    }

    {
        var rd_buf: [10]u8 = undefined;
        const len = try r.readAll(rd_buf[0..1]);
        try tst.expectEqual(len, 1);
        try tst.expectEqual(rd_buf[0], '7');
    }

    //std.debug.print("{}", .{rb});
}

test "RingBuffer: random writing and reading" {
    const seed = @intCast(u64, std.time.timestamp());

    var prng = std.rand.DefaultPrng.init(seed);
    var rand = prng.random();

    const BUF_SIZE = 25;

    var buf: [BUF_SIZE]u8 = undefined;
    var rb = RingBuffer(.{}).init(&buf);
    const w = rb.writer();
    const r = rb.reader();

    var temp: [BUF_SIZE]u8 = undefined;

    var feeder_array: [2048]u8 = undefined;
    rand.bytes(feeder_array[0..2048]);

    var feeder_write_idx: usize = 0;
    var feeder_read_idx: usize = 0;
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const free = rb.getFreeSpace();
        const to_write = rand.uintAtMost(usize, free);
        _ = try w.writeAll(feeder_array[feeder_write_idx..to_write+feeder_write_idx]);
        
        //std.debug.print("\nWrote {} bytes: {}", .{to_write, rb});

        const used = rb.used;
        const to_read = rand.uintAtMost(usize, used);
        const len = try r.readAll(temp[0..to_read]);

        //std.debug.print("Used : {}\n", .{used});
        //std.debug.print("Read {} bytes: {}", .{to_read, rb});
        
        try std.testing.expectEqual(to_read, len);
        try expectEqualSlicesPrint(temp[0..to_read], feeder_array[feeder_read_idx..to_read+feeder_read_idx]);

        feeder_write_idx += to_write;
        feeder_read_idx += to_read;
    }
}

test "RingBuffer: push and pop" {
    const tst = std.testing;

    var buf: [10]i9 = undefined;
    var rb = RingBuffer(.{ .ContainedType = i9 }).init(&buf);

    try rb.push(255);
    try tst.expectEqual(@as(usize, 1), rb.used);
    try tst.expectEqual(@as(usize, 9), rb.getFreeSpace());
    try tst.expectEqual(@as(i9, 255), try rb.pop());
    try tst.expectError(error.RingBufferEmpty, rb.pop());

    var i: i9 = 0;
    while (i < 10) : (i += 1) {
        try rb.push(i);
    }
    try tst.expectError(error.RingBufferFull, rb.push(11));

    i = 0;
    while (i < 10) : (i += 1) {
        try tst.expectEqual(i, try rb.pop());
    }
    try tst.expectError(error.RingBufferEmpty, rb.pop());
}

fn expectEqualSlicesPrint(expected: []const u8, actual: []const u8) !void {
    if (expected.len != actual.len) {
        std.debug.print("slice lengths differ. expected {d}, found {d}\n", .{ expected.len, actual.len });
        return error.TestExpectedEqual;
    }
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        if (expected[i] != actual[i]) {
            std.debug.print("Actual: \n", .{});
            for (actual) |c| {
                std.debug.print("{x:0>2} ", .{c});
            }
            std.debug.print("\nExpected: \n", .{});
            for (expected) |c| {
                std.debug.print("{x:0>2} ", .{c});
            }
            std.debug.print("\n", .{});
            return error.TestExpectedEqual;
        }
    }
}