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
pub inline fn callMember(lhs: anytype, memberFunc: EnumLiteral, params: anytype) void {
    const LhsType = @TypeOf(lhs);
    const lhs_ti = @typeInfo(LhsType);
    const ObjectType = if (lhs_ti == .pointer) lhs_ti.pointer.child else LhsType;
    const function = @field(ObjectType, @tagName(memberFunc));
    const func_info = @typeInfo(@TypeOf(function));
    const self_param = func_info.@"fn".params[0];
    if (self_param.type) |SelfParam| {
        const self_param_info = @typeInfo(SelfParam);
        if ((self_param_info == .pointer) == (lhs_ti == .pointer)) {
            @call(.auto, function, .{lhs} ++ params);
        } else if (self_param_info == .pointer) {
            @call(.auto, function, .{&lhs} ++ params);
        } else {
            @call(.auto, function, .{lhs.*} ++ params);
        }
    } else {
        @call(.auto, function, .{lhs} ++ params);
    }
}

// Oof
pub fn erasePtr(ptr: anytype) ?*anyopaque {
    if (@TypeOf(ptr) == @TypeOf(null)) {
        return null;
    } else if (@TypeOf(ptr) == @TypeOf(undefined)) {
        return undefined;
    } else {
        return @ptrCast(@constCast(ptr));
    }
}

// // Oof
// const ErasedPointer = struct {
//     erased: ?*anyopaque,

//     pub fn init(ptr: anytype) ErasedPointer {
//         if (@TypeOf(ptr) == @TypeOf(null)) {
//             return .{ .erased = null };
//         } else if (@TypeOf(ptr) == @TypeOf(undefined)) {
//             return .{ .erased = undefined };
//         } else {
//             return .{ .erased = @constCast(@ptrCast(ptr)) };
//         }
//     }

//     pub fn get(ptr: ErasedPointer, comptime PtrType: type) PtrType {
//         if (PtrType == @TypeOf(null)) {
//             return null;
//         } else if (PtrType == @TypeOf(undefined)) {
//             return undefined;
//         } else {
//             return @ptrCast(@alignCast(ptr.erased));
//         }
//     }

// };

pub const Callback = struct {
    object: ?*anyopaque,
    callback: ?*const fn (?*anyopaque) void,

    pub const none: Callback = .{ .object = undefined, .callback = null };

    pub fn bindNoParams(comptime function: fn () void) Callback {
        const Wrap = struct {
            fn callbackBindNoArgs(ptr: ?*anyopaque) void {
                _ = ptr;
                function();
            }
        };
        return .{ .object = undefined, .callback = Wrap.callbackBindNoArgs };
    }

    pub fn bind(comptime function: anytype, raw_ptr: anytype) Callback {
        const ParamType = @TypeOf(raw_ptr);
        const Wrap = struct {
            fn callbackBindWrapper(ptr: ?*anyopaque) void {
                if (ParamType == @TypeOf(null)) {
                    function(null);
                } else if (ParamType == @TypeOf(undefined)) {
                    function(undefined);
                } else {
                    function(@as(ParamType, @ptrCast(@alignCast(ptr))));
                }
            }
        };
        return .{ .object = erasePtr(raw_ptr), .callback = Wrap.callbackBindWrapper };
    }

    pub fn bindMember(objPtr: anytype, functionName: EnumLiteral) Callback {
        const ptr = if (@typeInfo(@TypeOf(objPtr)) == .optional or @TypeOf(objPtr) == @TypeOf(null)) blk: {
            if (objPtr == null) {
                return none;
            }
            break :blk objPtr.?;
        } else objPtr;
        const PtrType = @TypeOf(ptr);
        const pti = @typeInfo(PtrType);
        if (pti != .pointer or pti.pointer.size != .one) {
            @compileError("Cannot bind member function for non-pointer type " ++ @typeName(PtrType));
        }
        if (!@hasDecl(pti.pointer.child, @tagName(functionName))) {
            @compileError("Type " ++ @typeName(pti.pointer.child) ++ " has no member function " ++ @tagName(functionName));
        }

        const Wrap = struct {
            fn callbackMemberWrapper(inner_ptr: ?*anyopaque) void {
                callMember(@as(PtrType, @ptrCast(@alignCast(inner_ptr.?))), functionName, .{});
            }
        };

        return .{ .object = erasePtr(ptr), .callback = Wrap.callbackMemberWrapper };
    }

    pub fn call(cb: Callback) void {
        if (cb.callback) |func| {
            func(cb.object);
        }
    }
};

