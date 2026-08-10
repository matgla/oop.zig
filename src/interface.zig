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

/// The shared reference count behind `ConstructCountingInterface`.
///
/// This is the backbone of every shared object's lifetime -- in YasOS, every
/// `IFile`, `IDirectory` and `IFileSystem` -- so it is the one place in this
/// library where a lost update frees memory that is still in use, or leaks
/// memory that is not. It used to be a plain `r.* += 1` / `r.* -= 1`, which is
/// a read-modify-write: two contexts can read the same value and both write
/// back the same result, dropping one of the two operations. On one core that
/// needs an interrupt to land between the load and the store; on two it needs
/// nothing at all.
///
/// The counter is `i32` rather than something unsigned because `get_refcount`
/// has always returned `i32`, and a negative value is a real diagnostic: it
/// means a double release, which is worth seeing rather than wrapping.
pub const refcount = struct {
    /// Called on every freshly allocated counter, when installed.
    ///
    /// The hazard it exists for is invisible otherwise. A counter allocated
    /// from a *process* heap can land in external PSRAM, and on the RP2350 the
    /// global exclusive monitor does not cover the PSRAM window -- so the
    /// exclusives below still succeed, against the core's local monitor, and
    /// guarantee nothing between cores. No fault, no log line, just the
    /// occasional freed-too-early object months later.
    ///
    /// This library has no business knowing a board's memory map, so the check
    /// is injected: the kernel installs `kernel.sync.placement.assert_coherent`
    /// here during boot. Left null, nothing is checked and behaviour is
    /// unchanged.
    pub var placement_check: ?*const fn (counter: *const i32) void = null;

    /// A counter with exactly one owner.
    pub fn init(counter: *i32) void {
        if (placement_check) |check| check(counter);
        // Plain: nothing else can reach a counter that has not been published
        // yet, and publishing it is the caller's release.
        counter.* = 1;
    }

    /// Take a reference.
    ///
    /// Monotonic is sufficient and is not an oversight. An increment is only
    /// ever performed by a context that already holds a reference, so the
    /// object is provably alive across it and there is nothing to order against.
    pub fn acquire(counter: *i32) void {
        _ = @atomicRmw(i32, counter, .Add, 1, .monotonic);
    }

    /// Drop a reference. Returns true if this was the last one and the caller
    /// must now destroy the object.
    ///
    /// `acq_rel`, both halves load-bearing:
    ///
    ///   * **release**, so everything this context wrote through the object is
    ///     visible to whoever ends up running the destructor;
    ///   * **acquire**, so that when this *is* the last reference, every other
    ///     context's writes are visible here before the destructor reads them.
    ///
    /// The textbook form puts the acquire in a standalone fence on the
    /// last-reference branch only. This Zig has no `@fence`, and on Armv8-M
    /// `acq_rel` lowers to `ldaex`/`stlex` with no extra barrier instruction, so
    /// paying it on every decrement costs approximately nothing and removes a
    /// subtlety from a function that must not have any.
    pub fn release(counter: *i32) bool {
        return @atomicRmw(i32, counter, .Sub, 1, .acq_rel) == 1;
    }

    /// The current count.
    ///
    /// Diagnostics only, and monotonic on purpose: any answer is stale by the
    /// time the caller can act on it, so ordering would buy a false sense of
    /// precision. The one value that is meaningful is the one `release`
    /// returned, because that context owns the transition.
    pub fn get(counter: *const i32) i32 {
        return @atomicLoad(i32, counter, .monotonic);
    }
};

fn deduce_type(info: anytype, object_type: anytype) type {
    if (info.pointer.attrs.@"const") {
        return *const object_type;
    }
    return *object_type;
}

fn prune_type_info(info: anytype) type {
    if (info.pointer.attrs.@"const") {
        return *const anyopaque;
    }
    return *anyopaque;
}

fn get_vcall_args(comptime fun: anytype) type {
    // Zig 0.17 replaced `Type.Fn.params` (a slice of structs with `.type`) with
    // parallel `param_types`/`param_attrs` slices.
    const param_types = @typeInfo(@TypeOf(fun)).@"fn".param_types;
    if (param_types.len == 0) {
        return .{};
    }
    comptime var args: []const type = &.{}; // The first parameter is always the object pointer
    for (param_types[1..]) |param_type| {
        const arg: []const type = &.{param_type.?};
        args = args ++ arg;
    }
    // `std.meta.Tuple` is gone in Zig 0.17; `@Tuple` is the builtin equivalent.
    return @Tuple(args);
}

// Zig 0.17 removed `@Type`; struct synthesis is now `@Struct(layout,
// backing_int, field_names, field_types, field_attrs)`, which takes parallel
// name/type slices instead of `std.builtin.Type.StructField` values. So this
// yields just the field type and BuildVTable collects names separately.
fn erasedFnType(comptime Method: anytype) type {
    const info = @typeInfo(@TypeOf(Method)).@"fn";
    const ErasedSelf = prune_type_info(@typeInfo(info.param_types[0].?));
    comptime var params: []const type = &.{ErasedSelf};
    inline for (info.param_types[1..]) |param_type| {
        params = params ++ &[_]type{param_type.?};
    }
    return @Fn(params, &@splat(.{}), info.return_type.?, .{});
}

