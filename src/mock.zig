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

const interface = @import("interface.zig");

const std = @import("std");

pub const any = struct {};

fn deduce_type(comptime T: type) type {
    switch (@typeInfo(T)) {
        .pointer => return @typeInfo(T).pointer.child,
        else => return T,
    }
}

fn find_best_expectation(ExpectationType: type, expectations: *std.DoublyLinkedList, args: anytype) !?*ExpectationHolder {
    var best_score: i32 = -1;
    var best_node: ?*std.DoublyLinkedList.Node = null;

    var it = expectations.first;
    while (it) |list_node| {
        const holder: *ExpectationHolder = @fieldParentPtr("_node", list_node);
        const expectation = @as(*ExpectationType, @ptrCast(@alignCast(holder.expectation)));

        if (expectation._sequence) |seq| {
            if (seq.isExpectationAllowed(expectation)) {
                if (expectation.matchesArgs(args) > 0) {
                    return holder;
                }
            }

            // sequence is broken, but maybe we have other expectation that matches and do not require sequence
            var itt = list_node.next;
            while (itt) |n| {
                const h: *ExpectationHolder = @fieldParentPtr("_node", n);
                const e = @as(*ExpectationType, @ptrCast(@alignCast(h.expectation)));
                if (e._sequence == null) {
                    const sc = e.matchesArgs(args);
                    if (sc > best_score) {
                        best_score = sc;
                        best_node = itt;
                    }
                }
                itt = n.next;
            }
            if (best_node != null) {
                return @as(*ExpectationHolder, @fieldParentPtr("_node", best_node.?));
            }

            std.debug.print("Sequence was broken due to the call\n", .{});
            std.debug.dumpCurrentStackTrace(null);
            std.debug.print("Expectation set at:\n", .{});
            std.debug.dumpStackTrace(expectation._stack_trace);
            std.debug.print("Required in sequence call:\n", .{});
            seq.dumpExpectation();
            return error.SequenceBroken;
        }

        var score = expectation.matchesArgs(args);
        if (score == 0 and expectation._callback != null) {
            score = 1;
        }

        if (score > best_score) {
            best_score = score;
            best_node = list_node;
        }

        it = list_node.next;
    }

    if (best_node == null) {
        return null;
    }

    return @as(*ExpectationHolder, @fieldParentPtr("_node", best_node.?));
}

fn verify_mock_call(self: anytype, comptime method_name: [:0]const u8, args: anytype, ReturnType: type) ReturnType {
    var expectations = self.expectations.getPtr(method_name) orelse {
        std.debug.print("No expectations found for method: {s}.{s}\n", .{ @typeName(deduce_type(@TypeOf(self))), method_name });
        unreachable;
    };

    if (expectations.len() == 0) {
        std.debug.print("No more expectations left for method: {s}.{s}\n", .{ @typeName(deduce_type(@TypeOf(self))), method_name });
        unreachable;
    }

    const maybe_holder = find_best_expectation(Expectation(@TypeOf(args), ReturnType), expectations, args) catch |err| {
        switch (err) {
            error.SequenceBroken => {
                unreachable;
            },
            else => unreachable,
        }
    };

    if (maybe_holder) |holder| {
        const expectation = @as(*Expectation(@TypeOf(args), ReturnType), @ptrCast(@alignCast(holder.expectation)));
        var ret: ReturnType = undefined;
        if (expectation._callback) |cb| {
            ret = cb(args) catch unreachable;
        } else {
            ret = expectation.getReturnValue();
        }

        if (expectation._times) |*times| {
            times.* -= 1;
            if (times.* == 0) {
                if (expectation._sequence) |seq| {
                    seq.popFirst();
                }
                Expectation(@TypeOf(args), ReturnType).verify(expectation) catch unreachable;

                expectations.remove(&holder._node);
                self.allocator.destroy(holder);
            }
        }
        return ret;
    } else {
        std.debug.print("No matching expectation found for method: {s}.{s}\n", .{ @typeName(deduce_type(@TypeOf(self))), method_name });
        unreachable;
    }
}

