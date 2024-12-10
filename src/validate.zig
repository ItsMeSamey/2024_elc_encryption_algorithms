const std = @import("std");

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

