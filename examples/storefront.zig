/// examples/storefront.zig
///
/// A runnable storefront page rendered to stdout.
/// Exercises: deep nesting, loops, conditionals, cls,
///            []const ?Attr, []const Node slices, fragment, none.
///
/// Run:  zig build example

const std = @import("std");
const ztree = @import("ztree");

const Allocator = std.mem.Allocator;
const Node      = ztree.Node;
const Attr      = ztree.Attr;

const element       = ztree.element;
const closedElement = ztree.closedElement;
const fragment      = ztree.fragment;
const text          = ztree.text;
const raw           = ztree.raw;
const none          = ztree.none;
const attr          = ztree.attr;
const cls           = ztree.cls;

// ── Domain types ─────────────────────────────────────────────────────────────

const Tag = []const u8;

const Product = struct {
    id:          u32,
    name:        []const u8,
    description: []const u8,
    price:       u32,       // cents
    sale_price:  ?u32,      // cents, null if no sale
    image:       []const u8,
    tags:        []const Tag,
    featured:    bool,
    in_stock:    bool,
};

const Category = struct {
    slug:   []const u8,
    name:   []const u8,
    count:  u32,
};

const User = struct {
    name:  []const u8,
    admin: bool,
};

const Pagination = struct { current: u32, total: u32 };

const Context = struct {
    user:            ?User,
    active_nav:      []const u8,  // e.g. "/products"
    active_category: ?[]const u8, // slug or null
    cart_count:      u32,
    price_max:       u32,         // cents
    categories:      []const Category,
    products:        []const Product,
    page:            Pagination,
};

// ── Formatting helpers ────────────────────────────────────────────────────────

/// Format cents as "$N.NN" into the arena.
fn fmtPrice(a: Allocator, cents: u32) ![]const u8 {
    return std.fmt.allocPrint(a, "${d}.{d:0>2}", .{ cents / 100, cents % 100 });
}

/// Format an integer into the arena.
fn fmtInt(a: Allocator, n: u32) ![]const u8 {
    return std.fmt.allocPrint(a, "{d}", .{n});
}

// ── Components ────────────────────────────────────────────────────────────────

/// Single nav link — highlighted when href matches the active path.
fn navLink(a: Allocator, label: []const u8, href: []const u8, active: bool) !Node {
    return element(a, "li", .{}, .{
        try element(a, "a", &[_]?Attr{
            attr("href", href),
            attr("class", try cls(a, &.{ "nav-link", if (active) "active" else null })),
        }, .{ text(label) }),
    });
}

/// Cart button with dynamic badge count.
fn cartBtn(a: Allocator, count: u32) !Node {
    const label = try std.fmt.allocPrint(a, "🛒 Cart ({d})", .{count});
    return element(a, "a", &[_]?Attr{
        attr("href", "/cart"),
        attr("class", try cls(a, &.{ "btn", if (count > 0) "btn-active" else null })),
    }, .{ text(label) });
}

/// Site-wide navigation bar.
fn navbar(a: Allocator, ctx: Context) !Node {
    const active = ctx.active_nav;

    // User area — login link or dropdown trigger
    const user_area = if (ctx.user) |u|
        try element(a, "a", .{ .href = "/account", .class = "btn btn-ghost" }, .{ text(u.name) })
    else
        try element(a, "a", .{ .href = "/login", .class = "btn" }, .{ text("Login") });

    return element(a, "header", .{ .class = "navbar" }, .{
        try element(a, "div", .{ .class = "logo" }, .{
            try element(a, "a", .{ .href = "/" }, .{ text("ShopZig") }),
        }),
        try element(a, "ul", .{ .class = "nav-links" }, .{
            try navLink(a, "Home",     "/",         std.mem.eql(u8, active, "/")),
            try navLink(a, "Products", "/products", std.mem.eql(u8, active, "/products")),
            try navLink(a, "About",    "/about",    std.mem.eql(u8, active, "/about")),
        }),
        try element(a, "div", .{ .class = "nav-actions" }, .{
            try cartBtn(a, ctx.cart_count),
            user_area,
        }),
    });
}

