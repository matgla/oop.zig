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

const BuildVTable = @import("interface.zig").BuildVTable;
const GenerateClass = @import("interface.zig").GenerateClass;

fn ShapeInterface(comptime SelfType: type) type {
    return struct {
        pub const Self = SelfType;

        pub fn draw(self: *const Self) void {
            return self._vtable.draw(self._ptr, .{});
        }

        pub fn area(self: *const Self) u32 {
            return self._vtable.area(self._ptr, .{});
        }

        pub fn set_size(self: *Self, new_size: u32) void {
            return self._vtable.set_size(self._ptr, .{new_size});
        }
    };
}

const Shape = struct {
    _vtable: *const VTable,
    _ptr: *anyopaque,

    pub const VTable = BuildVTable(ShapeInterface);
    pub usingnamespace GenerateClass(ShapeInterface(Shape));
};

const Triangle = struct {
    size: u32,

    pub fn draw(self: *const Triangle) void {
        std.debug.print("Drawing triangle with size: {}\n", .{self.size});
    }

    pub fn area(self: *const Triangle) u32 {
        return self.size << 2;
    }

    pub fn set_size(self: *Triangle, new_size: u32) void {
        self.size = new_size;
    }

    pub fn ishape(self: *Triangle) Shape {
        return Shape.init(self);
    }

    // pub usingnamespace DeriveInterface(Shape, Triangle);
};

const Rectangle = struct {
    size: u32,

    pub fn draw(self: *const Rectangle) void {
        std.debug.print("Drawing rectangle with size: {}\n", .{self.size});
    }

    pub fn area(self: *const Rectangle) u32 {
        return self.size + 10000;
    }

    pub fn set_size(self: *Rectangle, a: u32) void {
        self.size = a;
    }

    pub fn ishape(self: *Rectangle) Shape {
        return Shape.init(self);
    }
    // pub usingnamespace DeriveInterface(Shape, Rectangle);
};

pub fn process(triangle: *Shape) void {
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

    // @compileLog("Shape Interface: ", @TypeOf(A.a));
    // @compileLog("Shape Interface: ", prune_type(@typeInfo(@TypeOf(A.a)).@"fn"));
    var triangle = Triangle{ .size = 5 };
    var rectangle = Rectangle{ .size = 15 };
    var shape1 = triangle.ishape();
    var shape2 = rectangle.ishape();
    process(&shape1);
    process(&shape2);
    // ishape.set_size(20);
    // process(&rectangle);
}
