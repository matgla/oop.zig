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

//! The shared reference count under contention.
//!
//! `shared.zig` covers the ordinary lifetime; this covers the property that
//! makes it safe to share an object between two cores at all, which no
//! single-threaded test can observe.

const std = @import("std");

const interface = @import("interface");

const refcount = interface.refcount;

test "refcount counts every acquire and release exactly once under contention" {
    // The failure being tested for: `r.* += 1` is a load, an add and a store.
    // Two contexts can read the same value and write back the same result, so
    // one of the two increments disappears -- which frees a live object. It
    // needs an interrupt between the load and the store on one core, and
    // nothing at all on two.
    var counter: i32 = 0;
    refcount.init(&counter);

    const Hammer = struct {
        fn run(target: *i32, iterations: usize) void {
            for (0..iterations) |_| {
                refcount.acquire(target);
                // Never the last reference: the caller below holds the initial
                // one for the whole test, so `release` must never claim it.
                std.debug.assert(!refcount.release(target));
            }
        }
    };

    const thread_count = 4;
    const iterations = 20_000;
    var threads: [thread_count]std.Thread = undefined;
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, Hammer.run, .{ &counter, iterations });
    }
    for (threads) |thread| thread.join();

    // Back to the single reference the test started with.
    try std.testing.expectEqual(@as(i32, 1), refcount.get(&counter));
    try std.testing.expect(refcount.release(&counter));
}

test "exactly one releaser is told to destroy" {
    // The other half of the same bug. `release` has to fuse the decrement and
    // the "was that the last one" test: read back separately, two contexts
    // dropping the final two references can both observe zero and both run the
    // destructor -- a double free -- or, with the opposite interleaving,
    // neither can and the object leaks.
    const thread_count = 8;

    var counter: i32 = 0;
    refcount.init(&counter);
    for (1..thread_count) |_| refcount.acquire(&counter);
    try std.testing.expectEqual(@as(i32, thread_count), refcount.get(&counter));

    var destroyers = std.atomic.Value(u32).init(0);

    const Dropper = struct {
        fn run(target: *i32, tally: *std.atomic.Value(u32)) void {
            if (refcount.release(target)) {
                _ = tally.fetchAdd(1, .monotonic);
            }
        }
    };

    var threads: [thread_count]std.Thread = undefined;
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, Dropper.run, .{ &counter, &destroyers });
    }
    for (threads) |thread| thread.join();

    try std.testing.expectEqual(@as(u32, 1), destroyers.load(.monotonic));
    try std.testing.expectEqual(@as(i32, 0), refcount.get(&counter));
}

test "a fresh counter is checked for placement when a check is installed" {
    // The kernel installs a check here that refuses counters allocated in
    // PSRAM, where the RP2350's global exclusive monitor does not reach and the
    // exclusives above would silently stop excluding anything. The library has
    // no memory map of its own, so all it can guarantee is that the hook is
    // reached with the right pointer.
    const Probe = struct {
        var seen: ?*const i32 = null;
        var calls: u32 = 0;

        fn check(counter: *const i32) void {
            seen = counter;
            calls += 1;
        }
    };

    Probe.seen = null;
    Probe.calls = 0;
    refcount.placement_check = &Probe.check;
    defer refcount.placement_check = null;

    var counter: i32 = 0;
    refcount.init(&counter);

    try std.testing.expectEqual(@as(u32, 1), Probe.calls);
    try std.testing.expectEqual(@as(?*const i32, &counter), Probe.seen);

    // Not on every acquire -- it is an allocation-time check, and putting it on
    // the hot path would cost a memory-map walk per reference taken.
    refcount.acquire(&counter);
    try std.testing.expectEqual(@as(u32, 1), Probe.calls);
    try std.testing.expect(!refcount.release(&counter));
}

test "a null placement check leaves behaviour unchanged" {
    refcount.placement_check = null;
    var counter: i32 = 0;
    refcount.init(&counter);
    try std.testing.expectEqual(@as(i32, 1), refcount.get(&counter));
    try std.testing.expect(refcount.release(&counter));
}
