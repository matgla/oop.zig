// Copyright (c) 2025 Mateusz Stadnik
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
// the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
// FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

const std = @import("std");

const interface = @import("interface");

// Constructs an interface for Shape objects
// all methods are pure virtual, so they must be implemented in the derived types
// SelfType is type of InterfaceHolder struct (in c++ it would be a class with pure virtual methods)
fn ShapeInterface(comptime SelfType: type) type {
    return struct {
        pub const Self = SelfType;

        pub fn area(self: *const Self) u32 {
            return interface.VirtualCall(self, "area", .{}, u32);
        }

        pub fn set_size(self: *Self, new_size: u32) void {
            return interface.VirtualCall(self, "set_size", .{new_size}, void);
        }

        // do not forget about virtual destructor
        pub fn delete(self: *Self, allocator: std.mem.Allocator) void {
            return interface.VirtualCall(self, "delete", .{allocator}, void);
        }
    };
}

// IShape is struct which is really an interface type
const IShape = interface.ConstructInterface(ShapeInterface);

// Let's derive Triangle and Rectangle from IShape
// Child object must be packed to enforce defined memory layout
const Triangle = packed struct {
    // Let's derive from IShape, this call constructs a vtable
    pub usingnamespace interface.DeriveFromBase(IShape, Triangle);
    height: u32,
    base: u32,
    size: u32,

    pub fn area(self: *const Triangle) u32 {
        return self.height * self.base / 2 * self.size;
    }

    pub fn set_size(self: *Triangle, new_size: u32) void {
        self.size = new_size;
    }
};

const Rectangle = struct {
    // Let's derive from IShape, this call constructs a vtable
    pub usingnamespace interface.DeriveFromBase(IShape, Rectangle);
    a: u32,
    b: u32,
    size: u32,

    pub fn area(self: *const Rectangle) u32 {
        return self.a * self.b * self.size;
    }

    pub fn set_size(self: *Rectangle, new_size: u32) void {
        self.size = new_size;
    }
};

const Square = struct {
    // This object is derived from Rectangle and overrides some methods
    pub usingnamespace interface.DeriveFromBase(Rectangle, Square);
    base: Rectangle,

    pub fn create(a: u32) Square {
        return Square{
            .base = Rectangle{
                .a = a,
                .b = a,
                .size = 1,
            },
        };
    }
};

const BadSquare = struct {
    // This object is derived from Rectangle and overrides some methods
    base: Square, //   this implementation requires base class to be first field
    pub usingnamespace interface.DeriveFromBase(Square, BadSquare);

    pub fn area(self: *const BadSquare) u32 {
        return self.base.base.area() / 10;
    }

    pub fn create(a: u32) BadSquare {
        return BadSquare{
            .base = Square.create(a),
        };
    }
};

test "heap allocation" {
    const allocator = std.testing.allocator;
    var shape1: IShape = try (Triangle{ .base = 10, .height = 3, .size = 2 }).new(allocator);
    defer shape1.delete(allocator);
    var shape2: IShape = try (Rectangle{ .a = 5, .b = 2, .size = 1 }).new(allocator);
    defer shape2.delete(allocator);
    var shape3: IShape = try (Square.create(3)).new(allocator);
    defer shape3.delete(allocator);
    var shape4: IShape = try (BadSquare.create(5)).new(allocator);
    defer shape4.delete(allocator);

    try std.testing.expectEqual(30, shape1.area());
    try std.testing.expectEqual(10, shape2.area());
    try std.testing.expectEqual(9, shape3.area());
    shape1.set_size(3);
    shape2.set_size(2);
    shape3.set_size(4);
    try std.testing.expectEqual(45, shape1.area());
    try std.testing.expectEqual(20, shape2.area());
    try std.testing.expectEqual(36, shape3.area());
    try std.testing.expectEqual(2, shape4.area());
    shape4.set_size(30);
    try std.testing.expectEqual(75, shape4.area());
}
