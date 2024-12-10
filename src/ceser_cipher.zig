const std = @import("std");

/// Shifting direction for Ceser Cipher
const ShiftingDirection = enum { increase, decrease };

/// Simd stuff for fast validate
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

/// Simd approach involves @select and turns out to be even slower,
/// or its a skill issue form my side ;)
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


// a simple test for correctness of CeserCipher
test CeserCipher {
  var ce = CeserCipher.init(5, .increase);

  const abcs = CeserCipher.abc;
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

/// A helper function for testing speed
fn speedtest(data: []align(simdVectorLength) u8, ce: anytype, times: usize) u64 {
  var timer = std.time.Timer.start() catch unreachable;
  for (0..times) |_| {
    ce.encrypt(data);
    ce.decrypt(data);
  }
  return timer.read();
}

/// give a random seed for the PRNG (this can never fail)
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

  const ce = CeserCipher.init(5, .increase);

  {
    const warmupTimes = 2;
    _ = speedtest(memory, ce, warmupTimes);
  }

  const times = 1 << 5;
  const time_ce = speedtest(memory, ce, times);
  std.debug.print("CeserCipher: time: \t{d:.6} ns/byte\n", .{@as(f128, @floatFromInt(time_ce)) / @as(f128, @floatFromInt(memory.len))});
}

