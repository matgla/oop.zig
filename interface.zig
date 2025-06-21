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

fn gen_pure_virtual_call(comptime ArgsType: anytype) type {
    return struct {
        fn call(ptr: *const anyopaque, args: ArgsType) void {
            _ = ptr;
            _ = args;
            @panic("Pure virtual function call");
        }
    };
}

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

fn genVTableEntry(comptime Method: anytype, name: [:0]const u8) std.builtin.Type.StructField {
    const MethodType = @TypeOf(Method);
    const SelfType = @typeInfo(MethodType).@"fn".params[0].type.?;
    const Type = prune_type_info(@typeInfo(SelfType));
    const ReturnType = @typeInfo(@TypeOf(Method)).@"fn".return_type.?;
    const TupleArgs = get_vcall_args(Method);
    const FinalType = *const fn (ptr: Type, args: TupleArgs) ReturnType;
    return .{
        .name = name,
        .type = FinalType,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = 0,
    };
}

pub fn BuildVTable(comptime InterfaceType: anytype) type {
    comptime var fields: []const std.builtin.Type.StructField = &[_]std.builtin.Type.StructField{};
    inline for (std.meta.declarations(InterfaceType(anyopaque))) |d| {
        if (std.meta.hasMethod(InterfaceType(anyopaque), d.name)) {
            const Method = @field(InterfaceType(anyopaque), d.name);
            fields = fields ++ &[_]std.builtin.Type.StructField{genVTableEntry(Method, d.name)};
        }
    }
    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .is_tuple = false,
        .fields = fields,
        .decls = &.{},
    } });
}

pub fn GenerateClass(comptime InterfaceType: type) type {
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
                const vtable = build_vtable(Self);
            };
            return InterfaceType.Self{
                ._vtable = &gen_vtable.vtable,
                ._ptr = @ptrCast(ptr),
            };
        }
        pub usingnamespace InterfaceType;
    };
}
