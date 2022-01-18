const std = @import("std");
const json = std.json;
const time = std.time;

pub fn main() anyerror!void {
    const stdout = std.io.getStdOut().writer();
    const absPath = "/tmp/zpomo.json";

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file = try std.fs.createFileAbsolute(absPath, .{ .read = true, .truncate = false });
    defer file.close();
    try file.lock(.Exclusive);
    defer file.unlock();
    var state: State = blk: {
        var buf: [64]u8 = undefined;
        const n = try file.readAll(&buf);
        if (n == 0) {
            break :blk State{ .paused = false, .ts = time.timestamp(), .dur = 0 };
        } else {
            break :blk try json.parse(State, &json.TokenStream.init(buf[0..n]), .{});
        }
    };

    var args = std.process.args();
    _ = args.skip();
    const cmd = args.nextPosix().?;

    const cur_ts = time.timestamp();
    const diff = cur_ts - state.ts;
    const prev_dur = state.dur;
    const cur_dur = @mod(prev_dur + diff, interval);
    state.ts = cur_ts;
    if (std.mem.eql(u8, cmd, "status")) {
        if (!state.paused) state.dur = cur_dur;
        if (cur_dur < rounds[0] and prev_dur >= rounds[0]) {
            const child = try std.ChildProcess.init(&.{ "notify-send", "pomodoro", "Time to start working" }, allocator);
            _ = try child.spawnAndWait();
        }
        if (cur_dur >= rounds[0] and prev_dur < rounds[0]) {
            const child = try std.ChildProcess.init(&.{ "notify-send", "pomodoro", "Time to take a break" }, allocator);
            _ = try child.spawnAndWait();
        }
        try showStatus(stdout, &state);
    } else if (std.mem.eql(u8, cmd, "toggle")) {
        state.paused = !state.paused;
        if (!state.paused) state.dur = cur_dur;
    } else if (std.mem.eql(u8, cmd, "reset")) {
        state.paused = false;
        state.dur = 0;
    } else unreachable;

    // try stdout.print("{}\n", .{state});

    // truncate file at first
    try file.seekTo(0);
    try file.setEndPos(0);
    try json.stringify(state, .{}, file.writer());
}

const rounds: [2]i64 = .{ 25 * time.s_per_min, 5 * time.s_per_min };
const interval = rounds[0] + rounds[1];

fn showStatus(stdout: anytype, state: *const State) !void {
    const paused = if (state.paused) "[paused] " else "";
    const status = if (state.dur < rounds[0]) "working" else "resting";
    const remain = if (state.dur < rounds[0]) rounds[0] - state.dur else interval - state.dur;

    try stdout.print("{s}{s}: {}", .{ paused, status, std.fmt.fmtDurationSigned(remain * time.ns_per_s) });
}

const State = struct {
    paused: bool,
    ts: i64,
    dur: i64,
};
