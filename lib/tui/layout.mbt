///|
/// Layout manager for TUI split-screen layout.
///
/// Provides a tree-based layout system where each node has a direction
/// (horizontal/vertical), constraints, and children. The layout manager
/// recursively computes positions for all nodes based on available space.

///|
/// Direction for laying out child nodes.
pub(all) enum LayoutDirection {
  /// Children are arranged left-to-right.
  Horizontal
  /// Children are arranged top-to-bottom.
  Vertical
} derive(Eq, Debug, Show)

///|
/// Size constraints and flex weight for a layout node.
pub(all) struct LayoutConstraints {
  /// Minimum width in columns.
  min_width : Int
  /// Maximum width in columns (0 = unbounded).
  max_width : Int
  /// Minimum height in rows.
  min_height : Int
  /// Maximum height in rows (0 = unbounded).
  max_height : Int
  /// Flex weight for distributing remaining space (1.0 = equal share).
  weight : Double
} derive(Debug)

///|
/// Default constraints with no minimum and weight 1.0.
pub fn LayoutConstraints::default_() -> LayoutConstraints {
  { min_width: 0, max_width: 0, min_height: 0, max_height: 0, weight: 1.0 }
}

///|
/// A node in the layout tree.
pub(all) struct LayoutNode {
  /// Unique identifier for this node.
  id : String
  /// Layout direction for children.
  direction : LayoutDirection
  /// Size constraints and flex weight.
  constraints : LayoutConstraints
  /// Child nodes.
  mut children : Array[LayoutNode]
  /// Computed rectangle: (x, y, width, height).
  mut computed_rect : (Int, Int, Int, Int)
} derive(Debug)

///|
/// Create a new layout node with the given id and direction.
pub fn LayoutNode::new(id : String, direction : LayoutDirection) -> LayoutNode {
  {
    id,
    direction,
    constraints: LayoutConstraints::default_(),
    children: [],
    computed_rect: (0, 0, 0, 0),
  }
}

///|
/// Create a new layout node with custom constraints.
pub fn LayoutNode::with_constraints(
  id : String,
  direction : LayoutDirection,
  constraints : LayoutConstraints,
) -> LayoutNode {
  { id, direction, constraints, children: [], computed_rect: (0, 0, 0, 0) }
}

///|
/// Root-level layout manager that owns the layout tree and screen dimensions.
pub(all) struct LayoutManager {
  /// Root node of the layout tree.
  root : LayoutNode
  /// Current screen width in columns.
  mut screen_width : Int
  /// Current screen height in rows.
  mut screen_height : Int
} derive(Debug)

///|
/// Create a new LayoutManager with the given screen dimensions.
///
/// The root node fills the entire screen and lays out children vertically.
pub fn LayoutManager::new(width : Int, height : Int) -> LayoutManager {
  let root = LayoutNode::new("root", Vertical)
  root.computed_rect = (0, 0, width, height)
  { root, screen_width: width, screen_height: height }
}

///|
/// Add a child node under the parent identified by `parent_id`.
///
/// Returns Err if the parent node is not found.
pub fn LayoutManager::add_child(
  self : LayoutManager,
  parent_id : String,
  node : LayoutNode,
) -> Result[Unit, String] {
  match find_node_mut(self.root, parent_id) {
    Some(parent) => {
      parent.children.push(node)
      Ok(())
    }
    None => Err("Parent node not found: \{parent_id}")
  }
}

///|
/// Remove a node by its id from anywhere in the tree.
///
/// Returns Err if the node is not found.
pub fn LayoutManager::remove_child(
  self : LayoutManager,
  node_id : String,
) -> Result[Unit, String] {
  if remove_from_children(self.root, node_id) {
    Ok(())
  } else {
    Err("Node not found: \{node_id}")
  }
}

///|
/// Compute the layout for all nodes based on current screen dimensions.
///
/// This recursively assigns `computed_rect` to every node in the tree.
pub fn LayoutManager::compute_layout(self : LayoutManager) -> Unit {
  self.root.computed_rect = (0, 0, self.screen_width, self.screen_height)
  compute_node_layout(self.root)
}

