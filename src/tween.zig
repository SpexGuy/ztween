const std = @import("std");
const util = @import("util.zig");
const maps = @import("maps.zig");

const EnumLiteral = @Type(.enum_literal);
pub const Any = util.Any;
pub const nestedOffsetOf = util.nestedOffsetOf;

// ScalarTweenTypes can match any object where the layout of data matches an array of the scalar.
// This includes vectors and structs where all fields are of the target type. For example, the f32 type can
// match all of the following:
// [3]f32
// @Vector(3, f32)
// struct { a: f32, b: f32, c: f32 }
// struct { arr: [2]f32, extra: f32 }
// extern union { vals: [3]f32, names: extern struct { x: f32, y: f32, z: f32 } }
pub fn ScalarTweenType(ScalarType: type, config: BaseConfiguration) type {
    return struct {
        pub fn compatibleWithType(comptime T: type) ?usize {
            const scalar_info = util.deduceScalarTypeInfo(T) orelse return null;
            if (scalar_info.ScalarType != ScalarType) return null;
            return scalar_info.first_offset;
        }
        pub fn getLen(comptime T: type, field_ptr: *const anyopaque) usize {
            _ = field_ptr;
            const scalar_info = util.deduceScalarTypeInfo(T) orelse @compileError("getLen called with incompatible type");
            if (scalar_info.ScalarType != ScalarType) @compileError("getLen called with incompatible type");
            return scalar_info.num_items;
        }
        pub fn getValues(field_ptr: *const anyopaque, out_values: []config.ValueFloat) void {
            const obj_values: [*]const ScalarType = @ptrCast(@alignCast(field_ptr));
            for (0..out_values.len) |i| {
                out_values[i] = util.floatCast(config.ValueFloat, obj_values[i]);
            }
        }
        pub fn setValues(field_ptr: *anyopaque, new_values: []const config.ValueFloat) void {
            const obj_values: [*]ScalarType = @ptrCast(@alignCast(field_ptr));
            for (0..new_values.len) |i| {
                obj_values[i] = util.castFromFloat(ScalarType, new_values[i]);
            }
        }
    };
}

// StructTweenType generates code to write fields of varied types or with varied offsets.
// Note that many structs can be handled by ScalarTweenType. But if the struct is bit-packed
// or has fields of different types (like f32 rgb and u8 alpha, for example, or rgb10a2),
// this can make that easily tweenable.
pub fn StructTweenType(StructType: type, config: BaseConfiguration, fields: []const EnumLiteral) type {
    return struct {
        pub fn compatibleWithType(comptime T: type) ?usize {
            return if (T == StructType) 0 else null;
        }
        pub fn getLen(comptime T: type, field_ptr: *const anyopaque) usize {
            _ = field_ptr;
            if (T != StructType) @compileError("getLen called with incompatible type");
            return fields.len;
        }
        pub fn getValues(object: *const anyopaque, out_values: []config.ValueFloat) void {
            const struct_ptr: *const StructType = @ptrCast(@alignCast(object));
            inline for (0..@min(fields.len, config.max_channels)) |i| {
                out_values[i] = util.floatCast(config.ValueFloat, @field(struct_ptr, @tagName(fields[i])));
            }
        }
        pub fn setValues(object: *anyopaque, new_values: []const config.ValueFloat) void {
            const struct_ptr: *StructType = @ptrCast(@alignCast(object));
            inline for (0..@min(fields.len, config.max_channels)) |i| {
                const FieldType = std.meta.FieldType(StructType, fields[i]);
                @field(struct_ptr, @tagName(fields[i])) = util.castFromFloat(FieldType, new_values[i]);
            }
        }
    };
}

pub const default_scalar_types: []const type = &.{ u8, u16, u32, u64, i8, i16, i32, i64, f16, f32, f64 };

pub fn defaultTweenTypes(config: BaseConfiguration) []const type {
    var types: []const type = &.{};
    for (default_scalar_types) |Type| {
        types = types ++ .{ ScalarTweenType(Type, config) };
    }
    return types;
}

fn testScalarTween(comptime config: BaseConfiguration, comptime IndexableType: type, value: *IndexableType) !void {
    const TweenType = ScalarTweenType(IndexableType, config);
    const FieldType = std.meta.Child(IndexableType);
    const len = util.len(value.*);
    var buf = std.mem.zeroes([config.max_channels]config.ValueFloat);
    for (0..len) |i| {
        buf[i] = util.floatCast(config.ValueFloat, 2 + i);
        value.*[i] = util.castFromFloat(FieldType, @as(config.ValueFloat, @floatFromInt(102 + i)));
    }
    info.setValues.get()(value, &buf);
    for (0..len) |i| {
        try std.testing.expectEqual(@as(config.ValueFloat, @floatFromInt(2+i)), buf[i]);
        try std.testing.expectEqual(util.castFromFloat(FieldType, @as(config.ValueFloat, @floatFromInt(2+i))), value.*[i]);
        buf[i] = util.floatCast(config.ValueFloat, 2 + i);
        value.*[i] = util.castFromFloat(FieldType, @as(config.ValueFloat, @floatFromInt(102 + i)));
    }
    info.getValues.get()(value, &buf);
    for (0..len) |i| {
        try std.testing.expectEqual(@as(config.ValueFloat, @floatFromInt(102+i)), buf[i]);
        try std.testing.expectEqual(util.castFromFloat(FieldType, @as(config.ValueFloat, @floatFromInt(102+i))), value.*[i]);
    }
}

