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

const IAnimal = interface.ConstructInterface(struct {
    pub const Self = @This();

    pub fn make_sound(self: *const Self) []const u8 {
        return interface.VirtualCall(self, "make_sound", .{}, []const u8);
    }
});

const Dog = interface.DeriveFromBase(IAnimal, struct {
    pub const Self = @This();

    pub fn make_sound(self: *const Self) []const u8 {
        _ = self;
        return "Woof!";
    }
});

const Cat = interface.DeriveFromBase(IAnimal, packed struct {
    pub const Self = @This();

    pub fn make_sound(self: *const Self) []const u8 {
        _ = self;
        return "Meow!";
    }
});

fn make_sound(animal: IAnimal) []const u8 {
    return animal.interface.make_sound();
}

test "simple interface" {
    var cat: Cat = Cat.init(.{});
    var dog: Dog = Dog.init(.{});

    try std.testing.expectEqualStrings("Woof!", make_sound(dog.interface.create()));
    try std.testing.expectEqualStrings("Meow!", make_sound(cat.interface.create()));
}
