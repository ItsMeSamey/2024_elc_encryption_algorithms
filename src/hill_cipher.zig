const std = @import("std");

const halfusize = std.meta.Int(.unsigned, @sizeOf(usize) * 4);
fn GetSquareMatrix(T: type, zero: T) type {
  return struct {
    size: halfusize,
    data: [*]T,

    /// Create a new matric, data is left uninitialized
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

    /// Convert this matrix to identity matrix
    pub fn toIdentity(self: @This()) void {
      var till: usize = 0;
      for (0..self.size) |i| {
        const v = self.data[till..][0..self.size];
        till += self.size;
        for (0..self.size) |j| {
          v[j] = if (i == j) 1 else 0;
        }
      }      
    }

    /// get pointer to value at x, y
    pub fn get(self: @This(), x: halfusize, y: halfusize) *T {
      std.debug.assert(x < self.size);
      std.debug.assert(y < self.size);
      return &self.data[x * @as(usize, self.size) + y];
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

    pub const RowPairs = struct {
      a: [*]T,
      b: [*]T,
    };

    fn getRowPairsSlice(self: @This(), allocator: std.mem.Allocator) !RowPairs {
      return allocator.alloc(RowPairs, self.size);
    }

    fn nonNullDiagonal(pointers: []RowPairs, size: halfusize, row: halfusize) !void {
      pointers[row].a[row] == 0;
      for (row..size) |i| {
        if (pointers[i].a[row] != 0) {
          const temp = pointers[row];
          pointers[row] = pointers[i];
          pointers[i] = temp;

          return try nonNullDiagonal(pointers, size, row + 1) catch {
            pointers[i] = pointers[row];
            pointers[row] = temp;
            continue;
          };
        }
      }
      return error.NonInvertible;
    }

    fn subRowA(pointers: []RowPairs, factor: T, src: halfusize, dest: halfusize, from: halfusize, till: halfusize) void {
      for (from..till) |i| {
        pointers[dest].a[i] -= factor * pointers[src].a[i];
      }
    }

    fn subRowB(pointers: []RowPairs, factor: T, src: halfusize, dest: halfusize, from: halfusize, till: halfusize) void {
      for (from..till) |i| {
        pointers[dest].b[i] -= factor * pointers[src].b[i];
      }
    }


    /// This matrix is on longer usable after this function is called
    /// self and dest must *NOT* be same
    fn invertToDestPointers(self: @This(), dest: @This(), pointers: []RowPairs) !void {
      // The dest must neevr be same as source matrix
      std.debug.assert(@intFromPtr(self) != @intFromPtr(dest));

      const size = self.size;
      std.debug.assert(size == dest.size);
      std.debug.assert(size == pointers.len);

      dest.toIdentity();

      var from: usize = 0;
      for (0..size) |i| {
        pointers[i].a = self.data[from..].ptr;
        pointers[i].b = dest.data[from..].ptr;
        from += size;
      }

      try nonNullDiagonal(pointers, size, 0);

      // Perform Gaussian elimination
      for (0..size) |row| {
        if (pointers[row].a[row] == 0) try nonNullDiagonal(pointers, size, row);

        const diag = pointers[row].a[row];
        for (row+1..size) |other_row| {
          const factor = pointers[other_row].a[row] / diag;
          subRowA(pointers, factor, row, other_row, 0, size);
          subRowB(pointers, factor, row, other_row, 0, size);
        }
      }

      // Make `a` as diagonal matrix
      for (0..size) |row| {
        const diag = pointers[row].a[row];
        for (0..size - row - 1) |other_row| {
          const factor = pointers[other_row].a[row] / diag;
          pointers[other_row].a[row] = 0;
          subRowB(pointers, factor, other_row, row, 0, size);
        }
      }

      // Make `a` as identity matrix
      for (0..size) |row| {
        const factor = pointers[row].a[row];
        for (0..size) |col| {
          pointers[row].b[col] /= factor;
        }
      }
    }

    /// Inverts and returns the inverted matrix, destroying this one
    /// The caller must free both the matrices
    fn invertWithAllocator(self: *@This(), allocator: std.mem.Allocator) !@This() {
      const dest = try new(allocator, self.size);
      errdefer dest.deinit(allocator);

      const pointers = try getRowPairsSlice(self, allocator);
      try self.invertToDestPointers(dest, pointers);
      return dest;
    }

    /// Multiply this matrix by a vector and store the result in dest
    /// vector and dest must *NOT* be same
    fn mulVector(self: *const @This(), vector: []const T, dest: []T) void {
      std.debug.assert(@intFromPtr(vector) != @intFromPtr(dest));
      std.debug.assert(vector.len == self.size);
      std.debug.assert(dest.len == self.size);

      @memset(dest, zero);
      var from: usize = 0;
      for (0..self.size) |i| {
        const v = self.data[from..self.size];
        from += self.size;
        for (0..self.size) |j| {
          dest[i] += v[j] * vector[j];
        }
      }
    }

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
      allocator.free(self.data[0..@as(usize, self.size) * @as(usize, self.size)]);
    }
  };
}

test GetSquareMatrix {
  const allocator = std.heap.page_allocator;

  const matrixSize = 3;
  const MatrixType = GetSquareMatrix(u8, 0);


  // Create a square matrix
  var matrix = try MatrixType.new(allocator, matrixSize);
  defer matrix.deinit(allocator);

  // Initialize the matrix with some values
  matrix.data[0] = 4;
  matrix.data[1] = 7;
  matrix.data[2] = 2;
  matrix.data[3] = 3;
  matrix.data[4] = 6;
  matrix.data[5] = 1;
  matrix.data[6] = 2;
  matrix.data[7] = 5;
  matrix.data[8] = 3;


  // Invert the matrix
  var inverseMatrix = try matrix.invertWithAllocator(allocator);
  defer inverseMatrix.deinit(allocator);

  // Print the inverse matrix
  for (0 .. matrixSize) |i| {
    for (0 .. matrixSize) |j| {
      std.debug.print("{d:.2} ", .{ inverseMatrix.get(@intCast(i), @intCast(j)).* });
    }
    std.debug.print("\n", .{});
  }
}

test {
  std.testing.refAllDeclsRecursive(@This());
}


