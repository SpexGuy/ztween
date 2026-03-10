const std = @import("std");

const EnumLiteral = @Type(.enum_literal);

pub const Any = struct {
    PtrType: type,
    ptr: *anyopaque,

    pub fn init(comptime val: anytype) Any {
        return .{
            .PtrType = @TypeOf(&val),
            .ptr = @ptrCast(@constCast(&val)),
        };
    }
    pub fn get(comptime self: Any) std.meta.Child(self.PtrType) {
        return @as(self.PtrType, @ptrCast(@alignCast(self.ptr))).*;
    }
};

test "Any" {
    // Any of a comptime_int
    const four_any: Any = .init(4);
    const four = four_any.get();
    try std.testing.expectEqual(@TypeOf(four), comptime_int);
    try std.testing.expectEqual(four, 4);
    // Any of a generic function
    const get_any: Any = .init(Any.get);
    const other_four = get_any.get()(four_any);
    try std.testing.expectEqual(@TypeOf(other_four), comptime_int);
    try std.testing.expectEqual(other_four, 4);
    // Any of a comptime known value
    const seven_any: Any = .init(@as(u32, 7));
    const seven = seven_any.get();
    try std.testing.expectEqual(@TypeOf(seven), u32);
    try std.testing.expectEqual(seven, @as(u32, 7));
    // Any of a runtime value
    // Not allowed
    // var nine: u32 = 9;
    // _ = &nine; // allow var
    // const nine_any: Any = .init(nine);
    // const extracted = nine_any.get();
    // try std.testing.expectEqual(@TypeOf(extracted), u32);
    // try std.testing.expectEqual(extracted, @as(u32, nine));
}

pub fn nestedOffsetOf(Type: type, field_chain: anytype) comptime_int {
    if (field_chain.len == 0) return 0;
    const FieldType = @TypeOf(@field(@as(Type, undefined), @tagName(field_chain[0])));
    return @offsetOf(Type, @tagName(field_chain[0])) + nestedOffsetOf(FieldType, sliceTuple(field_chain, 1, field_chain.len).get());
}

test "nestedOffsetOf" {
    const Nested = extern struct {
        a: u32,
        b: u32,
        c: extern struct {
            d: u64,
            e: f32,
        },
        f: extern union {
            g: u32,
            h: f32,
        },
    };

    try std.testing.expectEqual(0, nestedOffsetOf(Nested, .{}));
    try std.testing.expectEqual(0, nestedOffsetOf(Nested, .{.a}));
    try std.testing.expectEqual(4, nestedOffsetOf(Nested, .{.b}));
    try std.testing.expectEqual(8, nestedOffsetOf(Nested, .{.c}));
    try std.testing.expectEqual(8, nestedOffsetOf(Nested, .{ .c, .d }));
    try std.testing.expectEqual(16, nestedOffsetOf(Nested, .{ .c, .e }));
    try std.testing.expectEqual(24, nestedOffsetOf(Nested, .{.f}));
}

pub fn NestedFieldType(comptime T: type, field_chain: anytype) type {
    var Curr = T;
    for (field_chain) |field| {
        Curr = @FieldType(Curr, @tagName(field));
    }
    return Curr;
}

test "NestedFieldType" {
    const Tuple = struct { f32, f64 };
    const A = struct {
        x: u32,
        t: Tuple,
    };
    const B = struct {
        a: A,
    };

    try std.testing.expectEqual(B, NestedFieldType(B, .{}));
    try std.testing.expectEqual(A, NestedFieldType(B, .{.a}));
    try std.testing.expectEqual(u32, NestedFieldType(B, .{ .a, .x }));
    try std.testing.expectEqual(Tuple, NestedFieldType(B, .{ .a, .t }));
    try std.testing.expectEqual(f32, NestedFieldType(B, .{ .a, .t, .@"0" }));
    try std.testing.expectEqual(f64, NestedFieldType(B, .{ .a, .t, .@"1" }));
}

