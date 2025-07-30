# About 

Interface.zig is object oriented programming library for Zig language.

Primary goal is to reach C++-like polimorphism into Zig ecosystem.

# Design decisions

Below design decision are worth to be aware of:

1) Virtual functions can be declared only inside interface and not inside base / child structs. 
2) Interface contains pure virtual functions ( = 0 from C++). It's verified at comptime when .interface() is called
3) Methods can be overridden in childs, so base classes are possible to be implemented
4) Fields can't be overidden except of 'base' field
5) Base class must be added as first field by now, trying to find solution to automatize this 
6) new/delete is automatically added to interface implementations to create owning interface instance
7) Interface uses fat pointer technique, so owner of VTable and pointer to object is interface, this may be changed if I find reason to move it into child structs

# How to use it 

Firstly add dependency to your `build.zig.zon`
`zig fetch --save=modules/oop git+https://github.com/matgla/oop.zig/#HEAD`

Then import module in build.zig. 
For example:
```
    const oop = b.dependency("modules/oop", .{});
    tests.root_module.addImport("interface", oop.module("interface"));
```

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
        interface.VirtualCall(self, "delete", .{}, void);
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

```

# Zig usingnamespace removal

Due to removal of using namespace feature all namespaces are named in current version of framework. 
To access interface(vtable) functions use `.interface` on object constructed from ConstructInterface. 

To access base object there is base function exported, example usage: `interface.base(self).name`.

If access to object type is needed then use .InstanceType. 

For creating interface object use `.interface` followed by `.new` or `.create`. 

# Destruction of objects 

`delete` member field is reserved for deinitalization purposes, if your code needs to be deinitialized then add `delete` as virtual method and call `delete`.

`delete` may be called by framework when `DestructorCall` is executed.