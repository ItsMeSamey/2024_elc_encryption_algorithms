const std = @import("std");

const Validate = @import("validate.zig");

const CeserCipher = @import("ceser_cipher.zig");
const PlayfairCipher = @import("playfair_cipher.zig");
const HillCipher = @import("hill_cipher.zig");

fn printUsage() noreturn {
  std.debug.print(
    \\Usage: <file> <cipher>
    \\    Cipher can be
    \\        ceser
    \\        playfair
    \\        hill
    , .{}
  );
}

const exit = std.process.exit;

fn readFile(file_name: []const u8, allocator: std.mem.Allocator) ![]u8 {
  const dir_name = std.fs.path.dirname(file_name);
  var dir = if (dir_name) |name| try std.fs.cwd().openDir(name, .{}) else std.fs.cwd();
  defer if (dir_name) |_| dir.close();

  var file = try dir.openFile(file_name[if (dir_name) |name| name.len + 1 else 0..], .{});
  defer file.close();

  return file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

const Cipher = enum {
  ceser,
  playfair,
  hill,
};

fn encryptData(allocator: std.mem.Allocator, file_data: []u8, cipher: Cipher) ![]u8 {
  const stdio = std.io.getStdOut().writer();

  switch (cipher) {
    .ceser => {
      const ceser = CeserCipher.init(
        5, // Shift amount
        .increase, // `.increase` to go from A to Z, or `.decrease` to go from Z to A
      );

      // Encrypt data in place
      var timer = try std.time.Timer.start();
      ceser.encrypt(file_data);
      var elapsed = timer.read();

      stdio.print("{s}\n", .{file_data}) catch {};
      std.log.info("Encryption took {d:.4} ms", .{@as(f128, @floatFromInt(elapsed)) / @as(f128, @floatFromInt(std.time.ns_per_ms))});

      timer.reset();
      ceser.decrypt(file_data);
      elapsed = timer.read();

      std.log.info("Decryption took {d:.4} ms", .{@as(f128, @floatFromInt(elapsed)) / @as(f128, @floatFromInt(std.time.ns_per_ms))});

      return file_data;
    },
    .playfair => {
      var playfair = PlayfairCipher.init(
        // Key can be any 5x5 matrix, of unique characters
        [5][5]u8{ // This is the key, we leave out 'J', which is automatically deduced by the function
          [5]u8{ 'E', 'D', 'C', 'B', 'A' },
          [5]u8{ 'F', 'G', 'H', 'I', 'K' }, // <- as we skipped 'J', it is 
          [5]u8{ 'L', 'M', 'N', 'O', 'P' },
          [5]u8{ 'Q', 'R', 'S', 'T', 'U' },
          [5]u8{ 'V', 'W', 'X', 'Y', 'Z' } 
        },
        'I', // All the 'j's are treated as 'I's (i.e this character)
        'X', // This is the rare characters, eg. 'LL' in 'HELLO' would become 'LXL' or 'QQ' -> 'QXQ'
        'Q' // This is secondary rare characters, eg. 'XX' would become 'XQX'
      ) catch |err| {
        std.log.err("Failed to init Playfair Cipher: {s}", .{@errorName(err)});
        exit(1);
      };

      var timer = try std.time.Timer.start();
      const message = playfair.encryptAllocator(file_data, allocator) catch |err| {
        std.log.err("Failed to encrypt: {s}", .{@errorName(err)});
        exit(1);
      };
      var elapsed = timer.read();

      stdio.print("{s}\n", .{file_data}) catch {};
      std.log.info("Encryption took {d:.4} ms", .{@as(f128, @floatFromInt(elapsed)) / @as(f128, @floatFromInt(std.time.ns_per_ms))});

      timer.reset();
      playfair.decrypt(message);
      elapsed = timer.read();

      std.log.info("Decryption took {d:.4} ms", .{@as(f128, @floatFromInt(elapsed)) / @as(f128, @floatFromInt(std.time.ns_per_ms))});

      return message;
    },
    .hill => {
      @panic("Not implemented");
    },
  }
}

const EncryptionResult = struct {
  message: []u8,
  freeable_buffer: []u8,
};

fn encryptFile(allocator: std.mem.Allocator, file_name: []const u8, cipher: Cipher) !EncryptionResult {
  const untrimmed_file_data = try readFile(file_name, allocator);
  errdefer allocator.free(untrimmed_file_data);

  const file_data: []u8 = @constCast(std.mem.trim(u8, untrimmed_file_data, "\n\r\t"));
  if (!Validate.validate(file_data)) return error.InvalidFileData;

  @prefetch(file_data.ptr, .{});

  return encryptData(allocator, file_data, cipher);
}

pub fn main() anyerror!void {
  // var GPA = std.heap.GeneralPurposeAllocator(.{}){};
  // const allocator = GPA.allocator();
  const allocator = std.heap.page_allocator;

  const args = std.process.argsAlloc(allocator) catch |err| {
    std.log.err("Failed to get process args: {s}", .{@errorName(err)});
    printUsage();
    exit(1);
  };

  if (args.len != 3) {
    printUsage();
    exit(1);
  }

  const file_name = args[1];
  const cipher = args[2];
}

