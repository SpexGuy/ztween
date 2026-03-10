const std = @import("std");
const c = @import("root").c;

var g_Allocator: *c.VkAllocationCallbacks = undefined;
var g_Instance: c.VkInstance = undefined;
var g_PhysicalDevice: c.VkPhysicalDevice = undefined;
var g_Device: c.VkDevice = undefined;
var g_QueueFamily: ?u32 = null;
var g_Queue: c.VkQueue = undefined;
var g_DebugReport: c.VkDebugReportCallbackEXT = undefined;
var g_PipelineCache: c.VkPipelineCache = undefined;
var g_DescriptorPool: c.VkDescriptorPool = undefined;

var g_MainWindowData: c.ImGui_ImplVulkanH_Window = undefined;
var g_MinImageCount: u32 = 2;
var g_SwapChainRebuild: bool = false;

var g_Window: ?*c.GLFWwindow = null;

const g_ApiVersion: u32 = c.VK_API_VERSION_1_2;

const required_layers = [_][*:0]const u8{
    //"VK_LAYER_KHRONOS_validation",
};

// T must be an optional. Returns the payload of the optional. ?T => T
fn NonNull(comptime T: type) type {
    return @typeInfo(T).optional.child;
}

fn get_vulkan_instance_func(comptime PFN: type, instance: c.VkInstance, name: [*c]const u8) NonNull(PFN) {
    const ptr: PFN = @ptrCast(c.glfwGetInstanceProcAddress(instance, name));
    return ptr orelse std.debug.panic("Couldn't fetch vulkan instance func: {s}", .{name});
}

fn get_vulkan_device_func(comptime PFN: type, device: c.VkDevice, name: [*c]const u8) NonNull(PFN) {
    const ptr: PFN = @ptrCast(vkGetDeviceProcAddr(device, name));
    return ptr orelse std.debug.panic("Couldn't fetch vulkan device func: {s}", .{name});
}

var vkEnumerateInstanceExtensionProperties: NonNull(c.PFN_vkEnumerateInstanceExtensionProperties) = undefined;
var vkEnumerateInstanceLayerProperties: NonNull(c.PFN_vkEnumerateInstanceLayerProperties) = undefined;
var vkEnumerateDeviceExtensionProperties: NonNull(c.PFN_vkEnumerateDeviceExtensionProperties) = undefined;
var vkCreateInstance: NonNull(c.PFN_vkCreateInstance) = undefined;

fn fetchGlobalVkFunctions() void {
    vkEnumerateInstanceExtensionProperties = get_vulkan_instance_func(c.PFN_vkEnumerateInstanceExtensionProperties, null, "vkEnumerateInstanceExtensionProperties");
    vkEnumerateInstanceLayerProperties = get_vulkan_instance_func(c.PFN_vkEnumerateInstanceLayerProperties, null, "vkEnumerateInstanceLayerProperties");
    vkEnumerateDeviceExtensionProperties = get_vulkan_instance_func(c.PFN_vkEnumerateDeviceExtensionProperties, null, "vkEnumerateDeviceExtensionProperties");
    vkCreateInstance = get_vulkan_instance_func(c.PFN_vkCreateInstance, null, "vkCreateInstance");
}

var vkGetDeviceProcAddr: NonNull(c.PFN_vkGetDeviceProcAddr) = undefined;
var vkGetPhysicalDeviceSurfaceSupportKHR: NonNull(c.PFN_vkGetPhysicalDeviceSurfaceSupportKHR) = undefined;
var vkCreateDebugReportCallbackEXT: NonNull(c.PFN_vkCreateDebugReportCallbackEXT) = undefined;
var vkDestroyDebugReportCallbackEXT: NonNull(c.PFN_vkDestroyDebugReportCallbackEXT) = undefined;
var vkGetPhysicalDeviceProperties: NonNull(c.PFN_vkGetPhysicalDeviceProperties) = undefined;
var vkEnumeratePhysicalDevices: NonNull(c.PFN_vkEnumeratePhysicalDevices) = undefined;
var vkGetPhysicalDeviceQueueFamilyProperties: NonNull(c.PFN_vkGetPhysicalDeviceQueueFamilyProperties) = undefined;
var vkCreateDevice: NonNull(c.PFN_vkCreateDevice) = undefined;
var vkDestroyInstance: NonNull(c.PFN_vkDestroyInstance) = undefined;