test "index vector" {
    const config: BaseConfiguration = .{};
    inline for (1..config.max_channels+1) |channels| {
        inline for (default_scalar_types) |Element| {
            var array: [channels]Element = undefined;
            try testIndexableTween(config, @TypeOf(array), &array);
            var vec: @Vector(channels, Element) = undefined;
            try testIndexableTween(config, @TypeOf(vec), &vec);
            var slice: []Element = &array;
            try testIndexableTween(config, []Element, &slice);
        }
    }
}

pub const DefaultTweenContext = struct {
    pub fn FieldType(comptime HandleType: type, comptime field_chain: anytype) type {
        // TODO better error messages
        const StructType = @typeInfo(HandleType).pointer.child;
        return util.NestedFieldType(StructType, field_chain);
    }
    pub fn initMapping(ctx: *DefaultTweenContext, handle: anytype, comptime field_chain: anytype, comptime extra_offset: usize) DefaultFieldHandle {
        _ = ctx;
        const StructType = @typeInfo(@TypeOf(handle)).pointer.child;
        const offset = util.nestedOffsetOf(StructType, field_chain) + extra_offset;
        return .{ .owner = @ptrCast(handle), .offset = offset };
    }
    pub fn getField(ctx: *DefaultTweenContext, handle: DefaultFieldHandle) ?*anyopaque {
        _ = ctx;
        return @ptrCast(@as([*]u8, @ptrCast(handle.owner)) + handle.offset);
    }
}

pub const DefaultFieldHandle = struct {
    owner: *anyopaque,
    offset: usize,
};

// pub fn defaultInitMapping(TweenContext: type) Any {
//     const DefaultInitMapping = struct {
//         pub fn defaultInitMapping(ctx: TweenContext, handle: anytype, comptime field_chain: anytype) ?DefaultFieldHandle {
//             _ = ctx;
            
//         }
//     };
//     return .init(DefaultInitMapping.defaultInitMapping);
// }

pub const BaseConfiguration = struct {
    TimeFloat: type = f32,
    ValueFloat: type = f32,
    max_channels: comptime_int = 4,
};

pub const Configuration = struct {
    base: BaseConfiguration = .{},
    TweenContext: type = void,
    FieldHandle: type = DefaultFieldHandle,
    accessors: []const type = &.{},
    //defaultInitMapping: Any = defaultInitMapping(void),

    pub fn init(base: BaseConfiguration) Configuration {
        return .{
            .base = base,
            .TweenContext = void,
            .FieldHandle = DefaultFieldHandle,
            .accessors = defaultTweenTypes(base),
            .special_mappers = &.{},
            //.defaultInitMapping = defaultInitMapping(void),
        };
    }
};

