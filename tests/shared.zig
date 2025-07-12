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
fn ShapeInterface(comptime SelfType: type) type {
    return struct {
        pub const Self = SelfType;

        pub fn area(self: *const Self) u32 {
            return interface.VirtualCall(self, "area", .{}, u32);
        }

        pub fn set_size(self: *Self, new_size: u32) void {
            return interface.VirtualCall(self, "set_size", .{new_size}, void);
        }

        // do not forget about virtual destructor
        pub fn delete(self: *Self) void {
            interface.VirtualCall(self, "delete", .{}, void);
            interface.DestructorCall(self);
        }
    };
}

// IShape is struct which is really an interface type
const IShape = interface.ConstructCountingInterface(ShapeInterface);

// Let's derive Triangle and Rectangle from IShape
// Child object must be packed to enforce defined memory layout
const Triangle = struct {
    // Let's derive from IShape, this call constructs a vtable
    pub usingnamespace interface.DeriveFromBase(IShape, Triangle);
    height: u32,
    base: u32,
    size: u32,

    pub fn area(self: *const Triangle) u32 {
        return self.height * self.base / 2 * self.size;
    }

    pub fn set_size(self: *Triangle, new_size: u32) void {
        self.size = new_size;
    }

    pub fn delete(self: *Triangle) void {
        _ = self;
    }
};

test "shared objects should be correctly deleted" {
    const allocator = std.testing.allocator;
    var shape1: IShape = try (Triangle{ .base = 10, .height = 3, .size = 2 }).new(allocator);
    defer shape1.delete();
    var shape2 = shape1.share();
    defer shape2.delete();
    var shape3 = shape1.share();
    defer shape3.delete();
}
