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
};

var timestamp: u64 = undefined;
var wasi_enter_timestamp: u64 = undefined;

var current_state: State = State.NONE;
var wasi_elapsed_time: u64 = 0;
var wasm_elapsed_time: u64 = 0;
var lwip_elapsed_time: u64 = 0;
var malloc_elapsed_time: u64 = 0;
var timer_elapsed_time: u64 = 0;

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
        else => {},
    }

    timestamp = new_timestamp;
    current_state = s;
}