pub fn floatCast(FloatType: type, value: anytype) FloatType {
    return switch (@typeInfo(@TypeOf(value))) {
        .comptime_float, .comptime_int => value,
        .float => @floatCast(value),
        .int => @floatFromInt(value),
        .bool => if (value) 1.0 else 0.0,
        else => @compileError("Cannot convert from " ++ @typeName(@TypeOf(value)) ++ " to float."),
    };
}

pub fn castFromFloat(Type: type, value: anytype) Type {
    return switch (@typeInfo(Type)) {
        .float => @floatCast(value),
        .int => @intFromFloat(@round(value)),
        .bool => value < 0.5,
        .comptime_float => value,
        .comptime_int => @round(@as(comptime_float, value)),
        else => @compileError("Cannot convert from float to " ++ @typeName(Type) ++ "."),
    };
}

test "floatCast" {
    try std.testing.expectEqual(@as(f32, 4.0), floatCast(f32, 4.0));
    try std.testing.expectEqual(@as(f32, 4.0), floatCast(f32, 4));
    try std.testing.expectEqual(@as(f32, 4.0), floatCast(f32, @as(u32, 4)));
    try std.testing.expectEqual(@as(f32, 4.0), floatCast(f32, @as(i32, 4)));
    try std.testing.expectEqual(@as(f32, 4.0), floatCast(f32, @as(f32, 4.0)));
    try std.testing.expectEqual(@as(f32, 4.0), floatCast(f32, @as(f64, 4.0)));
    try std.testing.expectEqual(@as(f32, 4.0), floatCast(f32, @as(f16, 4.0)));
    try std.testing.expectEqual(@as(f32, 1.0), floatCast(f32, true));
    try std.testing.expectEqual(@as(f32, 0.0), floatCast(f32, false));
}

// Oof
pub inline fn len(indexable: anytype) usize {
    return switch (@typeInfo(@TypeOf(indexable))) {
        .vector => |vi| vi.len,
        else => indexable.len,
    };
}

// Oof
// This is no longer supported :(
//@field(@as(PtrType, @ptrCast(@alignCast(inner_ptr.?))), @tagName(functionName))();
// So we need this worse implementation
pub inline fn callMember(lhs: anytype, memberFunc: EnumLiteral, params: anytype, ReturnType: type) ReturnType {
    const LhsType = @TypeOf(lhs);
    const lhs_ti = @typeInfo(LhsType);
    const ObjectType = if (lhs_ti == .pointer) lhs_ti.pointer.child else LhsType;
    const function = @field(ObjectType, @tagName(memberFunc));
    const func_info = @typeInfo(@TypeOf(function));
    const self_param = func_info.@"fn".params[0];
    if (self_param.type) |SelfParam| {
        const self_param_info = @typeInfo(SelfParam);
        if ((self_param_info == .pointer) == (lhs_ti == .pointer)) {
            return @call(.auto, function, .{lhs} ++ params);
        } else if (self_param_info == .pointer) {
            return @call(.auto, function, .{&lhs} ++ params);
        } else {
            return @call(.auto, function, .{lhs.*} ++ params);
        }
    } else {
        return @call(.auto, function, .{lhs} ++ params);
    }
}

