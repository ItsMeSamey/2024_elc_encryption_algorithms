const std = @import("std");

/// Shifting direction for Ceser Cipher
const ShiftingDirection = enum { increase, decrease };

const optionalSimdVectorLength: ?comptime_int = std.simd.suggestVectorLength(u8);
pub const simdVectorLength = optionalSimdVectorLength orelse @sizeOf(usize);
pub const Chunk = @Vector(simdVectorLength, u8);


/// Validates that the input is a valid Ceser Cipher string
/// (i.e. it contains only uppercase letters
pub fn validate(data: []const u8) bool {
  const max: Chunk = @splat('Z');
  const min: Chunk = @splat('A');
  
  const till = (data.len - 1) / simdVectorLength;
  for (0..till) |i| {
    const chunk: Chunk = @bitCast(data[i * simdVectorLength ..][0..simdVectorLength].*);
    if (@reduce(.Or, chunk > max) or @reduce(.Or, chunk < min)) return false;
  }
  for (till..data.len) |i| {
    if (data[i] > 'Z' or data[i] < 'A') return false;
  }
  return true;
}

test validate {
  try std.testing.expect(validate("ABCDEFGHIJKLMNOPQRSTUVWXYZ"));
  try std.testing.expect(!validate("!ABCDEFGHIJKLMNOPQRSTUVWXYZZ"));
  try std.testing.expect(!validate("A!BCDEFGHIJKLMNOPQRSTUVWXYZZ"));
  try std.testing.expect(!validate("ABCDEFGHIJKLMNOPQRSTUVWXYZZ!"));
  try std.testing.expect(!validate("ABCDEFGHIJKLMN!OPQRSTUVWXYZZ"));
}

const SimdCeserCipher = struct {
  shift_amount: u5,
  shift_direction: ShiftingDirection,

  pub fn init(amount: usize, direction: ShiftingDirection) @This() {
    return .{
      .shift_amount = @intCast(amount & 31),
      .shift_direction = direction,
    };
  }

  fn uoptimizedOperate(self: *const @This(), bytes: []u8, comptime direction: ShiftingDirection) void {
    for (0..bytes.len) |i| {
      if (direction == .increase) {
        bytes[i] += self.shift_amount;
        if (bytes[i] > 'Z') {
          bytes[i] -= 'Z' + 1 - 'A';
        }
      } else {
        bytes[i] -= self.shift_amount;
        if (bytes[i] < 'A') {
          bytes[i] += 'Z' + 1 - 'A';
        }
      }
    }
  }

  fn operate(self: *const @This(), bytes: []align(simdVectorLength) u8, comptime direction: ShiftingDirection) void {
    const shift_vec: @Vector(simdVectorLength, u8) = @splat(@mod(self.shift_amount, 26));
    const sub_vec: @Vector(simdVectorLength, u8) = @splat('Z' + 1 - 'A');

    const till = (bytes.len - 1) / simdVectorLength;
    for (0..till) |i| {
      const chunk: *Chunk = @alignCast(@ptrCast(bytes[i * simdVectorLength ..][0..simdVectorLength]));
      chunk.* += shift_vec;
      if (direction == .increase) {
        chunk.* += shift_vec;
        const max: Chunk = @splat('Z');
        const outliars = (chunk.* > max);
        chunk.* = @select(u8, outliars, chunk.* - sub_vec, chunk.*);
      } else {
        chunk.* -= shift_vec;
        const min: Chunk = @splat('A');
        const outliars = (chunk.* < min);
        chunk.* = @select(u8, outliars, chunk.* + sub_vec, chunk.*);
      }
    }

    self.uoptimizedOperate(bytes[till..], direction);
  }

  pub fn encrypt(self: *const @This(), data: []align(simdVectorLength) u8) void {
    switch (self.shift_direction) {
      inline .increase => self.operate(data, .increase),
      inline .decrease => self.operate(data, .decrease),
    }
  }

  pub fn decrypt(self: *const @This(), data: []align(simdVectorLength) u8) void {
    switch (self.shift_direction) {
      inline .increase => self.operate(data, .decrease),
      inline .decrease => self.operate(data, .increase),
    }
  }
};

