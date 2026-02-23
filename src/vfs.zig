const fs = @import("fs.zig");
const fuse = @import("fuse.zig");
const log = @import("log.zig");
const virtio_fs_driver = @import("drivers/virtio/fs.zig");

pub const VfsFile = struct {
    backend: Backend,
    pos: u64 = 0,

    const Backend = union(enum) {
        mem_file: MemFileBackend,
        virtio_file: VirtioFileBackend,
    };

    const MemFileBackend = struct {
        inner: *fs.RegularFile,
    };

    const VirtioFileBackend = struct {
        nodeid: u64,
        fh: u64,
        file_size: u64,
    };

    const Self = @This();

    pub fn read(self: *Self, buffer: []u8) error{ FdFull, Failed, Again }!usize {
        switch (self.backend) {
            .mem_file => |*mf| {
                const data = mf.inner.data;
                const pos = @as(usize, @intCast(self.pos));
                const nread = @min(buffer.len, data.len - pos);
                @memcpy(buffer[0..nread], data[pos..][0..nread]);
                self.pos += @as(u64, @intCast(nread));
                return nread;
            },
            .virtio_file => |*vf| {
                const dev = virtio_fs_driver.virtio_fs orelse return 0;
                const nread = dev.fuseRead(vf.nodeid, vf.fh, self.pos, @as(u32, @intCast(@min(buffer.len, 65536 - 80))), buffer) orelse return 0;
                self.pos += @as(u64, @intCast(nread));
                return nread;
            },
        }
    }

    pub fn close(self: *Self) void {
        switch (self.backend) {
            .mem_file => {},
            .virtio_file => |*vf| {
                const dev = virtio_fs_driver.virtio_fs orelse return;
                dev.fuseRelease(vf.nodeid, vf.fh, false);
            },
        }
    }

    pub fn size(self: *const Self) u64 {
        return switch (self.backend) {
            .mem_file => |*mf| @as(u64, @intCast(mf.inner.data.len)),
            .virtio_file => |*vf| vf.file_size,
        };
    }

    pub fn bytesCanRead(self: *Self) usize {
        switch (self.backend) {
            .mem_file => |*mf| {
                const pos = @as(usize, @intCast(self.pos));
                return mf.inner.data.len - pos;
            },
            .virtio_file => |*vf| {
                const pos = self.pos;
                if (pos >= vf.file_size) return 0;
                return @as(usize, @intCast(vf.file_size - pos));
            },
        }
    }
};

pub const VfsDir = struct {
    backend: Backend,
    name: []const u8,

    const Backend = union(enum) {
        mem_dir: MemDirBackend,
        virtio_dir: VirtioDirBackend,
    };

    const MemDirBackend = struct {
        dir: fs.Directory,
    };

    const VirtioDirBackend = struct {
        nodeid: u64,
    };

    const Self = @This();

    pub fn openFile(self: *Self, path: []const u8) ?VfsFile {
        switch (self.backend) {
            .mem_dir => |*md| {
                var dir = md.dir;
                const regular_file = dir.getFileByName(path) orelse return null;
                return VfsFile{
                    .backend = .{ .mem_file = .{ .inner = regular_file } },
                    .pos = 0,
                };
            },
            .virtio_dir => |*vd| {
                return openVirtioFile(vd.nodeid, path);
            },
        }
    }
};

fn openVirtioFile(parent_nodeid: u64, path: []const u8) ?VfsFile {
    const dev = virtio_fs_driver.virtio_fs orelse return null;

    // Walk path components separated by '/'
    var current_nodeid = parent_nodeid;
    var remaining = path;

    // Strip leading '/' if present
    if (remaining.len > 0 and remaining[0] == '/') {
        remaining = remaining[1..];
    }

    while (remaining.len > 0) {
        // Find next path separator
        var sep_idx: usize = 0;
        while (sep_idx < remaining.len and remaining[sep_idx] != '/') : (sep_idx += 1) {}

        const component = remaining[0..sep_idx];
        if (component.len == 0) {
            remaining = if (sep_idx < remaining.len) remaining[sep_idx + 1 ..] else remaining[remaining.len..];
            continue;
        }

        const is_last = (sep_idx >= remaining.len) or (sep_idx == remaining.len - 1);

        const entry = dev.fuseLookup(current_nodeid, component) orelse return null;
        const attr = entry.attr;

        if (is_last) {
            if (!attr.isRegular()) return null;

            const open_out = dev.fuseOpen(entry.nodeid, false) orelse return null;
            return VfsFile{
                .backend = .{ .virtio_file = .{
                    .nodeid = entry.nodeid,
                    .fh = open_out.fh,
                    .file_size = attr.size,
                } },
                .pos = 0,
            };
        }

        if (!attr.isDir()) return null;
        current_nodeid = entry.nodeid;
        remaining = remaining[sep_idx + 1 ..];
    }

    return null;
}

var virtio_fs_available: bool = false;

pub fn isVirtioFsAvailable() bool {
    return virtio_fs_available;
}

pub fn init() void {
    virtio_fs_available = virtio_fs_driver.init();

    fs.init();

    log.debug.printf("vfs: initialized (virtio-fs={any})\n", .{virtio_fs_available});
}

pub fn makeRootDir() VfsDir {
    if (virtio_fs_available) {
        return VfsDir{
            .backend = .{ .virtio_dir = .{ .nodeid = fuse.FUSE_ROOT_ID } },
            .name = "/",
        };
    }

    if (fs.num_dirs > 0) {
        return VfsDir{
            .backend = .{ .mem_dir = .{ .dir = fs.dirs[0] } },
            .name = fs.dirs[0].name,
        };
    }

    return VfsDir{
        .backend = .{ .mem_dir = .{ .dir = fs.Directory{ .name = @constCast(&[_]u8{ '.', '/' }) } } },
        .name = "./",
    };
}