pub fn MockDestructorCall(self: anytype) !void {
    var it = self.expectations.iterator();
    // clean expectation with any times call
    while (it.next()) |entry| {
        var list = entry.value_ptr;
        var node_it = list.first;
        while (node_it) |list_node| {
            const holder: *ExpectationHolder = @fieldParentPtr("_node", list_node);
            try holder.verify();
            const next_node = list_node.next;
            list.remove(list_node);
            self.allocator.destroy(holder);
            node_it = next_node;
        }
    }
    self.expectations.deinit();
}

// Type-erased argument matcher that can store any type
const ArgMatcher = struct {
    value_ptr: ?*anyopaque,
    match: ?*const fn (stored: *anyopaque, actual: *anyopaque) bool,
    deinit: ?*const fn (value: *anyopaque, allocator: std.mem.Allocator) void,

    pub fn create(comptime T: type, allocator: std.mem.Allocator, value: anytype) !ArgMatcher {
        if (@TypeOf(value) == any) {
            return ArgMatcher{
                .value_ptr = null,
                .match = null,
                .deinit = null,
            };
        }

        const ValueHolder = struct {
            fn matchFn(stored: *anyopaque, actual: *anyopaque) bool {
                const stored_val: *T = @ptrCast(@alignCast(stored));
                const actual_val: *T = @ptrCast(@alignCast(actual));
                return std.meta.eql(stored_val.*, actual_val.*);
            }

            fn deinitFn(val: *anyopaque, alloc: std.mem.Allocator) void {
                const typed_val: *T = @ptrCast(@alignCast(val));
                alloc.destroy(typed_val);
            }
        };

        const stored = try allocator.create(T);
        stored.* = value;

        return ArgMatcher{
            .value_ptr = stored,
            .match = ValueHolder.matchFn,
            .deinit = ValueHolder.deinitFn,
        };
    }

    pub fn matches(self: *const ArgMatcher, value: anytype) i32 {
        var val = value;
        if (self.value_ptr) |value_ptr| {
            return if (self.match.?(value_ptr, @ptrCast(&val))) 10 else 0;
        }
        return 1;
    }

    pub fn destroy(self: *const ArgMatcher, allocator: std.mem.Allocator) void {
        if (self.value_ptr) |value_ptr| {
            self.deinit.?(value_ptr, allocator);
        }
    }
};

const ArgsMatcher = struct {
    allocator: std.mem.Allocator,
    matchers: std.ArrayList(ArgMatcher),

    pub fn init(allocator: std.mem.Allocator) ArgsMatcher {
        return .{
            .allocator = allocator,
            .matchers = std.ArrayList(ArgMatcher).initCapacity(allocator, 0) catch unreachable,
        };
    }

    pub fn addMatcher(self: *ArgsMatcher, comptime T: type, value: T) !void {
        const matcher = try ArgMatcher.create(T, self.allocator, value);
        try self.matchers.append(self.allocator, matcher);
    }

    pub fn matchesArgs(self: *const ArgsMatcher, args: anytype) i32 {
        const fields = std.meta.fields(@TypeOf(args));
        var total_score: i32 = 0;
        if (fields.len != self.matchers.items.len) {
            return 0;
        }

        inline for (fields, 0..) |field, i| {
            const value: i32 = self.matchers.items[i].matches(@field(args, field.name));
            if (value == 0) {
                return 0;
            }
            total_score += value;
        }
        return total_score;
    }

    pub fn deinit(self: *ArgsMatcher) void {
        for (self.matchers.items) |matcher| {
            matcher.destroy(self.allocator);
        }
        self.matchers.deinit(self.allocator);
    }
};

fn isTuple(comptime T: type) bool {
    const info = @typeInfo(T);
    return switch (info) {
        .@"struct" => info.@"struct".is_tuple,
        else => false,
    };
}

pub const ExpectationHolder = struct {
    _node: std.DoublyLinkedList.Node,
    expectation: *anyopaque,
    verify_fn: *const fn (*anyopaque) anyerror!void,

    pub fn verify(self: *ExpectationHolder) anyerror!void {
        return self.verify_fn(self.expectation);
    }
};

