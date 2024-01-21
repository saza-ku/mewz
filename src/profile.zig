const log = @import("log.zig");
const sync = @import("sync.zig");

extern fn rdtsc() u64;

pub const State = enum {
    NONE,
    WASI,
    WASM,
    LWIP,
    MALLOC,
    TIMER,
    VIRTIO,
    POLL,
};

var timestamp: u64 = undefined;
var wasm_enter_timestamp: u64 = undefined;
var wasi_enter_timestamp: u64 = undefined;

var current_state: State = State.NONE;
var wasi_elapsed_time: u64 = 0;
var wasm_elapsed_time: u64 = 0;
var lwip_elapsed_time: u64 = 0;
var malloc_elapsed_time: u64 = 0;
var timer_elapsed_time: u64 = 0;
var virtio_elapsed_time: u64 = 0;
var poll_elapsed_time: u64 = 0;

pub fn swtch(s: State) void {
    sync.pushcli();
    defer sync.popcli();

    const new_timestamp = rdtsc();

    switch (current_state) {
        .WASI => {
            wasi_elapsed_time += new_timestamp - timestamp;
            wasi_enter_timestamp = new_timestamp;
        },
        .WASM => {
            wasm_elapsed_time += new_timestamp - timestamp;
        },
        .LWIP => {
            lwip_elapsed_time += new_timestamp - timestamp;
        },
        .MALLOC => {
            malloc_elapsed_time += new_timestamp - timestamp;
        },
        .TIMER => {
            timer_elapsed_time += new_timestamp - timestamp;
        },
        .VIRTIO => {
            virtio_elapsed_time += new_timestamp - timestamp;
        },
        .POLL => {
            poll_elapsed_time += new_timestamp - timestamp;
        },
        else => {},
    }

    timestamp = new_timestamp;
    current_state = s;
}

pub fn swtchWithOldState(s: State) State {
    sync.pushcli();
    defer sync.popcli();

    const old_state = current_state;
    swtch(s);
    return old_state;
}

pub fn printResult() void {
    log.fatal.printf("total: {} cycles\n", .{wasi_enter_timestamp - wasm_enter_timestamp});
    log.fatal.printf("wasi: {} cycles\n", .{wasi_elapsed_time});
    log.fatal.printf("wasm: {} cycles\n", .{wasm_elapsed_time});
    log.fatal.printf("lwip: {} cycles\n", .{lwip_elapsed_time});
    log.fatal.printf("malloc: {} cycles\n", .{malloc_elapsed_time});
    log.fatal.printf("timer: {} cycles\n", .{timer_elapsed_time});
    log.fatal.printf("virtio: {} cycles\n", .{virtio_elapsed_time});
    log.fatal.printf("poll: {} cycles\n", .{poll_elapsed_time});
}

pub fn init() void {
    wasm_enter_timestamp = rdtsc();
}
