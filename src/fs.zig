const log = @import("log.zig");
const stream = @import("stream.zig");
const options = @import("options");
const std = @import("std");
const heap = @import("heap.zig");
const virtio_fs = @import("drivers/virtio/fs.zig");
const fuse = @import("drivers/virtio/fuse.zig");

const Stream = stream.Stream;
const FILES_MAX: usize = 200;

// Filesystem types
pub const FsType = enum {
    tarfs,
    virtio_fs,
};

// Current active filesystem type
var active_fs_type: FsType = .tarfs;

// TarFS specific structures and variables
extern var _binary_build_disk_tar_start: [*]u8;
pub var files: [FILES_MAX]RegularFile = undefined;
pub var dirs: [FILES_MAX]Directory = undefined;

const TarHeader = extern struct {
    name: [100]u8,
    mode: [8]u8,
    uid: [8]u8,
    gid: [8]u8,
    size: [12]u8,
    mtime: [12]u8,
    checksum: [8]u8,
    typeflag: u8,
    linkname: [100]u8,
    magic: [6]u8,
    version: [2]u8,
    uname: [32]u8,
    gname: [32]u8,
    devmajor: [8]u8,
    devminor: [8]u8,
    prefix: [155]u8,
    padding: [12]u8,
    // Flexible array member pointing to the data following the header
};

pub const RegularFile = struct {
    name: []u8,
    data: []u8,
    // Add virtio-fs specific fields
    nodeid: ?u64 = null,
};

pub const OpenedFile = struct {
    inner: *RegularFile,
    pos: usize = 0,
    // Add virtio-fs specific fields
    fh: ?u64 = null,

    const Self = @This();
    const Error = error{Failed};

    pub fn read(self: *Self, buffer: []u8) Stream.Error!usize {
        if (active_fs_type == .virtio_fs and self.inner.nodeid != null) {
            const fs_dev = virtio_fs.virtio_fs orelse return error.Failed;

            var in_header = fuse.FuseInHeader{
                .len = @sizeOf(fuse.FuseInHeader) + @sizeOf(u64) * 2,
                .opcode = fuse.FUSE_READ,
                .unique = 2, // TODO: Generate unique IDs
                .nodeid = self.inner.nodeid.?,
                .uid = 0,
                .gid = 0,
                .pid = 0,
                .padding = 0,
            };

            var read_in = struct {
                fh: u64,
                offset: u64,
                size: u32,
                _padding: u32,
            }{
                .fh = self.fh.?,
                .offset = self.pos,
                .size = @as(u32, @intCast(@min(buffer.len, 4096))),
                ._padding = 0,
            };

            const response = fs_dev.sendFuseRequest(&in_header, std.mem.asBytes(&read_in)) catch |err| {
                log.err.printf("Failed to send FUSE_READ request: {}\n", .{err});
                return error.Failed;
            };

            const out_header = @as(*fuse.FuseOutHeader, @ptrCast(@alignCast(response.ptr)));
            if (out_header.err < 0) {
                return error.Failed;
            }

            const data_len = response.len - @sizeOf(fuse.FuseOutHeader);
            @memcpy(buffer[0..data_len], response[@sizeOf(fuse.FuseOutHeader)..][0..data_len]);
            self.pos += data_len;
            return data_len;
        }

        const nread = @min(buffer.len, self.inner.data.len - self.pos);
        @memcpy(buffer[0..nread], self.inner.data[self.pos..][0..nread]);
        self.pos = self.pos + nread;
        return nread;
    }

    pub fn write(self: *Self, buffer: []const u8) Stream.Error!usize {
        if (active_fs_type == .virtio_fs and self.inner.nodeid != null) {
            const fs_dev = virtio_fs.virtio_fs orelse return error.Failed;

            const len = @sizeOf(fuse.FuseInHeader) + @sizeOf(u64) * 2 + buffer.len;
            const len_u32: u32 = @intCast(len);

            var in_header = fuse.FuseInHeader{
                .len = len_u32,
                .opcode = fuse.FUSE_WRITE,
                .unique = 3,
                .nodeid = self.inner.nodeid.?,
                .uid = 0,
                .gid = 0,
                .pid = 0,
                .padding = 0,
            };

            var write_in = struct {
                fh: u64,
                offset: u64,
                size: u32,
                flags: u32,
            }{
                .fh = self.fh.?,
                .offset = self.pos,
                .size = @as(u32, @intCast(buffer.len)),
                .flags = 0,
            };

            // Concatenate write_in and buffer
            var write_data = heap.runtime_allocator.alloc(u8, @sizeOf(@TypeOf(write_in)) + buffer.len) catch return error.Failed;
            defer heap.runtime_allocator.free(write_data);

            @memcpy(write_data[0..@sizeOf(@TypeOf(write_in))], std.mem.asBytes(&write_in));
            @memcpy(write_data[@sizeOf(@TypeOf(write_in))..], buffer);

            const response = fs_dev.sendFuseRequest(&in_header, write_data) catch |err| {
                log.err.printf("Failed to send FUSE_WRITE request: {}\n", .{err});
                return error.Failed;
            };

            const out_header = @as(*fuse.FuseOutHeader, @ptrCast(@alignCast(response.ptr)));
            if (out_header.err < 0) {
                return error.Failed;
            }

            const write_size = @as(*u32, @ptrCast(@alignCast(&response[@sizeOf(fuse.FuseOutHeader)])))[0];
            self.pos += write_size;
            return write_size;
        }

        return error.Failed; // TarFS is read-only
    }
};

