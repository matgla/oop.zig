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

// IShape is struct which is really an interface type
const IShape = interface.ConstructInterface(struct {
    pub const Self = @This();

    pub fn draw(self: *const Self) void {
        return interface.VirtualCall(self, "draw", .{}, void);
    }

    pub fn set_size(self: *Self, new_size: u32) void {
        return interface.VirtualCall(self, "set_size", .{new_size}, void);
    }

    pub fn delete(self: *Self) void {
        interface.VirtualCall(self, "delete", .{}, void);
        interface.DestructorCall(self);
    }
});

// Let's derive Triangle and Rectangle from IShape
// Child object must be packed to enforce defined memory layout
const Triangle = interface.DeriveFromBase(IShape, struct {
    const Self = @This();
    // Let's derive from IShape, this call constructs a vtable
    size: u32,

    pub fn draw(self: *const Self) void {
        std.debug.print("Triangle.draw: {d}\n", .{self.size});
    }

    pub fn set_size(self: *Self, new_size: u32) void {
        std.debug.print("Triangle.set_size: {d}->{d}\n", .{ self.size, new_size });
        self.size = new_size;
    }

    pub fn delete(self: *Self) void {
        _ = self;
    }
});

const Rectangle = interface.DeriveFromBase(IShape, struct {
    // Let's derive from IShape, this call constructs a vtable
    const Self = @This();
    size: u32,

    pub fn draw(self: *const Self) void {
        std.debug.print("Rectangle.draw: {d}\n", .{self.size});
    }

    pub fn set_size(self: *Self, new_size: u32) void {
        std.debug.print("Rectangle.set_size: {d}->{d}\n", .{ self.size, new_size });
        self.size = new_size;
    }

    pub fn delete(self: *Self) void {
        _ = self;
    }
});

const Square = interface.DeriveFromBase(Rectangle, struct {
    const Self = @This();
    base: Rectangle, //   this implementation requires base class to be first field
    name: []const u8, // and it must be at first position to ensure correct type casting

    pub fn draw(self: *const Self) void {
        std.debug.print("Square.draw[{s}]: {d}\n", .{ self.name, interface.base(self).size });
    }
});

// This is function that uses interface instead of concrete types
pub fn draw_and_modify_shape(shape: *IShape) void {
    // Call the draw method of the shape
    shape.interface.draw();
    // We will panic there for Rectangle
    shape.interface.set_size(123);
    shape.interface.draw();
}

pub fn draw_shape(shape: *const IShape) void {
    shape.interface.draw();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = true,
    }){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    var shape1: IShape = try (Triangle.init(.{ .size = 10 })).interface.new(allocator);
    defer shape1.interface.delete();
    var shape2: IShape = try (Rectangle.init(.{ .size = 20 })).interface.new(allocator);
    defer shape2.interface.delete();
    var shape3: IShape = try (Square.init(.{
        .base = Rectangle.init(.{
            .size = 30,
        }),
        .name = "Square",
    })).interface.new(allocator);
    defer shape3.interface.delete();

    draw_shape(&shape1);
    std.debug.print("-  Drawing triangle started\n", .{});
    draw_and_modify_shape(&shape1);
    std.debug.print("-  Drawing triangle finished\n", .{});
    std.debug.print("-  Drawing rectangle started\n", .{});
    draw_and_modify_shape(&shape2);
    std.debug.print("-  Drawing rectangle finished\n", .{});
    std.debug.print("-  Drawing square started\n", .{});
    draw_and_modify_shape(&shape3);
    std.debug.print("-  Drawing square finished\n", .{});
}