/// Sidebar category list + price filter.
fn sidebar(a: Allocator, ctx: Context) !Node {
    // Category links — loop-built children
    const cat_items = try a.alloc(Node, ctx.categories.len);
    for (ctx.categories, 0..) |cat, i| {
        const is_active = if (ctx.active_category) |ac| std.mem.eql(u8, ac, cat.slug) else false;
        const label = try std.fmt.allocPrint(a, "{s} ({d})", .{ cat.name, cat.count });
        cat_items[i] = try element(a, "li", .{}, .{
            try element(a, "a", &[_]?Attr{
                attr("href",  try std.fmt.allocPrint(a, "/products?cat={s}", .{cat.slug})),
                attr("class", try cls(a, &.{ "cat-link", if (is_active) "active" else null })),
            }, .{ text(label) }),
        });
    }

    // Price filter slider
    const price_label = try std.fmt.allocPrint(a, "Up to {s}", .{try fmtPrice(a, ctx.price_max)});

    return element(a, "aside", .{ .class = "sidebar" }, .{
        try element(a, "h2", .{}, .{ text("Categories") }),
        try element(a, "ul", .{ .class = "category-list" }, cat_items),
        try element(a, "div", .{ .class = "price-filter" }, .{
            try element(a, "h3", .{}, .{ text("Price range") }),
            try closedElement(a, "input", &[_]?Attr{
                attr("type",  "range"),
                attr("min",   "0"),
                attr("max",   try fmtInt(a, ctx.price_max)),
                attr("value", try fmtInt(a, ctx.price_max)),
            }),
            try element(a, "p", .{}, .{ text(price_label) }),
        }),
    });
}

/// Badge strip at the top of each product card (featured / sale / out-of-stock).
fn cardBadges(a: Allocator, p: Product) !Node {
    // Collect only the badges that apply. Count first so we allocate exactly
    // what we need from the arena — stack allocation would dangle after return.
    const count: usize =
        @as(usize, @intFromBool(p.featured)) +
        @as(usize, @intFromBool(p.sale_price != null)) +
        @as(usize, @intFromBool(!p.in_stock));

    if (count == 0) return none();

    const buf = try a.alloc(Node, count);
    var i: usize = 0;

    if (p.featured) {
        buf[i] = try element(a, "span", .{ .class = "badge badge-featured" }, .{ text("★ Featured") });
        i += 1;
    }
    if (p.sale_price != null) {
        buf[i] = try element(a, "span", .{ .class = "badge badge-sale" }, .{ text("Sale") });
        i += 1;
    }
    if (!p.in_stock) {
        buf[i] = try element(a, "span", .{ .class = "badge badge-oos" }, .{ text("Out of stock") });
        i += 1;
    }

    // fragment is transparent — renders children without a wrapper tag
    return fragment(a, buf);
}

/// Tag pill list inside a card body.
fn tagList(a: Allocator, tags: []const Tag) !Node {
    const items = try a.alloc(Node, tags.len);
    for (tags, 0..) |t, i| {
        items[i] = try element(a, "li", .{}, .{
            try element(a, "span", .{ .class = "tag" }, .{ text(t) }),
        });
    }
    return element(a, "ul", .{ .class = "tag-list" }, items);
}

/// Price display: strikethrough + sale price, or plain price.
fn priceBox(a: Allocator, p: Product) !Node {
    if (p.sale_price) |sale| {
        return element(a, "div", .{ .class = "price-box" }, .{
            try element(a, "span", .{ .class = "price-original" }, .{ text(try fmtPrice(a, p.price)) }),
            try element(a, "span", .{ .class = "price-sale" },     .{ text(try fmtPrice(a, sale)) }),
        });
    }
    return element(a, "div", .{ .class = "price-box" }, .{
        try element(a, "span", .{ .class = "price" }, .{ text(try fmtPrice(a, p.price)) }),
    });
}

