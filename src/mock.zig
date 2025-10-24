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
    if (!@hasField(deduce_type(@TypeOf(self)), "_mock")) {
        @compileError("MockVirtualCall called on non-mock object, please add ._mock: interface.GenerateMockTable() to the derived mock struct");
    }

    var expectations = self._mock.expectations.get(method_name) orelse {
        std.debug.print("No expectations found for method: {s}.{s}\n", .{ @typeName(deduce_type(@TypeOf(self))), method_name });
        unreachable;
    };

    if (expectations.len() == 0) {
        std.debug.print("No more expectations left for method: {s}.{s}\n", .{ @typeName(deduce_type(@TypeOf(self))), method_name });
        unreachable;
    }

    const list_node = expectations.popFirst() orelse unreachable;
    var expectation = @as(*Expectation, @fieldParentPtr("_node", list_node));
    defer self._mock.allocator.destroy(expectation);
    if (expectation._return) |r| {
        defer self._mock.allocator.destroy(@as(*return_type, @ptrCast(@alignCast(r))));
        return expectation.getReturnValue(return_type);
    } else {
        std.debug.print("No return value set for method: {s}.{s}\n", .{ @typeName(deduce_type(@TypeOf(self))), method_name });
        unreachable;
    }
}

pub fn MockDestructorCall(self: anytype) void {
    if (!@hasField(deduce_type(@TypeOf(self)), "_mock")) {
        @compileError("MockVirtualCall called on non-mock object, please add ._mock: interface.GenerateMockTable() to the derived mock struct");
    }
    self._mock.expectations.deinit();
}

const Expectation = struct {
    _allocator: std.mem.Allocator,
    _return: ?*anyopaque,
    _node: std.DoublyLinkedList.Node,

    pub fn willReturn(self: *Expectation, value: anytype) void {
        const return_object = self._allocator.create(@TypeOf(value)) catch unreachable;
        return_object.* = value;
        self._return = return_object;
    }

    pub fn getReturnValue(self: *Expectation, return_type: type) return_type {
        std.testing.expect(self._return != null) catch unreachable;
        return @as(*return_type, @ptrCast(@alignCast(self._return.?))).*;
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
