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

//! This module provides basic object oriented programming features in Zig.

const std = @import("std");

const MemFunctionsHolder = struct {
    allocator: std.mem.Allocator,
    destroy: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,
    dupe: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) ?*anyopaque,
};

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
        .alignment = @alignOf(FinalType),
    };
}

fn BuildVTable(comptime InterfaceType: anytype) type {
    comptime var fields: []const std.builtin.Type.StructField = &[_]std.builtin.Type.StructField{};
    inline for (std.meta.declarations(InterfaceType)) |d| {
        if (std.meta.hasMethod(InterfaceType, d.name)) {
            const Method = @field(InterfaceType, d.name);
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

fn decorate_with_const(comptime T: type, comptime BaseType: type) type {
    if (@typeInfo(T).pointer.is_const) {
        return *const BaseType;
    } else {
        return *BaseType;
    }
}

fn gen_vcall(Type: type, ArgsType: anytype, name: []const u8, index: u32, ObjectType: type) type {
    return struct {
        const RetType = @typeInfo(@TypeOf(ArgsType)).@"fn".return_type.?;
        const Params = @typeInfo(@TypeOf(ArgsType)).@"fn".params;
        const SelfType = Params[0].type.?;
        comptime {
            if (@typeInfo(SelfType) != .pointer) {
                @compileError("First argument of virtual function must be a pointer to the object type, failed for: " ++ @typeName(Type) ++ "::" ++ name ++ " with self type: " ++ @typeName(SelfType));
            }
        }

        fn call(ptr: prune_type_info(@typeInfo(SelfType)), call_params: get_vcall_args(ArgsType)) RetType {
            std.debug.assert(@typeInfo(SelfType) == .pointer);
            const self: decorate_with_const(SelfType, Type) = @ptrCast(@alignCast(ptr));
            if (index == 0 or std.mem.eql(u8, name, "delete")) {
                return @call(.auto, @field(Type, name), .{self} ++ call_params);
            } else {
                // seek for parent that has the method
                comptime var ChildType = ObjectType;
                var base: decorate_with_const(SelfType, anyopaque) = self;
                inline while (@hasField(ChildType, "base")) {
                    const BaseType = ChildType;
                    ChildType = @FieldType(@FieldType(ChildType, "base"), "__data");
                    base = &@field(@as(decorate_with_const(SelfType, BaseType), @ptrCast(@alignCast(base))), "base");
                    // base = &@field(@as(decorate_with_const(SelfType, BaseType), @ptrCast(@alignCast(base))), "base");
                    // if child has the method then it's the one we want
                    if (@hasDecl(ChildType, name)) {
                        // for (0..index) |_| {
                        // base = &@as(BaseType, @ptrCast(base)).base;
                        return @call(.auto, @field(ChildType, name), .{@as(decorate_with_const(@TypeOf(ptr), ChildType), @ptrCast(@alignCast(base)))} ++ call_params);
                    }
                }
                @compileError("Parent not found for function: '" ++ name ++ "' in '" ++ @typeName(ObjectType) ++ "'");
            }
        }
    };
}

fn GenerateClass(comptime InterfaceType: type) type {
    return struct {
        fn __build_vtable_chain(chain: []const type) InterfaceType.Self.VTable {
            var vtable: InterfaceType.Self.VTable = undefined;
            for (std.meta.fields(InterfaceType.Self.VTable)) |field| {
                @field(vtable, field.name) = null; // Initialize all fields to null
            }
            var index: isize = chain.len - 1;
            inline while (index >= 0) : (index -= 1) {
                comptime var base = chain[index];
                comptime if (@hasField(chain[index], "__data")) {
                    base = @FieldType(chain[index], "__data");
                };
                for (std.meta.fields(InterfaceType.Self.VTable)) |field| {
                    if (std.meta.hasMethod(base, field.name)) {
                        const field_type = @field(base, field.name);
                        const vcall = gen_vcall(base, field_type, field.name, index, chain[0]);
                        const VTableCallType = *const @TypeOf(vcall.call);
                        const VTableEntryType = @typeInfo(@TypeOf(@field(vtable, field.name))).optional.child;
                        if (VTableCallType != VTableEntryType) {
                            @compileError("Virtual call type mismatch for '" ++ field.name ++ "' in interface: " ++ @typeName(InterfaceType) ++ "\n" ++ "Expected: " ++ @typeName(VTableEntryType) ++ "\n" ++ "Got:      " ++ @typeName(VTableCallType) ++ "\n" ++ "Chain: " ++ std.fmt.comptimePrint("{any}", .{chain}));
                        }
                        @field(vtable, field.name) = vcall.call;
                    }
                }
            }

            inline for (std.meta.fields(InterfaceType.Self.VTable)) |field| {
                if (@field(vtable, field.name) == null) {
                    @compileError("Pure virtual function '" ++ field.name ++ "' for interface: " ++ @typeName(InterfaceType) ++ "\n" ++ "Chain: " ++ std.fmt.comptimePrint("{any}", .{chain}));
                }
            }
            return vtable;
        }

        pub fn __init_chain(ptr: anytype, chain: []const type, memfunctions: ?MemFunctionsHolder, reference_counter: ?*i32) InterfaceType.Self {
            const gen_vtable = struct {
                const Self = @TypeOf(ptr.*);
                const vtable = __build_vtable_chain(chain);
            };

            if (@hasField(InterfaceType.Self, "__refcount")) {
                return InterfaceType.Self{
                    .__vtable = &gen_vtable.vtable,
                    .__ptr = @ptrCast(ptr),
                    .__memfunctions = memfunctions,
                    .__refcount = reference_counter,
                };
            } else {
                return InterfaceType.Self{
                    .__vtable = &gen_vtable.vtable,
                    .__ptr = @ptrCast(ptr),
                    .__memfunctions = memfunctions,
                };
            }
        }
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

    comptime var current: ?type = Base;
    inline while (current != null) {
        const a: []const type = &.{current.?};
        chain = chain ++ a;
        current = current.?.Base;
    }
    return chain;
}

fn DeriveFromChain(comptime chain: []const type, comptime Derived: type) type {
    return struct {
        pub const Base: ?type = if (chain.len > 1) chain[1] else null;
        pub const InterfaceType = chain[chain.len - 1];

        const Self = @This();

        pub fn create(ptr: *Self) InterfaceType {
            if (comptime std.mem.indexOf(u8, @typeName(InterfaceType), "CountingInterface") != null) {
                @compileError("Can't create static interface for CountingInterface");
            }
            comptime var BaseType = Base;
            if (BaseType == null) {
                BaseType = InterfaceType;
            }
            const parent: *DeriveFromBase(BaseType.?, Derived) = @alignCast(@fieldParentPtr("interface", ptr));
            return InterfaceType.InterfaceType.__init_chain(parent, chain[0 .. chain.len - 1], null, null);
        }

        pub fn new(ptr: *const Self, allocator: std.mem.Allocator) !InterfaceType {
            comptime var BaseType = Base;
            if (BaseType == null) {
                BaseType = InterfaceType;
            }
            const parent: *const DeriveFromBase(BaseType.?, Derived) = @alignCast(@fieldParentPtr("interface", ptr));

            const object = try allocator.create(DeriveFromBase(BaseType.?, Derived));
            object.* = parent.*;
            const release = struct {
                fn call(p: *anyopaque, alloc: std.mem.Allocator) void {
                    const self: *DeriveFromBase(BaseType.?, Derived) = @ptrCast(@alignCast(p));
                    alloc.destroy(self);
                }
            };
            const dupe = struct {
                fn call(p: *anyopaque, alloc: std.mem.Allocator) ?*anyopaque {
                    const Type = Derived;
                    const self: *Type = @ptrCast(@alignCast(p));
                    var copy = alloc.create(Type) catch return null;
                    if (@hasDecl(Derived, "__clone")) {
                        copy.__clone(self);
                    } else {
                        copy.* = self.*;
                    }
                    return copy;
                }
            };

            const destroy: MemFunctionsHolder = .{
                .allocator = allocator,
                .destroy = &release.call,
                .dupe = &dupe.call,
            };

            var refcounter: ?*i32 = null;

            if (@hasField(InterfaceType, "__refcount")) {
                refcounter = try allocator.create(i32);
                refcounter.?.* = 1;
            }

            return InterfaceType.InterfaceType.__init_chain(object, chain[0 .. chain.len - 1], destroy, refcounter);
        }

        pub fn __destructor(self: *Self, allocator: std.mem.Allocator) void {
            const obj: *Derived = @alignCast(@fieldParentPtr("interface", self));
            allocator.destroy(obj);
        }
    };
}

/// This is basic inheritance mechanism that allows to derive from a base class
/// `Base` must be an interface type or a struct that is derived from an interface type.
/// `Derived` must be a struct that has a `base` field of type `Base` when `Base` is not an interface.
/// To declare an interface type, use `ConstructInterface` function.
pub fn DeriveFromBase(comptime BaseType: anytype, comptime Derived: type) type {
    comptime if (!@hasDecl(BaseType, "IsInterface")) { // ensure we have base member
        if (!@hasField(Derived, "base") or !(@FieldType(Derived, "base") == BaseType)) {
            @compileError("Deriving from a base instead of an interface requires a 'base' field in the derived type.");
        }
    };

    return struct {
        const Self = @This();
        pub const Base = BaseType;
        pub const InstanceType = Derived;
        interface: DeriveFromChain(build_inheritance_chain(Base, Derived), Derived) = .{},
        __data: Derived,

        pub fn init(init_data: anytype) Self {
            var obj: @This() = undefined;
            inline for (std.meta.fields(Derived)) |f| {
                if (!@hasField(@TypeOf(init_data), f.name)) {
                    @compileError("Initializer for " ++ @typeName(Derived) ++ " has no field ." ++ f.name);
                }
                @field(obj.__data, f.name) = @field(init_data, f.name);
            }
            return obj;
        }

        pub fn data(self: *Self) *Derived {
            return &self.__data;
        }
    };
}

/// This is a wrapper to delegate virtual calls to the vtable.
/// Look into 'examples' for usage examples.
/// `self` is a pointer to the object that implements the interface.
/// `name` is the name of the method to call.
/// `args` is a tuple of arguments to pass to the method.
/// `ReturnType` is the type of the return value of the method.
pub fn VirtualCall(self: anytype, comptime name: []const u8, args: anytype, ReturnType: type) ReturnType {
    const parent: decorate_with_const(@TypeOf(self), ConstructInterface(@TypeOf(self.*))) = @alignCast(@fieldParentPtr("interface", self));
    return @field(parent.__vtable, name).?(parent.__ptr, args);
}

pub fn DestructorCall(self: anytype) void {
    const parent: decorate_with_const(@TypeOf(self), ConstructInterface(@TypeOf(self.*))) = @alignCast(@fieldParentPtr("interface", self));
    parent.__destructor();
}

pub fn CountingInterfaceVirtualCall(self: anytype, comptime name: []const u8, args: anytype, ReturnType: type) ReturnType {
    const parent: decorate_with_const(@TypeOf(self), ConstructCountingInterface(@TypeOf(self.*))) = @alignCast(@fieldParentPtr("interface", self));
    return @field(parent.__vtable, name).?(parent.__ptr, args);
}

pub fn CountingInterfaceDestructorCall(self: anytype) void {
    const parent: decorate_with_const(@TypeOf(self), ConstructCountingInterface(@TypeOf(self.*))) = @alignCast(@fieldParentPtr("interface", self));
    parent.__destructor();
}

/// This function constructs an interface type.
/// `SelfType` is a type of the interface holder generator function.
/// Returns a struct that represents the interface type.
pub fn ConstructInterface(comptime SelfType: type) type {
    return struct {
        pub const Self = @This();
        pub const VTable = BuildVTable(SelfType);
        pub const IsInterface = true;
        pub const Base: ?type = null;
        const InterfaceType = GenerateClass(@This());

        __vtable: *const VTable,
        __ptr: *anyopaque,
        __memfunctions: ?MemFunctionsHolder,
        interface: SelfType = .{},
        pub const iface = Self.interface;

        pub fn __destructor(self: *Self) void {
            if (@hasField(VTable, "delete")) {
                self.__vtable.delete.?(self.__ptr, .{});
            }
            if (self.__memfunctions) |memfuncs| {
                memfuncs.destroy(self.__ptr, memfuncs.allocator);
            }
        }

        pub fn clone(self: *const Self) !Self {
            var new = self.*;
            if (self.__memfunctions == null) {
                return error.CannotDuplicateStaticInterface;
            }

            const newdata = self.__memfunctions.?.dupe(self.__ptr, self.__memfunctions.?.allocator);
            if (newdata == null) {
                return error.DuplicateFailed;
            }
            new.__ptr = newdata.?;

            return new;
        }
    };
}

/// This function constructs an reference counting interface type.
/// It is intended for objects that may be shared
/// `SelfType` is a type of the interface holder generator function.
/// Returns a struct that represents the interface type.
pub fn ConstructCountingInterface(comptime SelfType: type) type {
    return struct {
        pub const Self = @This();
        pub const VTable = BuildVTable(SelfType);
        pub const IsInterface = true;
        pub const Base: ?type = null;
        const InterfaceType = GenerateClass(@This());

        __vtable: *const VTable,
        __ptr: *anyopaque,
        __memfunctions: ?MemFunctionsHolder,
        __refcount: ?*i32,
        interface: SelfType = .{},

        pub fn __destructor(self: *Self) void {
            if (self.__refcount != null) {
                self.__refcount.?.* -= 1;

                if (self.__refcount.?.* == 0) {
                    if (@hasField(VTable, "delete")) {
                        self.__vtable.delete.?(self.__ptr, .{});
                    }
                    if (self.__memfunctions) |destroy| {
                        destroy.destroy(self.__ptr, destroy.allocator);
                        destroy.allocator.destroy(self.__refcount.?);
                    }
                }
            } else {
                if (@hasField(VTable, "delete")) {
                    self.__vtable.delete.?(self.__ptr, .{});
                }
            }
        }

        pub fn share(self: *Self) Self {
            if (self.__refcount) |r| {
                r.* += 1;
            }

            return self.*;
        }

        pub fn get_refcount(self: *Self) i32 {
            if (self.__refcount) |r| {
                return r.*;
            }
            return 1;
        }

        pub fn clone(self: *const Self) !Self {
            var new = self.*;
            if (self.__memfunctions == null) {
                return error.CannotDuplicateStaticInterface;
            }

            const newdata = self.__memfunctions.?.dupe(self.__ptr, self.__memfunctions.?.allocator);
            if (newdata == null) {
                return error.DuplicateFailed;
            }
            new.__ptr = newdata.?;

            if (self.__refcount != null) {
                new.__refcount = try self.__memfunctions.?.allocator.create(i32);
                new.__refcount.?.* = 1;
            }

            return new;
        }

        pub fn as(self: *Self, comptime T: type) *T {
            return @ptrCast(@alignCast(self.__ptr));
        }
    };
}

pub fn GetBase(self: anytype) decorate_with_const(@TypeOf(self), @TypeOf(self.*.base.__data)) {
    return &(self.*.base.__data);
}
