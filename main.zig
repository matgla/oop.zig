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

const Interface = @import("interface.zig").Interface;
const Constructor = @import("interface.zig").Constructor;
const BuildVTable = @import("interface.zig").BuildVTable;

fn deduce_type(info: anytype, object_type: anytype) type {
    if (info.pointer.is_const) {
        return *const object_type;
    }
    return *object_type;
}

fn prune_type_info(info: anytype) type {
    if (info.pointer.is_const) {
        return *const anyopaque;
    }
    return *anyopaque;
}

fn gen_vcall(Type: type, ArgsType: anytype, name: []const u8) type {
    return struct {
        const RetType = @typeInfo(@TypeOf(ArgsType)).@"fn".return_type.?;
        const Params = @typeInfo(@TypeOf(ArgsType)).@"fn".params;
        const SelfType = Params[0].type.?;

        fn call(ptr: prune_type_info(@typeInfo(SelfType)), call_params: get_vcall_args(ArgsType)) RetType {
            std.debug.assert(@typeInfo(SelfType) == .pointer);
            const self: SelfType = @ptrCast(@alignCast(ptr));
            return @call(.auto, @field(Type, name), .{self} ++ call_params);
        }
    };
}

fn get_vcall_args(comptime fun: anytype) type {
    const params = @typeInfo(@TypeOf(fun)).@"fn".params;
    if (params.len == 0) {
        return .{};
    }
    comptime var args: []const type = &.{}; // The first parameter is always the object pointer
    for (params[1..]) |param| {
        const arg: []const type = &.{param.type.?};
        args = args ++ arg;
    }
    return std.meta.Tuple(args);
}

fn decorate(comptime InterfaceType: type) type {
    return struct {
        fn build_vtable(comptime Self: anytype) InterfaceType.Self.VTable {
            var vtable: InterfaceType.Self.VTable = undefined;

            inline for (std.meta.fields(InterfaceType.Self.VTable)) |field| {
                const field_type = @field(Self, field.name);
                const vcall = gen_vcall(Self, field_type, field.name);
                @field(vtable, field.name) = vcall.call;
            }
            return vtable;
        }
        pub fn init(ptr: anytype) InterfaceType.Self {
            const gen_vtable = struct {
                const Self = @TypeOf(ptr.*);
                // const vtable = InterfaceType.Self.VTable{
                // .draw = gen_draw,
                // .area = gen_area,
                // .set_size = gen_set_size,
                // };
                const vtable = build_vtable(Self);
                // const gen_draw = gen_vcall(@TypeOf(ptr.*), Self.draw, void, "draw").call;
                // const gen_area = gen_vcall(@TypeOf(ptr.*), Self.area, u32, "area").call;
                // const gen_set_size = gen_vcall(@TypeOf(ptr.*), Self.set_size, void, "set_size").call;
            };
            return InterfaceType.Self{
                ._vtable = &gen_vtable.vtable,
                ._ptr = @ptrCast(ptr),
            };
        }
        pub usingnamespace InterfaceType;
    };
}

fn ShapeInterface(comptime SelfType: type) type {
    return struct {
        const Self = SelfType;

        pub fn draw(self: Self) void {
            return self._vtable.draw(self._ptr, .{});
        }

        pub fn area(self: Self) u32 {
            return self._vtable.area(self._ptr, .{});
        }

        pub fn set_size(self: Self, new_size: u32) void {
            return self._vtable.set_size(self._ptr, .{new_size});
        }
    };
}

const Shape = struct {
    const VTable = struct {
        draw: *const fn (self: *const anyopaque, params: std.meta.Tuple(&.{})) void,
        area: *const fn (self: *const anyopaque, params: std.meta.Tuple(&.{})) u32,
        set_size: *const fn (self: *anyopaque, params: std.meta.Tuple(&.{u32})) void,
    };
    _vtable: *const VTable,
    _ptr: *anyopaque,

    pub usingnamespace decorate(ShapeInterface(Shape));
};

pub fn DeriveInterface(comptime InterfaceType: type, ChildType: type) type {
    return struct {
        pub fn ishape(self: *ChildType) InterfaceType {
            return InterfaceType.init(self);
        }
    };
}

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

const A = struct {
    pub fn a(_: *const A, arg: u32) u32 {
        std.debug.print("A.a called!\n", .{});
        return arg * 2;
    }
};
pub fn main() void {
    std.debug.print("Testing shape interface!\n", .{});

    // @compileLog("Shape Interface: ", @TypeOf(A.a));
    // @compileLog("Shape Interface: ", prune_type(@typeInfo(@TypeOf(A.a)).@"fn"));
    var triangle = Triangle{ .size = 5 };
    // var rectangle = Rectangle{ .size = 15 };
    var shape1 = triangle.ishape();
    // var shape2 = rectangle.ishape();
    process(&shape1);
    // process(&shape2);
    // ishape.set_size(20);
    // process(&rectangle);
}
