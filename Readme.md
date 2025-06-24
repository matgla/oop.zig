# About 

Interface.zig is object oriented programming library for Zig language.

Primary goal is to reach C++-like polimorphism into Zig ecosystem.

# Design decisions

Below design decision are worth to be aware of:

1) Virtual functions can be declared only inside interface and not inside base / child structs. 

2) Interface contains pure virtual functions ( = 0 from C++)

3) Methods can be overided in childs, so base classes are possible to be implemented

4) Fields can't be overidden 

5) Base class must be added as first field by now, trying to find solution to automatize this 

6) Structs must be extern to have defined memory layout (for zig < 0.15.0)

7) new/delete is automatically added to interface implementations to create owning interface instance

8) Interface uses fat pointer technique, so owner of VTable and pointer to object is interface, this may be changed if I find reason to move it into child structs

# How to use it 

TODO: how to add zig package

Two branches are currently supported: 
- main which has support for nigtly build
- zig 14.0 dedicated branch 

# Example 

Let's write below C++ example:

``` cpp
#include <iostream>
#include <memory>

// Interface class
class IAnimal {
public:
    virtual void speak() const = 0;
    virtual void describe() const = 0;
    virtual void play(const std::string& toy) const = 0;
    virtual ~IAnimal() = default;
};

// Base class implementing the interface
class Animal : public IAnimal {
protected:
    std::string name;
    int age;

public:
    Animal(const std::string& name, int age) : name(name), age(age) {}
    void describe() const override {
        std::cout << name << " is " << age << " years old." << std::endl;
    }
};

// Derived class 1
class Dog : public Animal {
    std::string breed;

public:
    Dog(const std::string& name, int age, const std::string& breed)
        : Animal(name, age), breed(breed) {}

    void speak() const override {
        std::cout << name << " says: Woof!" << std::endl;
    }

    void describe() const override {
        std::cout << name << " is " << age << " years old " << breed << "." << std::endl;
    }

    void play(const std::string& toy) const override {
        std::cout << name << " doesn't like: " << toy << "." << std::endl;
    }
};

// Derived class 2
class Cat : public Animal {
public:
    Cat(const std::string& name, int age)
        : Animal(name, age) {}

    void speak() const override {
        std::cout << name << " says: Meow!" << std::endl;
    }

    void play(const std::string& toy) const override {
        std::cout << name << " plays with " << toy << "." << std::endl;
    }
};

void test_animal(IAnimal *animal) {
    animal->describe();
    animal->speak();
    animal->play("Mouse");
}

int main() {
    std::unique_ptr<IAnimal> cat = std::make_unique<Cat>("Garfield", 7);
    std::unique_ptr<IAnimal> dog = std::make_unique<Dog>("Lassie", 12, "Rough Collie");
    

    test_animal(cat.get());
    std::cout << std::endl;
    test_animal(dog.get());
}
```

``` zig
// examples/animals.zig

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

const Animal = extern struct {
    pub usingnamespace interface.DeriveFromBase(IAnimal, Animal);

    name: [*:0]const u8,
    age: u32,

    pub fn describe(self: *const Animal) void {
        std.debug.print("{s} is {d} years old.\n", .{ self.name, self.age });
    }
};

const Dog = extern struct {
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

const Cat = extern struct {
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

```
