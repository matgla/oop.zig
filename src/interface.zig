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
    const FinalType = ?*const fn (ptr: Type, args: TupleArgs) ReturnType;
    return .{
        .name = name,
        .type = FinalType,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = 0,
    };
}

fn addDecl(comptime T: type, d: anytype) std.builtin.Type.StructField {
    const F = @TypeOf(@field(T, d.name));
    return .{
        .name = d.name,
        .type = F,
        .default_value_ptr = @field(T, d.name),
        .is_comptime = true,
        .alignment = @alignOf(F),
    };
}

fn BuildVTable(comptime InterfaceType: anytype) type {
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

fn pure_virtual_function() void {
    @panic("Pure virtual function called");
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

fn GenerateClass(comptime InterfaceType: type) type {
    return struct {
        fn build_vtable_chain(chain: []const type) InterfaceType.Self.VTable {
            var vtable: InterfaceType.Self.VTable = undefined;
            for (std.meta.fields(InterfaceType.Self.VTable)) |field| {
                @field(vtable, field.name) = null; // Initialize all fields to null
            }
            var index: isize = chain.len - 1;
            while (index >= 0) : (index -= 1) {
                const base = chain[index];
                for (std.meta.fields(InterfaceType.Self.VTable)) |field| {
                    if (!std.meta.hasMethod(base, field.name)) {
                        if (@field(vtable, field.name) == null) {
                            @field(vtable, field.name) = @ptrCast(&pure_virtual_function);
                        }
                    } else {
                        const field_type = @field(base, field.name);
                        const vcall = gen_vcall(base, field_type, field.name);
                        @field(vtable, field.name) = vcall.call;
                    }
                }
            }
            return vtable;
        }

        pub fn init_chain(ptr: anytype, chain: []const type) InterfaceType.Self {
            const gen_vtable = struct {
                const Self = @TypeOf(ptr.*);
                const vtable = build_vtable_chain(chain);
            };
            return InterfaceType.Self{
                ._vtable = &gen_vtable.vtable,
                ._ptr = @ptrCast(ptr),
            };
        }
        pub usingnamespace InterfaceType;
    };
}

pub fn ConstructInterface(comptime SelfType: anytype) type {
    return struct {
        pub const Self = @This();
        pub const VTable = BuildVTable(SelfType);
        pub const IsInterface = true;
        pub const Base: ?type = null;
        _vtable: *const VTable,
        _ptr: *anyopaque,

        pub usingnamespace GenerateClass(SelfType(@This()));
    };
}

fn deduce_interface(comptime Base: type) type {
    comptime var base: type = Base;
    while (true) {
        if (base.Base == null) {
            return base;
        }
        base = Base.Base.?;
    }
    return Base;
}

fn build_inheritance_chain(comptime Base: type, comptime Derived: type) []const type {
    comptime var chain: []const type = &.{};

    const arg: []const type = &.{Derived};
    chain = chain ++ arg;

    var current: ?type = Base;

    while (current != null) {
        const a: []const type = &.{current.?};
        chain = chain ++ a;
        current = current.?.Base;
    }

    return chain;
}

pub fn DeriveFromChain(comptime chain: []const type, comptime Derived: anytype) type {
    return struct {
        pub const Base: type = chain[chain.len - 1];
        pub fn interface(ptr: *Derived) Base {
            return Base.init_chain(ptr, chain[0 .. chain.len - 1]);
        }

        pub fn new(self: *const Derived, allocator: std.mem.Allocator) !Base {
            const object: *Derived = try allocator.create(Derived);
            object.* = self.*;
            return object.interface();
        }

        pub fn delete(self: *Derived, allocator: std.mem.Allocator) void {
            allocator.destroy(self);
        }
    };
}

pub fn DeriveFromBase(comptime Base: anytype, comptime Derived: anytype) type {
    comptime if (!@hasDecl(Base, "IsInterface")) { // ensure we have base member
        if (!@hasField(Derived, "base")) {
            @compileError("Deriving from a base instead of an interface requires a 'base' field in the derived type.");
        }
        var base: ?type = Base;
        while (base != null) {
            for (std.meta.fields(Derived)) |field| {
                if (@hasField(base.?, field.name)) {
                    @compileError("Field already exists in the base: " ++ field.name);
                }
            }
            base = base.?.Base;
        }
    };
    return struct {
        pub usingnamespace DeriveFromChain(build_inheritance_chain(Base, Derived), Derived);
    };
}

pub fn VirtualCall(self: anytype, comptime name: []const u8, args: anytype, ReturnType: type) ReturnType {
    return @field(self._vtable, name).?(self._ptr, args);
}