pub const Directory = struct {
    name: []u8,
    nodeid: ?u64 = null,

    const Self = @This();
    const Error = error{Failed};

    pub fn getFileByName(self: *Self, file_name: []const u8) ?*RegularFile {
        if (active_fs_type == .virtio_fs and self.nodeid != null) {
            const fs_dev = virtio_fs.virtio_fs orelse return null;

            const len = @sizeOf(fuse.FuseInHeader) + file_name.len;
            const len_u32: u32 = @intCast(len);

            var in_header = fuse.FuseInHeader{
                .len = len_u32,
                .opcode = fuse.FUSE_LOOKUP,
                .unique = 4,
                .nodeid = self.nodeid.?,
                .uid = 0,
                .gid = 0,
                .pid = 0,
                .padding = 0,
            };

            const response = fs_dev.sendFuseRequest(&in_header, file_name) catch |err| {
                log.err.printf("Failed to send FUSE_LOOKUP request: {}\n", .{err});
                return null;
            };

            const out_header = @as(*fuse.FuseOutHeader, @ptrCast(@alignCast(response.ptr)));
            if (out_header.err < 0) {
                return null;
            }

            // Parse entry response
            const entry = @as(*fuse.FuseEntryOut, @ptrCast(@alignCast(&response[@sizeOf(fuse.FuseOutHeader)])));

            // Create new RegularFile entry
            for (&files) |*file| {
                if (file.name.len == 0) {
                    // Found empty slot
                    const full_name = heap.runtime_allocator.alloc(u8, self.name.len + file_name.len) catch return null;
                    @memcpy(full_name[0..self.name.len], self.name);
                    @memcpy(full_name[self.name.len..], file_name);
                    file.* = RegularFile{
                        .name = full_name,
                        .data = &[_]u8{}, // Empty data for virtio-fs files
                        .nodeid = entry.nodeid,
                    };
                    return file;
                }
            }
            return null;
        }

        // Existing TarFS implementation
        for (&files) |*file| {
            if (file.name.len != self.name.len + file_name.len) {
                continue;
            }
            if (std.mem.eql(u8, file.name[0..self.name.len], self.name) and
                std.mem.eql(u8, file.name[self.name.len..], file_name))
            {
                return file;
            }
        }
        return null;
    }

    pub fn readdir(self: *Self, offset: u64) ?[]const DirEntry {
        if (active_fs_type == .virtio_fs and self.nodeid != null) {
            const fs_dev = virtio_fs.virtio_fs orelse return null;

            var in_header = fuse.FuseInHeader{
                .len = @sizeOf(fuse.FuseInHeader) + @sizeOf(u64) * 2,
                .opcode = fuse.FUSE_READDIR,
                .unique = 5,
                .nodeid = self.nodeid.?,
                .uid = 0,
                .gid = 0,
                .pid = 0,
                .padding = 0,
            };

            var read_in = struct {
                fh: u64,
                offset: u64,
                size: u32,
                _padding: u32,
            }{
                .fh = 0, // TODO: Store directory handle
                .offset = offset,
                .size = 4096,
                ._padding = 0,
            };

            const response = fs_dev.sendFuseRequest(&in_header, std.mem.asBytes(&read_in)) catch |err| {
                log.err.printf("Failed to send FUSE_READDIR request: {}\n", .{err});
                return null;
            };

            const out_header = @as(*fuse.FuseOutHeader, @ptrCast(@alignCast(response.ptr)));
            if (out_header.err < 0) {
                return null;
            }

            // Parse directory entries
            // TODO: Parse FUSE dirent format and return entries
            return null;
        }

        // TODO: Implement TarFS readdir
        return null;
    }
};

pub const DirEntry = struct {
    name: []const u8,
    ino: u64,
    type: u32,
};

fn oct2int(oct: []const u8, len: usize) u32 {
    var dec: u32 = 0;
    var i: usize = 0;

    while (i < len) : (i += 1) {
        if (oct[i] < '0' or oct[i] > '7') {
            break;
        }

        dec = dec * 8 + (oct[i] - '0');
    }
    return dec;
}

