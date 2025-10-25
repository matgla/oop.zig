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

const interface = @import("interface");

// Constructs an interface for Shape objects
// all methods are pure virtual, so they must be implemented in the derived types
// SelfType is type of InterfaceHolder struct (in c++ it would be a class with pure virtual methods)
const IShape = interface.ConstructCountingInterface(struct {
    pub const Self = @This();

    pub fn area(self: *const Self) u32 {
        return interface.CountingInterfaceVirtualCall(self, "area", .{}, u32);
    }

    pub fn set_size(self: *Self, new_size: u32) void {
        return interface.CountingInterfaceVirtualCall(self, "set_size", .{new_size}, void);
    }

    pub fn allocate_some(self: *Self) void {
        return interface.CountingInterfaceVirtualCall(self, "allocate_some", .{}, void);
    }

    // do not forget about virtual destructor
    pub fn delete(self: *Self) void {
        interface.CountingInterfaceDestructorCall(self);
    }
});

const MockShape = interface.DeriveFromBase(IShape, struct {
    const Self = @This();
    mock: *interface.MockTableType,

    pub fn create() MockShape {
        return MockShape.init(.{
            .mock = interface.GenerateMockTable(IShape, std.testing.allocator),
        });
    }

    pub fn area(self: *const Self) u32 {
        return interface.MockVirtualCall(self, "area", .{}, u32);
    }

    pub fn set_size(self: *Self, new_size: u32) void {
        return interface.MockVirtualCall(self, "set_size", .{new_size}, void);
    }

    pub fn allocate_some(self: *Self) void {
        return interface.MockVirtualCall(self, "allocate_some", .{}, void);
    }

    pub fn delete(self: *Self) void {
        interface.MockDestructorCall(self);
    }
});

test "interface can be mocked for tests" {
    var mock = MockShape.InstanceType.create();
    var obj = try mock.interface.new(std.testing.allocator);
    defer obj.interface.delete();

    _ = mock.data().mock
        .expectCall("area")
        .willReturn(@as(i32, 10))
        .times(3);

    _ = mock.data().mock
        .expectCall("area")
        .willReturn(@as(i32, 15));

    try std.testing.expectEqual(10, obj.interface.area());
    try std.testing.expectEqual(10, obj.interface.area());
    try std.testing.expectEqual(10, obj.interface.area());

    try std.testing.expectEqual(15, obj.interface.area());

    _ = mock.data().mock
        .expectCall("set_size")
        .withArgs(.{@as(u32, 150)});

    obj.interface.set_size(150);
}
