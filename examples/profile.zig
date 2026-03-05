const std = @import("std");
const ztree = @import("ztree");

const Allocator = std.mem.Allocator;
const Node = ztree.Node;
const Attr = ztree.Attr;

const element = ztree.element;
const closedElement = ztree.closedElement;
const fragment = ztree.fragment;
const text = ztree.text;
const raw = ztree.raw;
const none = ztree.none;
const attr = ztree.attr;
const cls = ztree.cls;

// ── Domain ───────────────────────────────────────────────────────────────────

const Role = enum { admin, editor, viewer };

const Skill = struct { name: []const u8, level: u8 }; // level 1–5

const Project = struct {
    name: []const u8,
    url: []const u8,
    stars: u32,
    archived: bool,
};

const User = struct {
    name: []const u8,
    email: []const u8,
    avatar: []const u8,
    bio: ?[]const u8,
    role: Role,
    verified: bool,
    online: bool,
    skills: []const Skill,
    projects: []const Project,
};

// ── Components ───────────────────────────────────────────────────────────────

fn roleBadge(a: Allocator, role: Role) !Node {
    const label = @tagName(role);
    return element(a, "span", .{
        .class = switch (role) {
            .admin => "badge badge-red",
            .editor => "badge badge-blue",
            .viewer => "badge badge-gray",
        },
    }, .{text(label)});
}

fn statusDot(a: Allocator, online: bool) !Node {
    return closedElement(a, "span", &[_]?Attr{
        attr("class", try cls(a, &.{ "dot", if (online) "dot-green" else "dot-gray" })),
        attr("title", if (online) "Online" else "Offline"),
        attr("aria-label", if (online) "Online" else "Offline"),
    });
}

fn skillBar(a: Allocator, skill: Skill) !Node {
    const width = try std.fmt.allocPrint(a, "width: {d}%", .{@as(u32, skill.level) * 20});
    const level = try std.fmt.allocPrint(a, "{d}/5", .{skill.level});
    return element(a, "div", .{ .class = "skill" }, .{
        try element(a, "div", .{ .class = "skill-header" }, .{
            try element(a, "span", .{ .class = "skill-name" }, .{text(skill.name)}),
            try element(a, "span", .{ .class = "skill-level" }, .{text(level)}),
        }),
        try element(a, "div", .{ .class = "skill-track" }, .{
            try closedElement(a, "div", .{
                .class = "skill-fill",
                .style = width,
                .role = "progressbar",
                .@"aria-valuenow" = try std.fmt.allocPrint(a, "{d}", .{skill.level}),
                .@"aria-valuemin" = "0",
                .@"aria-valuemax" = "5",
            }),
        }),
    });
}

fn skillList(a: Allocator, skills: []const Skill) !Node {
    if (skills.len == 0) {
        return element(a, "p", .{ .class = "empty" }, .{text("No skills listed.")});
    }
    const items = try a.alloc(Node, skills.len);
    for (skills, 0..) |s, i| {
        items[i] = try skillBar(a, s);
    }
    return element(a, "div", .{ .class = "skill-list" }, items);
}

fn projectCard(a: Allocator, p: Project, viewer_is_admin: bool) !Node {
    const stars = try std.fmt.allocPrint(a, "★ {d}", .{p.stars});
    return element(a, "li", &[_]?Attr{
        attr("class", try cls(a, &.{
            "project",
            if (p.archived) "project-archived" else null,
            if (p.stars >= 100) "project-popular" else null,
        })),
        attr("data-stars", try std.fmt.allocPrint(a, "{d}", .{p.stars})),
        if (p.archived) attr("aria-disabled", "true") else null,
    }, .{
        try element(a, "div", .{ .class = "project-header" }, .{
            try element(a, "a", &[_]?Attr{
                attr("href", p.url),
                attr("class", "project-link"),
                attr("target", "_blank"),
                attr("rel", "noopener noreferrer"),
                if (p.archived) attr("tabindex", "-1") else null,
            }, .{text(p.name)}),
            try element(a, "span", .{ .class = "project-stars" }, .{text(stars)}),
        }),
        try element(a, "div", .{ .class = "project-actions" }, .{
            if (p.archived)
                try element(a, "span", .{ .class = "label label-muted" }, .{text("Archived")})
            else
                try element(a, "a", .{ .href = p.url, .class = "btn btn-sm" }, .{text("View")}),
            if (viewer_is_admin)
                try element(a, "button", &[_]?Attr{
                    attr("class", "btn btn-sm btn-danger"),
                    attr("data-action", "delete"),
                    attr("data-project", p.name),
                }, .{text("Delete")})
            else
                none(),
        }),
    });
}

fn projectList(a: Allocator, projects: []const Project, viewer_is_admin: bool) !Node {
    if (projects.len == 0) {
        return element(a, "p", .{ .class = "empty" }, .{text("No projects yet.")});
    }
    const items = try a.alloc(Node, projects.len);
    for (projects, 0..) |p, i| {
        items[i] = try projectCard(a, p, viewer_is_admin);
    }
    return element(a, "ul", .{ .class = "project-list", .role = "list" }, items);
}

