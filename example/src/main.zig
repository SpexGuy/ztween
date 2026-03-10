const std = @import("std");
const render = @import("render.zig");

const assert = std.debug.assert;

pub const c = @cImport({
    @cDefine("ZIG_TRANSLATE_C", "1");
    @cDefine("GLFW_INCLUDE_VULKAN", "1");
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cInclude("GLFW/glfw3.h");
    @cInclude("dcimgui.h");
    @cInclude("dcimgui_internal.h");
    @cInclude("backends/dcimgui_impl_glfw.h");
    @cInclude("backends/dcimgui_impl_vulkan.h");
});

const tweez = @import("ztween");
pub const tw = tweez.TweenLibrary(.init(.{}));

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
var mgr: tw.TweenManager = .init(.init(gpa.allocator()));

var tween_funcs: struct {
    linear: f32 = 0,
    quad_in: f32 = 0,
    cubic_in: f32 = 0,
    quartic_in: f32 = 0,
    quintic_in: f32 = 0,
    sine_in: f32 = 0,
    expo_in: f32 = 0,
    circ_in: f32 = 0,
    bounce_in: f32 = 0,
    quad_out: f32 = 0,
    cubic_out: f32 = 0,
    quartic_out: f32 = 0,
    quintic_out: f32 = 0,
    sine_out: f32 = 0,
    expo_out: f32 = 0,
    circ_out: f32 = 0,
    bounce_out: f32 = 0,
    quad_inout: f32 = 0,
    cubic_inout: f32 = 0,
    quartic_inout: f32 = 0,
    quintic_inout: f32 = 0,
    sine_inout: f32 = 0,
    expo_inout: f32 = 0,
    circ_inout: f32 = 0,
    bounce_inout: f32 = 0,
} = .{};

fn callbackResetTweenFuncs(_: *tw.TweenManager, _: tw.TweenId, flags: tw.CallbackFlags) void {
    if (flags.start) {
        tween_funcs = .{};
    }
}

fn setupGlobalTweens() !void {
    const loop_duration: f32 = 2.0;

    // Set up each property of tween_funcs to be tweened with the matching ease, in parallel.
    const parallel_group = mgr.parallel();
    inline for (tw.config.eases) |ease| {
        _ = parallel_group.add(
            mgr.to(&tween_funcs, ease[0], 1, loop_duration)
                .ease(ease[0]),
        );
    }

    // The whole animation will be a sequence
    try mgr.sequence()
        // Wait 2 seconds before running the sequence the first time
        .delay(2)
        // Use a callback to reset the values each time the sequence restarts
        .callback(.bindStatic(callbackResetTweenFuncs), .{ .start = true })
        // Wait 0.5 seconds to let the viewer get used to the sliders being on the left
        .add(mgr.wait(0.5))
        // Run the field tweens in parallel
        .add(parallel_group)
        // Then wait 0.5 seconds in this final state and do it all again, forever!
        .repeat(tw.infinite, 0.5, false)
        // Finally, submit the sequence for execution.
        .submit();
}

fn drawTweenExampleWindow() void {
    if (c.ImGui_Begin("tween example", null, 0)) {
        inline for (comptime std.meta.fieldNames(@TypeOf(tween_funcs))) |field| {
            _ = c.ImGui_SliderFloat(field, &@field(tween_funcs, field), 0.0, 1.0);
        }

    }
    c.ImGui_End();
}

pub fn main() !void {
    try render.setup("tweez example");
    defer render.teardown();

    render.set_clear_color(.{ 0.2, 0.2, 0.2, 1.0 });

    var show_imgui_demo: bool = true;

    var abs_time = c.glfwGetTime();
    var raw_delta_time: f32 = 1.0 / 60.0;

    try setupGlobalTweens();

    while (true) {
        const delta_time = @min(raw_delta_time, 3.0 / 60.0);

        render.poll_events();
        if (render.should_close_window()) break;
        render.begin_frame();

        mgr.update(delta_time);

        if (show_imgui_demo) c.ImGui_ShowDemoWindow(&show_imgui_demo);

        drawTweenExampleWindow();

        render.end_frame();

        const new_time = c.glfwGetTime();
        raw_delta_time = @floatCast(new_time - abs_time);
        abs_time = new_time;
    }

    mgr.deinit();
    assert(gpa.deinit() == .ok);
}

fn doTest() !void {
    //const LinearColor = packed struct (u32) { r: u11, g: u11, b: u10 };
    const Vec3 = struct { x: f32, y: f32, z: f32 };
    const Color = struct { r: u8, g: u8, b: u8, a: u8 };

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
