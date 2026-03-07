/// ztree — Format-agnostic document tree library for Zig.
const create = @import("create.zig");
const render = @import("render.zig");
const tree_builder = @import("tree_builder.zig");

// Types
pub const Node    = create.Node;
pub const Element = create.Element;
pub const Attr    = create.Attr;

// Leaf constructors — no allocation, safe anywhere
pub const text = create.text;
pub const raw  = create.raw;
pub const none = create.none;
/// Construct individual attributes for runtime `[]const Attr` or `[]const ?Attr` slices.
pub const attr = create.attr;

// Element constructors — take an allocator, return !Node
pub const element        = create.element;
pub const closedElement  = create.closedElement;
pub const fragment       = create.fragment;

// Tree traversal (consumer side)
pub const renderWalk = render.renderWalk;
pub const WalkAction = render.WalkAction;

// Tree construction (producer side)
pub const TreeBuilder = tree_builder.TreeBuilder;

test {
    @import("std").testing.refAllDecls(@This());
}