fn fetchInstanceVkFunctions(instance: c.VkInstance) void {
    vkGetDeviceProcAddr = get_vulkan_instance_func(c.PFN_vkGetDeviceProcAddr, instance, "vkGetDeviceProcAddr");
    vkGetPhysicalDeviceSurfaceSupportKHR = get_vulkan_instance_func(c.PFN_vkGetPhysicalDeviceSurfaceSupportKHR, instance, "vkGetPhysicalDeviceSurfaceSupportKHR");
    vkCreateDebugReportCallbackEXT = get_vulkan_instance_func(c.PFN_vkCreateDebugReportCallbackEXT, instance, "vkCreateDebugReportCallbackEXT");
    vkDestroyDebugReportCallbackEXT = get_vulkan_instance_func(c.PFN_vkDestroyDebugReportCallbackEXT, instance, "vkDestroyDebugReportCallbackEXT");
    vkGetPhysicalDeviceProperties = get_vulkan_instance_func(c.PFN_vkGetPhysicalDeviceProperties, instance, "vkGetPhysicalDeviceProperties");
    vkEnumeratePhysicalDevices = get_vulkan_instance_func(c.PFN_vkEnumeratePhysicalDevices, instance, "vkEnumeratePhysicalDevices");
    vkGetPhysicalDeviceQueueFamilyProperties = get_vulkan_instance_func(c.PFN_vkGetPhysicalDeviceQueueFamilyProperties, instance, "vkGetPhysicalDeviceQueueFamilyProperties");
    vkCreateDevice = get_vulkan_instance_func(c.PFN_vkCreateDevice, instance, "vkCreateDevice");
    vkDestroyInstance = get_vulkan_instance_func(c.PFN_vkDestroyInstance, instance, "vkDestroyInstance");
}

var vkAcquireNextImageKHR: NonNull(c.PFN_vkAcquireNextImageKHR) = undefined;
var vkWaitForFences: NonNull(c.PFN_vkWaitForFences) = undefined;
var vkResetFences: NonNull(c.PFN_vkResetFences) = undefined;
var vkGetDeviceQueue: NonNull(c.PFN_vkGetDeviceQueue) = undefined;
var vkCreateDescriptorPool: NonNull(c.PFN_vkCreateDescriptorPool) = undefined;
var vkCmdBeginRenderPass: NonNull(c.PFN_vkCmdBeginRenderPass) = undefined;
var vkCmdEndRenderPass: NonNull(c.PFN_vkCmdEndRenderPass) = undefined;
var vkEndCommandBuffer: NonNull(c.PFN_vkEndCommandBuffer) = undefined;
var vkQueueSubmit: NonNull(c.PFN_vkQueueSubmit) = undefined;
var vkResetCommandPool: NonNull(c.PFN_vkResetCommandPool) = undefined;
var vkBeginCommandBuffer: NonNull(c.PFN_vkBeginCommandBuffer) = undefined;
var vkQueuePresentKHR: NonNull(c.PFN_vkQueuePresentKHR) = undefined;
var vkDeviceWaitIdle: NonNull(c.PFN_vkDeviceWaitIdle) = undefined;
var vkDestroyDescriptorPool: NonNull(c.PFN_vkDestroyDescriptorPool) = undefined;
var vkDestroyDevice: NonNull(c.PFN_vkDestroyDevice) = undefined;

