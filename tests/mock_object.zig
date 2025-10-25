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

const ShapeMock = interface.mock.MockInterface(IShape);

test "interface can be mocked for tests" {
    var mock = try ShapeMock.create(std.testing.allocator);
    defer mock.delete();
    var obj = mock.get_interface();
    defer obj.interface.delete();

    _ = mock
        .expectCall("area")
        .willReturn(@as(u32, 10))
        .times(3);

    _ = mock
        .expectCall("area")
        .willReturn(@as(u32, 15));

    try std.testing.expectEqual(10, obj.interface.area());
    try std.testing.expectEqual(10, obj.interface.area());
    try std.testing.expectEqual(10, obj.interface.area());

    try std.testing.expectEqual(15, obj.interface.area());

    _ = mock
        .expectCall("set_size")
        .withArgs(.{interface.mock.any{}});

    _ = mock
        .expectCall("set_size")
        .withArgs(.{@as(u32, 101)});

    // best match selection is used here
    obj.interface.set_size(101);
    obj.interface.set_size(102);
}

test "mock can be called any times" {
    const any = interface.mock.any{};
    var mock = try ShapeMock.create(std.testing.allocator);
    defer mock.delete();
    var obj = mock.get_interface();
    defer obj.interface.delete();

    _ = mock
        .expectCall("area")
        .willReturn(@as(u32, 10))
        .times(any);

    try std.testing.expectEqual(10, obj.interface.area());
    try std.testing.expectEqual(10, obj.interface.area());
    try std.testing.expectEqual(10, obj.interface.area());
    try std.testing.expectEqual(10, obj.interface.area());
    try std.testing.expectEqual(10, obj.interface.area());
}

test "enforce sequence for tests" {
    const any = interface.mock.any{};
    var sequence = interface.mock.Sequence.init(std.testing.allocator);
    var mock = try ShapeMock.create(std.testing.allocator);
    defer mock.delete();
    var obj = mock.get_interface();
    defer obj.interface.delete();

    _ = mock
        .expectCall("area")
        .willReturn(@as(u32, 10))
        .times(3)
        .inSequence(&sequence);

    _ = mock
        .expectCall("set_size")
        .withArgs(.{@as(u32, 101)});

    _ = mock
        .expectCall("set_size")
        .withArgs(.{any})
        .inSequence(&sequence);

    _ = mock
        .expectCall("area")
        .willReturn(@as(u32, 15))
        .inSequence(&sequence);

    try std.testing.expectEqual(10, obj.interface.area());

    obj.interface.set_size(101);
    try std.testing.expectEqual(10, obj.interface.area());
    try std.testing.expectEqual(10, obj.interface.area());

    obj.interface.set_size(102);

    try std.testing.expectEqual(15, obj.interface.area());
}

test "mock can invoke callback function" {
    var mock = try ShapeMock.create(std.testing.allocator);
    defer mock.delete();
    var obj = mock.get_interface();
    defer obj.interface.delete();

    // // Test callback that computes the return value
    // // Use std.meta.Tuple with empty array to get the correct type
    const areaCallback = struct {
        fn call(args: std.meta.Tuple(&[_]type{})) anyerror!u32 {
            _ = args;
            return 123;
        }
    }.call;

    _ = mock
        .expectCall("area")
        .invoke(areaCallback);

    try std.testing.expectEqual(123, obj.interface.area());

    // Test callback with arguments
    const setSizeCallback = struct {
        fn call(args: std.meta.Tuple(&[_]type{u32})) anyerror!void {
            try std.testing.expectEqual(@as(u32, 999), args[0]);
        }
    }.call;

    _ = mock
        .expectCall("set_size")
        .invoke(setSizeCallback);

    obj.interface.set_size(999);
}

// test "mock invoke can be combined with withArgs" {
//     var mock = try ShapeMock.create(std.testing.allocator);
//     defer mock.delete();
//     var obj = mock.get_interface();
//     defer obj.interface.delete();

//     const callback = struct {
//         fn call(args: struct { u32 }) void {
//             // Verify we got the expected argument
//             std.testing.expectEqual(@as(u32, 42), args[0]) catch unreachable;
//         }
//     }.call;

//     _ = mock
//         .expectCall("set_size")
//         .withArgs(.{@as(u32, 42)})
//         .invoke(callback);

//     obj.interface.set_size(42);
// }