fn genVTableEntryType(comptime Method: anytype) type {
    return ?*const erasedFnType(Method);
}

fn BuildVTable(comptime InterfaceType: anytype) type {
    comptime var names: []const [:0]const u8 = &.{};
    comptime var types: []const type = &.{};
    // `std.meta.declarations` yields names directly in Zig 0.17, not
    // `Declaration` structs with a `.name` field.
    inline for (std.meta.declarations(InterfaceType)) |decl_name| {
        if (std.meta.hasMethod(InterfaceType, decl_name)) {
            const Method = @field(InterfaceType, decl_name);
            names = names ++ &[_][:0]const u8{decl_name};
            types = types ++ &[_]type{genVTableEntryType(Method)};
        }
    }
    return @Struct(.auto, null, names, types, &@splat(.{}));
}

fn decorate_with_const(comptime T: type, comptime BaseType: type) type {
    if (@typeInfo(T).pointer.attrs.@"const") {
        return *const BaseType;
    } else {
        return *BaseType;
    }
}

fn gen_vcall(Type: type, ArgsType: anytype, name: []const u8, index: u32, ObjectType: type) type {
    const info = @typeInfo(@TypeOf(ArgsType)).@"fn";
    const SelfType = info.param_types[0].?;
    const Erased = prune_type_info(@typeInfo(SelfType));
    const R = info.return_type.?;
    const P = info.param_types;

    comptime {
        if (@typeInfo(SelfType) != .pointer) {
            @compileError("First argument of virtual function must be a pointer to the object type, failed for: " ++ @typeName(Type) ++ "::" ++ name ++ " with self type: " ++ @typeName(SelfType));
        }
    }

    const Resolve = struct {
        inline fn invoke(ptr: Erased, call_params: anytype) R {
            const self: decorate_with_const(SelfType, Type) = @ptrCast(@alignCast(ptr));
            if (comptime (index == 0 or std.mem.eql(u8, name, "delete"))) {
                return @call(.auto, @field(Type, name), .{self} ++ call_params);
            } else {
                comptime var ChildType = ObjectType;
                var base: decorate_with_const(SelfType, anyopaque) = self;
                inline while (@hasField(ChildType, "base")) {
                    const BaseType = ChildType;
                    ChildType = @FieldType(@FieldType(ChildType, "base"), "__data");
                    base = &@field(@as(decorate_with_const(SelfType, BaseType), @ptrCast(@alignCast(base))), "base");
                    if (@hasDecl(ChildType, name)) {
                        return @call(.auto, @field(ChildType, name), .{@as(decorate_with_const(Erased, ChildType), @ptrCast(@alignCast(base)))} ++ call_params);
                    }
                }
                @compileError("Parent not found for function: '" ++ name ++ "' in '" ++ @typeName(ObjectType) ++ "'");
            }
        }
    };

    return switch (P.len) {
        1 => struct {
            fn call(p: Erased) R {
                return Resolve.invoke(p, .{});
            }
        },
        2 => struct {
            fn call(p: Erased, a0: P[1].?) R {
                return Resolve.invoke(p, .{a0});
            }
        },
        3 => struct {
            fn call(p: Erased, a0: P[1].?, a1: P[2].?) R {
                return Resolve.invoke(p, .{ a0, a1 });
            }
        },
        4 => struct {
            fn call(p: Erased, a0: P[1].?, a1: P[2].?, a2: P[3].?) R {
                return Resolve.invoke(p, .{ a0, a1, a2 });
            }
        },
        5 => struct {
            fn call(p: Erased, a0: P[1].?, a1: P[2].?, a2: P[3].?, a3: P[4].?) R {
                return Resolve.invoke(p, .{ a0, a1, a2, a3 });
            }
        },
        6 => struct {
            fn call(p: Erased, a0: P[1].?, a1: P[2].?, a2: P[3].?, a3: P[4].?, a4: P[5].?) R {
                return Resolve.invoke(p, .{ a0, a1, a2, a3, a4 });
            }
        },
        7 => struct {
            fn call(p: Erased, a0: P[1].?, a1: P[2].?, a2: P[3].?, a3: P[4].?, a4: P[5].?, a5: P[6].?) R {
                return Resolve.invoke(p, .{ a0, a1, a2, a3, a4, a5 });
            }
        },
        else => @compileError("interface: virtual method '" ++ name ++ "' has more parameters than gen_vcall supports; add another arity above"),
    };
}

