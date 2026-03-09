const std = @import("std");
const assert = std.debug.assert;

/// Called when memory growth is necessary. Returns a capacity larger than
/// minimum that grows super-linearly.
/// Copied from std/array_list.zig
fn growCapacity(current: usize, minimum: usize) usize {
    var new = current;
    while (true) {
        new +|= new / 2 + @bitSizeOf(usize);
        if (new >= minimum)
            return new;
    }
}

pub fn SparseSlotMap(comptime Value: type) type {
    return struct {
        const Map = @This();

        pub const Key = u32;

        free_slots: std.DynamicBitSetUnmanaged = .{},
        values: [*]Value = undefined,

        pub fn capacity(sm: *Map) Key {
            return @intCast(sm.free_slots.bit_length);
        }

        pub fn numFree(sm: *Map) Key {
            return @intCast(sm.free_slots.count());
        }

        pub fn numAllocated(sm: *Map) Key {
            return sm.capacity() - sm.numFree();
        }

        pub fn isAllocated(sm: *Map, key: Key) bool {
            return key < sm.capacity() and !sm.free_slots.isSet(key);
        }

        pub fn get(sm: *Map, key: Key) *Value {
            assert(sm.isAllocated(key));
            return &sm.values[key];
        }

        pub fn release(sm: *Map, key: Key) void {
            assert(sm.isAllocated(key));
            sm.values[key] = undefined;
            sm.free_slots.set(key);
        }

        pub fn alloc(sm: *Map, allocator: std.mem.Allocator) !Key {
            if (sm.free_slots.toggleFirstSet()) |idx| {
                return @intCast(idx);
            }
            try sm.ensureTotalCapacity(allocator, sm.capacity() + 1);
            return sm.allocAssumeCapacity();
        }

        pub fn allocAssumeCapacity(sm: *Map) Key {
            return @intCast(sm.free_slots.toggleFirstSet().?);
        }

        pub fn ensureAdditionalCapacity(sm: *Map, allocator: std.mem.Allocator, count: usize) !void {
            const available = sm.free_slots.count();
            if (available >= count) return;
            try sm.ensureTotalCapacity(allocator, sm.free_slots.bit_length + (count - available));
        }

        pub fn ensureTotalCapacity(sm: *Map, allocator: std.mem.Allocator, count: usize) !void {
            if (count <= sm.free_slots.bit_length) return;
            const granularity = @bitSizeOf(std.DynamicBitSetUnmanaged.MaskInt);
            const orig_len = sm.free_slots.bit_length;
            const unaligned_new_len = growCapacity(orig_len, count);
            const final_len = std.mem.alignForward(usize, unaligned_new_len, granularity);

            // Need to resize multiple allocations atomically, as we only track one size
            if (allocator.resize(sm.values[0..orig_len], final_len)) {
                // Sizes of values and the bit set should match.
                // This could be fixed by grouping everything together into one allocation.
                errdefer if (!allocator.resize(sm.values[0..final_len], orig_len))
                    @panic("SparseSlotMap is in an irrecoverable invalid state due to allocator resize being irreversible!");

                try sm.free_slots.resize(allocator, final_len, true);
            } else {
                const new_values = try allocator.alloc(Value, final_len);
                errdefer allocator.free(new_values);

                try sm.free_slots.resize(allocator, final_len, true);

                @memcpy(new_values[0..orig_len], sm.values);

                allocator.free(sm.values[0..orig_len]);
                sm.values = new_values.ptr;
            }
        }

        pub fn deinit(sm: *Map, allocator: std.mem.Allocator) void {
            allocator.free(sm.values[0..sm.free_slots.bit_length]);
            sm.free_slots.deinit(allocator);
        }

        pub fn clear(sm: *Map, allocator: std.mem.Allocator) void {
            sm.deinit(allocator);
            sm.* = .{};
        }

        pub fn clearRetainingCapacity(sm: *Map) void {
            for (sm.values[0..sm.free_slots.bit_length]) |*elem| {
                elem.* = undefined;
            }
            sm.free_slots.setAll();
        }

        pub const Direction = std.bit_set.IteratorOptions.Direction;
        pub fn Iterator(comptime direction: Direction) type {
            return struct {
                values: [*]Value,
                bit_iter: std.DynamicBitSetUnmanaged.Iterator(.{ .direction = direction, .kind = .unset }),

                pub fn init(sm: *Map) @This() {
                    return .{ .values = sm.values, .bit_iter = sm.free_slots.iterator(.{ .direction = direction, .kind = .unset }) };
                }

                pub fn nextKey(iter: *@This()) ?Key {
                    if (iter.bit_iter.next()) |idx| {
                        return @intCast(idx);
                    }
                    return null;
                }

                pub fn nextValue(iter: *@This()) ?*Value {
                    if (iter.bit_iter.next()) |idx| {
                        return &iter.values[idx];
                    }
                    return null;
                }
            };
        }
        pub fn iterator(sm: *@This(), comptime direction: Direction) Iterator(direction) {
            return .init(sm);
        }
    };
}

