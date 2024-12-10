//! Simd approach involves @select and turns out to be even slower,
//! or its a skill issue form my side ;)

const std = @import("std");
const Validate = @import("validate.zig");

/// Shifting direction for Ceser Cipher
const ShiftingDirection = enum { increase, decrease };

shift_amount: u5,
shift_direction: ShiftingDirection,
buf: [2 * Validate.ABCD.len]u8,

pub fn init(amount: usize, direction: ShiftingDirection) @This() {
  var self = @This(){
    .shift_amount = @intCast(amount & 31),
    .shift_direction = direction,
    .buf = undefined,
  };
  const foreword = self.buf[0..Validate.ABCD.len];
  const backward = self.buf[Validate.ABCD.len..];

  @memcpy(foreword, Validate.ABCD);
  @memcpy(backward, Validate.ABCD);

  if (self.shift_direction == .increase) {
    std.mem.rotate(u8, foreword, self.shift_amount);
    std.mem.rotate(u8, backward, Validate.ABCD.len - self.shift_amount);
  } else {
    std.mem.rotate(u8, foreword, Validate.ABCD.len - self.shift_amount);
    std.mem.rotate(u8, backward, self.shift_amount);
  }

  return self;
}

pub fn encrypt(self: *const @This(), data: []u8) void {
  encryptImmutable(self, data, data);
}

pub fn encryptImmutable(self: *const @This(), data: []const u8, out: []u8) void {
  std.debug.assert(data.len <= out.len);
  const table: [*]const u8 = @ptrFromInt(@intFromPtr(self.buf[0..].ptr) - @as(usize, 'A'));
  for (data, 0..) |byte, i| out[i] = table[byte];
}

pub fn decrypt(self: *const @This(), data: []u8) void {
  decryptImmutable(self, data, data);
}

pub fn decryptImmutable(self: *const @This(), data: []const u8, out: []u8) void {
  std.debug.assert(data.len <= out.len);
  const table: [*]const u8 = @ptrFromInt(@intFromPtr(self.buf[Validate.ABCD.len..].ptr) - @as(usize, 'A'));
  for (data, 0..) |byte, i| out[i] = table[byte];
}

// a simple test for correctness of CeserCipher
test {
  const CeserCipher = @This();
  var ce = CeserCipher.init(5, .increase);

  const abcs = Validate.ABCD;
  var abcs_buf: [abcs.len]u8 = undefined;
  @memcpy(&abcs_buf, abcs);

  var shifted_buf: [abcs.len]u8 = undefined;
  @memcpy(&shifted_buf, abcs);
  std.mem.rotate(u8, &shifted_buf, ce.shift_amount);

  ce.encrypt(&abcs_buf);
  try std.testing.expectEqualStrings(&shifted_buf, &abcs_buf);

  ce.decrypt(&shifted_buf);
  try std.testing.expectEqualStrings(abcs, &shifted_buf);
}