fn fetchDeviceVkFunctions(device: c.VkDevice) void {
    vkAcquireNextImageKHR = get_vulkan_device_func(c.PFN_vkAcquireNextImageKHR, device, "vkAcquireNextImageKHR");
    vkWaitForFences = get_vulkan_device_func(c.PFN_vkWaitForFences, device, "vkWaitForFences");
    vkResetFences = get_vulkan_device_func(c.PFN_vkResetFences, device, "vkResetFences");
    vkGetDeviceQueue = get_vulkan_device_func(c.PFN_vkGetDeviceQueue, device, "vkGetDeviceQueue");
    vkCreateDescriptorPool = get_vulkan_device_func(c.PFN_vkCreateDescriptorPool, device, "vkCreateDescriptorPool");
    vkCmdBeginRenderPass = get_vulkan_device_func(c.PFN_vkCmdBeginRenderPass, device, "vkCmdBeginRenderPass");
    vkCmdEndRenderPass = get_vulkan_device_func(c.PFN_vkCmdEndRenderPass, device, "vkCmdEndRenderPass");
    vkEndCommandBuffer = get_vulkan_device_func(c.PFN_vkEndCommandBuffer, device, "vkEndCommandBuffer");
    vkQueueSubmit = get_vulkan_device_func(c.PFN_vkQueueSubmit, device, "vkQueueSubmit");
    vkResetCommandPool = get_vulkan_device_func(c.PFN_vkResetCommandPool, device, "vkResetCommandPool");
    vkBeginCommandBuffer = get_vulkan_device_func(c.PFN_vkBeginCommandBuffer, device, "vkBeginCommandBuffer");
    vkQueuePresentKHR = get_vulkan_device_func(c.PFN_vkQueuePresentKHR, device, "vkQueuePresentKHR");
    vkDeviceWaitIdle = get_vulkan_device_func(c.PFN_vkDeviceWaitIdle, device, "vkDeviceWaitIdle");
    vkDestroyDescriptorPool = get_vulkan_device_func(c.PFN_vkDestroyDescriptorPool, device, "vkDestroyDescriptorPool");
    vkDestroyDevice = get_vulkan_device_func(c.PFN_vkDestroyDevice, device, "vkDestroyDevice");
}

fn loader(name: [*c]const u8, instance: ?*anyopaque) callconv(.c) ?*const fn () callconv(.c) void {
    return c.glfwGetInstanceProcAddress(@ptrCast(instance), name);
}

fn glfw_error_callback(err: c_int, description: [*c]const u8) callconv(.c) void {
    std.debug.print("GLFW Error {d}: {s}\n", .{ err, description });
}

fn check_vk_result(err: c.VkResult) callconv(.c) void {
    if (err == 0) return;
    std.debug.print("[vulkan] Error: VkResult = {d}\n", .{err});
    if (err < 0) std.process.exit(1);
}

fn debugReport(_: c.VkDebugReportFlagsEXT, objectType: c.VkDebugReportObjectTypeEXT, _: u64, _: usize, _: i32, _: ?*const u8, pMessage: ?[*:0]const u8, _: ?*anyopaque) callconv(.c) c.VkBool32 {
    std.debug.print("[vulkan] Debug report from ObjectType: {any}\nMessage: {s}\n\n", .{ objectType, pMessage orelse "No message available" });
    return c.VK_FALSE;
}

fn IsExtensionAvailable(properties: []const c.VkExtensionProperties, extension: []const u8) bool {
    for (0..properties.len) |i| {
        if (std.mem.eql(u8, &properties[i].extensionName, extension)) return true;
    } else return false;
}

fn IsLayerAvailable(layers: []const c.VkLayerProperties, layer: [*:0]const u8) bool {
    const span = std.mem.span(layer);
    for (0..layers.len) |i| {
        if (std.mem.eql(u8, layers[i].layerName[0..span.len], span)) return true;
    } else return false;
}