test "SparseSlotMap" {
    const allocator = std.testing.allocator;
    var map: SparseSlotMap(u8) = .{};

    const k0 = try map.alloc(allocator);
    map.get(k0).* = 100;
    try std.testing.expectEqual(0, k0);
    const k1 = try map.alloc(allocator);
    map.get(k1).* = 101;
    try std.testing.expectEqual(1, k1);
    const k2 = try map.alloc(allocator);
    map.get(k2).* = 102;
    try std.testing.expectEqual(2, k2);

    try std.testing.expectEqual(3, map.numAllocated());

    map.release(k1);

    try std.testing.expectEqual(2, map.numAllocated());
    try std.testing.expectEqual(100, map.get(k0).*);
    try std.testing.expectEqual(102, map.get(k2).*);

    var it = map.iterator(.forward);
    var total: usize = 0;
    while (it.nextKey()) |key| total += map.get(key).*;
    try std.testing.expectEqual(202, total);

    it = map.iterator(.forward);
    total = 0;
    while (it.nextValue()) |val| total += val.*;
    try std.testing.expectEqual(202, total);

    try std.testing.expectEqual(1, map.allocAssumeCapacity());
    try std.testing.expectEqual(3, try map.alloc(allocator));

    map.clearRetainingCapacity();
    map.clear(allocator);
    map.deinit(allocator);
}

const DenseSlotMapKeyConfig = struct {
    key_bits: comptime_int = 32,
    // Set uniq to `opaque{}` explicitly to force the generated
    // Key and Value types to be unique for your call site
    uniq: type = opaque {},
    // Maybe someday xD
    // generation_bits: comptime_int = 0,
};