fn profilePage(a: Allocator, user: User, viewer_is_admin: bool) !Node {
    const mailto = try std.fmt.allocPrint(a, "mailto:{s}", .{user.email});
    const project_count = try std.fmt.allocPrint(a, "Projects ({d})", .{user.projects.len});

    return element(a, "html", .{ .lang = "en" }, .{
        try element(a, "head", .{}, .{
            try closedElement(a, "meta", .{ .charset = "utf-8" }),
            try element(a, "title", .{}, .{
                text(try std.fmt.allocPrint(a, "{s} — Profile", .{user.name})),
            }),
            try closedElement(a, "link", .{ .rel = "stylesheet", .href = "/css/profile.css" }),
        }),
        try element(a, "body", .{ .class = "page-profile" }, .{
            // ── Header card ──────────────────────────────────────────────
            try element(a, "section", .{
                .class = "profile-card",
                .@"aria-label" = "User profile",
            }, .{
                try element(a, "div", .{ .class = "profile-card-left" }, .{
                    try closedElement(a, "img", &[_]?Attr{
                        attr("src", user.avatar),
                        attr("alt", try std.fmt.allocPrint(a, "{s}'s avatar", .{user.name})),
                        attr("class", "avatar avatar-lg"),
                        attr("width", "96"),
                        attr("height", "96"),
                        if (!user.online) attr("style", "opacity: 0.6") else null,
                    }),
                }),
                try element(a, "div", .{ .class = "profile-card-body" }, .{
                    try element(a, "div", .{ .class = "profile-name-row" }, .{
                        try element(a, "h1", .{ .class = "profile-name" }, .{text(user.name)}),
                        try statusDot(a, user.online),
                        try roleBadge(a, user.role),
                        if (user.verified)
                            try element(a, "span", .{
                                .class = "badge badge-green",
                                .title = "Verified account",
                            }, .{text("✓ Verified")})
                        else
                            none(),
                    }),
                    try element(a, "a", .{ .href = mailto, .class = "profile-email" }, .{
                        text(user.email),
                    }),
                    if (user.bio) |bio|
                        try element(a, "p", .{ .class = "profile-bio" }, .{text(bio)})
                    else
                        try element(a, "p", .{ .class = "profile-bio muted" }, .{
                            text("No bio provided."),
                        }),
                }),
            }),

            // ── Skills section ───────────────────────────────────────────
            try element(a, "section", .{
                .class = "section",
                .@"aria-label" = "Skills",
            }, .{
                try element(a, "h2", .{}, .{text("Skills")}),
                try skillList(a, user.skills),
            }),

            // ── Projects section ─────────────────────────────────────────
            try element(a, "section", .{
                .class = "section",
                .@"aria-label" = "Projects",
            }, .{
                try element(a, "h2", .{}, .{text(project_count)}),
                try projectList(a, user.projects, viewer_is_admin),
            }),
        }),
    });
}

// ── Inline HTML renderer (minimal, for demo purposes) ────────────────────────

const VOID = [_][]const u8{
    "area", "base", "br", "col", "embed", "hr",
    "img", "input", "link", "meta", "source", "track", "wbr",
};

fn isVoid(tag: []const u8) bool {
    for (VOID) |v| if (std.mem.eql(u8, v, tag)) return true;
    return false;
}

fn esc(gpa: Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    for (s) |c| switch (c) {
        '<' => try out.appendSlice(gpa, "&lt;"),
        '>' => try out.appendSlice(gpa, "&gt;"),
        '&' => try out.appendSlice(gpa, "&amp;"),
        '"' => try out.appendSlice(gpa, "&quot;"),
        else => try out.append(gpa, c),
    };
}

fn render(gpa: Allocator, out: *std.ArrayList(u8), n: Node) !void {
    switch (n) {
        .text => |s| try esc(gpa, out, s),
        .raw => |s| try out.appendSlice(gpa, s),
        .fragment => |ch| for (ch) |c| try render(gpa, out, c),
        .element => |el| {
            try out.append(gpa, '<');
            try out.appendSlice(gpa, el.tag);
            for (el.attrs) |a| {
                try out.append(gpa, ' ');
                try out.appendSlice(gpa, a.key);
                if (a.value) |v| {
                    try out.appendSlice(gpa, "=\"");
                    try esc(gpa, out, v);
                    try out.append(gpa, '"');
                }
            }
            try out.append(gpa, '>');
            if (!isVoid(el.tag)) {
                for (el.children) |c| try render(gpa, out, c);
                try out.appendSlice(gpa, "</");
                try out.appendSlice(gpa, el.tag);
                try out.append(gpa, '>');
            }
        },
    }
}

// ── Entry point ──────────────────────────────────────────────────────────────

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const user = User{
        .name = "Alice Chen",
        .email = "alice@example.com",
        .avatar = "/img/alice.jpg",
        .bio = "Systems programmer. Zig enthusiast. Building things that last.",
        .role = .admin,
        .verified = true,
        .online = true,
        .skills = &.{
            .{ .name = "Zig", .level = 5 },
            .{ .name = "C", .level = 4 },
            .{ .name = "Rust", .level = 3 },
            .{ .name = "Go", .level = 2 },
        },
        .projects = &.{
            .{ .name = "ztree", .url = "https://github.com/alice/ztree", .stars = 142, .archived = false },
            .{ .name = "zigfmt", .url = "https://github.com/alice/zigfmt", .stars = 87, .archived = false },
            .{ .name = "old-parser", .url = "https://github.com/alice/old-parser", .stars = 12, .archived = true },
        },
    };

    const tree = try profilePage(a, user, true);

    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "<!doctype html>\n");
    try render(a, &out, tree);
    try out.append(a, '\n');
    try std.fs.File.stdout().writeAll(out.items);
}
