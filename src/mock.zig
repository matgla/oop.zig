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

fn generateMockMethod(comptime Method: type, comptime name: [:0]const u8) std.builtin.Type.StructField {
    @compileLog("Generating mock method: ", name);
    return std.builtin.Type.StructField{
        .name = name,
        .type = Method,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = @alignOf(Method),
    };
}

fn GenerateMockStruct(comptime InterfaceType: type) type {
    comptime var fields: []const std.builtin.Type.StructField = &[_]std.builtin.Type.StructField{};
    inline for (std.meta.fields(InterfaceType)) |d| {
        @compileLog("Checking method: ", d.name);
        fields = fields ++ &[_]std.builtin.Type.StructField{generateMockMethod(d.type, d.name)};
    }

    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .is_tuple = false,
        .fields = fields,
        .decls = &.{},
    } });
}

pub fn MockInterface(comptime InterfaceType: type) type {
    const MockType = GenerateMockStruct(InterfaceType.VTable);
    return interface.DeriveFromBase(InterfaceType, MockType);
}

fn deduce_type(comptime T: type) type {
    switch (@typeInfo(T)) {
        .pointer => return @typeInfo(T).pointer.child,
        else => return T,
    }
}

pub fn MockVirtualCall(self: anytype, comptime method_name: [:0]const u8, args: anytype, return_type: type) return_type {
    _ = args; // Suppress unused variable warning
    if (!@hasField(deduce_type(@TypeOf(self)), "mock")) {
        @compileError("MockVirtualCall called on non-mock object, please add .mock: interface.GenerateMockTable() to the derived mock struct");
    }

    var expectations = self.mock.expectations.getPtr(method_name) orelse {
        std.debug.print("No expectations found for method: {s}.{s}\n", .{ @typeName(deduce_type(@TypeOf(self))), method_name });
        unreachable;
    };

    if (expectations.len() == 0) {
        std.debug.print("No more expectations left for method: {s}.{s}\n", .{ @typeName(deduce_type(@TypeOf(self))), method_name });
        unreachable;
    }

    const list_node = expectations.first orelse unreachable;
    const expectation = @as(*Expectation, @fieldParentPtr("_node", list_node));
    expectation._times -= 1;
    const ret = expectation.getReturnValue(return_type);
    if (expectation._times == 0) {
        defer self.mock.allocator.destroy(expectation);
        if (expectation._return) |r| {
            defer {
                self.mock.allocator.destroy(@as(*return_type, @ptrCast(@alignCast(r))));
                expectation._return = null;
            }
        }
        expectations.remove(list_node);
    }
    return ret;
}

pub fn MockDestructorCall(self: anytype) void {
    if (!@hasField(deduce_type(@TypeOf(self)), "mock")) {
        @compileError("MockVirtualCall called on non-mock object, please add .mock: interface.GenerateMockTable() to the derived mock struct");
    }
    var it = self.mock.expectations.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.len() != 0) {
            std.debug.print("Not all expectations were met for method: {s}.{s}\n", .{ @typeName(deduce_type(@TypeOf(self))), entry.key_ptr.* });
        }
        var list = entry.value_ptr;
        while (list.pop()) |node| {
            var expectation = @as(*Expectation, @fieldParentPtr("_node", node));
            expectation.delete();
        }
    }
    self.mock.expectations.deinit();
    self.mock.allocator.destroy(self.mock);
}

const ArgMatcher = struct {
    alignment: u8,
    value_ptr: *anyopaque,
    match: *const fn (*anyopaque, *anyopaque) bool,
    deinit: *const fn (*anyopaque) void,
};

const ArgsMatcher = struct {
    allocator: std.mem.Allocator,
    args: std.ArrayList(ArgMatcher),

    pub fn deinit(self: *ArgsMatcher) void {
        self.args.deinit(self.allocator);
    }
};

fn isTuple(comptime T: type) bool {
    const info = @typeInfo(T);
    return switch (info) {
        .@"struct" => info.@"struct".is_tuple,
        else => false,
    };
}

const Expectation = struct {
    _allocator: std.mem.Allocator,
    _return: ?*anyopaque,
    _node: std.DoublyLinkedList.Node,
    _deinit: ?*const fn (self: *Expectation) void,
    _args_matcher: ArgsMatcher,
    _times: i32,

    pub fn willReturn(self: *Expectation, value: anytype) *Expectation {
        const return_object = self._allocator.create(@TypeOf(value)) catch unreachable;
        return_object.* = value;
        self._return = return_object;
        const FunctorType = struct {
            pub fn call(s: *Expectation) void {
                if (s._return) |r| {
                    s._allocator.destroy(@as(*@TypeOf(value), @ptrCast(@alignCast(r))));
                    s._return = null;
                }
            }
        };
        self._deinit = &FunctorType.call;
        return self;
    }

    pub fn times(self: *Expectation, count: i32) *Expectation {
        self._times = count;
        return self;
    }

    pub fn getReturnValue(self: *Expectation, return_type: type) return_type {
        if (return_type == void) {
            return;
        }
        std.testing.expect(self._return != null) catch unreachable;
        return @as(*return_type, @ptrCast(@alignCast(self._return.?))).*;
    }

    pub fn withArgs(self: *Expectation, args: anytype) *Expectation {
        if (!isTuple(@TypeOf(args))) {
            @compileError("argument must be tuple for withArgs");
        }
        return self;
    }

    pub fn delete(self: *Expectation) void {
        if (self._deinit) |deinit_fn| {
            deinit_fn(self);
        }
    }
};

pub const MockTableType = struct {
    allocator: std.mem.Allocator,
    expectations: std.StringHashMap(std.DoublyLinkedList),

    pub fn init(allocator: std.mem.Allocator) MockTableType {
        return MockTableType{
            .allocator = allocator,
            .expectations = std.StringHashMap(std.DoublyLinkedList).init(allocator),
        };
    }

    pub fn expectCall(self: *MockTableType, comptime method_name: [:0]const u8) *Expectation {
        var list = self.expectations.getPtr(method_name) orelse blk: {
            self.expectations.put(method_name, std.DoublyLinkedList{}) catch unreachable;
            break :blk self.expectations.getPtr(method_name) orelse unreachable;
        };
        const expectation = self.allocator.create(Expectation) catch unreachable;
        expectation.* = Expectation{
            ._allocator = self.allocator,
            ._return = null,
            ._node = std.DoublyLinkedList.Node{},
            ._deinit = null,
            ._times = 1,
            ._args_matcher = null,
        };
        _ = list.append(&expectation._node);
        return expectation;
    }
};

pub fn GenerateMockTable(InterfaceType: type, allocator: std.mem.Allocator) *MockTableType {
    var table = allocator.create(MockTableType) catch unreachable;
    table.* = MockTableType.init(allocator);
    inline for (std.meta.fields(InterfaceType.VTable)) |field| {
        table.expectations.put(field.name, std.DoublyLinkedList{}) catch unreachable;
    }
    return table;
}