fn SetupVulkan_SelectPhysicalDevice(allocator: std.mem.Allocator) !c.VkPhysicalDevice {
    var gpu_count: u32 = undefined;
    var err = vkEnumeratePhysicalDevices(g_Instance, &gpu_count, null);
    check_vk_result(err);

    const gpus = try allocator.alloc(c.VkPhysicalDevice, gpu_count);
    err = vkEnumeratePhysicalDevices(g_Instance, &gpu_count, gpus.ptr);
    check_vk_result(err);

    for (gpus) |device| {
        var properties: c.VkPhysicalDeviceProperties = undefined;
        vkGetPhysicalDeviceProperties(device, &properties);
        if (properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) return device;
    }

    // Use first GPU (Integrated) is a Discrete one is not available.
    if (gpu_count > 0) return gpus[0];
    return error.NoPhysicalDeviceAvailable;
}

fn SetupVulkan(allocator: std.mem.Allocator, instance_extensions: *std.ArrayList([*:0]const u8)) !void {
    var err: c.VkResult = undefined;

    fetchGlobalVkFunctions();

    var app_info = c.VkApplicationInfo{};
    app_info.pApplicationName = "example_glfw_vulkan";
    app_info.applicationVersion = g_ApiVersion;
    app_info.pEngineName = "No Engine";
    app_info.engineVersion = g_ApiVersion;
    app_info.apiVersion = g_ApiVersion;

    // Setup the debug report callback
    var debug_report_ci = c.VkDebugReportCallbackCreateInfoEXT{};
    debug_report_ci.sType = c.VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT;
    debug_report_ci.flags = c.VK_DEBUG_REPORT_ERROR_BIT_EXT | c.VK_DEBUG_REPORT_WARNING_BIT_EXT | c.VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT;
    debug_report_ci.pfnCallback = debugReport;
    debug_report_ci.pUserData = null;

    // Create Vulkan Instance
    var create_info = c.VkInstanceCreateInfo{};
    create_info.sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    create_info.pApplicationInfo = &app_info;
    create_info.pNext = &debug_report_ci;

    // Enumerate available extensions
    var properties_count: u32 = undefined;
    _ = vkEnumerateInstanceExtensionProperties(null, &properties_count, null);
    const properties = try allocator.alloc(c.VkExtensionProperties, properties_count);
    err = vkEnumerateInstanceExtensionProperties(null, &properties_count, properties.ptr);
    check_vk_result(err);

    // Enable required extensions
    if (IsExtensionAvailable(properties[0..properties_count], c.VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME))
        try instance_extensions.append(allocator, c.VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME);

    // Enumerate available layers
    var layers_count: u32 = undefined;
    _ = vkEnumerateInstanceLayerProperties(&layers_count, null);
    const layers = try allocator.alloc(c.VkLayerProperties, layers_count);
    err = vkEnumerateInstanceLayerProperties(&layers_count, layers.ptr);
    check_vk_result(err);

    // Enable required layers
    for (required_layers) |layer| {
        if (!IsLayerAvailable(layers[0..layers_count], layer))
            return error.RequiredLayerNotAvailable;
    }

    // Enabling validation layers
    create_info.enabledLayerCount = required_layers.len;
    create_info.ppEnabledLayerNames = required_layers[0..].ptr;
    try instance_extensions.append(allocator, "VK_EXT_debug_report");

    // Create Vulkan Instance
    create_info.enabledExtensionCount = @intCast(instance_extensions.items.len);
    create_info.ppEnabledExtensionNames = instance_extensions.items.ptr;
    err = vkCreateInstance(&create_info, g_Allocator, &g_Instance);
    check_vk_result(err);

    fetchInstanceVkFunctions(g_Instance);

    err = vkCreateDebugReportCallbackEXT(g_Instance, &debug_report_ci, g_Allocator, &g_DebugReport);
    check_vk_result(err);

    // Select Physical Device (GPU)
    g_PhysicalDevice = try SetupVulkan_SelectPhysicalDevice(allocator);

    // Select graphics queue family
    var count: u32 = undefined;
    vkGetPhysicalDeviceQueueFamilyProperties(g_PhysicalDevice, &count, null);
    const queues = try allocator.alloc(c.VkQueueFamilyProperties, count);
    defer allocator.free(queues);
    vkGetPhysicalDeviceQueueFamilyProperties(g_PhysicalDevice, &count, queues.ptr);
    var i: u32 = 0;
    while (i < count) {
        if (queues[i].queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            g_QueueFamily = i;
            break;
        }
        i += 1;
    }

    // Create Logical Device (with 1 queue)
    var device_extensions = std.ArrayList([*:0]const u8){};
    try device_extensions.append(allocator, "VK_KHR_swapchain");

    // Enumerate physical device extension
    _ = vkEnumerateDeviceExtensionProperties(g_PhysicalDevice, null, &properties_count, null);
    const properties2 = try allocator.alloc(c.VkExtensionProperties, properties_count);
    _ = vkEnumerateDeviceExtensionProperties(g_PhysicalDevice, null, &properties_count, properties2.ptr);

    const queue_priority = [_]f32{1.0};
    var queue_info = [1]c.VkDeviceQueueCreateInfo{.{}};
    queue_info[0].sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queue_info[0].queueFamilyIndex = g_QueueFamily.?;
    queue_info[0].queueCount = 1;
    queue_info[0].pQueuePriorities = &queue_priority;
    var device_create_info = c.VkDeviceCreateInfo{};
    device_create_info.sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    device_create_info.queueCreateInfoCount = queue_info.len;
    device_create_info.pQueueCreateInfos = &queue_info;
    device_create_info.enabledLayerCount = required_layers.len;
    device_create_info.ppEnabledLayerNames = required_layers[0..].ptr;
    device_create_info.enabledExtensionCount = @intCast(device_extensions.items.len);
    device_create_info.ppEnabledExtensionNames = device_extensions.items.ptr;
    err = vkCreateDevice(g_PhysicalDevice, &device_create_info, g_Allocator, &g_Device);
    check_vk_result(err);

    fetchDeviceVkFunctions(g_Device);

    vkGetDeviceQueue(g_Device, g_QueueFamily.?, 0, &g_Queue);

    // Create Descriptor Pool
    // The example only requires a single combined image sampler descriptor for the font image and only uses one descriptor set (for that)
    // If you wish to load e.g. additional textures you may need to alter pools sizes.
    const pool_sizes = [_]c.VkDescriptorPoolSize{
        .{
            .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
        },
    };
    var pool_info = c.VkDescriptorPoolCreateInfo{};
    pool_info.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    pool_info.flags = c.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT;
    pool_info.maxSets = 1;
    pool_info.poolSizeCount = pool_sizes.len;
    pool_info.pPoolSizes = &pool_sizes;
    err = vkCreateDescriptorPool(g_Device, &pool_info, g_Allocator, &g_DescriptorPool);
    check_vk_result(err);
}