///|
/// Resize the layout to new screen dimensions and recompute.
pub fn LayoutManager::resize(
  self : LayoutManager,
  width : Int,
  height : Int,
) -> Unit {
  self.screen_width = width
  self.screen_height = height
  self.compute_layout()
}

///|
/// Find a node by its id in the layout tree.
///
/// Returns None if not found.
pub fn LayoutManager::find_node(
  self : LayoutManager,
  id : String,
) -> LayoutNode? {
  find_node_impl(self.root, id)
}

// ── Internal helpers ────────────────────────────────────────────────

///|
/// Recursively compute layout for a node's children.
fn compute_node_layout(node : LayoutNode) -> Unit {
  if node.children.length() == 0 {
    return
  }

  let (x, y, w, h) = node.computed_rect
  let children = node.children
  let n = children.length()

  // Calculate total weight and fixed space
  let mut total_weight = 0.0
  for child in children {
    total_weight = total_weight + child.constraints.weight
  }
  if total_weight <= 0.0 {
    total_weight = 1.0
  }

  match node.direction {
    Vertical => {
      // Distribute height among children
      let mut current_y = y
      for i = 0; i < n; i = i + 1 {
        let child = children[i]
        let child_h = compute_child_size(
          child.constraints,
          h,
          total_weight,
          i,
          n,
        )
        let actual_h = clamp_size(
          child.constraints.min_height,
          child.constraints.max_height,
          child_h,
        )
        child.computed_rect = (x, current_y, w, actual_h)
        compute_node_layout(child)
        current_y = current_y + actual_h
      }
    }
    Horizontal => {
      // Distribute width among children
      let mut current_x = x
      for i = 0; i < n; i = i + 1 {
        let child = children[i]
        let child_w = compute_child_size(
          child.constraints,
          w,
          total_weight,
          i,
          n,
        )
        let actual_w = clamp_size(
          child.constraints.min_width,
          child.constraints.max_width,
          child_w,
        )
        child.computed_rect = (current_x, y, actual_w, h)
        compute_node_layout(child)
        current_x = current_x + actual_w
      }
    }
  }
}

///|
/// Compute a child's share of available space.
fn compute_child_size(
  constraints : LayoutConstraints,
  available : Int,
  total_weight : Double,
  _index : Int,
  _count : Int,
) -> Int {
  let share = (available.to_double() * constraints.weight / total_weight).to_int()
  share
}

///|
/// Clamp a size value between min and max (0 max = unbounded).
fn clamp_size(min_val : Int, max_val : Int, value : Int) -> Int {
  let v = if value < min_val { min_val } else { value }
  if max_val > 0 && v > max_val {
    max_val
  } else {
    v
  }
}

///|
/// Find a mutable reference to a node by id.
fn find_node_mut(node : LayoutNode, id : String) -> LayoutNode? {
  if node.id == id {
    return Some(node)
  }
  for child in node.children {
    match find_node_mut(child, id) {
      Some(found) => return Some(found)
      None => ()
    }
  }
  None
}

///|
/// Find a node by id (immutable).
fn find_node_impl(node : LayoutNode, id : String) -> LayoutNode? {
  if node.id == id {
    return Some(node)
  }
  for child in node.children {
    match find_node_impl(child, id) {
      Some(found) => return Some(found)
      None => ()
    }
  }
  None
}

///|
/// Remove a child node by id from a parent's children array.
fn remove_from_children(node : LayoutNode, id : String) -> Bool {
  let children = node.children
  let mut i = 0
  while i < children.length() {
    if children[i].id == id {
      // Remove by rebuilding array without that element
      let new_children : Array[LayoutNode] = []
      for j = 0; j < children.length(); j = j + 1 {
        if j != i {
          new_children.push(children[j])
        }
      }
      // Clear and repopulate
      while children.length() > 0 {
        let _ = children.pop()
      }
      for c in new_children {
        children.push(c)
      }
      return true
    }
    if remove_from_children(children[i], id) {
      return true
    }
    i = i + 1
  }
  false
}