const ErasedObj = extern union {
    ptr: ?*anyopaque,
    bits: usize,

    const ErasureStrategy = enum {
        cannot_erase,
        bitcast,
        unwrap_pointer,
    };

    pub fn erase(ParamType: type, param: ParamType) ErasedObj {
        if (ParamType == @TypeOf(null) or ParamType == @TypeOf(undefined)) {
            return undefined;
        }
        return switch (comptime findErasureStrategy(ParamType)) {
            .cannot_erase => @compileError("Type " ++ @typeName(ParamType) ++ " is too large to be erased."),
            .bitcast => b: {
                var packed_val: usize = 0;
                std.mem.asBytes(&packed_val)[0..@sizeOf(ParamType)].* = std.mem.asBytes(&param).*;
                break :b .{ .bits = packed_val };
            },
            .unwrap_pointer => .{ .ptr = unwrapWrappedPtr(param) },
        };
    }

    pub inline fn unerase(obj: ErasedObj, ParamType: type) ParamType {
        return switch (comptime findErasureStrategy(ParamType)) {
            .cannot_erase => @compileError("Type " ++ @typeName(ParamType) ++ " is too large to be erased."),
            .bitcast => b: {
                var result: ParamType = undefined;
                std.mem.asBytes(&result).* = std.mem.asBytes(&obj.bits)[0..@sizeOf(ParamType)].*;
                break :b result;
            },
            .unwrap_pointer => wrapWrappedPtr(ParamType, obj.ptr),
        };
    }

    inline fn findErasureStrategy(T: type) ErasureStrategy {
        if (comptime isWrappedPtrOrOptPtr(T)) {
            return .unwrap_pointer;
        } else if (@sizeOf(T) <= @sizeOf(usize)) {
            return .bitcast;
        } else {
            return .cannot_erase;
        }
    }

    fn isWrappedPtrOrOptPtr(T: type) bool {
        if (comptime isPtrOrOptPtr(T)) return true;
        if (getSingleField(T)) |field| {
            return isWrappedPtrOrOptPtr(field.type);
        }
        return false;
    }

    fn unwrapWrappedPtr(wrapped: anytype) ?*anyopaque {
        const Wrapper = @TypeOf(wrapped);
        if (comptime isPtrOrOptPtr(Wrapper)) {
            return @ptrCast(@constCast(wrapped));
        } else if (comptime getSingleField(Wrapper)) |field| {
            return unwrapWrappedPtr(@field(wrapped, field.name));
        } else {
            @compileError("unwrapWrappedPtr cannot unwrap type " ++ @typeName(Wrapper));
        }
    }

    fn wrapWrappedPtr(comptime Wrapper: type, ptr: ?*anyopaque) Wrapper {
        if (comptime isPtrOrOptPtr(Wrapper)) {
            return @ptrCast(@alignCast(ptr));
        } else if (comptime getSingleField(Wrapper)) |field| {
            var result: Wrapper = undefined;
            @field(result, field.name) = wrapWrappedPtr(field.type, ptr);
            return result;
        } else {
            @compileError("wrapWrappedPtr cannot wrap type " ++ @typeName(Wrapper));
        }
    }

    fn isPtrOrOptPtr(comptime T: type) bool {
        const ti = @typeInfo(T);
        return isPtr(ti) or (ti == .optional and isPtr(@typeInfo(ti.optional.child)));
    }

    fn isPtr(comptime ti: std.builtin.Type) bool {
        return ti == .pointer and ti.pointer.size != .slice;
    }

    /// If a struct has only one non-comptime field, returns that field.
    /// Otherwise returns null.
    fn getSingleField(comptime T: type) ?std.builtin.Type.StructField {
        switch (@typeInfo(T)) {
            .@"struct" => |str| {
                var field: ?std.builtin.Type.StructField = null;
                for (str.fields) |f| {
                    if (f.is_comptime) continue;
                    if (field != null) return null; // two fields found
                    field = f;
                }
                return field;
            },
            else => {},
        }
        return null;
    }
};

pub inline fn isComptimeKnown(param: anytype) bool {
    return @typeInfo(@TypeOf(.{param})).@"struct".fields[0].is_comptime;
}

