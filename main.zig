// Copyright (c) 2025 Mateusz Stadnik
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");

const interface = @import("interface.zig");

fn ShapeInterface(comptime SelfType: type) type {
    return struct {
        pub const Self = SelfType;

        pub fn draw(self: *const Self) void {
            return interface.VirtualCall(self, "draw", .{}, void);
        }

        pub fn area(self: *const Self) u32 {
            return interface.VirtualCall(self, "area", .{}, u32);
        }

        pub fn set_size(self: *Self, new_size: u32) void {
            return interface.VirtualCall(self, "set_size", .{new_size}, void);
        }
    };
}

// ShapeInterface methods are pure virtual, derive them in the childs
const IShape = interface.ConstructInterface(ShapeInterface);

const Triangle = packed struct {
    pub usingnamespace interface.DeriveFromBase(IShape, Triangle);
    size: u32,

    pub fn draw(self: *const Triangle) void {
        std.debug.print("Triangle.draw: {d}\n", .{self.size});
    }

    pub fn area(self: *const Triangle) u32 {
        std.debug.print("Triangle.area: {d}\n", .{self.size});
        return self.size << 2;
    }

    pub fn set_size(self: *Triangle, new_size: u32) void {
        std.debug.print("Triangle.set_size: {d}->{d}\n", .{ self.size, new_size });
        self.size = new_size;
    }
};

const Rectangle = packed struct {
    pub usingnamespace interface.DeriveFromBase(IShape, Rectangle);
    size: u32,

    pub fn draw(self: *const Rectangle) void {
        std.debug.print("Rectangle.draw: {d}\n", .{self.size});
    }

    pub fn area(self: *const Rectangle) u32 {
        std.debug.print("Rectangle.area: {d}\n", .{self.size});
        return self.size + 10000;
    }

    pub fn set_size(self: *Rectangle, new_size: u32) void {
        std.debug.print("Rectangle.set_size: {d}->{d}\n", .{ self.size, new_size });
        self.size = new_size;
    }
};

const Square = packed struct {
    pub usingnamespace interface.DeriveFromBase(Rectangle, Square);
    base: Rectangle, // this will ensure correct type casting
    name: [*:0]const u8,
    other_field: u92 = 0,

    pub fn draw(self: *const @This()) void {
        std.debug.print("Square.draw[{s}]: {d}\n", .{ self.name, self.base.size });
    }

    pub fn set_size(self: *@This(), a: u32) void {
        std.debug.print("Square.set_size[{s}]: {d}->{d} : {d}\n", .{ self.name, self.base.size, a, self.other_field });
        self.base.size = a;
    }
};

pub fn process(triangle: *IShape) void {
    std.debug.print("-------    Processing     -------\n", .{});
    triangle.draw();
    std.debug.print("shape.area: {}\n", .{triangle.area()});
    triangle.set_size(10);
    std.debug.print("shape.area: {}\n", .{triangle.area()});
    triangle.draw();
    std.debug.print("------- End of processing -------\n", .{});
}

pub fn main() void {
    std.debug.print("Testing shape interface!\n", .{});

    var triangle = Triangle{ .size = 5 };
    var rectangle = Rectangle{ .size = 15 };
    var square = Square{
        .base = Rectangle{
            .size = 20,
        },
        .name = "Square1",
        .other_field = 42,
    };
    var square2 = Square{
        .base = Rectangle{
            .size = 20,
        },
        .name = "Square2",
        .other_field = 84,
    };

    var shape1 = triangle.interface();
    var shape2 = rectangle.interface();
    var shape3 = square.interface();
    var shape4 = square2.interface();

    process(&shape1);
    process(&shape2);
    process(&shape3);
    process(&shape4);
}