/// The DenseSlotMap is a list-like container with the following properties:
///  - Each value is assiged a stable "key" which can always be used to reference it.
///  - Values are stored in a dense array which can be iterated quickly
///  - The corresponding keys can also be iterated in parallel
pub fn DenseSlotMap(comptime Value: type, key_config: DenseSlotMapKeyConfig) type {
    const l_uniq = key_config.uniq;
    const l_SizeInt = @Type(.{ .int = .{ .bits = key_config.key_bits, .signedness = .unsigned } });
    const l_Key = enum(l_SizeInt) {
        _,
        const _uniq = l_uniq;
    };
    return struct {
        const Map = @This();
        pub const SizeInt = l_SizeInt;
        pub const Index = l_SizeInt;
        pub const Key = l_Key;

        const index_max = ~@as(SizeInt, 0);

        /// Allocated storage
        storage: std.MultiArrayList(struct {
            /// Dense array of values
            value: Value,
            /// Reverse mapping from values to keys.
            /// After len, contains a dense list of free keys.
            key: Key,
            /// Sparse mapping from keys to values. This is initialized
            /// even for unallocated keys, pointing to the key in the free list.
            index: Index,
        }) = .{},
        /// The number of currently allocated items
        len: SizeInt = 0,

        /// The total number of items which can be simultaneously allocated
        /// without allocating new backing memory
        pub fn capacity(sm: *Map) SizeInt {
            return @intCast(sm.storage.capacity);
        }

        /// The number of available slots which could be allocated
        pub fn numFree(sm: *Map) SizeInt {
            return sm.capacity() - sm.numAllocated();
        }

        /// The number of slots which have been allocated to the user
        pub fn numAllocated(sm: *Map) SizeInt {
            return sm.len;
        }

        /// DenseSlotMap can allocate a key again immediately after it is freed,
        /// so use of this function for logic may lead to a use-after-free.
        pub fn assertAllocatedKey(sm: *Map, key: Key) void {
            if (std.debug.runtime_safety) {
                const key_int = @intFromEnum(key);
                assert(key_int < sm.storage.len);
                const index = sm.storage.items(.index)[key_int];
                assert(sm.storage.items(.key)[index] == key); // Internal consistency: should always be true
                assert(index < sm.len); // Allocated items are before .len
            }
        }

        pub fn assertAllocatedIndex(sm: *Map, index: Index) void {
            if (std.debug.runtime_safety) {
                assert(index < sm.len); // Allocated items are before .len
                const key = sm.storage.items(.key)[index];
                const key_int = @intFromEnum(key);
                assert(key_int < sm.storage.len);
                assert(sm.storage.items(.index)[key_int] == index); // Internal consistency: should always be true
            }
        }

        pub fn getIndex(sm: *Map, key: Key) Index {
            sm.assertAllocatedKey(key);
            return sm.storage.items(.index)[@intFromEnum(key)];
        }

        /// Find the value associated with a Key
        pub fn get(sm: *Map, key: Key) *Value {
            sm.assertAllocatedKey(key);
            const slice = sm.storage.slice();
            const index = slice.items(.index)[@intFromEnum(key)];
            return &slice.items(.value)[index];
        }

        pub fn getAt(sm: *Map, index: Index) *Value {
            sm.assertAllocatedIndex(index);
            return &sm.storage.items(.value)[index];
        }

        pub fn getKeyAt(sm: *Map, index: Index) Key {
            sm.assertAllocatedIndex(index);
            return sm.storage.items(.key)[index];
        }

        /// Release the value associated with a Key,
        /// allowing the key and slot to be reused.
        /// This invalidates any pointers or slices to
        /// existing values, including from the bulkAlloc functions.
        pub fn release(sm: *Map, key: Key) void {
            sm.assertAllocatedKey(key);
            const key_int = @intFromEnum(key);
            const slice = sm.storage.slice();
            const index = slice.items(.index)[key_int];
            assert(slice.items(.key)[index] == key);
            sm.len -= 1;
            const last_idx = sm.len;
            if (index != last_idx) {
                const moved_key = slice.items(.key)[last_idx];
                slice.items(.key)[last_idx] = key;
                slice.items(.index)[key_int] = last_idx;
                slice.items(.key)[index] = moved_key;
                slice.items(.index)[@intFromEnum(moved_key)] = index;
                slice.items(.value)[index] = slice.items(.value)[last_idx];
            }
            slice.items(.value)[last_idx] = undefined;
        }

        /// Swap the indexes of two allocated items.
        /// Keys remain stable. This is useful for
        /// partitioning the allocated array into
        /// two or more segments for more efficient
        /// iteration.
        pub fn swapIndexes(sm: *Map, a_idx: Index, b_idx: Index) void {
            sm.assertAllocatedIndex(a_idx);
            if (a_idx != b_idx) {
                sm.assertAllocatedIndex(b_idx);
                const slice = sm.storage.slice();
                const a_key = slice.items(.key)[a_idx];
                const b_key = slice.items(.key)[b_idx];
                std.mem.swap(Value, &slice.items(.value)[a_idx], &slice.items(.value)[b_idx]);
                slice.items(.key)[a_idx] = b_key;
                slice.items(.key)[b_idx] = a_key;
                slice.items(.index)[@intFromEnum(a_key)] = b_idx;
                slice.items(.index)[@intFromEnum(b_key)] = a_idx;
            }
        }

        const Alloc = struct { Key, *Value };

        /// Allocates a value and a stable key. Allocates
        /// more capacity if needed.
        pub fn alloc(sm: *Map, allocator: std.mem.Allocator) !Alloc {
            try sm.ensureAdditionalCapacity(allocator, 1);
            return sm.allocAssumeCapacity();
        }

        /// Allocates a value and a stable key, assuming that the
        /// necessary capacity already exists.
        pub fn allocAssumeCapacity(sm: *Map) Alloc {
            const slice = sm.storage.slice();
            const index = sm.len;
            sm.len += 1;
            return .{ slice.items(.key)[index], &slice.items(.value)[index] };
        }

        const BulkAlloc = struct { []const Key, []Value };

        /// Allocates a large number of keys at once. O(1) if the capacity already exists.
        /// Allocates more capacity if needed.
        /// The returned slices are valid until a key is deleted from the DenseSlotMap or the capacity changes.
        pub fn bulkAlloc(sm: *Map, allocator: std.mem.Allocator, num: usize) !BulkAlloc {
            try sm.ensureAdditionalCapacity(allocator, num);
            return sm.bulkAllocAssumeCapacity(num);
        }

        /// Allocates a large number of keys at once. O(1).
        /// The returned slices are valid until a key is deleted from the DenseSlotMap or the capacity changes.
        pub fn bulkAllocAssumeCapacity(sm: *Map, num: usize) BulkAlloc {
            assert(num <= sm.storage.len - sm.len);
            const slice = sm.storage.slice();
            const base_index = sm.len;
            sm.len += @intCast(num);
            const new_keys = slice.items(.key)[base_index..][0..num];
            const new_values = slice.items(.value)[base_index..][0..num];
            return .{ new_keys, new_values };
        }

        /// Resizes the capacity so that at least `count` more values can be allocated.
        pub fn ensureAdditionalCapacity(sm: *Map, allocator: std.mem.Allocator, count: usize) !void {
            // Check that the new size doesn't overflow our key type
            assert(@addWithOverflow(@as(SizeInt, @intCast(count)), @as(SizeInt, @intCast(sm.len)))[1] == 0);
            if (sm.len + count <= sm.storage.len) return;
            try sm.ensureTotalCapacity(allocator, sm.len + count);
        }

        /// Resizes the backing memory so that at least `count` values can be simultaneously allocated.
        pub fn ensureTotalCapacity(sm: *Map, allocator: std.mem.Allocator, count: usize) !void {
            assert(count <= @as(usize, index_max));
            if (count <= sm.storage.len) return;
            try sm.storage.ensureTotalCapacity(allocator, count);
            const orig_len = sm.storage.len;
            const new_len = @min(sm.storage.capacity, index_max);
            sm.storage.len = new_len;
            const slice = sm.storage.slice();
            const all_keys = slice.items(.key);
            const indices = slice.items(.index);
            for (orig_len..new_len) |i| {
                all_keys[i] = @enumFromInt(@as(SizeInt, @intCast(i)));
                indices[i] = @intCast(i);
            }
        }

        /// Releases all keys and backing memory, leaving the map in an undefined state
        pub fn deinit(sm: *Map, allocator: std.mem.Allocator) void {
            sm.storage.deinit(allocator);
        }

        /// Releases all keys and backing memory, and restores the map to an empty state
        pub fn clear(sm: *Map, allocator: std.mem.Allocator) void {
            sm.deinit(allocator);
            sm.* = .{};
        }

        /// Releases all keys, but keeps backing memory for fast reuse.
        pub fn clearRetainingCapacity(sm: *Map) void {
            const slice = sm.storage.slice();
            for (slice.items(.value)) |*value| {
                value.* = undefined;
            }
            sm.len = 0;
        }

        // List of allocated keys. Note that if iterating, you should
        // iterate items() in parallel rather than looking up each key.
        pub fn keys(sm: *Map) []Key {
            return sm.storage.items(.key)[0..sm.len];
        }

        // List of allocated values.
        pub fn values(sm: *Map) []Value {
            return sm.storage.items(.value)[0..sm.len];
        }
    };
}