///
pub fn BoundFn(InFnType: type) type {
    {
        const ti = @typeInfo(InFnType);
        if (ti != .@"fn") @compileError("BoundFn requires a function type to bind");
        if (ti.@"fn".is_generic or ti.@"fn".return_type == null) @compileError("Cannot bind a runtime pointer for a generic function");
        if (ti.@"fn".is_var_args) @compileError("Cannot bind a varargs function");
    }
    return struct {
        pub const FnType = InFnType;
        pub const ArgPack = std.meta.ArgsTuple(FnType);
        pub const ReturnType = @typeInfo(FnType).@"fn".return_type.?;

        object: ErasedObj,
        function: ?*const fn (ErasedObj, ArgPack) ReturnType,

        /// A bound function with no binding, useful for default initialization.
        pub const none: @This() = .{ .object = undefined, .function = null };

        /// Create a bound function with no extra context pointer parameter.
        pub fn bindStatic(comptime function: FnType) @This() {
            const Wrap = struct {
                fn boundFnStatic(_: ErasedObj, args: ArgPack) ReturnType {
                    return @call(.auto, function, args);
                }
            };
            return .{ .object = undefined, .function = Wrap.boundFnStatic };
        }

        /// Create a bound function for a function and a pointer or handle.
        /// The parameter can be any type, as long as it is smaller than or
        /// the same size as a pointer. It must match (or be coercible to)
        /// the type of the first argument of the function.
        pub fn bind(comptime function: anytype, param: anytype) @This() {
            // This isn't an inline function, but comptime-only types like `null`
            // need special handling, as they force the `unerase` function to be
            // comptime, which is problematic. As a bonus, this allows any parameter
            // (even large or unsized ones) to be bound at comptime by calling `comptime .bind(...)`.
            if (isComptimeKnown(param)) {
                const Wrap = struct {
                    fn boundFnComptime(_: ErasedObj, args: ArgPack) ReturnType {
                        return @call(.auto, function, .{param} ++ args);
                    }
                };
                return .{ .object = undefined, .function = &Wrap.boundFnComptime };
            } else {
                const ParamType = @TypeOf(param);
                const Wrap = struct {
                    fn boundFnWrap(obj: ErasedObj, args: ArgPack) ReturnType {
                        return @call(.auto, function, .{obj.unerase(ParamType)} ++ args);
                    }
                };
                return .{ .object = .erase(ParamType, param), .function = &Wrap.boundFnWrap };
            }
        }

        /// Create a bound function for a member function. This performs the
        /// same automatic adjustments as `obj.func()` syntax, allowing the
        /// first parameter to be passed as a pointer or a value. Note that
        /// the parameter to this function will be copied into the BoundFn,
        /// so it should only be passed as a value if it is a Handle type.
        pub fn bindMember(ptrOrHandle: anytype, functionName: EnumLiteral) @This() {
            const ParamType = @TypeOf(ptrOrHandle);
            const pti = @typeInfo(ParamType);
            const NamespaceType = if (pti == .pointer and pti.pointer.size == .one) pti.pointer.child else ParamType;
            const nsti = @typeInfo(NamespaceType);
            if (nsti != .@"struct" and nsti != .@"union" and nsti != .@"opaque") {
                @compileError("Type " ++ @typeName(ParamType) ++ " does not have member functions to bind!");
            }
            if (!@hasDecl(NamespaceType, @tagName(functionName))) {
                @compileError("Type " ++ @typeName(NamespaceType) ++ " has no member function " ++ @tagName(functionName));
            }
            const Wrap = struct {
                fn boundFnMember(obj: ErasedObj, args: ArgPack) ReturnType {
                    return callMember(obj.unerase(ParamType), functionName, args, ReturnType);
                }
            };
            return .{ .object = .erase(ParamType, ptrOrHandle), .function = Wrap.boundFnMember };
        }

        /// Check whether a function is bound.
        pub fn isBound(cb: @This()) bool {
            return cb.function != null;
        }

        /// Invoke the bound function. If no function is bound, returns null.
        pub inline fn call(cb: @This(), args: std.meta.ArgsTuple(FnType)) ?ReturnType {
            if (cb.function) |func| {
                return @as(ReturnType, func(cb.object, args));
            } else {
                return null;
            }
        }

        /// Invoke the bound function, asserting that a function is bound. This
        /// should only be called after checking isBound().
        pub inline fn callBound(cb: @This(), args: std.meta.ArgsTuple(FnType)) ReturnType {
            return @as(ReturnType, cb.function.?(cb.object, args));
        }
    };
}

