const std = @import("std");

// FUSE protocol constants
pub const FUSE_LOOKUP = 1;
pub const FUSE_FORGET = 2;
pub const FUSE_GETATTR = 3;
pub const FUSE_SETATTR = 4;
pub const FUSE_READLINK = 5;
pub const FUSE_SYMLINK = 6;
pub const FUSE_MKDIR = 9;
pub const FUSE_RMDIR = 11;
pub const FUSE_OPEN = 14;
pub const FUSE_READ = 15;
pub const FUSE_WRITE = 16;
pub const FUSE_STATFS = 17;
pub const FUSE_RELEASE = 18;
pub const FUSE_FSYNC = 20;
pub const FUSE_SETXATTR = 21;
pub const FUSE_GETXATTR = 22;
pub const FUSE_LISTXATTR = 23;
pub const FUSE_REMOVEXATTR = 24;
pub const FUSE_FLUSH = 25;
pub const FUSE_INIT = 26;
pub const FUSE_OPENDIR = 27;
pub const FUSE_READDIR = 28;
pub const FUSE_RELEASEDIR = 29;
pub const FUSE_FSYNCDIR = 30;
pub const FUSE_ACCESS = 34;
pub const FUSE_CREATE = 35;

pub const FuseInHeader = extern struct {
    len: u32,
    opcode: u32,
    unique: u64,
    nodeid: u64,
    uid: u32,
    gid: u32,
    pid: u32,
    padding: u32,
};

pub const FuseOutHeader = extern struct {
    len: u32,
    err: i32,
    unique: u64,
};

pub const FuseAttr = extern struct {
    ino: u64,
    size: u64,
    blocks: u64,
    atime: u64,
    mtime: u64,
    ctime: u64,
    atimensec: u32,
    mtimensec: u32,
    ctimensec: u32,
    mode: u32,
    nlink: u32,
    uid: u32,
    gid: u32,
    rdev: u32,
    blksize: u32,
    padding: u32,
};

pub const FuseInitIn = extern struct {
    major: u32,
    minor: u32,
    max_readahead: u32,
    flags: u32,
};

pub const FuseInitOut = extern struct {
    major: u32,
    minor: u32,
    max_readahead: u32,
    flags: u32,
    max_background: u16,
    congestion_threshold: u16,
    max_write: u32,
    time_gran: u32,
    max_pages: u16,
    padding: u16,
    unused: [8]u32,
};

pub const FUSE_ENTRY_OUT_PADDING = 8;
pub const FUSE_DIRENT_ALIGN = 8;

pub const FuseEntryOut = extern struct {
    nodeid: u64,
    generation: u64,
    entry_valid: u64,
    attr_valid: u64,
    entry_valid_nsec: u32,
    attr_valid_nsec: u32,
    attr: FuseAttr,
};

pub const FuseDirent = extern struct {
    ino: u64,
    off: u64,
    namelen: u32,
    type: u32,
};

pub const FuseOpenIn = extern struct {
    flags: u32,
    unused: u32,
};

pub const FuseOpenOut = extern struct {
    fh: u64,
    open_flags: u32,
    padding: u32,
};

pub const FuseReadIn = extern struct {
    fh: u64,
    offset: u64,
    size: u32,
    read_flags: u32,
    lock_owner: u64,
    flags: u32,
    padding: u32,
};

pub const FuseWriteIn = extern struct {
    fh: u64,
    offset: u64,
    size: u32,
    write_flags: u32,
    lock_owner: u64,
    flags: u32,
    padding: u32,
};

// FUSE attribute flags
pub const FUSE_FATTR_MODE = 1 << 0;
pub const FUSE_FATTR_UID = 1 << 1;
pub const FUSE_FATTR_MTIME = 1 << 5;
pub const FUSE_FATTR_CTIME = 1 << 6;

// File types
pub const S_IFMT: u32 = 0o170000;
pub const S_IFREG: u32 = 0o100000;
pub const S_IFDIR: u32 = 0o040000;
pub const S_IFCHR: u32 = 0o020000;
pub const S_IFBLK: u32 = 0o060000;
pub const S_IFIFO: u32 = 0o010000;
pub const S_IFLNK: u32 = 0o120000;
pub const S_IFSOCK: u32 = 0o140000;