/// Full product card.
fn productCard(a: Allocator, p: Product, user: ?User) !Node {
    const oos    = !p.in_stock;
    const is_admin = if (user) |u| u.admin else false;

    // "Add to cart" — disabled when out of stock
    const add_btn = try element(a, "button", &[_]?Attr{
        attr("class", "btn btn-cart"),
        if (oos) attr("disabled", null) else null,
    }, .{ text("Add to cart") });

    // Admin-only edit button — none() when not admin
    const edit_btn = if (is_admin)
        try element(a, "button", .{ .class = "btn btn-edit" }, .{ text("Edit") })
    else
        none();

    return element(a, "article", &[_]?Attr{
        attr("class", try cls(a, &.{
            "product-card",
            if (p.featured) "featured"  else null,
            if (oos)        "out-of-stock" else null,
        })),
        attr("data-id", try fmtInt(a, p.id)),
    }, .{
        // Badge strip (fragment — no wrapper tag)
        try cardBadges(a, p),

        // Product image
        try element(a, "div", .{ .class = "card-image" }, .{
            try closedElement(a, "img", &[_]?Attr{
                attr("src", p.image),
                attr("alt", p.name),
                attr("class", try cls(a, &.{ "card-img", if (oos) "greyed" else null })),
            }),
        }),

        // Card body
        try element(a, "div", .{ .class = "card-body" }, .{
            try element(a, "h3", .{ .class = "card-title" }, .{ text(p.name) }),
            try element(a, "p",  .{ .class = "card-desc"  }, .{ text(p.description) }),
            try tagList(a, p.tags),
            try element(a, "div", .{ .class = "card-footer" }, .{
                try priceBox(a, p),
                try element(a, "div", .{ .class = "card-actions" }, .{
                    add_btn,
                    edit_btn,
                }),
            }),
        }),
    });
}

/// Pagination bar.
fn pagination(a: Allocator, pg: Pagination) !Node {
    const label = try std.fmt.allocPrint(a, "Page {d} of {d}", .{ pg.current, pg.total });

    return element(a, "nav", .{ .class = "pagination" }, .{
        try element(a, "button", &[_]?Attr{
            attr("class", "btn btn-page"),
            if (pg.current <= 1) attr("disabled", null) else null,
        }, .{ text("← Prev") }),
        try element(a, "span", .{ .class = "page-label" }, .{ text(label) }),
        try element(a, "button", &[_]?Attr{
            attr("class", "btn btn-page"),
            if (pg.current >= pg.total) attr("disabled", null) else null,
        }, .{ text("Next →") }),
    });
}

/// Full product grid + pagination.
fn productGrid(a: Allocator, ctx: Context) !Node {
    if (ctx.products.len == 0) {
        return element(a, "div", .{ .class = "empty-state" }, .{
            try element(a, "p", .{}, .{ text("No products found.") }),
        });
    }

    const cards = try a.alloc(Node, ctx.products.len);
    for (ctx.products, 0..) |p, i| {
        cards[i] = try productCard(a, p, ctx.user);
    }

    return element(a, "div", .{}, .{
        try element(a, "div", .{ .class = "product-grid" }, cards),
        try pagination(a, ctx.page),
    });
}

/// Full page document.
fn page(a: Allocator, ctx: Context) !Node {
    return element(a, "html", .{ .lang = "en" }, .{
        try element(a, "head", .{}, .{
            try element(a, "title", .{}, .{ text("ShopZig — Products") }),
            try closedElement(a, "meta", .{ .charset = "utf-8" }),
            try closedElement(a, "meta", &[_]Attr{
                attr("name", "viewport"),
                attr("content", "width=device-width, initial-scale=1"),
            }),
            try closedElement(a, "link", .{ .rel = "stylesheet", .href = "/app.css" }),
        }),
        try element(a, "body", .{}, .{
            try navbar(a, ctx),
            try element(a, "div", .{ .class = "layout" }, .{
                try sidebar(a, ctx),
                try element(a, "main", .{ .class = "content" }, .{
                    try element(a, "h1", .{}, .{ text("Products") }),
                    try productGrid(a, ctx),
                }),
            }),
            try element(a, "footer", .{}, .{
                try element(a, "p", .{}, .{ text("© 2026 ShopZig") }),
            }),
        }),
    });
}