test "BoundFn" {
    const TestObj = struct {
        const TestObj = @This();
        var global_count: u32 = 0;

        count: u32 = 0,

        pub fn increment(self: *TestObj, amt: u32) usize {
            self.count +%= amt;
            return self.count;
        }
        pub fn decrement(self: *TestObj, amt: u32) usize {
            self.count -%= amt;
            return self.count;
        }

        pub fn sumValue(self: TestObj, amt: u32) usize {
            return self.count + amt;
        }

        pub fn optional_increment(o: ?*TestObj, amt: u32) usize {
            if (o) |to| {
                return to.increment(amt);
            } else {
                return static_increment(amt);
            }
        }

        pub fn static_increment(amt: u32) usize {
            global_count += amt;
            return global_count;
        }
    };

    const Handle = struct {
        id: u32 = 4,
        generation: u32 = 8,

        pub fn handle_set(handle: @This(), amt: u32) usize {
            TestObj.global_count = handle.generation + amt;
            return TestObj.global_count;
        }
    };

    const WrapPtr = struct {
        val: ?*TestObj = null,

        pub fn incr(self: @This(), amt: u32) usize {
            return if (self.val) |v| v.increment(amt) else TestObj.static_increment(amt);
        }
        pub fn incr_const(self: *const @This(), amt: u32) usize {
            return self.incr(amt);
        }
    };

    const EmptyStruct = struct {
        pub fn incr(_: *const @This(), amt: u32) usize {
            return TestObj.static_increment(amt);
        }
    };

    TestObj.global_count = 0;
    var to: TestObj = .{};
    var handle: Handle = .{};
    var wrap_to: WrapPtr = .{ .val = &to };
    var empty: EmptyStruct = .{};

    try std.testing.expectEqual(ErasedObj.ErasureStrategy.unwrap_pointer, ErasedObj.findErasureStrategy(WrapPtr));

    const Callback = BoundFn(fn (u32) usize);

    const cb_incr: Callback = .bindMember(&to, .increment);
    const cb_decr: Callback = .bindMember(&to, .decrement);
    const cb_sum: Callback = .bindMember(&to, .sumValue);
    const cb_null: Callback = .none;
    const cb_static_incr: Callback = .bindStatic(TestObj.static_increment);
    const cb_opt_static: Callback = .bind(TestObj.optional_increment, @as(?*TestObj, null));
    const cb_opt_to: Callback = .bind(TestObj.optional_increment, @as(?*TestObj, &to));
    const cb_opt_static_2: Callback = .bind(TestObj.optional_increment, null);
    const cb_opt_to_2: Callback = .bind(TestObj.optional_increment, &to);
    const cb_handle: Callback = .bind(Handle.handle_set, handle);
    const cb_handle_member: Callback = .bindMember(handle, .handle_set);
    const cb_wrap: Callback = .bind(WrapPtr.incr, wrap_to);
    const cb_wrap_member: Callback = .bindMember(wrap_to, .incr);
    const cb_wrap_member_const: Callback = .bindMember(wrap_to, .incr_const);
    const cb_empty: Callback = .bind(EmptyStruct.incr, &empty);
    const cb_empty_member: Callback = .bindMember(empty, .incr);
    const cb_empty_member_ptr: Callback = .bindMember(&empty, .incr);

    // Clear the handles to make sure they were copied
    handle = .{ .generation = 0, .id = 0 };
    wrap_to = .{ .val = null };

    try std.testing.expect(cb_incr.isBound());
    try std.testing.expect(cb_decr.isBound());
    try std.testing.expect(!cb_null.isBound());
    try std.testing.expect(cb_static_incr.isBound());
    try std.testing.expect(cb_opt_static.isBound());
    try std.testing.expect(cb_opt_to.isBound());
    try std.testing.expect(cb_opt_static_2.isBound());
    try std.testing.expect(cb_opt_to_2.isBound());
    try std.testing.expect(cb_handle.isBound());
    try std.testing.expect(cb_handle_member.isBound());
    try std.testing.expect(cb_wrap.isBound());
    try std.testing.expect(cb_wrap_member.isBound());
    try std.testing.expect(cb_wrap_member_const.isBound());
    try std.testing.expect(cb_empty.isBound());
    try std.testing.expect(cb_empty_member.isBound());
    try std.testing.expect(cb_empty_member_ptr.isBound());

    var rv: ?usize = null;
    try std.testing.expectEqual(@as(u32, 0), to.count);
    try std.testing.expectEqual(@as(u32, 0), TestObj.global_count);
    rv = cb_incr.call(.{1});
    try std.testing.expectEqual(@as(?usize, 1), rv);
    try std.testing.expectEqual(@as(u32, 1), to.count);
    try std.testing.expectEqual(@as(u32, 0), TestObj.global_count);
    rv = cb_incr.call(.{1});
    try std.testing.expectEqual(@as(?usize, 2), rv);
    try std.testing.expectEqual(@as(u32, 2), to.count);
    try std.testing.expectEqual(@as(u32, 0), TestObj.global_count);
    rv = cb_decr.call(.{1});
    try std.testing.expectEqual(@as(u32, 1), to.count);
    try std.testing.expectEqual(@as(u32, 0), TestObj.global_count);
    rv = cb_null.call(.{1});
    try std.testing.expectEqual(null, rv);
    try std.testing.expectEqual(@as(u32, 1), to.count);
    try std.testing.expectEqual(@as(u32, 0), TestObj.global_count);
    rv = cb_sum.call(.{4});
    try std.testing.expectEqual(@as(?usize, 5), rv);
    try std.testing.expectEqual(@as(u32, 1), to.count);
    try std.testing.expectEqual(@as(u32, 0), TestObj.global_count);
    rv = cb_static_incr.call(.{1});
    try std.testing.expectEqual(@as(u32, 1), to.count);
    try std.testing.expectEqual(@as(u32, 1), TestObj.global_count);
    rv = cb_opt_static.call(.{1});
    try std.testing.expectEqual(@as(u32, 1), to.count);
    try std.testing.expectEqual(@as(u32, 2), TestObj.global_count);
    rv = cb_opt_to.call(.{1});
    try std.testing.expectEqual(@as(u32, 2), to.count);
    try std.testing.expectEqual(@as(u32, 2), TestObj.global_count);
    rv = cb_opt_static_2.call(.{1});
    try std.testing.expectEqual(@as(?usize, 3), rv);
    try std.testing.expectEqual(@as(u32, 2), to.count);
    try std.testing.expectEqual(@as(u32, 3), TestObj.global_count);
    rv = cb_opt_to_2.call(.{1});
    try std.testing.expectEqual(@as(u32, 3), to.count);
    try std.testing.expectEqual(@as(u32, 3), TestObj.global_count);
    rv = cb_handle.callBound(.{2});
    try std.testing.expectEqual(@as(u32, 3), to.count);
    try std.testing.expectEqual(@as(u32, 10), TestObj.global_count);
    rv = cb_handle_member.callBound(.{1});
    try std.testing.expectEqual(@as(u32, 3), to.count);
    try std.testing.expectEqual(@as(u32, 9), TestObj.global_count);
    rv = cb_wrap.callBound(.{1});
    try std.testing.expectEqual(@as(u32, 4), to.count);
    try std.testing.expectEqual(@as(u32, 9), TestObj.global_count);
    rv = cb_wrap_member.callBound(.{1});
    try std.testing.expectEqual(@as(u32, 5), to.count);
    try std.testing.expectEqual(@as(u32, 9), TestObj.global_count);
    rv = cb_wrap_member_const.callBound(.{1});
    try std.testing.expectEqual(@as(u32, 6), to.count);
    try std.testing.expectEqual(@as(u32, 9), TestObj.global_count);
    rv = cb_empty.call(.{1});
    try std.testing.expectEqual(@as(u32, 6), to.count);
    try std.testing.expectEqual(@as(u32, 10), TestObj.global_count);
    rv = cb_empty_member.call(.{1});
    try std.testing.expectEqual(@as(u32, 6), to.count);
    try std.testing.expectEqual(@as(u32, 11), TestObj.global_count);
    rv = cb_empty_member_ptr.call(.{1});
    try std.testing.expectEqual(@as(u32, 6), to.count);
    try std.testing.expectEqual(@as(u32, 12), TestObj.global_count);
}

