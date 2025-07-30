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

    pub fn speak(self: *const Self) void {
        return interface.VirtualCall(self, "speak", .{}, void);
    }

    pub fn describe(self: *const Self) void {
        return interface.VirtualCall(self, "describe", .{}, void);
    }

    pub fn play(self: *const Self, toy: []const u8) void {
        return interface.VirtualCall(self, "play", .{toy}, void);
    }

    pub fn delete(self: *Self) void {
        interface.DestructorCall(self);
    }
});

const Animal = interface.DeriveFromBase(IAnimal, struct {
    const Self = @This();

    name: []const u8,
    age: u32,

    pub fn describe(self: *const Self) void {
        std.debug.print("{s} is {d} years old.\n", .{ self.name, self.age });
    }
});

const Dog = interface.DeriveFromBase(Animal, struct {
    const Self = @This();

    base: Animal,
    breed: []const u8,

    pub fn create(name: []const u8, age: u32, breed: []const u8) Dog {
        return Dog.init(.{ .base = Animal.init(.{
            .name = name,
            .age = age,
        }), .breed = breed });
    }

    pub fn speak(self: *const Self) void {
        std.debug.print("{s} says: Woof!\n", .{interface.base(self).name});
    }

    pub fn describe(self: *const Self) void {
        std.debug.print("{s} is {d} years old {s}.\n", .{ interface.base(self).name, interface.base(self).age, self.breed });
    }

    pub fn play(self: *const Self, toy: []const u8) void {
        std.debug.print("{s} doesn't like: {s}.\n", .{ interface.base(self).name, toy });
    }

    pub fn delete(self: *Self) void {
        _ = self;
    }
});

const Cat = interface.DeriveFromBase(Animal, struct {
    const Self = @This();
    base: Animal,

    pub fn create(name: []const u8, age: u32) Cat {
        return Cat.init(.{ .base = Animal.init(.{
            .name = name,
            .age = age,
        }) });
    }

    pub fn speak(self: *const Self) void {
        std.debug.print("{s} says: Meow!\n", .{interface.base(self).name});
    }

    pub fn play(self: *const Self, toy: []const u8) void {
        std.debug.print("{s} plays with {s}.\n", .{ interface.base(self).name, toy });
    }

    pub fn delete(self: *Self) void {
        _ = self;
    }
});

pub fn test_animal(animal: IAnimal) void {
    animal.interface.describe();
    animal.interface.speak();
    animal.interface.play("Mouse");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = true,
    }){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var cat = try Cat.InstanceType.create("Garfield", 7).interface.new(allocator);

    defer cat.interface.delete();
    var dog = try Dog.InstanceType.create("Lassie", 12, "Rough Collie").interface.new(allocator);
    defer dog.interface.delete();
    test_animal(cat);
    std.debug.print("\n", .{});
    test_animal(dog);
}
