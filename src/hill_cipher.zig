const std = @import("std");
const builtin = @import("builtin");

const halfusize = std.meta.Int(.unsigned, @sizeOf(usize) * 4);
fn GetSquareMatrix(T: type) type {
  return struct {
    size: halfusize,
    data: [*]T,

    /// Create a new matrix, data is left uninitialized
    pub fn new(allocator: std.mem.Allocator, size: halfusize) !@This() {
      return @This(){
        .size = size,
        .data = (try allocator.alloc(T, @as(usize, size) * @as(usize, size))).ptr,
      };
    }

    /// Clone this matrix using the allocator
    pub fn dupe(self: @This(), allocator: std.mem.Allocator) !@This() {
      return .{
        .size = self.size,
        .data = (try allocator.dupe(T, self.data[0.. @as(usize, self.size) * @as(usize, self.size)])).ptr,
      };
    }

    /// get pointer to value at x, y
    pub fn get(self: @This(), x: halfusize, y: halfusize) *T {
      std.debug.assert(x < self.size);
      std.debug.assert(y < self.size);
      return &self.data[@as(usize, x)*@as(usize, self.size) + @as(usize, y)];
    }

    /// if this function returns false, the matrix is not invertible
    /// otherwise, the matrix __may__ be inverible
    pub fn checkMaybeNonInvertible(self: @This()) void {
      for (0..self.size) |i| {
        if (self.get(i, i).* == 0) {
          return error.NonInvertible;
        }
      }
    }

    /// Struct used for gaussian elimination
    pub const RowPairs = struct {
      a: [*]T,
      b: [*]T,
    };

    const MatrixInversionError = error {NonInvertible};

    /// Makes sure that the diagonal entries are non-zero, if it is impossible to do s, returns error.NonInvertible
    fn nonNullDiagonal(pointers: []RowPairs, row: halfusize) MatrixInversionError!void {
      if (pointers[row].a[row] == 0) {
        for (row..pointers.len) |i| {
          if (pointers[i].a[row] != 0) {
            const temp = pointers[row];
            pointers[row] = pointers[i];
            pointers[i] = temp;

            return nonNullDiagonal(pointers, row + 1) catch {
              pointers[i] = pointers[row];
              pointers[row] = temp;
              continue;
            };
          }
        }
        return MatrixInversionError.NonInvertible;
      } else {
        for (row..pointers.len) |i| {
          if (pointers[i].a[i] == 0) return nonNullDiagonal(pointers, @intCast(i)) catch {};
        }
      }
    }

    /// Row operations on first matrix
    fn subRowA(pointers: []RowPairs, factor: T, src: halfusize, dest: halfusize, from: halfusize, till: halfusize) void {
      for (from..till) |i| {
        pointers[dest].a[i] -= factor * pointers[src].a[i];
      }
    }

    /// row operations on second matrix
    fn subRowB(pointers: []RowPairs, factor: T, src: halfusize, dest: halfusize, from: halfusize, till: halfusize) void {
      for (from..till) |i| {
        pointers[dest].b[i] -= factor * pointers[src].b[i];
      }
    }

    /// This matrix is on longer usable after this function is called
    /// self and dest must *NOT* be same
    pub fn invertToDestPointers(self: @This(), dest: @This(), pointers: []RowPairs) MatrixInversionError!void {
      // The dest must neevr be same as source matrix
      std.debug.assert(@intFromPtr(self.data) != @intFromPtr(dest.data));

      const size = self.size;
      std.debug.assert(size == dest.size);
      std.debug.assert(size == pointers.len);

      var from: usize = 0;
      for (0..size) |i| {
        pointers[i].a = self.data[from..];
        pointers[i].b = dest.data[from..];
        from += size;
      }

      try nonNullDiagonal(pointers, 0);
      @memset(dest.data[0..size], 0);
      for (0..size) |i| pointers[i].b[i] = 1;

      // Perform Gaussian elimination
      for (0..size) |row| {
        debugPrintPointers(pointers);
        if (pointers[row].a[row] == 0) {
          try nonNullDiagonal(pointers, @intCast(row));
        }

        const diag = pointers[row].a[row];
        for (row+1..size) |other_row| {
          const factor = pointers[other_row].a[row] / diag;
          subRowA(pointers, factor, @intCast(row), @intCast(other_row), 0, size);
          subRowB(pointers, factor, @intCast(row), @intCast(other_row), 0, size);
        }
      }


      // Make `a` as diagonal matrix
      for (0..size) |row| {
        debugPrintPointers(pointers);
        const _row_ = size - row - 1;
        const diag = pointers[_row_].a[_row_];
        for (0.._row_) |other_row| {
          const factor = pointers[other_row].a[_row_] / diag;
          if (builtin.mode == .Debug) subRowA(pointers, factor, @intCast(_row_), @intCast(other_row), 0, size);
          subRowB(pointers, factor, @intCast(_row_), @intCast(other_row), 0, size);
        }
      }

      // Make `a` as identity matrix
      for (0..size) |row| {
        debugPrintPointers(pointers);
        const factor = pointers[row].a[row];
        for (0..size) |col| {
          if (builtin.mode == .Debug) pointers[row].a[col] /= factor;
          pointers[row].b[col] /= factor;
        }
      }

      debugPrintPointers(pointers);

      dest.debugPrint();
    }

    const invertWithAllocatorError = MatrixInversionError || std.mem.Allocator.Error;

    /// Inverts and returns the inverted matrix, destroying this one
    /// The caller must free both the matrices
    pub fn invertWithAllocator(self: *@This(), allocator: std.mem.Allocator) invertWithAllocatorError!@This() {
      const dest = try new(allocator, self.size);
      errdefer dest.deinit(allocator);

      const pointers = try allocator.alloc(RowPairs, self.size);
      try self.invertToDestPointers(dest, pointers);
      return dest;
    }

    /// Multiply this matrix by a vector and store the result in dest
    /// vector and dest must *NOT* be same
    pub fn mulVector(self: *const @This(), vector: []const T, dest: []T) void {
      std.debug.assert(@intFromPtr(vector.ptr) != @intFromPtr(dest.ptr));
      std.debug.assert(vector.len == self.size);
      std.debug.assert(dest.len == self.size);

      @memset(dest, 0);
      var from: usize = 0;
      for (0..self.size) |i| {
        const v = self.data[from..][0..self.size];
        from += self.size;
        for (0..self.size) |j| {
          dest[i] += v[j] * vector[j];
        }
      }
    }

    /// Free this matrix
    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
      allocator.free(self.data[0..@as(usize, self.size) * @as(usize, self.size)]);
    }

    const format = "{d:4.4} ";

    /// Prints the matrix
    pub fn print(self: @This(), writer: std.io.AnyWriter) !void {
      for (0..self.size) |i| {
        for (0..self.size) |j| {
          try writer.print(format, .{self.get(@intCast(i), @intCast(j)).*});
        }
        try writer.print("\n", .{});
      }
    }

    /// Print matrix but ignore errors
    fn debugPrint(self: @This()) void {
      self.print(std.io.getStdOut().writer().any()) catch {};
    }

    /// Print the matrix as represenred by pointers slice
    fn debugPrintPointers(pointers: []RowPairs) void {
      for (pointers) |row| {
        for (row.a[0..pointers.len]) |v| std.debug.print(format, .{v});
        std.debug.print("| ", .{});
        for (row.b[0..pointers.len]) |v| std.debug.print(format, .{v});
        std.debug.print("\n", .{});
      }
      std.debug.print("\n", .{});
    }
  };
}