// All the ImGui_ImplVulkanH_XXX structures/functions are optional helpers used by the demo.
// Your real engine/app may not use them.
fn SetupVulkanWindow(wd: *c.ImGui_ImplVulkanH_Window, surface: c.VkSurfaceKHR, width: i32, height: i32) !void {
    // cimgui doesn't bind the constructor for ImGui_ImplVulkanH_Window,
    // so this is copied and manually translated from there.
    wd.* = .{};
    wd.PresentMode = ~@as(c_uint, 0);
    wd.AttachmentDesc.format = c.VK_FORMAT_UNDEFINED;
    wd.AttachmentDesc.samples = c.VK_SAMPLE_COUNT_1_BIT;
    wd.AttachmentDesc.loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR;
    wd.AttachmentDesc.storeOp = c.VK_ATTACHMENT_STORE_OP_STORE;
    wd.AttachmentDesc.stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    wd.AttachmentDesc.stencilStoreOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    wd.AttachmentDesc.initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED;
    wd.AttachmentDesc.finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

    wd.Surface = surface;

    // Check for WSI support
    var res: c.VkBool32 = undefined;
    _ = vkGetPhysicalDeviceSurfaceSupportKHR(g_PhysicalDevice, g_QueueFamily.?, wd.Surface, &res);
    if (res != c.VK_TRUE) return error.NoWSISupport;

    // Select Surface Format
    const requestSurfaceImageFormat = [_]c.VkFormat{ c.VK_FORMAT_B8G8R8A8_UNORM, c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_FORMAT_B8G8R8_UNORM, c.VK_FORMAT_R8G8B8_UNORM };
    const ptrRequestSurfaceImageFormat: [*]const c.VkFormat = &requestSurfaceImageFormat;
    const requestSurfaceColorSpace = c.VK_COLORSPACE_SRGB_NONLINEAR_KHR;
    wd.SurfaceFormat = c.cImGui_ImplVulkanH_SelectSurfaceFormat(g_PhysicalDevice, wd.Surface, ptrRequestSurfaceImageFormat, requestSurfaceImageFormat.len, requestSurfaceColorSpace);

    // Select Present Mode
    const present_modes = [_]c.VkPresentModeKHR{c.VK_PRESENT_MODE_FIFO_KHR};
    wd.PresentMode = c.cImGui_ImplVulkanH_SelectPresentMode(g_PhysicalDevice, wd.Surface, &present_modes[0], present_modes.len);

    // Create SwapChain, RenderPass, Framebuffer, etc.
    c.cImGui_ImplVulkanH_CreateOrResizeWindow(g_Instance, g_PhysicalDevice, g_Device, wd, g_QueueFamily.?, g_Allocator, width, height, g_MinImageCount, c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT);
}