const ScalarTypeInfo = struct {
    ScalarType: type,
    first_offset: usize,
    num_items: usize,
    padding: usize,

    fn ascByOffset(_: void, a: ScalarTypeInfo, b: ScalarTypeInfo) bool {
        return a.first_offset < b.first_offset;
    }
};

pub fn deduceScalarTypeInfo(comptime T: type) ?ScalarTypeInfo {
    switch (@typeInfo(T)) {
        .int, .float, .bool => {
            return .{
                .ScalarType = T,
                .first_offset = 0,
                .num_items = 1,
                .padding = 0,
            };
        },
        .array => |arr| {
            if (deduceScalarTypeInfo(arr.child)) |subinfo| {
                if (subinfo.first_offset == 0 and subinfo.padding == 0) {
                    return .{
                        .ScalarType = subinfo.ScalarType,
                        .first_offset = 0,
                        .num_items = subinfo.num_items * arr.len,
                        .padding = 0,
                    };
                }
            }
        },
        .vector => |vec| {
            return .{
                .ScalarType = vec.child,
                .first_offset = 0,
                .num_items = vec.len,
                .padding = @sizeOf(T) - vec.len * @sizeOf(vec.child),
            };
        },
        .@"struct" => |str| {
            var values: []const ScalarTypeInfo = &.{};
            for (str.fields) |f| {
                if (f.is_comptime) continue;
                if (@sizeOf(f.type) == 0) continue;
                if (@bitOffsetOf(T, f.name) != @offsetOf(T, f.name) * 8) {
                    return null; // Bit fields are incompatible
                }
                var field_info = deduceScalarTypeInfo(f.type) orelse return null;
                field_info.first_offset += @offsetOf(T, f.name);
                if (values.len != 0 and values[0].ScalarType != field_info.ScalarType) return null;
                values = values ++ @as([]const ScalarTypeInfo, &.{field_info});
            }
            if (values.len == 0) return null;
            var sorted_fields = values[0..values.len].*;
            if (str.layout != .@"extern") {
                std.mem.sort(ScalarTypeInfo, &sorted_fields, {}, ScalarTypeInfo.ascByOffset);
            }
            var offset = sorted_fields[0].first_offset;
            var count: usize = 0;
            for (&sorted_fields) |*field| {
                if (offset != field.first_offset) return null; // sparse data
                count += field.num_items;
                offset += field.num_items * @sizeOf(field.ScalarType);
            }
            return .{
                .ScalarType = sorted_fields[0].ScalarType,
                .first_offset = sorted_fields[0].first_offset,
                .num_items = count,
                .padding = @sizeOf(T) - offset,
            };
        },
        .@"union" => |un| {
            if (un.layout == .@"extern") {
                var shared_info: ?ScalarTypeInfo = null;
                for (un.fields) |f| {
                    if (@sizeOf(f.type) == 0) continue;
                    const field_info = deduceScalarTypeInfo(f.type) orelse return null;
                    if (shared_info == null) {
                        shared_info = field_info;
                    } else {
                        if (shared_info.?.ScalarType != field_info.ScalarType or shared_info.?.first_offset != field_info.first_offset or shared_info.?.num_items != field_info.num_items)
                            return null;
                    }
                    if (shared_info) |si| {
                        return .{
                            .ScalarType = si.ScalarType,
                            .first_offset = si.first_offset,
                            .num_items = si.num_items,
                            .padding = @sizeOf(T) - si.first_offset - si.num_items * @sizeOf(si.ScalarType),
                        };
                    }
                }
            }
        },
        else => {},
    }
    return null;
}

