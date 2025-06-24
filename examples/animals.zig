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

fn AnimalInterface(comptime SelfType: type) type {
    return struct {
        pub const Self = SelfType;

        pub fn speak(self: *const Self) void {
            return interface.VirtualCall(self, "speak", .{}, void);
        }

        pub fn describe(self: *const Self) void {
            return interface.VirtualCall(self, "describe", .{}, void);
        }

        pub fn play(self: *const Self, toy: []const u8) void {
            return interface.VirtualCall(self, "play", .{toy}, void);
        }

        pub fn delete(self: *Self, allocator: std.mem.Allocator) void {
            return interface.VirtualCall(self, "delete", .{allocator}, void);
        }
    };
}

const IAnimal = interface.ConstructInterface(AnimalInterface);

const Animal = packed struct {
    pub usingnamespace interface.DeriveFromBase(IAnimal, Animal);

    name: [*:0]const u8,
    age: u32,

    pub fn describe(self: *const Animal) void {
        std.debug.print("{s} is {d} years old.\n", .{ self.name, self.age });
    }
};

const Dog = packed struct {
    pub usingnamespace interface.DeriveFromBase(Animal, Dog);
    base: Animal,
    breed: [*:0]const u8,

    pub fn create(name: [*:0]const u8, age: u32, breed: [*:0]const u8) Dog {
        return Dog{ .base = Animal{
            .name = name,
            .age = age,
        }, .breed = breed };
    }

    pub fn speak(self: *const Dog) void {
        std.debug.print("{s} says: Woof!\n", .{self.base.name});
    }

    pub fn describe(self: *const Dog) void {
        std.debug.print("{s} is {d} years old {s}.\n", .{ self.base.name, self.base.age, self.breed });
    }

    pub fn play(self: *const Dog, toy: []const u8) void {
        std.debug.print("{s} doesn't like: {s}.\n", .{ self.base.name, toy });
    }
};

const Cat = packed struct {
    pub usingnamespace interface.DeriveFromBase(Animal, Cat);
    base: Animal,

    pub fn create(name: [*:0]const u8, age: u32) Cat {
        return Cat{ .base = Animal{
            .name = name,
            .age = age,
        } };
    }

    pub fn speak(self: *const Cat) void {
        std.debug.print("{s} says: Meow!\n", .{self.base.name});
    }

    pub fn play(self: *const Cat, toy: []const u8) void {
        std.debug.print("{s} plays with {s}.\n", .{ self.base.name, toy });
    }
};

pub fn test_animal(animal: IAnimal) void {
    animal.describe();
    animal.speak();
    animal.play("Mouse");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = true,
    }){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var cat = try Cat.create("Garfield", 7).new(allocator);
    defer cat.delete(allocator);
    var dog = try Dog.create("Lassie", 12, "Rough Collie").new(allocator);
    defer dog.delete(allocator);
    test_animal(cat);
    std.debug.print("\n", .{});
    test_animal(dog);
}