fn CleanupVulkan() void {
    vkDestroyDescriptorPool(g_Device, g_DescriptorPool, g_Allocator);

    // Remove the debug report callback
    vkDestroyDebugReportCallbackEXT(g_Instance, g_DebugReport, g_Allocator);

    vkDestroyDevice(g_Device, g_Allocator);
    vkDestroyInstance(g_Instance, g_Allocator);
}

fn CleanupVulkanWindow() void {
    c.cImGui_ImplVulkanH_DestroyWindow(g_Instance, g_Device, &g_MainWindowData, g_Allocator);
}

fn FrameRender(wd: *c.ImGui_ImplVulkanH_Window, draw_data: *c.ImDrawData) void {
    var err: c.VkResult = undefined;

    var image_acquired_semaphore = wd.FrameSemaphores.Data[wd.SemaphoreIndex].ImageAcquiredSemaphore;
    var render_complete_semaphore = wd.FrameSemaphores.Data[wd.SemaphoreIndex].RenderCompleteSemaphore;
    err = vkAcquireNextImageKHR(g_Device, wd.Swapchain, std.math.maxInt(u64), image_acquired_semaphore, null, &wd.FrameIndex);
    if (err == c.VK_ERROR_OUT_OF_DATE_KHR or err == c.VK_SUBOPTIMAL_KHR) {
        g_SwapChainRebuild = true;
        return;
    }
    check_vk_result(err);

    var fd = &wd.Frames.Data[wd.FrameIndex];
    err = vkWaitForFences(g_Device, 1, &fd.Fence, c.VK_TRUE, std.math.maxInt(u64)); // wait indefinitely instead of periodically checking
    check_vk_result(err);

    {
        err = vkResetFences(g_Device, 1, &fd.Fence);
        check_vk_result(err);
        err = vkResetCommandPool(g_Device, fd.CommandPool, 0);
        check_vk_result(err);
        var info = c.VkCommandBufferBeginInfo{};
        info.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        info.flags |= c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        err = vkBeginCommandBuffer(fd.CommandBuffer, &info);
        check_vk_result(err);
    }
    {
        var info = c.VkRenderPassBeginInfo{};
        info.sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
        info.renderPass = wd.RenderPass;
        info.framebuffer = fd.Framebuffer;
        info.renderArea.extent.width = @intCast(wd.Width);
        info.renderArea.extent.height = @intCast(wd.Height);
        info.clearValueCount = 1;
        info.pClearValues = &wd.ClearValue;
        vkCmdBeginRenderPass(fd.CommandBuffer, &info, c.VK_SUBPASS_CONTENTS_INLINE);
    }

    // Record dear imgui primitives into command buffer
    c.cImGui_ImplVulkan_RenderDrawData(draw_data, fd.CommandBuffer);

    // Submit command buffer
    vkCmdEndRenderPass(fd.CommandBuffer);
    {
        var wait_stage: c.VkPipelineStageFlags = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        var info = c.VkSubmitInfo{};
        info.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        info.waitSemaphoreCount = 1;
        info.pWaitSemaphores = &image_acquired_semaphore;
        info.pWaitDstStageMask = &wait_stage;
        info.commandBufferCount = 1;
        info.pCommandBuffers = &fd.CommandBuffer;
        info.signalSemaphoreCount = 1;
        info.pSignalSemaphores = &render_complete_semaphore;

        err = vkEndCommandBuffer(fd.CommandBuffer);
        check_vk_result(err);
        err = vkQueueSubmit(g_Queue, 1, &info, fd.Fence);
        check_vk_result(err);
    }
}

