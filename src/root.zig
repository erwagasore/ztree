/// ztree — Format-agnostic document tree library for Zig.
const create = @import("create.zig");

// Types
pub const Node = create.Node;
pub const Element = create.Element;
pub const Attr = create.Attr;

// Construction functions
pub const element = create.element;
pub const closedElement = create.closedElement;
pub const fragment = create.fragment;
pub const text = create.text;
pub const raw = create.raw;
pub const attr = create.attr;
pub const none = create.none;

test {
    @import("std").testing.refAllDecls(@This());
}