test "ScalarTypeInfo Struct" {
    const Color = struct {
        rgb: [3]u8,
        a: u8,
    };
    const FancyColor = struct {
        value: Color,
    };
    const color_info = deduceScalarTypeInfo(Color).?;
    try std.testing.expectEqual(u8, color_info.ScalarType);
    try std.testing.expectEqual(@as(usize, 4), color_info.num_items);
    const fancy_info = deduceScalarTypeInfo(FancyColor).?;
    try std.testing.expectEqual(u8, fancy_info.ScalarType);
    try std.testing.expectEqual(@as(usize, 4), fancy_info.num_items);

    const vec_info = deduceScalarTypeInfo(@Vector(3, f32)).?;
    try std.testing.expectEqual(f32, vec_info.ScalarType);
    try std.testing.expectEqual(@as(usize, 3), vec_info.num_items);

    const FunkyVec = extern union {
        vec: @Vector(4, f32),
        arr: [4]f32,
        names: extern struct {
            x: f32,
            y: f32,
            z: f32,
            w: f32,
        },
    };
    const funky_info = deduceScalarTypeInfo(FunkyVec).?;
    try std.testing.expectEqual(f32, funky_info.ScalarType);
    try std.testing.expectEqual(@as(usize, 4), funky_info.num_items);
}