fn GenerateClass(comptime InterfaceType: type) type {
    return struct {
        fn __build_vtable_chain(chain: []const type) InterfaceType.Self.VTable {
            var vtable: InterfaceType.Self.VTable = undefined;
            inline for (@typeInfo(InterfaceType.Self.VTable).@"struct".field_names) |field_name| {
                @field(vtable, field_name) = null; // Initialize all fields to null
            }
            var index: isize = chain.len - 1;
            inline while (index >= 0) : (index -= 1) {
                comptime var base = chain[index];
                comptime if (@hasField(chain[index], "__data")) {
                    base = @FieldType(chain[index], "__data");
                };
                inline for (@typeInfo(InterfaceType.Self.VTable).@"struct".field_names) |field_name| {
                    if (std.meta.hasMethod(base, field_name)) {
                        const field_type = @field(base, field_name);
                        const vcall = gen_vcall(base, field_type, field_name, index, chain[0]);
                        const VTableCallType = *const @TypeOf(vcall.call);
                        const VTableEntryType = @typeInfo(@TypeOf(@field(vtable, field_name))).optional.child;
                        if (VTableCallType != VTableEntryType) {
                            @compileError("Virtual call type mismatch for '" ++ field_name ++ "' in interface: " ++ @typeName(InterfaceType) ++ "\n" ++ "Expected: " ++ @typeName(VTableEntryType) ++ "\n" ++ "Got:      " ++ @typeName(VTableCallType) ++ "\n" ++ "Chain: " ++ std.fmt.comptimePrint("{any}", .{chain}));
                        }
                        @field(vtable, field_name) = vcall.call;
                    }
                }
            }

            inline for (@typeInfo(InterfaceType.Self.VTable).@"struct".field_names) |field_name| {
                if (@field(vtable, field_name) == null) {
                    @compileError("Pure virtual function '" ++ field_name ++ "' for interface: " ++ @typeName(InterfaceType) ++ "\n" ++ "Chain: " ++ std.fmt.comptimePrint("{any}", .{chain}));
                }
            }
            return vtable;
        }

        // Zig 0.17 forbids a container-level decl inside a function from
        // referencing that function's parameters ('chain' not accessible outside
        // function scope). Routing it through a generic function makes `chain` a
        // comptime type parameter, which the returned struct may capture.
        fn VTableHolder(comptime chain: []const type) type {
            return struct {
                const vtable = __build_vtable_chain(chain);
            };
        }

        pub fn __init_chain(ptr: anytype, comptime chain: []const type, memfunctions: ?MemFunctionsHolder, reference_counter: ?*i32) InterfaceType.Self {
            const gen_vtable = VTableHolder(chain);

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
                // `allocator` is whatever the caller handed in, and for a
                // process-owned object that is the process heap -- see
                // `refcount.placement_check`.
                refcount.init(refcounter.?);
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
            inline for (@typeInfo(Derived).@"struct".field_names) |f_name| {
                if (!@hasField(@TypeOf(init_data), f_name)) {
                    @compileError("Initializer for " ++ @typeName(Derived) ++ " has no field ." ++ f_name);
                }
                @field(obj.__data, f_name) = @field(init_data, f_name);
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
    return @call(.auto, @field(parent.__vtable, name).?, .{parent.__ptr} ++ args);
}

pub fn DestructorCall(self: anytype) void {
    const parent: decorate_with_const(@TypeOf(self), ConstructInterface(@TypeOf(self.*))) = @alignCast(@fieldParentPtr("interface", self));
    parent.__destructor();
}

pub fn CountingInterfaceVirtualCall(self: anytype, comptime name: []const u8, args: anytype, ReturnType: type) ReturnType {
    const parent: decorate_with_const(@TypeOf(self), ConstructCountingInterface(@TypeOf(self.*))) = @alignCast(@fieldParentPtr("interface", self));
    return @call(.auto, @field(parent.__vtable, name).?, .{parent.__ptr} ++ args);
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
                self.__vtable.delete.?(self.__ptr);
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

        pub fn as(self: *Self, comptime T: type) *T {
            return @ptrCast(@alignCast(self.__ptr));
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
            if (self.__refcount) |counter| {
                // The decrement and the "was it the last one" test have to be
                // the same operation. Read back separately -- as this did --
                // two contexts releasing the last two references can both
                // observe 0 and both destroy, or neither can and the object
                // leaks.
                if (!refcount.release(counter)) return;

                if (@hasField(VTable, "delete")) {
                    self.__vtable.delete.?(self.__ptr);
                }
                if (self.__memfunctions) |destroy| {
                    destroy.allocator.destroy(counter);
                    destroy.destroy(self.__ptr, destroy.allocator);
                }
            } else {
                if (@hasField(VTable, "delete")) {
                    self.__vtable.delete.?(self.__ptr);
                }
            }
        }

        pub fn share(self: *Self) Self {
            if (self.__refcount) |r| {
                refcount.acquire(r);
            }

            return self.*;
        }

        pub fn get_refcount(self: *Self) i32 {
            if (self.__refcount) |r| {
                return refcount.get(r);
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
                refcount.init(new.__refcount.?);
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
