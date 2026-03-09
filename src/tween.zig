const std = @import("std");
const util = @import("util.zig");
const maps = @import("maps.zig");

const assert = std.debug.assert;
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
        pub fn compatibleWithType(comptime T: type) ?AccessorCompatibility {
            const scalar_info = util.deduceScalarTypeInfo(T) orelse return null;
            if (scalar_info.ScalarType != ScalarType) return null;
            return .{ .offset = scalar_info.first_offset, .len = scalar_info.num_items };
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
        pub fn compatibleWithType(comptime T: type) ?AccessorCompatibility {
            return if (T == StructType) .{ .offset = 0, .len = fields.len } else null;
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

const AccessorCompatibility = struct {
    offset: comptime_int,
    len: comptime_int,
};

pub const default_scalar_types: []const type = &.{ u8, u16, u32, u64, i8, i16, i32, i64, f16, f32, f64 };

pub fn defaultTweenTypes(config: BaseConfiguration) []const type {
    var types: []const type = &.{};
    for (default_scalar_types) |Type| {
        types = types ++ .{ScalarTweenType(Type, config)};
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
    TweenType.setValues(value, &buf);
    for (0..len) |i| {
        try std.testing.expectEqual(@as(config.ValueFloat, @floatFromInt(2 + i)), buf[i]);
        try std.testing.expectEqual(util.castFromFloat(FieldType, @as(config.ValueFloat, @floatFromInt(2 + i))), value.*[i]);
        buf[i] = util.floatCast(config.ValueFloat, 2 + i);
        value.*[i] = util.castFromFloat(FieldType, @as(config.ValueFloat, @floatFromInt(102 + i)));
    }
    TweenType.getValues(value, &buf);
    for (0..len) |i| {
        try std.testing.expectEqual(@as(config.ValueFloat, @floatFromInt(102 + i)), buf[i]);
        try std.testing.expectEqual(util.castFromFloat(FieldType, @as(config.ValueFloat, @floatFromInt(102 + i))), value.*[i]);
    }
}
// TODO test scalar tweens

pub const DefaultTweenContext = struct {
    ally: std.mem.Allocator,

    pub fn init(ally: std.mem.Allocator) DefaultTweenContext {
        return .{ .ally = ally };
    }

    pub fn FieldType(comptime HandleType: type, comptime raw_field_chain: anytype) type {
        // TODO better error messages

        // If the field chain is just a single field, wrap it in a tuple
        const field_chain = util.sanitizeFieldChain(raw_field_chain).get();
        const StructType = @typeInfo(HandleType).pointer.child;
        return util.NestedFieldType(StructType, field_chain);
    }
    pub fn initMapping(ctx: *DefaultTweenContext, handle: anytype, comptime raw_field_chain: anytype, comptime extra_offset: usize) DefaultFieldHandle {
        _ = ctx;
        const field_chain = util.sanitizeFieldChain(raw_field_chain).get();
        const StructType = @typeInfo(@TypeOf(handle)).pointer.child;
        const offset = util.nestedOffsetOf(StructType, field_chain) + extra_offset;
        return .{ .owner = @ptrCast(handle), .offset = offset };
    }
    pub fn getField(ctx: *DefaultTweenContext, handle: DefaultFieldHandle) ?*anyopaque {
        _ = ctx;
        return @ptrCast(@as([*]u8, @ptrCast(handle.owner)) + handle.offset);
    }
    pub fn allocator(ctx: *const DefaultTweenContext) std.mem.Allocator {
        return ctx.ally;
    }
};

pub const DefaultFieldHandle = struct {
    owner: *anyopaque,
    offset: usize,
};

pub const BaseConfiguration = struct {
    TimeFloat: type = f32,
    ValueFloat: type = f32,
    max_channels: comptime_int = 4,
};

/// Easing equations based on Robert Penner's work:
/// http://robertpenner.com/easing/
/// And the subsequent adaptations in aurelibon/universal-tween-engine
pub fn DefaultEases(Float: type) type {
    return struct {
        pub const default_named_eases: []const EaseDesc =
            Linear.default_named_eases ++
            Quad.default_named_eases ++
            Cubic.default_named_eases ++
            Quartic.default_named_eases ++
            Quintic.default_named_eases ++
            Sine.default_named_eases ++
            Expo.default_named_eases ++
            Circ.default_named_eases ++
            Bounce.default_named_eases;

        const pi = std.math.pi;
        const pi_over_2 = std.math.pi / 2.0;

        /// Generate an In tween from an Out or an Out from an In.
        /// Robert penner's book refers to this as the "inverse",
        /// but it's not a mathematical inverse. The function is
        /// flipped along the x=0.5 and y=0.5 axes.
        pub fn GenInverse(comptime InOrOut: type) type {
            return struct {
                pub fn ease(t: Float) Float {
                    return 1 - InOrOut.ease(1 - t);
                }
            };
        }

        /// Given an In and Out, generate an InOut by using In
        /// for 0 <= t < 0.5 and Out for 0.5 <= t <= 1.
        pub fn GenInOut(comptime In: type, comptime Out: type) type {
            return struct {
                pub fn ease(t: Float) Float {
                    return if (t < 0.5) In.ease(t * 2) * 0.5 else 0.5 + 0.5 * Out.ease(t * 2 - 1);
                }
            };
        }

        pub const Linear = struct {
            pub const default_named_eases: []const EaseDesc = &.{
                .{ .linear, Linear },
            };

            pub fn ease(t: Float) Float {
                return t;
            }
        };

        pub const Quad = struct {
            pub const default_named_eases: []const EaseDesc = &.{
                .{ .quad_in, In },
                .{ .quad_out, Out },
                .{ .quad_inout, InOut },
            };

            pub const In = struct {
                pub fn ease(t: Float) Float {
                    return t * t;
                }
            };
            pub const Out = GenInverse(In);
            pub const InOut = GenInOut(In, Out);
        };

        pub const Cubic = struct {
            pub const default_named_eases: []const EaseDesc = &.{
                .{ .cubic_in, In },
                .{ .cubic_out, Out },
                .{ .cubic_inout, InOut },
            };

            pub const In = struct {
                pub fn ease(t: Float) Float {
                    return t * t * t;
                }
            };
            pub const Out = GenInverse(In);
            pub const InOut = GenInOut(In, Out);
        };

        pub const Quartic = struct {
            pub const default_named_eases: []const EaseDesc = &.{
                .{ .quartic_in, In },
                .{ .quartic_out, Out },
                .{ .quartic_inout, InOut },
            };

            pub const In = struct {
                pub fn ease(t: Float) Float {
                    return (t * t) * (t * t);
                }
            };
            pub const Out = GenInverse(In);
            pub const InOut = GenInOut(In, Out);
        };

        pub const Quintic = struct {
            pub const default_named_eases: []const EaseDesc = &.{
                .{ .quintic_in, In },
                .{ .quintic_out, Out },
                .{ .quintic_inout, InOut },
            };

            pub const In = struct {
                pub fn ease(t: Float) Float {
                    return (t * t) * (t * t) * t;
                }
            };
            pub const Out = GenInverse(In);
            pub const InOut = GenInOut(In, Out);
        };

        pub const Sine = struct {
            pub const default_named_eases: []const EaseDesc = &.{
                .{ .sine_in, In },
                .{ .sine_out, Out },
                .{ .sine_inout, InOut },
            };

            pub const In = struct {
                pub fn ease(t: Float) Float {
                    return 1 - @cos(t * pi_over_2);
                }
            };
            pub const Out = struct {
                pub fn ease(t: Float) Float {
                    return @sin(t * pi_over_2);
                }
            };
            pub const InOut = struct {
                pub fn ease(t: Float) Float {
                    return 0.5 - 0.5 * @cos(t * pi);
                }
            };
        };

        pub const Expo = struct {
            pub const default_named_eases: []const EaseDesc = &.{
                .{ .expo_in, In },
                .{ .expo_out, Out },
                .{ .expo_inout, InOut },
            };

            pub const In = struct {
                pub fn ease(t: Float) Float {
                    return @exp2(t * 10 - 10);
                }
            };
            pub const Out = GenInverse(In);
            pub const InOut = GenInOut(In, Out);
        };

        pub const Circ = struct {
            pub const default_named_eases: []const EaseDesc = &.{
                .{ .circ_in, In },
                .{ .circ_out, Out },
                .{ .circ_inout, InOut },
            };

            pub const In = struct {
                pub fn ease(t: Float) Float {
                    return 1 - @sqrt(1 - t * t);
                }
            };
            pub const Out = GenInverse(In);
            pub const InOut = GenInOut(In, Out);
        };

        pub const Bounce = struct {
            pub const default_named_eases: []const EaseDesc = &.{
                .{ .bounce_in, In },
                .{ .bounce_out, Out },
                .{ .bounce_inout, InOut },
            };

            pub const In = GenInverse(Out);
            pub const Out = struct {
                pub fn ease(t: Float) Float {
                    if (t < (1.0 / 2.75)) {
                        return 7.5625 * t * t;
                    } else if (t < (2.0 / 2.75)) {
                        const t_off = t - (1.5 / 2.75);
                        return 7.5625 * t_off * t_off + 0.75;
                    } else if (t < (2.5 / 2.75)) {
                        const t_off = t - (2.25 / 2.75);
                        return 7.5625 * t_off * t_off + 0.9375;
                    } else {
                        const t_off = t - (2.625 / 2.75);
                        return 7.5625 * t_off * t_off + 0.984375;
                    }
                }
            };
            pub const InOut = GenInOut(In, Out);
        };
    };
}

pub fn DefaultInterps(Float: type) type {
    return struct {
        pub const default_named_interps: []const InterpDesc = &.{
            .{ .lerp, Lerp },
        };

        pub const Lerp = struct {
            pub fn interp(z: Float, a: [*]const Float, b: [*]const Float, out: [*]Float, len: usize) void {
                for (a[0..len], b, out) |fa, fb, *fout| {
                    fout.* = fa + (fb - fa) * z;
                }
            }
        };
    };
}

pub const EaseDesc = struct { EnumLiteral, type };
pub const InterpDesc = struct { EnumLiteral, type };

pub const Configuration = struct {
    base: BaseConfiguration = .{},
    TweenContext: type = DefaultTweenContext,
    FieldHandle: type = DefaultFieldHandle,
    accessors: []const type = &.{},
    eases: []const EaseDesc,
    interps: []const InterpDesc,

    pub fn init(base: BaseConfiguration) Configuration {
        return .{
            .base = base,
            .TweenContext = DefaultTweenContext,
            .FieldHandle = DefaultFieldHandle,
            .accessors = defaultTweenTypes(base),
            .eases = DefaultEases(base.ValueFloat).default_named_eases,
            .interps = DefaultInterps(base.ValueFloat).default_named_interps,
        };
    }
};

pub fn TweenLibrary(in_config: Configuration) type {
    return struct {
        pub const config = in_config;

        pub const TweenContext = config.TweenContext;
        pub const TimeFloat = config.base.TimeFloat;
        pub const ValueFloat = config.base.ValueFloat;
        pub const max_channels = config.base.max_channels;
        pub const TweenValues = [max_channels]ValueFloat;
        pub const Ease = util.MakeEnum(util.extractFields(in_config.eases, .@"0"));
        pub const Interp = util.MakeEnum(util.extractFields(in_config.interps, .@"0"));
        pub const default_ease: Ease = @enumFromInt(0);
        pub const default_interp: Interp = @enumFromInt(0);
        pub const infinite = ~@as(u32, 0);

        const Event = struct {
            const Kind = union(enum) {
                start_tween,
                end_tween,
            };

            time: TimeFloat,
            kind: Kind,
            handle: u32,

            fn compareTimes(_: void, a: Event, b: Event) std.math.Order {
                return std.math.order(a.time, b.time);
            }
        };

        pub const TweenPlan = struct {
            field: config.FieldHandle,
            duration: TimeFloat,
            start_values: TweenValues,
            target_values: TweenValues,
            ease: Ease,
            interp: Interp,
            len: u8,
            accessor: u8, // TODO maybe make this configurable or just bigger? 256 seems possible for large projects, though the switch would be crazy.
            time_remain: TimeFloat,
            inverse_length: TimeFloat,
        };

        const TweenCallback = util.BoundFn(fn (*TweenManager, TweenId, CallbackFlags) void);

        const TweenControl = struct {
            callback: TweenCallback,
            delay: TimeFloat,
            reverse_delay: TimeFloat,
            duration: TimeFloat,
            repeat_delay: TimeFloat,
            /// Number of times to repeat, not including the first run.
            num_repeats: u32,
            /// Number of times we have repeated
            repeat_counter: u32,
            plan: Tweens.Key,
            next_control_in_group: u32,
            first_child_control: u32,

            flags: packed struct(u11) {
                callbacks: CallbackFlags,
                yoyo_repeat: bool,
                reverse: bool,
                sequence_element: bool,
                has_start_values: bool,
                submitted: bool,
                killed: bool,
                out_of_mem: bool = false,
            },

            // "Instant" controls can have their start and end safely combined into one event.
            // Note that if a control has zero duration but has children, it cannot be instant
            // because the child callbacks must be invoked between the start and end of the parent.
            fn isInstant(ctrl: *TweenControl) bool {
                return ctrl.duration == 0 and ctrl.first_child_control == null_id;
            }
        };

        const Tweens = maps.DenseSlotMap(TweenPlan, .{ .key_bits = 32 });
        pub const TweenId = u32;

        const null_plan_id: Tweens.Key = @enumFromInt(~@as(u32, 0));
        const null_id: u32 = ~@as(u32, 0);

        pub const CallbackFlags = packed struct(u4) {
            /// Called with .start after the initial delay
            begin: bool = false,
            /// Called with begin and on each repeat
            start: bool = false,
            /// Called each time the percent hits 1.0
            end: bool = false,
            /// Called with .end after the last repeat
            complete: bool = false,
        };

        pub const Ordering = enum {
            parallel,
            sequential,
        };

        fn PlanBuilderMixin(comptime Cfg: type) type {
            return struct {
                pub fn ease(cfg: Cfg, func: Ease) Cfg {
                    if (!cfg.out_of_mem) {
                        const ctrl = cfg.mgr.controls.get(cfg.control_id);
                        assert(!ctrl.flags.submitted);
                        const plan = cfg.mgr.tweens.get(ctrl.plan);
                        plan.ease = func;
                    }
                    return cfg;
                }

                pub fn interp(cfg: Cfg, func: Interp) Cfg {
                    if (!cfg.out_of_mem) {
                        const ctrl = cfg.mgr.controls.get(cfg.control_id);
                        assert(!ctrl.flags.submitted);
                        const plan = cfg.mgr.tweens.get(ctrl.plan);
                        plan.interp = func;
                    }
                    return cfg;
                }

                pub fn startAt(cfg: Cfg, val: anytype) Cfg {
                    if (!cfg.out_of_mem) {
                        const ctrl = cfg.mgr.controls.get(cfg.control_id);
                        assert(!ctrl.flags.submitted);
                        const plan = cfg.mgr.tweens.get(ctrl.plan);
                        const accessor = TweenManager.findTweenAccessor(@TypeOf(val)) orelse
                            @compileError("No matching accessor for type " ++ @typeName(@TypeOf(val)));
                        assert(plan.len == accessor.len); // The number of components in the tween must match the starting value
                        const target_ptr: *const anyopaque = util.offsetPtr(&val, accessor.offset);
                        config.accessors[accessor.id].getValues(target_ptr, plan.start_values[0..plan.len]);
                        ctrl.flags.has_start_values = true;
                    }
                    return cfg;
                }
            };
        }

        fn CtrlBuilderMixin(comptime Cfg: type) type {
            return struct {
                pub fn delay(cfg: Cfg, amt: TimeFloat) Cfg {
                    if (!cfg.out_of_mem) {
                        const ctrl = cfg.mgr.controls.get(cfg.control_id);
                        assert(!ctrl.flags.submitted);
                        ctrl.delay = @max(0, amt);
                    }
                    return cfg;
                }

                pub fn repeat(cfg: Cfg, num_repeats: u32, repeat_delay: TimeFloat, yoyo: bool) Cfg {
                    if (!cfg.out_of_mem) {
                        const ctrl = cfg.mgr.controls.get(cfg.control_id);
                        assert(!ctrl.flags.submitted);
                        ctrl.repeat_delay = @max(0, repeat_delay);
                        ctrl.num_repeats = num_repeats;
                        ctrl.flags.yoyo_repeat = yoyo;
                    }
                    return cfg;
                }

                pub fn callback(cfg: Cfg, func: TweenCallback, events: CallbackFlags) Cfg {
                    if (!cfg.out_of_mem) {
                        const ctrl = cfg.mgr.controls.get(cfg.control_id);
                        assert(!ctrl.flags.submitted);
                        ctrl.callback = func;
                        ctrl.flags.callbacks = events;
                    }
                    return cfg;
                }
            };
        }

        fn RootBuilderMixin(comptime Cfg: type) type {
            return struct {
                pub fn submit(cfg: Cfg) !void {
                    if (cfg.out_of_mem) return error.OutOfMemory;
                    const ctrl = cfg.mgr.controls.get(cfg.control_id);
                    assert(!ctrl.flags.submitted);
                    if (ctrl.flags.out_of_mem) {
                        cfg.cancel();
                        return error.OutOfMemory;
                    } else {
                        ctrl.flags.submitted = true;
                        cfg.mgr.scheduleControl(cfg.control_id, cfg.mgr.event_time);
                    }
                }
                pub fn cancel(cfg: Cfg) void {
                    // TODO
                    _ = cfg;
                }
            };
        }

        pub const TweenGroupBuilder = struct {
            const Cfg = @This();
            mgr: *TweenManager,
            control_id: TweenId,
            out_of_mem: bool,
            order: Ordering,

            const ctrl_mixin = CtrlBuilderMixin(Cfg);
            pub const delay = ctrl_mixin.delay;
            pub const repeat = ctrl_mixin.repeat;
            pub const callback = ctrl_mixin.callback;

            pub fn add(cfg: Cfg, builder: anytype) Cfg {
                if (cfg.out_of_mem) {
                    builder.cancel();
                    return cfg;
                }

                const ctrl = cfg.mgr.controls.get(cfg.control_id);
                assert(!ctrl.flags.submitted);

                if (builder.out_of_mem) {
                    ctrl.flags.out_of_mem = true;
                    return cfg;
                }

                const sub_ctrl = cfg.mgr.controls.get(builder.control_id);
                assert(!sub_ctrl.flags.submitted);

                if (sub_ctrl.flags.out_of_mem) {
                    ctrl.flags.out_of_mem = true;
                    builder.cancel();
                    return cfg;
                }

                //assert(sub_ctrl.parent_control_id == null_id); TODO parent id
                assert(sub_ctrl.next_control_in_group == null_id);
                sub_ctrl.flags.submitted = true;

                //sub_ctrl.parent_control_id = cfg.control_id; TODO parent id

                if (sub_ctrl.num_repeats == infinite) {
                    // TODO error reporting: group containing infinite subgroup
                    sub_ctrl.num_repeats = 0;
                }

                var last_ctrl = &ctrl.first_child_control;
                while (last_ctrl.* != null_id) {
                    const chain_ctrl = cfg.mgr.controls.get(last_ctrl.*);
                    last_ctrl = &chain_ctrl.next_control_in_group;
                }
                last_ctrl.* = builder.control_id;

                const sub_duration = sub_ctrl.delay + sub_ctrl.duration + (sub_ctrl.repeat_delay + sub_ctrl.duration) * @as(TimeFloat, @floatFromInt(sub_ctrl.num_repeats));
                if (cfg.order == .sequential) {
                    ctrl.duration += sub_duration;
                    sub_ctrl.flags.sequence_element = true;
                } else {
                    ctrl.duration = @max(ctrl.duration, sub_duration);
                }

                return cfg;
            }

            const root_mixin = RootBuilderMixin(Cfg);
            pub const cancel = root_mixin.cancel;
            pub fn submit(cfg: Cfg) !void {
                if (cfg.out_of_mem) return error.OutOfMemory;
                const ctrl = cfg.mgr.controls.get(cfg.control_id);
                assert(!ctrl.flags.submitted);

                if (ctrl.flags.out_of_mem) {
                    cfg.cancel();
                    return error.OutOfMemory;
                }

                // Using duration, initialize the reverse delay of the child controls
                if (ctrl.first_child_control != null_id) {
                    if (cfg.order == .sequential) {
                        // For sequential, the reverse delay of any control is the forward delay of the next control.
                        // The delay of the first control is already baked into the duration of this control.
                        var prev_ctrl = cfg.mgr.controls.get(ctrl.first_child_control);
                        while (prev_ctrl.next_control_in_group != null_id) {
                            const next_ctrl = cfg.mgr.controls.get(prev_ctrl.next_control_in_group);
                            defer prev_ctrl = next_ctrl;
                            prev_ctrl.reverse_delay = next_ctrl.delay;
                        }
                    } else {
                        // For parallel, the reverse delay is the duration of this node minus the duration and delay of the child.
                        var id = ctrl.first_child_control;
                        while (id != null_id) {
                            const sub_ctrl = cfg.mgr.controls.get(id);
                            defer id = sub_ctrl.next_control_in_group;
                            const sub_duration = sub_ctrl.delay + sub_ctrl.duration + (sub_ctrl.repeat_delay + sub_ctrl.duration) * @as(TimeFloat, @floatFromInt(sub_ctrl.num_repeats));
                            sub_ctrl.reverse_delay = @max(0, ctrl.duration - sub_duration);
                        }
                    }
                }

                ctrl.flags.submitted = true;
                cfg.mgr.scheduleControl(cfg.control_id, cfg.mgr.event_time);
            }
        };

        pub const TweenBuilder = struct {
            const Cfg = @This();
            mgr: *TweenManager,
            control_id: TweenId,
            out_of_mem: bool,

            const plan_mixin = PlanBuilderMixin(Cfg);
            pub const ease = plan_mixin.ease;
            pub const interp = plan_mixin.interp;
            pub const startAt = plan_mixin.startAt;

            const ctrl_mixin = CtrlBuilderMixin(Cfg);
            pub const delay = ctrl_mixin.delay;
            pub const repeat = ctrl_mixin.repeat;
            pub const callback = ctrl_mixin.callback;

            const root_mixin = RootBuilderMixin(Cfg);
            pub const submit = root_mixin.submit;
            pub const cancel = root_mixin.cancel;
        };

        pub const TweenCallbackBuilder = struct {
            const Cfg = @This();
            mgr: *TweenManager,
            control_id: TweenId,
            out_of_mem: bool,

            const ctrl_mixin = CtrlBuilderMixin(Cfg);
            pub const delay = ctrl_mixin.delay;
            pub const repeat = ctrl_mixin.repeat;
            pub const callback = ctrl_mixin.callback;

            const root_mixin = RootBuilderMixin(Cfg);
            pub const submit = root_mixin.submit;
            pub const cancel = root_mixin.cancel;
        };

        const AccessorInfo = struct {
            id: comptime_int,
            offset: comptime_int,
            len: comptime_int,
        };

        pub const TweenManager = struct {
            ctx: TweenContext,
            tweens: Tweens = .{},
            controls: maps.SparseSlotMap(TweenControl) = .{},
            events: std.PriorityQueue(Event, void, Event.compareTimes),
            num_active_tweens: Tweens.Index = 0,
            event_time: TimeFloat = 0.0,

            pub fn init(ctx: TweenContext) TweenManager {
                return .{ .ctx = ctx, .events = .init(ctx.allocator(), {}) };
            }

            pub fn update(mgr: *TweenManager, raw_delta_time: TimeFloat) void {
                const delta_time = @max(raw_delta_time, 0);
                mgr.debugCheckForUnreleasedBuilders();
                mgr.updateActiveTweens(delta_time);
                mgr.processEvents(delta_time);
            }

            fn debugCheckForUnreleasedBuilders(mgr: *TweenManager) void {
                if (std.debug.runtime_safety) {
                    var it = mgr.controls.iterator(.forward);
                    while (it.nextValue()) |v| {
                        if (!v.flags.submitted) {
                            // TODO error reporting
                            // Error: builder was not cancelled, submitted, or added to a group!
                            // Enable callstack capturing to get a stack trace
                            // TODO callstack capturing
                        }
                    }
                }
            }

            fn updateActiveTweens(mgr: *TweenManager, delta: TimeFloat) void {
                const active_tweens = mgr.tweens.values();
                var i: Tweens.Index = mgr.num_active_tweens;
                while (i > 0) {
                    i -= 1;
                    const tween = &active_tweens[i];

                    tween.time_remain -= delta;
                    if (mgr.ctx.getField(tween.field)) |field_ptr| {
                        const percent = 1.0 - tween.time_remain * tween.inverse_length;
                        const eased = dispatchEase(tween.ease, percent);
                        var interpolated: TweenValues = undefined;
                        dispatchInterp(tween.interp, eased, &tween.start_values, &tween.target_values, &interpolated, tween.len);
                        setValues(field_ptr, interpolated[0..tween.len], tween.accessor);
                    }
                }
            }

            fn processEvents(mgr: *TweenManager, delta: TimeFloat) void {
                const event_end = mgr.event_time + delta;

                while (mgr.events.peek()) |evt| {
                    if (evt.time > event_end) break;
                    _ = mgr.events.remove();
                    handle_event: switch (evt.kind) {
                        .start_tween => {
                            var control = mgr.controls.get(evt.handle);
                            if (control.flags.killed) continue;
                            // TODO does kill need cleanup here?

                            if (control.callback.isBound()) {
                                var flags: CallbackFlags = .{ .start = true };
                                if (control.repeat_counter == 0) {
                                    flags.begin = true;
                                }
                                if (control.isInstant()) {
                                    flags.end = true;
                                    if (control.repeat_counter == control.num_repeats) {
                                        flags.complete = true;
                                    }
                                }
                                if (util.hasAnyFlags(CallbackFlags, control.flags.callbacks, flags)) {
                                    control.callback.callBound(.{ mgr, evt.handle, flags });
                                }
                                // Callback could kill the tween or realloc, check again.
                                control = mgr.controls.get(evt.handle);
                                if (control.flags.killed) continue;
                                // TODO does kill need cleanup here?
                            }

                            if (control.plan != null_plan_id) schedule_plan: {
                                const plan = mgr.tweens.get(control.plan);
                                const plan_index = mgr.tweens.getIndex(control.plan);
                                assert(plan_index >= mgr.num_active_tweens); // If the plan is active, events may have happened out of order!
                                // If we can't access the field, keep the callbacks and control but skip the tween
                                const field = mgr.ctx.getField(plan.field) orelse break :schedule_plan;
                                // TODO error reporting -- what to do if the object no longer exists?

                                const had_start_values = control.flags.has_start_values;

                                if (!had_start_values) {
                                    getValues(field, plan.start_values[0..plan.len], plan.accessor);
                                    control.flags.has_start_values = true;
                                }

                                if (control.duration != 0) {
                                    // TODO use partial timestamp here and ease
                                    if (had_start_values) {
                                        setValues(field, plan.start_values[0..plan.len], plan.accessor);
                                    }
                                    // Reset the tween
                                    plan.time_remain = plan.duration;
                                    // Activate the tween
                                    mgr.tweens.swapIndexes(plan_index, mgr.num_active_tweens);
                                    mgr.num_active_tweens += 1;
                                } else {
                                    setValues(field, plan.target_values[0..plan.len], plan.accessor);
                                }
                            }

                            var child_id = control.first_child_control;
                            while (child_id != null_id) {
                                mgr.scheduleControl(child_id, evt.time);
                                const child_ctrl = mgr.controls.get(child_id);
                                if (child_ctrl.flags.sequence_element) break;
                                child_id = child_ctrl.next_control_in_group;
                            }

                            if (!control.isInstant()) {
                                // TODO allocate events so that we can assume capacity
                                mgr.events.add(.{ .time = evt.time + control.duration, .kind = .end_tween, .handle = evt.handle }) catch @panic("TODO");
                            } else {
                                continue :handle_event .end_tween;
                            }
                        },
                        .end_tween => {
                            var control = mgr.controls.get(evt.handle);
                            if (control.flags.killed) continue;
                            // TODO does kill need cleanup here?

                            // Instant controls have their start and end combined into one callback
                            if (control.callback.isBound() and !control.isInstant()) {
                                var flags: CallbackFlags = .{ .end = true };
                                flags.end = true;
                                if (control.repeat_counter == control.num_repeats) {
                                    flags.complete = true;
                                }
                                if (util.hasAnyFlags(CallbackFlags, control.flags.callbacks, flags)) {
                                    control.callback.callBound(.{ mgr, evt.handle, flags });
                                }
                                // Callback could kill the tween or realloc, check again.
                                control = mgr.controls.get(evt.handle);
                                if (control.flags.killed) continue;
                                // TODO does kill need cleanup here?
                            }

                            if (control.plan != null_plan_id) {
                                const plan = mgr.tweens.get(control.plan);
                                const plan_idx = mgr.tweens.getIndex(control.plan);
                                if (mgr.ctx.getField(plan.field)) |field| {
                                    setValues(field, plan.target_values[0..plan.len], plan.accessor);
                                }
                                if (plan_idx < mgr.num_active_tweens) {
                                    mgr.num_active_tweens -= 1;
                                    mgr.tweens.swapIndexes(plan_idx, mgr.num_active_tweens);
                                }
                            }

                            control.repeat_counter +|= 1;
                            if (control.num_repeats == infinite or control.repeat_counter <= control.num_repeats) {
                                if (control.repeat_delay == 0) {
                                    if (control.num_repeats == infinite) {
                                        // TODO error handling -- infinite loop tween.
                                        control.flags.killed = true;
                                    } else {
                                        continue :handle_event .start_tween;
                                    }
                                } else {
                                    // TODO reserve events capacity so we can assume it here
                                    mgr.events.add(.{
                                        .time = evt.time + control.repeat_delay,
                                        .kind = .start_tween,
                                        .handle = evt.handle,
                                    }) catch @panic("TODO");
                                    break :handle_event;
                                }
                            }

                            // If we get here, the control will not repeat.
                            if (control.flags.sequence_element and control.next_control_in_group != null_id) {
                                mgr.scheduleControl(control.next_control_in_group, evt.time);
                            }
                        },
                    }
                }

                if (mgr.events.count() == 0) {
                    mgr.event_time = 0;
                } else {
                    mgr.event_time = event_end;
                }
            }

            fn scheduleControl(mgr: *TweenManager, control_id: TweenId, sched_time: TimeFloat) void {
                const ctrl = mgr.controls.get(control_id);
                ctrl.repeat_counter = 0;
                // TODO each tween can only schedule one event,
                // so we can assume capacity here if we allocate in the right places.
                mgr.events.add(.{
                    .time = sched_time + ctrl.delay,
                    .kind = .start_tween,
                    .handle = control_id,
                }) catch {
                    ctrl.flags.killed = true;
                    // TODO kill cleanup
                };
            }

            fn compactEventTime(mgr: *TweenManager) void {
                const evt_time = mgr.event_time;
                for (mgr.events.items) |*it| {
                    it.time -= evt_time;
                }
                mgr.event_time = 0;
            }

            /// Find the value which can be used as a runtime ID to access the fields of a type.
            /// Returns null if no accessor is compatible with the type.
            fn findTweenAccessor(comptime T: type) ?AccessorInfo {
                for (config.accessors, 0..) |Accessor, i| {
                    if (Accessor.compatibleWithType(T)) |info| {
                        return .{ .id = i, .offset = info.offset, .len = info.len };
                    }
                }
                return null;
            }

            /// Dispatch setValues to the appropriate accessor, using a runtime ID
            fn setValues(field_ptr: *anyopaque, values: []const config.base.ValueFloat, accessor: usize) void {
                switch (accessor) {
                    inline 0...config.accessors.len - 1 => |i| {
                        config.accessors[i].setValues(field_ptr, values);
                    },
                    else => unreachable,
                }
            }

            /// Dispatch getValues to the appropriate accessor, using a runtime ID.
            fn getValues(field_ptr: *const anyopaque, out_values: []config.base.ValueFloat, accessor: usize) void {
                switch (accessor) {
                    inline 0...config.accessors.len - 1 => |i| {
                        config.accessors[i].getValues(field_ptr, out_values);
                    },
                    else => unreachable,
                }
            }

            fn dispatchEase(id: Ease, value: ValueFloat) ValueFloat {
                switch (id) {
                    inline else => |i| {
                        return config.eases[@intFromEnum(i)][1].ease(value);
                    },
                }
            }

            fn dispatchInterp(id: Interp, z: ValueFloat, a: [*]const ValueFloat, b: [*]const ValueFloat, out: [*]ValueFloat, len: usize) void {
                switch (id) {
                    inline else => |i| {
                        return config.interps[@intFromEnum(i)][1].interp(z, a, b, out, len);
                    },
                }
            }

            pub fn to(
                mgr: *TweenManager,
                handle: anytype,
                comptime field_chain: anytype,
                target_val: TweenContext.FieldType(@TypeOf(handle), field_chain),
                duration: TimeFloat,
            ) TweenBuilder {
                return toOrImmediateError(mgr, handle, field_chain, target_val, duration) catch |err| switch (err) {
                    error.OutOfMemory => return .{ .mgr = mgr, .control_id = null_id, .out_of_mem = true },
                };
            }

            fn toOrImmediateError(
                mgr: *TweenManager,
                handle: anytype,
                comptime field_chain: anytype,
                target_val: TweenContext.FieldType(@TypeOf(handle), field_chain),
                duration: TimeFloat,
            ) !TweenBuilder {
                const FieldType = @TypeOf(target_val);
                // TODO: Pass field chain to find accessor, to allow hint items.
                // e.g. "When writing Player .position, use a special accessor"
                const accessor = findTweenAccessor(FieldType) orelse
                    @compileError("No tween accessor can handle field type " ++ @typeName(FieldType));
                const field_handle = mgr.ctx.initMapping(handle, field_chain, accessor.offset);
                const len = accessor.len;

                var target_values = std.mem.zeroes(TweenValues);
                const target_ptr: *const anyopaque = util.offsetPtr(&target_val, accessor.offset);
                config.accessors[accessor.id].getValues(target_ptr, target_values[0..len]);

                const plan_id, const plan = try mgr.tweens.alloc(mgr.ctx.allocator());
                errdefer mgr.tweens.release(plan_id);
                plan.* = .{
                    .field = field_handle,
                    .duration = @max(duration, 0),
                    .start_values = std.mem.zeroes(TweenValues),
                    .target_values = target_values,
                    .ease = default_ease,
                    .interp = default_interp,
                    .len = accessor.len,
                    .accessor = accessor.id,
                    .time_remain = 0,
                    .inverse_length = if (duration <= 0) 0 else 1.0 / duration,
                };

                const control_id = try mgr.controls.alloc(mgr.ctx.allocator());
                errdefer mgr.controls.release(control_id);
                const control = mgr.controls.get(control_id);
                control.* = .{
                    .callback = .none,
                    .delay = 0,
                    .reverse_delay = 0,
                    .duration = 0,
                    .repeat_delay = 0,
                    .repeat_counter = 0,
                    .num_repeats = 0,
                    .plan = plan_id,
                    .next_control_in_group = null_id,
                    .first_child_control = null_id,
                    .flags = .{
                        .callbacks = .{},
                        .yoyo_repeat = false,
                        .reverse = false,
                        .sequence_element = false,
                        .has_start_values = false,
                        .submitted = false,
                        .killed = false,
                    },
                };

                return .{ .mgr = mgr, .control_id = control_id, .out_of_mem = false };
            }

            pub fn set(
                mgr: *TweenManager,
                handle: anytype,
                comptime field_chain: anytype,
                target_val: TweenContext.FieldType(@TypeOf(handle), field_chain),
            ) TweenBuilder {
                return to(mgr, handle, field_chain, target_val, 0);
            }

            pub fn wait(mgr: TweenManager, duration: TimeFloat) TweenCallbackBuilder {
                const control_id = mgr.controls.alloc(mgr.ctx.allocator()) catch |err| switch (err) {
                    error.OutOfMemory => return .{ .mgr = mgr, .control_id = null_id, .out_of_mem = true },
                };

                const control = mgr.controls.get(control_id);
                control.* = .{
                    .callback = .none,
                    .delay = duration,
                    .reverse_delay = 0,
                    .duration = 0,
                    .repeat_delay = 0,
                    .num_repeats = 0,
                    .repeat_counter = 0,
                    .plan = null_plan_id,
                    .next_control_in_group = null_id,
                    .first_child_control = null_id,
                    .flags = .{
                        .callbacks = .{},
                        .yoyo_repeat = false,
                        .reverse = false,
                        .sequence_element = false,
                        .has_start_values = false,
                        .submitted = false,
                        .killed = false,
                    },
                };

                return .{ .mgr = mgr, .control_id = control_id, .out_of_mem = false };
            }

            pub fn call(
                mgr: *TweenManager,
                callback: TweenCallback,
            ) TweenCallbackBuilder {
                return mgr.wait(0).callback(callback, .{ .begin = true });
            }

            pub fn parallel(mgr: *TweenManager) TweenGroupBuilder {
                return mgr.group(.parallel);
            }

            pub fn sequence(mgr: *TweenManager) TweenGroupBuilder {
                return mgr.group(.sequential);
            }

            pub fn group(mgr: *TweenManager, order: Ordering) TweenGroupBuilder {
                const control_id = mgr.controls.alloc(mgr.ctx.allocator()) catch |err| switch (err) {
                    error.OutOfMemory => return .{ .mgr = mgr, .control_id = null_id, .out_of_mem = true, .order = order },
                };
                const control = mgr.controls.get(control_id);
                control.* = .{
                    .callback = .none,
                    .delay = 0,
                    .reverse_delay = 0,
                    .duration = 0,
                    .repeat_delay = 0,
                    .num_repeats = 0,
                    .repeat_counter = 0,
                    .plan = null_plan_id,
                    .next_control_in_group = null_id,
                    .first_child_control = null_id,
                    .flags = .{
                        .callbacks = .{},
                        .yoyo_repeat = false,
                        .reverse = false,
                        .sequence_element = false,
                        .has_start_values = false,
                        .submitted = false,
                        .killed = false,
                    },
                };

                // TODO: Debug checks that the previous one is done configuring

                return .{ .mgr = mgr, .control_id = control_id, .out_of_mem = false, .order = order };
            }

            pub fn deinit(mgr: *TweenManager) void {
                // TODO kill all tweens and apply side effects? Make callbacks?
                const allocator = mgr.ctx.allocator();
                mgr.tweens.deinit(allocator);
                mgr.controls.deinit(allocator);
                mgr.events.deinit();
            }
        };
    };
}

test "init default tween library" {
    //const LinearColor = packed struct (u32) { r: u11, g: u11, b: u10 };
    const Vec3 = struct { x: f32, y: f32, z: f32 };
    const Color = struct { r: u8, g: u8, b: u8, a: u8 };

    const tw = TweenLibrary(.init(.{}));
    var mgr = tw.TweenManager.init(.init(std.testing.allocator));

    const TestObject = struct {
        position: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
        rotation: f32 = 0,
        color: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    };

    var test_obj: TestObject = .{};
    try mgr.to(&test_obj, .position, .{ .x = 4, .y = 8, .z = 16 }, 10)
        .delay(2)
        .ease(.linear)
        .repeat(4, 1, false)
        .submit();

    mgr.update(1);

    try mgr.sequence()
        .add(mgr.to(&test_obj, .{ .position, .x }, 5, 2)
            .delay(1))
        .add(mgr.parallel()
            .add(mgr.to(&test_obj, .color, .{ .r = 128, .g = 0, .b = 255, .a = 255 }, 2))
            .add(mgr.to(&test_obj, .rotation, 180, 3)))
        .repeat(2, 0, false)
        .submit();

    mgr.update(1);

    mgr.deinit();
}
