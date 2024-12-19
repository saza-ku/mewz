const std = @import("std");
const builtin = std.builtin;
const debug = std.debug;
const log = @import("log.zig");
const format = std.fmt.format;

/// Implementation of the panic function.
pub const panic_fn = panic;

/// Flag to indicate that a panic occurred.
var panicked = false;

pub fn panic(msg: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
    log.fatal.printf("{s}\n", .{msg});
    asm volatile ("cli");

    if (panicked) {
        log.fatal.print("Double panic detected. Halting.\n");
        asm volatile ("hlt");
    }
    panicked = true;

    var it = std.debug.StackIterator.init(@returnAddress(), null);
    var ix: usize = 0;
    log.fatal.printf("=== Stack Trace ==============\n", .{});
    while (it.next()) |frame| : (ix += 1) {
        log.fatal.printf("#{d:0>2}: 0x{X:0>16}\n", .{ ix, frame });
    }

    asm volatile ("hlt");

    unreachable;
}