pub fn init() void {
    // Check if virtio-fs is available
    virtio_fs.init();
    if (virtio_fs.virtio_fs != null) {
        log.info.print("Using virtio-fs as primary filesystem\n");
        active_fs_type = .virtio_fs;
        initVirtioFs() catch |err| {
            log.err.printf("Failed to initialize virtio-fs: {}\n", .{err});
            // Fallback to tarfs
            active_fs_type = .tarfs;
            initTarFs();
        };
        return;
    }

    // Fallback to tarfs
    if (!options.has_fs) {
        log.debug.print("file system is not attached\n");
        return;
    }
    initTarFs();
}

fn initVirtioFs() !void {
    const fs_dev = virtio_fs.virtio_fs orelse return error.NoDevice;

    // Setup FUSE initialization message
    const init_in = fuse.FuseInHeader{
        .len = @sizeOf(fuse.FuseInHeader) + @sizeOf(fuse.FuseInitIn),
        .opcode = fuse.FUSE_INIT,
        .unique = 1,
        .nodeid = 0,
        .uid = 0,
        .gid = 0,
        .pid = 0,
        .padding = 0,
    };

    const init_in_arg = fuse.FuseInitIn{
        .major = 7,
        .minor = 31,
        .max_readahead = 4096,
        .flags = 0,
    };

    // Send FUSE_INIT request
    // TODO: Implement actual FUSE request sending through virtqueue
    _ = fs_dev;
    _ = init_in;
    _ = init_in_arg;

    // Create root directory
    dirs[0] = Directory{
        .name = "/",
        .nodeid = 1, // FUSE root inode is always 1
    };

    // Register root directory
    const new_fd = stream.fd_table.set(Stream{ .dir = dirs[0] }) catch {
        log.fatal.print("failed to set root directory\n");
        return error.FdTableFull;
    };
    log.debug.printf("virtio-fs root directory: fd={d}\n", .{new_fd});
}

fn initTarFs() void {
    log.debug.printf("FILES_MAX: {d}\n", .{FILES_MAX});
    const disk_ptr_addr = &_binary_build_disk_tar_start;
    const disk_pointer = @as([*]u8, @ptrCast(@constCast(disk_ptr_addr)));

    var off: usize = 0;
    var i: usize = 0;
    var i_regular: usize = 0;
    var i_dir: usize = 0;
    while (i < FILES_MAX) : (i += 1) {
        const header: *TarHeader = @as(*TarHeader, @ptrFromInt(@as(usize, @intFromPtr(disk_pointer)) + off));

        // file exists ?
        if (header.name[0] == 0) {
            break;
        }

        // check magic
        const ustar_magic = [6]u8{ 'u', 's', 't', 'a', 'r', 0 };
        var j: usize = 0;
        while (j < ustar_magic.len) : (j += 1) {
            if (ustar_magic[j] != header.magic[j]) {
                @panic("invalid tar magic\n");
            }
        }

        // get name len
        var name_len: usize = 0;
        while (name_len < header.name.len) : (name_len += 1) {
            if (header.name[name_len] == 0) {
                break;
            }
        }

        // check if directory
        if (header.typeflag == '5') {
            // register directory
            dirs[i_dir] = Directory{
                .name = header.name[0..name_len],
            };

            // update cursor
            off += @sizeOf(TarHeader);

            log.debug.printf("directory: {s}\n", .{@as([*]u8, @ptrCast(&header.name[0]))[0..name_len]});

            i_dir += 1;
            continue;
        }

        // check if regular file
        if (header.typeflag != '0') {
            // update cursor
            off += @sizeOf(TarHeader);

            if (header.typeflag == '2') {
                log.debug.printf("symlink: {s}\n", .{@as([*]u8, @ptrCast(&header.name[0]))[0..name_len]});
            } else {
                log.debug.printf("unknown typeflag: {c}\n", .{header.typeflag});
            }
            continue;
        }

        // register regular file
        files[i_regular] = RegularFile{
            .name = undefined,
            .data = undefined,
        };

        // get name
        files[i_regular].name = header.name[0..name_len];

        // get data
        const size: u32 = oct2int(&header.size, header.size.len);
        const data_ptr: [*]u8 = @as([*]u8, @ptrFromInt(@as(usize, @intFromPtr(disk_pointer)) + off + @sizeOf(TarHeader)));
        files[i_regular].data = data_ptr[0..size];

        // update offset to next file
        off += @sizeOf(TarHeader) + ((size + 511) / 512) * 512;

        // debug
        log.debug.printf("regular file: {s}\n", .{files[i_regular].name});

        i_regular += 1;
    }

    // register root directory as opend
    var dir = Directory{
        .name = undefined,
    };
    if (dirs[0].name.len > 0) {
        dir.name = dirs[0].name;
    } else {
        var current_dir = [_]u8{ '.', '/' };
        dir.name = &current_dir;
    }
    const new_fd = stream.fd_table.set(Stream{ .dir = dir }) catch {
        log.fatal.print("failed to set root directory\n");
        return;
    };
    log.debug.printf("root directory: fd={d}, path={s}\n", .{ new_fd, dir.name });
}