test "Callback" {
    const TestObj = struct {
        const TestObj = @This();
        var global_count: u32 = 0;

        count: u32 = 0,

        fn increment(self: *TestObj) void {
            self.count +%= 1;
        }
        fn decrement(self: *TestObj) void {
            self.count -%= 1;
        }

        fn optional_increment(o: ?*TestObj) void {
            if (o) |to| {
                to.increment();
            } else {
                static_increment();
            }
        }

        fn static_increment() void {
            global_count += 1;
        }
    };

    TestObj.global_count = 0;
    var to: TestObj = .{};

    const cb_incr: Callback = .bindMember(&to, .increment);
    const cb_decr: Callback = .bindMember(@as(?*TestObj, &to), .decrement);
    const cb_null: Callback = .bindMember(@as(?*TestObj, null), .decrement);
    const cb_null_2: Callback = .none;
    const cb_static_incr: Callback = .bindNoParams(TestObj.static_increment);
    const cb_opt_static: Callback = .bind(TestObj.optional_increment, @as(?*TestObj, null));
    const cb_opt_to: Callback = .bind(TestObj.optional_increment, @as(?*TestObj, &to));
    const cb_opt_static_2: Callback = .bind(TestObj.optional_increment, null);
    const cb_opt_to_2: Callback = .bind(TestObj.optional_increment, &to);

    try std.testing.expectEqual(@as(u32, 0), to.count);
    try std.testing.expectEqual(@as(u32, 0), TestObj.global_count);
    cb_incr.call();
    try std.testing.expectEqual(@as(u32, 1), to.count);
    cb_incr.call();
    try std.testing.expectEqual(@as(u32, 2), to.count);
    try std.testing.expectEqual(@as(u32, 0), TestObj.global_count);
    cb_decr.call();
    try std.testing.expectEqual(@as(u32, 1), to.count);
    try std.testing.expectEqual(@as(u32, 0), TestObj.global_count);
    cb_null.call();
    try std.testing.expectEqual(@as(u32, 1), to.count);
    try std.testing.expectEqual(@as(u32, 0), TestObj.global_count);
    cb_null_2.call();
    try std.testing.expectEqual(@as(u32, 1), to.count);
    try std.testing.expectEqual(@as(u32, 0), TestObj.global_count);
    cb_static_incr.call();
    try std.testing.expectEqual(@as(u32, 1), to.count);
    try std.testing.expectEqual(@as(u32, 1), TestObj.global_count);
    cb_opt_static.call();
    try std.testing.expectEqual(@as(u32, 1), to.count);
    try std.testing.expectEqual(@as(u32, 2), TestObj.global_count);
    cb_opt_to.call();
    try std.testing.expectEqual(@as(u32, 2), to.count);
    try std.testing.expectEqual(@as(u32, 2), TestObj.global_count);
    cb_opt_static_2.call();
    try std.testing.expectEqual(@as(u32, 2), to.count);
    try std.testing.expectEqual(@as(u32, 3), TestObj.global_count);
    cb_opt_to_2.call();
    try std.testing.expectEqual(@as(u32, 3), to.count);
    try std.testing.expectEqual(@as(u32, 3), TestObj.global_count);
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
    }
    return fields.tuple;
}
