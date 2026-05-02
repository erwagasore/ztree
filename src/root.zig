/// ztree — Format-agnostic document tree library for Zig.
const create = @import("create.zig");
const render = @import("render.zig");
const tree_builder = @import("tree_builder.zig");

// Types
pub const Node = create.Node;
pub const Element = create.Element;
pub const Attr = create.Attr;

// Leaf constructors — no allocation, safe anywhere
pub const text = create.text;
pub const raw = create.raw;
pub const none = create.none;
/// Construct individual attributes for runtime `[]const Attr` or `[]const ?Attr` slices.
pub const attr = create.attr;

// Element constructors — take an allocator, return !Node
pub const element = create.element;
pub const closedElement = create.closedElement;
pub const fragment = create.fragment;

// Tree traversal (consumer side)
pub const renderWalk = render.renderWalk;
pub const WalkAction = render.WalkAction;
pub const Walker = render.Walker;
pub const TypedWalker = render.TypedWalker;
pub const walker = render.walker;
pub const typedWalker = render.typedWalker;

// Tree construction (producer side)
pub const TreeBuilder = tree_builder.TreeBuilder;

test {
    const std = @import("std");

    std.testing.refAllDecls(@This());

    _ = @import("node.zig");
    _ = @import("create.zig");
    _ = @import("render.zig");
    _ = @import("tree_builder.zig");
}
