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
const IShape = interface.ConstructInterface(struct {
    pub const Self = @This();

    pub fn area(self: *const Self) u32 {
        return interface.VirtualCall(self, "area", .{}, u32);
    }

    pub fn set_size(self: *Self, new_size: u32) void {
        return interface.VirtualCall(self, "set_size", .{new_size}, void);
    }

    // do not forget about virtual destructor
    pub fn delete(self: *Self) void {
        interface.VirtualCall(self, "delete", .{}, void);
        interface.DestructorCall(self);
    }
});

// Let's derive Triangle and Rectangle from IShape
// Child object must be packed to enforce defined memory layout
const Triangle = interface.DeriveFromBase(IShape, struct {
    pub const Self = @This();
    height: u32,
    base: u32,
    size: u32,

    pub fn area(self: *const Self) u32 {
        return self.height * self.base / 2 * self.size;
    }

    pub fn set_size(self: *Self, new_size: u32) void {
        self.size = new_size;
    }

    pub fn delete(self: *Self) void {
        _ = self;
    }
});

const Rectangle = interface.DeriveFromBase(IShape, struct {
    const Self = @This();
    a: u32,
    b: u32,
    size: u32,

    pub fn area(self: *const Self) u32 {
        return self.a * self.b * self.size;
    }

    pub fn set_size(self: *Self, new_size: u32) void {
        self.size = new_size;
    }

    pub fn delete(self: *Self) void {
        _ = self;
    }
});

const Square = interface.DeriveFromBase(Rectangle, struct {
    base: Rectangle,

    pub fn create(a: u32) Square {
        return Square.init(.{
            .base = Rectangle.init(.{
                .a = a,
                .b = a,
                .size = 1,
            }),
        });
    }
});

const BadSquare = interface.DeriveFromBase(Square, struct {
    const Self = @This();
    base: Square,

    pub fn area(self: *const Self) u32 {
        return interface.base(interface.base(self)).area() / 10;
    }

    pub fn create(a: u32) BadSquare {
        return BadSquare.init(.{
            .base = Square.InstanceType.create(a),
        });
    }
});

test "heap allocation" {
    const allocator = std.testing.allocator;
    var shape1: IShape = try (Triangle.init(.{ .base = 10, .height = 3, .size = 2 })).interface.new(allocator);
    defer shape1.interface.delete();
    var shape2: IShape = try (Rectangle.init(.{ .a = 5, .b = 2, .size = 1 })).interface.new(allocator);
    defer shape2.interface.delete();
    var shape3: IShape = try (Square.InstanceType.create(3)).interface.new(allocator);
    defer shape3.interface.delete();
    var shape4: IShape = try (BadSquare.InstanceType.create(5)).interface.new(allocator);
    defer shape4.interface.delete();

    try std.testing.expectEqual(30, shape1.interface.area());
    try std.testing.expectEqual(10, shape2.interface.area());
    try std.testing.expectEqual(9, shape3.interface.area());
    shape1.interface.set_size(3);
    shape2.interface.set_size(2);
    shape3.interface.set_size(4);
    try std.testing.expectEqual(45, shape1.interface.area());
    try std.testing.expectEqual(20, shape2.interface.area());
    try std.testing.expectEqual(36, shape3.interface.area());
    try std.testing.expectEqual(2, shape4.interface.area());
    shape4.interface.set_size(30);
    try std.testing.expectEqual(75, shape4.interface.area());
}
