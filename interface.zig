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

fn addDecl(comptime interface: anytype, d: anytype) std.builtin.Type.StructField {
    const FieldType = @TypeOf(@field(interface, d.name));
    return .{
        .name = d.name,
        .type = FieldType,
        .default_value_ptr = @field(interface, d.name),
        .is_comptime = true,
        .alignment = @alignOf(FieldType),
    };
}

fn genDecl(comptime obj: anytype, name: [:0]const u8) std.builtin.Type.StructField {
    const FieldType = @TypeOf(obj);
    return .{
        .name = name,
        .type = FieldType,
        .default_value_ptr = obj,
        .is_comptime = true,
        .alignment = @alignOf(FieldType),
    };
}

fn prune_type(comptime T: anytype) type {
    comptime var params: []const std.builtin.Type.Fn.Param = &[_]std.builtin.Type.Fn.Param{
        .{
            .is_generic = T.params[0].is_generic,
            .is_noalias = T.params[0].is_noalias,
            .type = *const anyopaque,
        },
    };
    params = params ++ T.params[1..];
    return @Type(.{
        .@"fn" = .{
            .calling_convention = T.calling_convention,
            .is_generic = T.is_generic,
            .is_var_args = T.is_var_args,
            .params = params,
            .return_type = T.return_type,
        },
    });
}

pub fn Constructor(comptime InterfaceType: type, object: anytype) InterfaceType {
    return .{
        ._vtable = undefined,
        ._ptr = @ptrCast(object),
    };
}

pub fn Interface(comptime declarations: type) type {
    comptime var fields: []const std.builtin.Type.StructField = std.meta.fields(declarations);
    for (std.meta.declarations(declarations)) |d| {
        fields = fields ++ &[_]std.builtin.Type.StructField{addDecl(declarations, d)};
    }
    fields = fields ++ &[_]std.builtin.Type.StructField{genDecl(Constructor, "init")};
    // fields = fields ++ &[_]std.builtin.Type.StructField{.{
    //     .name = "_vtable",
    //     .type = @TypeOf(ShapeVTable),
    //     .default_value_ptr = ShapeVTable,
    //     .is_comptime = true,
    //     .alignment = @alignOf(@TypeOf(ShapeVTable)),
    // }};

    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .is_tuple = false,
        .fields = fields,
        .decls = &.{},
    } });
}

fn pure_virtual_call(_: *const anyopaque) void {
    @panic("Pure virtual function call");
}

fn genVTableEntry(comptime obj: anytype, name: [:0]const u8) std.builtin.Type.StructField {
    // @compileLog(obj, name);
    const FieldType = @field(obj, name);
    // @compileLog("FieldType: ", FieldType, @TypeOf(FieldType), @alignOf(@TypeOf(FieldType)));
    // @compileLog("Pruen: ", prune_type(@TypeOf(FieldType)));
    @compileLog("FieldType: ", prune_type(@typeInfo(@TypeOf(FieldType)).@"fn"));
    return .{
        .name = name,
        .type = *const prune_type(@typeInfo(@TypeOf(FieldType)).@"fn"),
        .default_value_ptr = @ptrCast(&pure_virtual_call),
        .is_comptime = true,
        .alignment = @alignOf(@TypeOf(&pure_virtual_call)),
    };
}

pub fn BuildVTable(comptime InterfaceType: anytype, comptime O: anytype) type {
    @compileLog(InterfaceType);
    inline for (std.meta.declarations(InterfaceType(O))) |field| {
        @compileLog(field);
    }
    comptime var fields: []const std.builtin.Type.StructField = &[_]std.builtin.Type.StructField{};
    inline for (std.meta.declarations(InterfaceType(O))) |d| {
        fields = fields ++ &[_]std.builtin.Type.StructField{genVTableEntry(InterfaceType(void), d.name)};
        @compileLog("Adding field: ", d);
    }
    // @compileLog(fields);
    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .is_tuple = false,
        .fields = fields,
        .decls = &.{},
    } });
    // return VTable;
}
