const std = @import("std");
const node = @import("node.zig");
const render = @import("render.zig");

const Element = node.Element;
const WalkAction = render.WalkAction;
const Allocator = std.mem.Allocator;

/// Minimal test renderer that records callback invocations as a string.
/// Shared across test modules (render.zig, tree_builder.zig).
pub const TraceRenderer = struct {
    buf: std.ArrayList(u8),
    gpa: Allocator,

    pub fn init(gpa: Allocator) TraceRenderer {
        return .{ .buf = .empty, .gpa = gpa };
    }

    pub fn deinit(self: *TraceRenderer) void {
        self.buf.deinit(self.gpa);
    }

    pub fn result(self: *TraceRenderer) []const u8 {
        return self.buf.items;
    }

    fn append(self: *TraceRenderer, s: []const u8) !void {
        try self.buf.appendSlice(self.gpa, s);
    }

    pub fn elementOpen(self: *TraceRenderer, el: Element) !WalkAction {
        try self.append("<");
        try self.append(el.tag);
        for (el.attrs) |a| {
            try self.append(" ");
            try self.append(a.key);
            if (a.value) |v| {
                try self.append("=\"");
                try self.append(v);
                try self.append("\"");
            }
        }
        try self.append(">");
        return .@"continue";
    }

    pub fn elementClose(self: *TraceRenderer, el: Element) !void {
        try self.append("</");
        try self.append(el.tag);
        try self.append(">");
    }

    pub fn onText(self: *TraceRenderer, content: []const u8) !void {
        try self.append(content);
    }

    pub fn onRaw(self: *TraceRenderer, content: []const u8) !void {
        try self.append(content);
    }
};