pub fn Expectation(comptime ArgsType: type, comptime ReturnType: type) type {
    return struct {
        const Self = @This();
        const CallbackFn = *const fn (ArgsType) anyerror!ReturnType;

        _allocator: std.mem.Allocator,
        _return: ?ReturnType,
        _args_matcher: ?ArgsMatcher,
        _times: ?i32,
        _callback: ?CallbackFn,
        _stack_trace: std.builtin.StackTrace,
        _sequence: ?*Sequence,

        pub fn init(allocator: std.mem.Allocator, stacktrace: std.builtin.StackTrace) Self {
            return Self{
                ._allocator = allocator,
                ._return = null,
                ._args_matcher = null,
                ._times = 1,
                ._callback = null,
                ._stack_trace = stacktrace,
                ._sequence = null,
            };
        }

        pub fn willReturn(self: *Self, value: ReturnType) *Self {
            self._return = value;
            return self;
        }

        pub fn times(self: *Self, count: anytype) *Self {
            if (@TypeOf(count) == any) {
                self._times = null;
                return self;
            }
            self._times = count;
            return self;
        }

        /// Set a callback function to invoke when this expectation is matched
        /// The callback receives the arguments and can return a value
        pub fn invoke(self: *Self, callback: CallbackFn) *Self {
            self._callback = callback;
            return self;
        }

        pub fn getReturnValue(self: *Self) ReturnType {
            // If callback is set, invoke it
            // Otherwise return the stored value
            if (ReturnType == void) {
                return;
            }
            std.debug.assert(self._return != null);
            return self._return.?;
        }

        pub fn withArgs(self: *Self, args: anytype) *Self {
            var matcher = ArgsMatcher.init(self._allocator);
            const fields = std.meta.fields(@TypeOf(args));
            inline for (fields) |field| {
                matcher.addMatcher(field.type, @field(args, field.name)) catch unreachable;
            }
            self._args_matcher = matcher;
            return self;
        }

        pub fn matchesArgs(self: *const Self, args: ArgsType) i32 {
            if (self._args_matcher) |*matcher| {
                return matcher.matchesArgs(args);
            }
            if (@TypeOf(args) == @TypeOf(.{})) {
                return 1;
            }
            return 0;
        }

        pub fn verify(ctx: *anyopaque) anyerror!void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            if (self._times) |t| {
                errdefer {
                    std.debug.print("Expectation not met times: {d} for: \n", .{t});
                    std.debug.dumpStackTrace(self._stack_trace);
                }
                try std.testing.expectEqual(t, 0);
            }
            if (self._sequence) |seq| {
                seq.release();
            }
            if (self._args_matcher) |*matcher| {
                matcher.deinit();
            }
            self._allocator.free(self._stack_trace.instruction_addresses);
            self._allocator.destroy(self);
        }

        pub fn dumpStackTrace(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            std.debug.dumpStackTrace(self._stack_trace);
        }

        pub fn inSequence(self: *Self, sequence: *Sequence) *Self {
            self._sequence = sequence.share();
            sequence.addExpectation(self, dumpStackTrace) catch unreachable;
            return self;
        }
    };
}

