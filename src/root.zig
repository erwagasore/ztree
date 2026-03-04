/// ztree — Format-agnostic document tree library for Zig.
const create = @import("create.zig");

// Types
pub const Node    = create.Node;
pub const Element = create.Element;
pub const Attr    = create.Attr;

// Leaf constructors — no allocation, safe anywhere
pub const text = create.text;
pub const raw  = create.raw;
pub const none = create.none;

// Element constructors — take an allocator, return !Node
pub const element        = create.element;
pub const closedElement  = create.closedElement;
pub const fragment       = create.fragment;

test {
    @import("std").testing.refAllDecls(@This());
}