const TestMap = DenseSlotMap(u8, .{});

fn testDenseSlotMap(map: *TestMap, key_order: [5]u32) !void {
    const allocator = std.testing.allocator;

    const k0, const e0 = try map.alloc(allocator);
    e0.* = 100;
    try std.testing.expectEqual(key_order[0], @intFromEnum(k0));
    const k1, const e1 = try map.alloc(allocator);
    e1.* = 101;
    try std.testing.expectEqual(key_order[1], @intFromEnum(k1));
    const k2, const e2 = try map.alloc(allocator);
    e2.* = 102;
    try std.testing.expectEqual(key_order[2], @intFromEnum(k2));

    try std.testing.expectEqual(3, map.len);

    map.release(k1);

    try std.testing.expectEqual(2, map.len);
    try std.testing.expectEqual(100, map.get(k0).*);
    try std.testing.expectEqual(102, map.get(k2).*);

    var total: usize = 0;
    for (map.values()) |item| total += item;
    try std.testing.expectEqual(202, total);

    const bulk_keys, const bulk_elems = try map.bulkAlloc(allocator, 3);
    try std.testing.expectEqual(5, map.len);
    for (bulk_elems, 0..) |*elem, i| {
        elem.* = @intCast(103 + i);
    }
    try std.testing.expectEqual(bulk_keys.ptr, map.keys()[2..].ptr);
    try std.testing.expectEqual(key_order[1], @intFromEnum(bulk_keys[0]));
    try std.testing.expectEqual(key_order[3], @intFromEnum(bulk_keys[1]));
    try std.testing.expectEqual(key_order[4], @intFromEnum(bulk_keys[2]));

    total = 0;
    for (map.values()) |item| total += item;
    try std.testing.expectEqual(514, total);
}

test "DenseSlotMap" {
    var map: TestMap = .{};
    try testDenseSlotMap(&map, .{ 0, 1, 2, 3, 4 });
    map.clearRetainingCapacity();
    try testDenseSlotMap(&map, .{ 0, 2, 1, 3, 4 });
    map.clear(std.testing.allocator);
    try testDenseSlotMap(&map, .{ 0, 1, 2, 3, 4 });
    map.deinit(std.testing.allocator);
}
