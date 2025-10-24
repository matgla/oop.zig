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

pub const DeriveFromBase = @import("interface.zig").DeriveFromBase;
pub const ConstructInterface = @import("interface.zig").ConstructInterface;
pub const VirtualCall = @import("interface.zig").VirtualCall;
pub const DestructorCall = @import("interface.zig").DestructorCall;

pub const ConstructCountingInterface = @import("interface.zig").ConstructCountingInterface;
pub const CountingInterfaceVirtualCall = @import("interface.zig").CountingInterfaceVirtualCall;
pub const CountingInterfaceDestructorCall = @import("interface.zig").CountingInterfaceDestructorCall;

pub const base = @import("interface.zig").GetBase;

pub const MockVirtualCall = @import("mock.zig").MockVirtualCall;
pub const MockDestructorCall = @import("mock.zig").MockDestructorCall;
pub const GenerateMockTable = @import("mock.zig").GenerateMockTable;
pub const MockTableType = @import("mock.zig").MockTableType;