pub const Sequence = struct {
    pub const DumpStacktraceFn = *const fn (ctx: *anyopaque) void;
    const ExpectationNode = struct {
        ptr: *anyopaque,
        stacktrace: DumpStacktraceFn,
    };
    allocator: std.mem.Allocator,
    expectations: std.ArrayList(ExpectationNode),
    ref_count: usize,

    pub fn init(allocator: std.mem.Allocator) Sequence {
        return Sequence{
            .allocator = allocator,
            .expectations = std.ArrayList(ExpectationNode).initCapacity(allocator, 0) catch unreachable,
            .ref_count = 0,
        };
    }

    pub fn addExpectation(self: *Sequence, expectation: *anyopaque, stacktrace: DumpStacktraceFn) !void {
        try self.expectations.append(self.allocator, .{ .ptr = expectation, .stacktrace = stacktrace });
    }

    pub fn dumpExpectation(self: *Sequence) void {
        if (self.expectations.items.len == 0) {
            std.debug.print("No expectations in sequence\n", .{});
            return;
        }
        self.expectations.items[0].stacktrace(self.expectations.items[0].ptr);
    }

    pub fn isExpectationAllowed(self: *Sequence, expectation: *anyopaque) bool {
        if (self.expectations.items.len == 0) {
            return false;
        }
        return self.expectations.items[0].ptr == expectation;
    }

    pub fn popFirst(self: *Sequence) void {
        if (self.expectations.items.len == 0) {
            return;
        }
        _ = self.expectations.orderedRemove(0);
    }

    pub fn share(self: *Sequence) *Sequence {
        self.ref_count += 1;
        return self;
    }

    pub fn release(self: *Sequence) void {
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.expectations.deinit(self.allocator);
        }
    }
};