pub fn hasAnyFlags(comptime T: type, a: T, b: T) bool {
    const Int = @typeInfo(T).@"struct".backing_integer.?;
    const a_int: Int = @bitCast(a);
    const b_int: Int = @bitCast(b);
    return a_int & b_int != 0;
}

pub fn offsetPtr(ptr: anytype, offset: usize) *anyopaque {
    return @ptrCast(@constCast(@as([*]const u8, @ptrCast(ptr)) + offset));
}

pub fn fastPow(comptime T: type, base: T, power: T) T {
    return @exp(power * @log(base));
}

pub fn extractFields(comptime slice: anytype, comptime field: EnumLiteral) []const @FieldType(std.meta.Child(@TypeOf(slice)), @tagName(field)) {
    return comptime b: {
        const Element = std.meta.Child(@TypeOf(slice));
        const Field = @FieldType(Element, @tagName(field));
        var values: []const Field = &.{};
        for (slice) |item| {
            values = values ++ @as([]const Field, &.{@field(item, @tagName(field))});
        }
        break :b values;
    };
}

pub fn MakeEnum(literals: []const EnumLiteral) type {
    const Tag = @Type(.{ .int = .{
        .bits = std.math.log2_int_ceil(usize, literals.len),
        .signedness = .unsigned,
    } });
    var fields: [literals.len]std.builtin.Type.EnumField = undefined;
    for (literals, 0..) |lit, i| {
        fields[i] = .{
            .name = @tagName(lit),
            .value = @as(Tag, @intCast(i)),
        };
    }
    return @Type(.{ .@"enum" = .{
        .decls = &.{},
        .is_exhaustive = true,
        .tag_type = Tag,
        .fields = &fields,
    } });
}

const TupleBuilder = struct {
    tuple: Any = .init(.{}),

    pub fn addItem(b: *TupleBuilder, item: anytype) void {
        b.tuple = .init(b.tuple.get() ++ .{item});
    }
    pub fn appendTuple(b: *TupleBuilder, tuple: anytype) void {
        b.tuple = .init(b.tuple.get() ++ tuple);
    }
};

fn sliceTuple(tuple: anytype, start_idx: usize, end_idx: usize) Any {
    var b: TupleBuilder = .{};
    for (start_idx..end_idx) |i| {
        b.addItem(tuple[i]);
    }
    return b.tuple;
}

pub fn sanitizeFieldChain(comptime field_chain: anytype) Any {
    var fields: TupleBuilder = .{};
    switch (@typeInfo(@TypeOf(field_chain))) {
        .enum_literal => fields.addItem(field_chain),
        .@"enum" => fields.addItem(field_chain),
        .int, .comptime_int => fields.addItem(@as(comptime_int, field_chain)),
        .@"struct" => |str| {
            if (str.is_tuple) {
                for (field_chain) |item| {
                    fields.appendTuple(sanitizeFieldChain(item).get());
                }
            }
        },
        .pointer => |ptr| {
            if (ptr.is_slice) {
                if (ptr.child == u8) {
                    @compileError("Fields must be decl literals, not strings.");
                }
                for (field_chain) |item| {
                    fields.appendTuple(sanitizeFieldChain(item).get());
                }
            }
        },
        .array => |_| {
            for (field_chain) |item| {
                fields.appendTuple(sanitizeFieldChain(item).get());
            }
        },
        else => fields.addItem(field_chain),
    }
    return fields.tuple;
}