const CeserCipher = struct {
  shift_amount: u5,
  shift_direction: ShiftingDirection,
  buf: [2 * abc.len]u8,

  const abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

  pub fn init(amount: usize, direction: ShiftingDirection) @This() {
    var self = @This(){
      .shift_amount = @intCast(amount & 31),
      .shift_direction = direction,
      .buf = undefined,
    };
    const foreword = self.buf[0..abc.len];
    const backward = self.buf[abc.len..];

    @memcpy(foreword, abc);
    @memcpy(backward, abc);

    if (self.shift_direction == .increase) {
      std.mem.rotate(u8, foreword, self.shift_amount);
      std.mem.rotate(u8, backward, abc.len - self.shift_amount);
    } else {
      std.mem.rotate(u8, foreword, abc.len - self.shift_amount);
      std.mem.rotate(u8, backward, self.shift_amount);
    }

    return self;
  }

  pub fn encrypt(self: *const @This(), data: []u8) void {
    const table: [*]const u8 = @ptrFromInt(@intFromPtr(self.buf[0..].ptr) - @as(usize, 'A'));
    for (data) |*byte| byte.* = table[byte.*];
  }

  pub fn decrypt(self: *const @This(), data: []u8) void {
    const table: [*]const u8 = @ptrFromInt(@intFromPtr(self.buf[abc.len..].ptr) - @as(usize, 'A'));
    for (data) |*byte| byte.* = table[byte.*];
  }
};

test SimdCeserCipher {
  var ce = SimdCeserCipher.init(5, .increase);

  const abcs = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  var abcs_buf: [abcs.len]u8 align(simdVectorLength) = undefined;
  @memcpy(&abcs_buf, abcs);

  var shifted_buf: [abcs.len]u8 align(simdVectorLength) = undefined;
  @memcpy(&shifted_buf, abcs);
  std.mem.rotate(u8, &shifted_buf, ce.shift_amount);

  ce.encrypt(&abcs_buf);
  try std.testing.expectEqualStrings(&shifted_buf, &abcs_buf);

  ce.decrypt(&shifted_buf);
  try std.testing.expectEqualStrings(abcs, &shifted_buf);
}

test CeserCipher {
  var ce = CeserCipher.init(5, .increase);

  const abcs = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  var abcs_buf: [abcs.len]u8 align(simdVectorLength) = undefined;
  @memcpy(&abcs_buf, abcs);

  var shifted_buf: [abcs.len]u8 align(simdVectorLength) = undefined;
  @memcpy(&shifted_buf, abcs);
  std.mem.rotate(u8, &shifted_buf, ce.shift_amount);

  ce.encrypt(&abcs_buf);
  try std.testing.expectEqualStrings(&shifted_buf, &abcs_buf);

  ce.decrypt(&shifted_buf);
  try std.testing.expectEqualStrings(abcs, &shifted_buf);
}

fn speedtest(data: []align(simdVectorLength) u8, ce: anytype, times: usize) u64 {
  var timer = std.time.Timer.start() catch unreachable;
  for (0..times) |_| {
    ce.encrypt(data);
    ce.decrypt(data);
  }
  return timer.read();
}

fn getPrng() std.Random.DefaultPrng {
  if (@inComptime()) @compileError("Rng cannot be initilaized at comptime");
  return std.Random.DefaultPrng.init(init: {
    const bigTimestamp = std.time.nanoTimestamp();
    const allegedTimestamp: i64 = @truncate(bigTimestamp ^ (bigTimestamp >> 64));
    var timestamp: u64 = @bitCast(allegedTimestamp);
    var seed: u64 = undefined;

    std.posix.getrandom(std.mem.asBytes(&seed)) catch |e| {
      std.log.err("Recoverable Error: RNG initialization failed:\n{}", .{e});
      timestamp ^= @bitCast(std.time.microTimestamp());
    };
    break :init timestamp ^ seed;
  });
}

pub fn main() !void {
  const allocator = std.heap.page_allocator;

  var rng = getPrng();
  var random = rng.random();

  const memory = try allocator.alignedAlloc(u8, simdVectorLength, 1 << 20);

  for (memory) |*byte| {
    byte.* = random.intRangeAtMost(u8, 'A', 'Z');
  }

  const sce = SimdCeserCipher.init(5, .increase);
  const ce = SimdCeserCipher.init(5, .increase);

  const times = 1 << 5;

  const time_sce = speedtest(memory, sce, times);
  const time_ce = speedtest(memory, ce, times);

  std.log.info("SimdCeserCipher: time: {d:6.2} ns/byte", .{time_sce});
  std.log.info("CeserCipher: time: {d:6.2} ns/byte", .{time_ce});
}