// ── Minimal HTML renderer ────────────────────────────────────────────────────

/// Void elements — self-closing, never get a </tag>.
const VOID_TAGS = [_][]const u8{
    "area", "base", "br", "col", "embed", "hr",
    "img", "input", "link", "meta", "source", "track", "wbr",
};

fn isVoid(tag: []const u8) bool {
    for (VOID_TAGS) |v| if (std.mem.eql(u8, v, tag)) return true;
    return false;
}

fn writeEscaped(gpa: Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    for (s) |c| switch (c) {
        '<'  => try out.appendSlice(gpa, "&lt;"),
        '>'  => try out.appendSlice(gpa, "&gt;"),
        '&'  => try out.appendSlice(gpa, "&amp;"),
        '"'  => try out.appendSlice(gpa, "&quot;"),
        else => try out.append(gpa, c),
    };
}

fn renderNode(gpa: Allocator, out: *std.ArrayList(u8), n: Node) !void {
    switch (n) {
        .text     => |s|  try writeEscaped(gpa, out, s),
        .raw      => |s|  try out.appendSlice(gpa, s),
        .fragment => |ch| for (ch) |c| try renderNode(gpa, out, c),
        .element  => |el| {
            try out.append(gpa, '<');
            try out.appendSlice(gpa, el.tag);
            for (el.attrs) |at| {
                try out.append(gpa, ' ');
                try out.appendSlice(gpa, at.key);
                if (at.value) |v| {
                    try out.appendSlice(gpa, "=\"");
                    try writeEscaped(gpa, out, v);
                    try out.append(gpa, '"');
                }
            }
            try out.append(gpa, '>');
            if (!isVoid(el.tag)) {
                for (el.children) |c| try renderNode(gpa, out, c);
                try out.appendSlice(gpa, "</");
                try out.appendSlice(gpa, el.tag);
                try out.append(gpa, '>');
            }
        },
    }
}

// ── Sample data + entry point ─────────────────────────────────────────────────

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ctx = Context{
        .user            = .{ .name = "alice", .admin = true },
        .active_nav      = "/products",
        .active_category = "zig",
        .cart_count      = 3,
        .price_max       = 15000,
        .categories      = &.{
            .{ .slug = "zig",  .name = "Zig",     .count = 4 },
            .{ .slug = "c",    .name = "C",        .count = 7 },
            .{ .slug = "rust", .name = "Rust",     .count = 2 },
        },
        .products = &.{
            .{
                .id          = 1,
                .name        = "Zig in Action",
                .description = "A comprehensive guide to the Zig programming language.",
                .price       = 3999,
                .sale_price  = 2999,
                .image       = "/img/zia.jpg",
                .tags        = &.{ "zig", "book", "beginner" },
                .featured    = true,
                .in_stock    = true,
            },
            .{
                .id          = 2,
                .name        = "Comptime Wizardry",
                .description = "Deep dive into Zig's compile-time metaprogramming.",
                .price       = 4999,
                .sale_price  = null,
                .image       = "/img/cw.jpg",
                .tags        = &.{ "zig", "advanced", "comptime" },
                .featured    = false,
                .in_stock    = false, // out of stock — triggers greyed img + disabled button
            },
            .{
                .id          = 3,
                .name        = "Build Systems Demystified",
                .description = "Everything you need to know about build.zig.",
                .price       = 2999,
                .sale_price  = null,
                .image       = "/img/bsd.jpg",
                .tags        = &.{ "zig", "tooling" },
                .featured    = false,
                .in_stock    = true,
            },
        },
        .page = .{ .current = 1, .total = 4 },
    };

    const tree = try page(a, ctx);

    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "<!doctype html>\n");
    try renderNode(a, &out, tree);
    try out.append(a, '\n');
    try std.fs.File.stdout().writeAll(out.items);
}
