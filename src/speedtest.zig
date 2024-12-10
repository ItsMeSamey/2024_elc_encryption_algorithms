//! This file is for testing the speed of Cipher Implementations

const std = @import("std");
const CeserCipher = @import("ceser_cipher.zig");

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

/// A helper function for testing speed of the CeserCipher
fn speedtestCeserCipher(allocator: std.mem.Allocator, data: []u8, warmup_times: usize, times: usize) u64 {
  const ce = CeserCipher.init(5, .increase);

  if (warmup_times > 0) _ = speedtestCeserCipher(allocator, data, 0, warmup_times);

  var timer = std.time.Timer.start() catch unreachable;
  for (0..times) |_| {
    ce.encrypt(data);
    ce.decrypt(data);
  }
  return timer.read();
}

/// the main function
pub fn main() !void {
  const allocator = std.heap.page_allocator;
  // The memory that will be encrypt and decrypted
  const memory = try allocator.alloc(u8, 1 << 20);

  // Swtup memory for the test with random data
  var rng = getPrng();
  var random = rng.random();
  for (memory) |*byte| byte.* = random.intRangeAtMost(u8, 'A', 'Z');

  // warmup memory before testing, this will lower the number of dubious results
  const warmup_times = 1;

  // How many times to run the test
  const times = 1 << 5;

  const time_ce = speedtestCeserCipher(allocator, memory, warmup_times, times);
  std.debug.print("CeserCipher: time: \t{d:.6} ns/byte\n", .{@as(f128, @floatFromInt(time_ce)) / @as(f128, @floatFromInt(memory.len))});
}