pub fn MockInterface(comptime InterfaceType: type) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        interface: InterfaceType,
        expectations: std.StringHashMap(std.DoublyLinkedList),

        // Helper to extract function signature types from VTable
        fn getMethodTypes(comptime method_name: [:0]const u8) struct { args: type, ret: type } {
            const vtable_fields = std.meta.fields(InterfaceType.VTable);
            inline for (vtable_fields) |field| {
                if (std.mem.eql(u8, field.name, method_name)) {
                    const field_type_info = @typeInfo(field.type);

                    // Handle optional pointer: ?*const fn(...)
                    const fn_info = switch (field_type_info) {
                        .optional => blk: {
                            const child_info = @typeInfo(field_type_info.optional.child);
                            break :blk switch (child_info) {
                                .pointer => @typeInfo(child_info.pointer.child).@"fn",
                                .@"fn" => child_info.@"fn",
                                else => @compileError("Expected function or function pointer in optional"),
                            };
                        },
                        .pointer => @typeInfo(field_type_info.pointer.child).@"fn",
                        .@"fn" => field_type_info.@"fn",
                        else => @compileError("Expected function, function pointer, or optional function pointer in VTable"),
                    };

                    const return_type = fn_info.return_type.?;

                    // Build tuple type from parameters (skip self parameter)
                    comptime var arg_types: []const type = &[_]type{};
                    inline for (fn_info.params[1..]) |param| {
                        arg_types = arg_types ++ [_]type{param.type.?};
                    }

                    return .{ .args = arg_types[0], .ret = return_type };
                }
            }
            @compileError("Method '" ++ method_name ++ "' not found in interface VTable");
        }

        pub fn expectCall(self: *Self, comptime method_name: [:0]const u8) *Expectation(getMethodTypes(method_name).args, getMethodTypes(method_name).ret) {
            const types = getMethodTypes(method_name);
            const ArgsType = types.args;
            const ReturnType = types.ret;

            var list = self.expectations.getPtr(method_name) orelse blk: {
                self.expectations.put(method_name, std.DoublyLinkedList{}) catch unreachable;
                break :blk self.expectations.getPtr(method_name) orelse unreachable;
            };

            const ExpectationType = Expectation(ArgsType, ReturnType);
            const expectation = self.allocator.create(ExpectationType) catch unreachable;
            var stacktrace: std.builtin.StackTrace = .{
                .index = 0,
                .instruction_addresses = self.allocator.alloc(usize, 32) catch unreachable,
            };

            std.debug.captureStackTrace(null, &stacktrace);

            expectation.* = ExpectationType.init(self.allocator, stacktrace);

            const holder = self.allocator.create(ExpectationHolder) catch unreachable;
            holder.* = .{
                ._node = std.DoublyLinkedList.Node{},
                .expectation = expectation,
                .verify_fn = ExpectationType.verify,
            };

            list.append(&holder._node);
            return expectation;
        }

        pub fn get_interface(self: *Self) InterfaceType {
            return self.interface;
        }

        pub fn create(allocator: std.mem.Allocator) !*Self {
            const gen_vtable = struct {
                const vtable = Self.__build_vtable_chain();
            };

            const self = try allocator.create(Self);

            const release = struct {
                fn call(p: *anyopaque, alloc: std.mem.Allocator) void {
                    const s: *Self = @ptrCast(@alignCast(p));
                    alloc.destroy(s);
                }
            };
            const dupe = struct {
                fn call(p: *anyopaque, alloc: std.mem.Allocator) ?*anyopaque {
                    const s: *Self = @ptrCast(@alignCast(p));
                    const copy = alloc.create(Self) catch return null;
                    copy.* = s.*;
                    return copy;
                }
            };

            if (@hasField(InterfaceType, "__refcount")) {
                const refcount: *i32 = try allocator.create(i32);
                refcount.* = 1;
                self.* = Self{
                    .allocator = allocator,
                    .interface = InterfaceType{
                        .__vtable = &gen_vtable.vtable,
                        .__ptr = self,
                        .__memfunctions = .{
                            .allocator = allocator,
                            .destroy = &release.call,
                            .dupe = &dupe.call,
                        },
                        .__refcount = refcount,
                    },
                    .expectations = std.StringHashMap(std.DoublyLinkedList).init(allocator),
                };
                inline for (std.meta.fields(InterfaceType.VTable)) |field| {
                    self.expectations.put(field.name, std.DoublyLinkedList{}) catch unreachable;
                }
            } else {
                self.* = Self{
                    .allocator = allocator,
                    .interface = InterfaceType{
                        .__vtable = &gen_vtable.vtable,
                        .__ptr = self,
                        .__memfunctions = .{
                            .allocator = allocator,
                            .destroy = &release.call,
                            .dupe = &dupe.call,
                        },
                    },
                    .expectations = std.StringHashMap(std.DoublyLinkedList).init(allocator),
                };
                inline for (std.meta.fields(InterfaceType.VTable)) |field| {
                    self.expectations.put(field.name, std.DoublyLinkedList{}) catch unreachable;
                }
            }
            return self;
        }

        pub fn __build_vtable_chain() InterfaceType.VTable {
            var vtable: InterfaceType.VTable = undefined;

            // Generate wrapper functions for each VTable entry
            inline for (std.meta.fields(InterfaceType.VTable)) |field| {
                const field_type_info = @typeInfo(field.type);
                const fn_info = switch (field_type_info) {
                    .optional => blk: {
                        const child_info = @typeInfo(field_type_info.optional.child);
                        break :blk switch (child_info) {
                            .pointer => @typeInfo(child_info.pointer.child).@"fn",
                            .@"fn" => child_info.@"fn",
                            else => @compileError("Expected function or function pointer in optional"),
                        };
                    },
                    .pointer => @typeInfo(field_type_info.pointer.child).@"fn",
                    .@"fn" => field_type_info.@"fn",
                    else => @compileError("Expected function, function pointer, or optional function pointer in VTable"),
                };

                const SelfType = fn_info.params[0].type.?;
                const ArgsType = fn_info.params[1].type.?;

                // Determine self pointer type (const or mutable, opaque)
                const is_const = @typeInfo(SelfType).pointer.is_const;

                if (std.mem.eql(u8, field.name, "delete")) {
                    const Wrapper = struct {
                        fn call(ptr: SelfType, args: ArgsType) void {
                            _ = args;
                            const self: if (is_const) *const Self else *Self = @ptrCast(@alignCast(ptr));
                            MockDestructorCall(self) catch unreachable;
                        }
                    };
                    @field(vtable, field.name) = &Wrapper.call;
                } else {
                    const Wrapper = struct {
                        fn call(ptr: SelfType, args: ArgsType) fn_info.return_type.? {
                            const self: if (is_const) *const Self else *Self = @ptrCast(@alignCast(ptr));
                            return verify_mock_call(self, field.name, args, fn_info.return_type.?);
                        }
                    };

                    @field(vtable, field.name) = &Wrapper.call;
                }
            }

            return vtable;
        }

        pub fn delete(self: *Self) void {
            _ = self;
        }
    };
}