test GetSquareMatrix {
  const allocator = std.heap.page_allocator;

  const matrixSize = 3;
  const dataType = f32;
  const MatrixType = GetSquareMatrix(dataType);

  var matrix = try MatrixType.new(allocator, matrixSize);
  defer matrix.deinit(allocator);

  for (0..matrixSize * matrixSize) |i| {
    matrix.data[i] = @floatFromInt(i*i + 1);
  }

  var dupe = try matrix.dupe(allocator);
  defer dupe.deinit(allocator);

  var inverseMatrix = try dupe.invertWithAllocator(allocator);
  defer inverseMatrix.deinit(allocator);

  const vec = try allocator.alloc(dataType, matrixSize);
  defer allocator.free(vec);

  const vec_out = try allocator.alloc(dataType, matrixSize);
  defer allocator.free(vec_out);

  const vec_copy = try allocator.alloc(dataType, matrixSize);
  defer allocator.free(vec_copy);

  for (0..matrixSize) |i| {
    vec[i] = @floatFromInt(i);
  }

  @memcpy(vec_copy, vec);

  matrix.mulVector(vec, vec_out);

  std.debug.print("\n", .{});
  for (vec_out) |i| std.debug.print("{d:.1} ", .{ i });
  std.debug.print("\n", .{});

  inverseMatrix.mulVector(vec_out, vec);


  try std.testing.expectEqualSlices(dataType, vec_copy, vec);
}

test {
  std.testing.refAllDeclsRecursive(@This());
}