pub fn TweenLibrary(in_config: Configuration) type {
    const Ease = enum {
        linear,
        exp_in,
        exp_out,
        bounce_in,
        bounce_out,
    };
    const Interp = enum {
        lerp,
        slerp,
    };

    const PendingTweenId = u32; // TODO

    return struct {
        pub const config = in_config;

        pub const TweenContext = config.TweenContext;

        pub const Tween = struct {
            field: config.FieldHandle,
            initial_values: [config.base.max_channels]config.base.ValueFloat,
            target_values: [config.base.max_channels]config.base.ValueFloat,
            time_remain: config.base.TimeFloat,
            inverse_length: config.base.TimeFloat,
            ease: Ease,
            interp: Interp,
            len: u8,
            accessor: u8, // TODO maybe make this configurable or just bigger? 256 seems possible for large projects, though the switch would be crazy.

            // TODO these don't belong in the hot data
            callback: util.Callback,
            next: ?PendingTweenId,
            peer: ?PendingTweenId,
        };

        pub const PendingTween = struct {
            field: config.FieldHandle,
            callback: util.Callback = .none,
            duration: config.base.TimeFloat,
            target_values: [config.base.max_channels]config.base.ValueFloat,
            ease: Ease = .linear,
            interp: Interp = .lerp,
            len: u8,
            accessor: u8, // TODO maybe make this configurable or just bigger? 256 seems possible for large projects, though the switch would be crazy.
            next: ?PendingTweenId = null,
            peer: ?PendingTweenId = null,
        };

        pub const CallbackFlags = packed struct (u8) {
            
        };

        const TweenControl = struct {
            callback: util.Callback,
            delay: config.base.TimeFloat,
            duration: config.base.TimeFloat,
            repeat_delay: config.base.TimeFloat,
            repeat_count: u32,
            flags: packed struct (u32) {

            },
        };

        pub const TweenManager = struct {
            ctx: TweenContext,
            active_tweens: maps.DenseSlotMap(ActiveTween),
            tweens: maps.SparseSlotMap(PendingTween),
            groups: maps.SparseSlotMap(TweenGroup),

            pub const ParallelGroup = struct {
                mgr: *TweenManager,
            };

            pub fn to(
                mgr: *TweenManager,
                handle: anytype,
                comptime field_chain_raw: anytype,
                target_val: TweenContext.FieldType(@TypeOf(handle), util.sanitizeFieldChain(field_chain_raw).get()),
                duration: config.base.TimeFloat,
            ) ActiveTweenContext {
                const FieldType = @TypeOf(target_val);
                const field_chain = util.sanitizeFieldChain(field_chain_raw).get();
                const accessor = findTweenAccessor(FieldType) orelse
                    @compileError("No tween accessor can handle field type "++@typeName(FieldType));
                const field_handle = mgr.ctx.initMapping(handle, field_chain, accessor.offset);
                const field_ptr = mgr.ctx.getField(field_handle) orelse
                    @panic("TODO handle immediately invalid field"); // TODO
                const len = config.accessors[accessor.id].getLen(FieldType, field_ptr);

                var target_values = std.mem.zeroes([config.base.max_channels]config.base.ValueFloat);
                const target_ptr: *const anyopaque = @ptrCast(@as([*]const u8, @ptrCast(&target_val)) + accessor.offset);
                config.accessors[accessor.id].getValues(target_ptr, target_values[0..len]);

                const result: PendingTween = .{
                    .field = field_handle,
                    .len = len,
                    .duration = duration,
                    .accessor = accessor.id,
                    .target_values = target_values,
                };
                _ = result; // TODO
            }

            pub fn parallel(mgr: *TweenManager) ParallelGroup {
                return .{ .mgr = mgr };
            }
            
            fn finishTween(mgr: *TweenManager, tween: *Tween, remaining_delta: config.base.TimeFloat) void {
                if (tween.callback_func) |func| {
                    func(tween.callback_obj);
                }
                var parallel_iter = tween.next;
                while (parallel_iter) |pi| {
                    const pt = mgr.startPendingTween(pi);
                    parallel_iter = pt.peer;
                }
            }

            const AccessorInfo = struct {
                id: comptime_int,
                offset: comptime_int,
            };

            /// Find the value which can be used as a runtime ID to access the fields of a type.
            /// Returns null if no accessor is compatible with the type.
            fn findTweenAccessor(comptime T: type) ?AccessorInfo {
                for (config.accessors, 0..) |Accessor, i| {
                    if (Accessor.compatibleWithType(T)) |offset| {
                        return .{ .id = i, .offset = offset };
                    }
                }
                return null;
            }

            /// Dispatch setValues to the appropriate accessor, using a runtime ID
            fn setValues(field_ptr: *anyopaque, values: []const config.base.ValueFloat, accessor: usize) void {
                switch (accessor) {
                    inline 0...config.accessors.len-1 => |i| {
                        config.accessors[i].setValues(field_ptr, values);
                    },
                    else => unreachable,
                }
            }

            /// Dispatch getValues to the appropriate accessor, using a runtime ID.
            fn getValues(field_ptr: *const anyopaque, out_values: []config.base.ValueFloat, accessor: usize) void {
                switch (accessor) {
                    inline 0...config.accessors.len-1 => |i| {
                        config.accessors[i].getValues(field_ptr, out_values);
                    },
                    else => unreachable,
                }
            }

            pub fn updateTweens(mgr: *TweenManager, delta: config.base.TimeFloat) void {
                var i: usize = 0;
                while (i < mgr.active_tweens.items.len) {
                    const tween = &mgr.active_tweens.items[i];
                    if (tween.time_remain <= delta) {
                        mgr.finishTween(tween, delta - tween.time_remain);
                        mgr.active_tweens.swapRemove(i);
                        continue;
                    }
                    tween.time_remain -= delta;
                    if (ctx.getField(tween.field)) |field_ptr| {
                        const percent = 1.0 - tween.time_remain * tween.inverse_length;
                        const eased = dispatchEase(tween.ease, percent);
                        const interpolated = dispatchInterp(tween.initial_values, tween.target_values, eased);
                        setValues(field_ptr, interpolated[0..tween.len], tween.accessor);
                    }
                }
                // 1. Update the time remaining for each tween
                // 2. Process any tweens that finished, starting and updating any new tweens
                // 3. Interpolate the values for each tween
                // 4. Write interpolated values back to source objects
            }
        };
    };
}

test "init default tween library" {
    const Lib = TweenLibrary(.init(.{}));
    inline for (Lib.config.types) |tt| {
        std.debug.print("Supported type: {s}\n", .{ @typeName(tt.Type) });
    }
}

