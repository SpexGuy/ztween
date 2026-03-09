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

pub fn main() !void {
    try render.setup("tweez example");
    defer render.teardown();

    render.set_clear_color(.{ 0.2, 0.2, 0.2, 1.0 });

    var show_imgui_demo: bool = true;

    var abs_time = c.glfwGetTime();
    var delta_time: f32 = 1.0 / 60.0;

    while (true) {
        render.poll_events();
        if (render.should_close_window()) break;
        render.begin_frame();

        if (show_imgui_demo) c.ImGui_ShowDemoWindow(&show_imgui_demo);

        render.end_frame();

        const new_time = c.glfwGetTime();
        delta_time = @floatCast(new_time - abs_time);
        abs_time = new_time;
    }

    defer assert(gpa.deinit() == .ok);
    var mgr: tw.TweenManager = .init(.init(gpa.allocator()));
    try doTest(&mgr);
    std.debug.print("Run succeeded!", .{});
}

fn doTest(mgr: *tw.TweenManager) !void {
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