fn FramePresent(wd: *c.ImGui_ImplVulkanH_Window) void {
    if (g_SwapChainRebuild) return;
    var render_complete_semaphore = wd.FrameSemaphores.Data[wd.SemaphoreIndex].RenderCompleteSemaphore;
    var info = c.VkPresentInfoKHR{};
    info.sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    info.waitSemaphoreCount = 1;
    info.pWaitSemaphores = &render_complete_semaphore;
    info.swapchainCount = 1;
    info.pSwapchains = &wd.Swapchain;
    info.pImageIndices = &wd.FrameIndex;
    const err = vkQueuePresentKHR(g_Queue, &info);
    if (err == c.VK_ERROR_OUT_OF_DATE_KHR or err == c.VK_SUBOPTIMAL_KHR) {
        g_SwapChainRebuild = true;
        return;
    }
    check_vk_result(err);
    wd.SemaphoreIndex = (wd.SemaphoreIndex + 1) % wd.SemaphoreCount; // Now we can use the next set of semaphores
}

pub fn setup(window_title: [*:0]const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    _ = c.glfwSetErrorCallback(glfw_error_callback);
    if (c.glfwInit() == 0) return error.glfwInitFailure;

    // Create window with Vulkan context
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    g_Window = c.glfwCreateWindow(1280, 720, window_title, null, null);
    if (c.glfwVulkanSupported() == 0) return error.VulkanNotSupported;

    var extensions = std.ArrayList([*:0]const u8){};
    var extensions_count: u32 = 0;
    const glfw_extensions = c.glfwGetRequiredInstanceExtensions(&extensions_count);
    for (0..extensions_count) |i| try extensions.append(allocator, std.mem.span(glfw_extensions[i]));
    try SetupVulkan(allocator, &extensions);

    // Create Window Surface
    var surface: c.VkSurfaceKHR = undefined;
    const err = c.glfwCreateWindowSurface(g_Instance, g_Window, g_Allocator, &surface);
    check_vk_result(err);

    if (!c.cImGui_ImplVulkan_LoadFunctions(g_ApiVersion, loader)) return error.ImGuiVulkanLoadFailure;

    // Create Framebuffers
    var w: i32 = undefined;
    var h: i32 = undefined;
    c.glfwGetFramebufferSize(g_Window, &w, &h);
    const wd = &g_MainWindowData;
    try SetupVulkanWindow(wd, surface, w, h);

    // Setup Dear ImGui context
    if (c.ImGui_CreateContext(null) == null) return error.ImGuiCreateContextFailure;
    const io = c.ImGui_GetIO(); // (void)io;
    io.*.ConfigFlags |= c.ImGuiConfigFlags_NavEnableKeyboard; // Enable Keyboard Controls
    io.*.ConfigFlags |= c.ImGuiConfigFlags_NavEnableGamepad; // Enable Gamepad Controls

    // Setup Dear ImGui style
    c.ImGui_StyleColorsDark(null);

    // Setup Platform/Renderer backends
    if (!c.cImGui_ImplGlfw_InitForVulkan(g_Window, true)) return error.ImGuiGlfwInitForVulkanFailure;
    var init_info = c.ImGui_ImplVulkan_InitInfo{};
    init_info.Instance = g_Instance;
    init_info.PhysicalDevice = g_PhysicalDevice;
    init_info.Device = g_Device;
    init_info.QueueFamily = g_QueueFamily.?;
    init_info.Queue = g_Queue;
    init_info.PipelineCache = g_PipelineCache;
    init_info.DescriptorPool = g_DescriptorPool;
    init_info.PipelineInfoMain.RenderPass = wd.RenderPass;
    init_info.PipelineInfoMain.Subpass = 0;
    init_info.PipelineInfoMain.MSAASamples = c.VK_SAMPLE_COUNT_1_BIT;
    init_info.MinImageCount = g_MinImageCount;
    init_info.ImageCount = wd.ImageCount;
    init_info.Allocator = g_Allocator;
    init_info.CheckVkResultFn = check_vk_result;
    if (!c.cImGui_ImplVulkan_Init(&init_info)) return error.ImGuiVulkanInitFailure;
}

