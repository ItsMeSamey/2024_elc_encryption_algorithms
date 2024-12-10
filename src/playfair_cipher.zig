//! This is implementation of Playfair Cipher
//! We replace / Treat all J's as I's as described in assignment

const std = @import("std");
const builtin = @import("builtin");
const Validate = @import("validate.zig");

key: [5][5]u8,
missing: u8 = 'J',
replacement: u8 = 'I',
uncommon: u8 = 'X',
secondary_uncommon: u8 = 'Q',

indexLookup: [Validate.ABCD.len]IndexPair,

const IndexPair = packed struct {
  x: u4,
  y: u4,
};

fn getIdxPtr(self: *@This()) [*]IndexPair {
  return @ptrFromInt(@intFromPtr(&self.indexLookup) - @as(usize, 'A'));
}

const keyError = error{ InvalidKey };

/// Setup the indexLookup table and the missing character
fn getMissingCharacter(self: *@This()) !void {
  const lt = self.getIdxPtr();
  var done = std.bit_set.IntegerBitSet(Validate.ABCD.len).initEmpty();
  for (self.key, 0..) |row, x| {
    for (row, 0..) |byte, y| {
      const idx = std.mem.indexOfScalar(u8, Validate.ABCD, byte).?;
      lt[idx] = IndexPair{ .x = @intCast(x), .y = @intCast(y) };
      done.set(idx);
    }
  }

  if (25 != done.count()) return keyError.InvalidKey;
  for (Validate.ABCD, 0..) |byte, i| {
    if (done.isSet(i)) continue;
    self.missing = byte;
    lt[i] = lt[self.replacement];
  }
}

/// Init the Playfair Cipher, returns error.InvalidKey if key is invalid
pub fn init(key: [5][5]u8, replacement: u8, uncommon: u8, secondary_uncommon: u8) keyError!@This() {
  // Ensure that all characters in key are unique
  var self = @This(){
    .key = key,
    .replacement = replacement,
    .uncommon = uncommon,
    .secondary_uncommon = secondary_uncommon,
    .missing = undefined,
    .indexLookup = undefined,
  };

  try self.getMissingCharacter();
  return self;
}

/// Alias for general purpose expanding sltring
const String = std.ArrayList(u8);

/// Fix the input so that it follows the rules of Playfair Cipher
fn fixInput(self: *@This(), input: []const u8, out: *String) !void {
  try out.append(input[0]);
  for (input[1..]) |byte| {
    const to_insrert = if (byte == self.missing) byte else self.replacement;
    if (to_insrert == out.getLast()) {
      try out.append(if(to_insrert == self.uncommon) self.secondary_uncommon else self.uncommon); 
    }
    try out.append(to_insrert);
  }

  // Make input of even length
  if (out.items.len & 1 == 1) {
    try out.append(if (out.getLast() == self.uncommon) self.secondary_uncommon else self.uncommon);
  }
}

/// Encrypts the input in place, provided that it is a valid Playfair Cipher string
/// i.e. fixInput has been called on it
fn encryptFixed(self: *@This(), data: []u8) void {
  // The input must be of even length
  std.debug.assert(data.len & 1 == 0);
  const lt = self.getIdxPtr();

  var i: usize = 0;
  while (i < data.len): (i += 2) {
    var first = lt[data[i]];
    var second =  lt[data[i + 1]];

    std.debug.assert(first.x != second.x or first.y != second.y);
    if (first.x == second.x) {
      first.x += 1; if (first.x == 5) first.x = 0;
      second.x += 1; if (second.x == 5) second.x = 0;
    } else if (first.y == second.y) {
      first.y += 1; if (first.y == 5) first.y = 0;
      second.y += 1; if (second.y == 5) second.y = 0;
    } else {
      const fx = first.x;
      const sx = second.x;

      first.x = sx;
      second.x = fx;
    }

    data[i] = self.key[first.x][first.y];
    data[i + 1] = self.key[second.x][second.y];
  }
}

/// The returned slice must be freed by the caller
pub fn encryptAllocator(self: *@This(), data: []const u8, allocator: std.mem.Allocator) ![]u8 {
  var out_string = String.init(allocator);

  errdefer out_string.deinit();
  try fixInput(self, data, &out_string);
  const out = try out_string.toOwnedSlice();
  self.encryptFixed(out);

  return out;
}

const OOM = std.mem.Allocator.Error.OutOfMemory;
/// Tries to encrypt the input, if slice is not large enough it will return OOM error
pub fn encryptBufAssumecapacity(self: *@This(), data: []const u8, slice: []u8) std.mem.Allocator![]u8 {
  if (data.len > slice.len) return OOM;

  // failing_allocator that always returns OOM
  const allocator = std.testing.failing_allocator_instance.allocator();

  var out_string = String.init(allocator);
  out_string.items = slice;
  out_string.capacity = slice.len;
  out_string.len = 0;

  try fixInput(self, data, &out_string);
  self.encryptFixed(out_string.items);
  return out_string.items;
}

/// Decrypt the input in place
pub fn decrypt(self: *@This(), data: []u8) void {
  decryptImmutable(self, data, data);
}

/// Decrypt the input to out
pub fn decryptImmutable(self: *@This(), data: []const u8, out: []u8) void {
  // The input must be of even length
  std.debug.assert(data.len & 1 == 0);
  std.debug.assert(data.len <= out.len);
  const lt = self.getIdxPtr();

  var i: usize = 0;
  while (i < data.len): (i += 2) {
    var first = lt[data[i]];
    var second =  lt[data[i + 1]];

    std.debug.assert(first.x != second.x or first.y != second.y);
    if (first.x == second.x) {
      if (first.x == 0) first.x = 4 else first.x -= 1;
      if (second.x == 0) second.x = 4 else second.x -= 1;
    } else if (first.y == second.y) {
      if (first.y == 0) first.y = 4 else first.y -= 1;
      if (second.y == 0) second.y = 4 else second.y -= 1;
    } else {
      const fx = first.x;
      const sx = second.x;

      first.x = sx;
      second.x = fx;
    }

    out[i] = self.key[first.x][first.y];
    out[i + 1] = self.key[second.x][second.y];
  }
}


test {
  const PlayfairCipher = @This();
  var pf = try PlayfairCipher.init(
    [5][5]u8{
      [5]u8{ 'A', 'B', 'C', 'D', 'E' },
      [5]u8{ 'F', 'G', 'H', 'I', 'K' },
      [5]u8{ 'L', 'M', 'N', 'O', 'P' },
      [5]u8{ 'Q', 'R', 'S', 'T', 'U' },
      [5]u8{ 'V', 'W', 'X', 'Y', 'Z' } 
    }, 'I', 'X', 'Q'
  );

  // Helo there there this is a playfair cipher implementation
  // NOTE: we use helo, and not hello because it has repeated l's
  const MESSAGE = "HELOXTHEREXTHISXISXAXPLAYFAIRXCIPHERXIMPLEMENTATION";
  const allocator = std.testing.allocator;

  const message = try pf.encryptAllocator(MESSAGE, allocator);
  std.debug.print("message: {s}\n", .{message});
  pf.decrypt(message);
  std.debug.print("decrypted: {s}\n", .{message});

  try std.testing.expectEqualStrings(MESSAGE, message);
}



