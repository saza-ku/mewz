const common = @import("common.zig");
const heap = @import("../../heap.zig");
const interrupt = @import("../../interrupt.zig");
const log = @import("../../log.zig");
const mem = @import("../../mem.zig");
const pci = @import("../../pci.zig");
const fuse = @import("fuse.zig");

const VIRTIO_FS_F_VERSION_1: u64 = 1 << 32;
const VIRTIO_FS_F_NOTIFY_ON_RELEASE: u64 = 1 << 0;

const VirtioFsConfig = extern struct {
    tag: [36]u8,
    num_request_queues: u32,
};

const VirtioFsQueue = enum(u16) {
    hiprio = 0,
    request = 1,
};

const VirtioFs = struct {
    virtio: common.Virtio(VirtioFsConfig),
    tag: []u8,
    request_buffer: []u8,

    const Self = @This();
    const REQ_BUFFER_SIZE: usize = 4096;

    fn new(virtio: common.Virtio(VirtioFsConfig)) !Self {
        var tag_len: usize = 0;
        while (tag_len < virtio.transport.device_config.tag.len) : (tag_len += 1) {
            if (virtio.transport.device_config.tag[tag_len] == 0) {
                break;
            }
        }

        // Allocate request buffer
        const req_buffer = mem.boottime_allocator.?.alloc(u8, REQ_BUFFER_SIZE) catch {
            return error.OutOfMemory;
        };

        return Self{
            .virtio = virtio,
            .tag = virtio.transport.device_config.tag[0..tag_len],
            .request_buffer = req_buffer,
        };
    }

    pub fn sendFuseRequest(self: *Self, in_header: *fuse.FuseInHeader, in_data: ?[]const u8) ![]u8 {
        // Setup request in the buffer
        @memcpy(self.request_buffer[0..@sizeOf(fuse.FuseInHeader)], @as([*]const u8, @ptrCast(in_header)));

        var total_len = @sizeOf(fuse.FuseInHeader);
        if (in_data) |data| {
            @memcpy(self.request_buffer[total_len..][0..data.len], data.ptr, data.len);
            total_len += data.len;
        }

        // Add request to virtqueue
        const req_queue = @as(u16, @intFromEnum(VirtioFsQueue.request));
        const desc_chain = self.virtio.transport.allocDescriptorChain(req_queue, 2) catch {
            return error.NoDescriptorsAvailable;
        };

        // Add request buffer
        _ = try self.virtio.transport.addDescriptor(req_queue, desc_chain, self.request_buffer[0..total_len], true);

        // Add response buffer (rest of the request buffer)
        const resp_desc = try self.virtio.transport.addDescriptor(req_queue, desc_chain, self.request_buffer[total_len..], false);

        // Notify device
        self.virtio.transport.submitDescriptorChain(req_queue, desc_chain);
        self.virtio.transport.notifyQueue(req_queue);

        // Wait for response
        while (!self.virtio.transport.isDescriptorUsed(req_queue, resp_desc)) {
            @import("../../x64.zig").pause();
        }

        // Get response length
        const resp_header = @as(*fuse.FuseOutHeader, @ptrCast(@alignCast(self.request_buffer.ptr)));
        if (resp_header.err < 0) {
            return error.FuseError;
        }

        return self.request_buffer[0..resp_header.len];
    }
};

pub var virtio_fs: ?*VirtioFs = null;

fn handleIrq(frame: *interrupt.InterruptFrame) void {
    _ = frame;
    if (virtio_fs) |fs| {
        const status = fs.virtio.transport.readIsr();
        if (status.isQueue()) {
            // TODO: Handle queue notifications
        }
    }
}

pub fn init() void {
    var pci_dev = find: {
        for (pci.devices) |d| {
            const dev = d orelse continue;
            if (dev.config.vendor_id == 0x1af4 and dev.config.device_id == 0x1043) {
                break :find dev;
            }
        }
        log.debug.print("virtio-fs device not found\n");
        return;
    };

    const features = VIRTIO_FS_F_VERSION_1;
    const virtio = common.Virtio(VirtioFsConfig).new(&pci_dev, features, 1, mem.boottime_allocator.?) catch {
        log.fatal.print("failed to initialize virtio-fs\n");
        return;
    };

    const fs_slice = mem.boottime_allocator.?.alloc(VirtioFs, 1) catch {
        log.fatal.print("failed to allocate virtio-fs\n");
        return;
    };

    virtio_fs = @as(*VirtioFs, @ptrCast(fs_slice.ptr));
    virtio_fs.?.* = VirtioFs.new(virtio) catch {
        log.fatal.print("failed to create virtio-fs\n");
        return;
    };

    interrupt.registerIrq(virtio_fs.?.virtio.transport.pci_dev.config.interrupt_line, handleIrq);
    log.info.printf("virtio-fs initialized with tag: {s}\n", .{virtio_fs.?.tag});
}