pub fn teardown() void {
    const err = vkDeviceWaitIdle(g_Device);
    check_vk_result(err);
    c.cImGui_ImplVulkan_Shutdown();
    c.cImGui_ImplGlfw_Shutdown();
    c.ImGui_DestroyContext(null);

    CleanupVulkanWindow();
    CleanupVulkan();

    c.glfwDestroyWindow(g_Window);
    c.glfwTerminate();
}

pub fn should_close_window() bool {
    return c.glfwWindowShouldClose(g_Window) != 0;
}

pub fn poll_events() void {
    c.glfwPollEvents();
}

pub fn set_clear_color(color: [4]f32) void {
    g_MainWindowData.ClearValue.color.float32 = color;
}

pub fn begin_frame() void {
    // Resize swap chain?
    if (g_SwapChainRebuild) {
        var width: i32 = undefined;
        var height: i32 = undefined;
        c.glfwGetFramebufferSize(g_Window, &width, &height);
        if (width > 0 and height > 0) {
            c.cImGui_ImplVulkan_SetMinImageCount(g_MinImageCount);
            c.cImGui_ImplVulkanH_CreateOrResizeWindow(g_Instance, g_PhysicalDevice, g_Device, &g_MainWindowData, g_QueueFamily.?, g_Allocator, width, height, g_MinImageCount, c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT);
            g_MainWindowData.FrameIndex = 0;
            g_SwapChainRebuild = false;
        }
    }

    // Start the Dear ImGui frame
    c.cImGui_ImplVulkan_NewFrame();
    c.cImGui_ImplGlfw_NewFrame();
    c.ImGui_NewFrame();
}

pub fn end_frame() void {
    // Rendering
    c.ImGui_Render();
    const draw_data = c.ImGui_GetDrawData();
    const is_minimized = (draw_data.*.DisplaySize.x <= 0.0 or draw_data.*.DisplaySize.y <= 0.0);
    if (!is_minimized) {
        FrameRender(&g_MainWindowData, draw_data);
        FramePresent(&g_MainWindowData);
    }
}
