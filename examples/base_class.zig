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

        pub fn draw(self: *const Self) void {
            return interface.VirtualCall(self, "draw", .{}, void);
        }

        pub fn set_size(self: *Self, new_size: u32) void {
            return interface.VirtualCall(self, "set_size", .{new_size}, void);
        }
    };
}

// IShape is struct which is really an interface type
const IShape = interface.ConstructInterface(ShapeInterface);

// Let's derive Triangle and Rectangle from IShape
// Child object must be extern to enforce defined memory layout
const Triangle = extern struct {
    // Let's derive from IShape, this call constructs a vtable
    pub usingnamespace interface.DeriveFromBase(IShape, Triangle);
    size: u32,

    pub fn draw(self: *const Triangle) void {
        std.debug.print("Triangle.draw: {d}\n", .{self.size});
    }

    pub fn set_size(self: *Triangle, new_size: u32) void {
        std.debug.print("Triangle.set_size: {d}->{d}\n", .{ self.size, new_size });
        self.size = new_size;
    }
};

const Rectangle = extern struct {
    // Let's derive from IShape, this call constructs a vtable
    pub usingnamespace interface.DeriveFromBase(IShape, Rectangle);
    size: u32,

    pub fn draw(self: *const Rectangle) void {
        std.debug.print("Rectangle.draw: {d}\n", .{self.size});
    }

    pub fn set_size(self: *Rectangle, new_size: u32) void {
        std.debug.print("Rectangle.set_size: {d}->{d}\n", .{ self.size, new_size });
        self.size = new_size;
    }
};

const Square = extern struct {
    // This object is derived from Rectangle and overrides some methods
    pub usingnamespace interface.DeriveFromBase(Rectangle, Square);
    base: Rectangle, //   this implementation requires base class to be first field
    name: [*:0]const u8, // and it must be at first position to ensure correct type casting

    pub fn draw(self: *const Square) void {
        std.debug.print("Square.draw[{s}]: {d}\n", .{ self.name, self.base.size });
    }
};

// This is function that uses interface instead of concrete types
pub fn draw_and_modify_shape(shape: *IShape) void {
    // Call the draw method of the shape
    shape.draw();
    // We will panic there for Rectangle
    shape.set_size(123);
    shape.draw();
}

pub fn draw_shape(shape: *const IShape) void {
    shape.draw();
}

pub fn main() void {
    var triangle = Triangle{ .size = 10 };
    var rectangle = Rectangle{ .size = 20 };
    var square = Square{
        .base = Rectangle{
            .size = 30,
        },
        .name = "Square",
    };
    // create interface pointers
    // in c++ you can't do this, but in my implemnetation you can since interface
    // is owner of vtable and pointer (fat pointer)
    var shape1: IShape = triangle.interface();
    var shape2: IShape = rectangle.interface();
    var shape3: IShape = square.interface();

    // Draw the shapes

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
