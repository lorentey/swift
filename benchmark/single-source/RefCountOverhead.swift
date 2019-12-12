
enum EnumSearchTree<Element: Comparable> {
  case empty
  indirect case node(EnumSearchTree<Element>, Element, EnumSearchTree<Element>)
}

extension EnumSearchTree {
  func forEach(_ body: (Element) -> Void) {
    switch self {
    case .empty:
      break
    case let .node(left, value, right):
      left.forEach(body)
      body(value)
      right.forEach(body)
    }
  }

  func contains(_ value: Element) -> Bool {
    switch self {
    case .empty:
      return false
    case let .node(left, v, right):
      if value == v { return true }
      return value < v ? left.contains(value) : right.contains(value)
    }
  }

  func inserting(_ value: Element) -> EnumSearchTree {
    switch self {
    case .empty:
      return .node(.empty, value, .empty)
    case let .node(left, root, right):
      if value == root {
        return self
      } else if value < root {
        return .node(left.inserting(value), root, right)
      } else {
        return .node(left, root, right.inserting(value))
      }
    }
  }
}

struct UnmanagedSearchTree<Element: Comparable> {
  class Node {
    var value: Element
    var left: UnmanagedSearchTree
    var right: UnmanagedSearchTree

    init(
      value: Element,
      left: UnmanagedSearchTree = .empty,
      right: UnmanagedSearchTree = .empty
    ) {
      self.left = left
      self.right = right
      self.value = value
    }
  }

  static let empty = UnmanagedSearchTree()

  var root: Unmanaged<Node>?

  init() {
    self.root = nil
  }

  init(_root: Unmanaged<Node>?) {
    self.root = _root
  }
}

extension UnmanagedSearchTree {
  mutating func deallocate() {
    guard let root = root else { return }
    root.left.deallocate()
    root.right.deallocate()
    root = nil
  }
}

extension UnmanagedSearchTree {
  func forEach(_ body: (Element) -> Void) {
    guard let root = root else { return }
    root._withUnsafeGuaranteedRef { root in
      root.left.forEach(body)
      body(root.value)
      root.right.forEach(body)
    }
  }

  func contains(_ value: Element) -> Bool {
    guard let root = root else { return false }
    return root._withUnsafeGuaranteedRef { root in
      if value == root.value { return true }
      return value < root.value
        ? root.left.contains(value)
        : root.right.contains(value)
    }
  }

  mutating func insert(_ value: Element) {
    guard let root = root else {
      root = Unmanaged.takeRetainedValue(Node(value: value))
      return
    }
    root._withUnsafeGuaranteedRef { root in
      if value == root.value {
        return
      } else if value < root.value {
        root.left.insert(value)
      } else {
        root.right.insert(value)
      }
    }
  }
}

struct PointerSearchTree<Element: Comparable> {
  struct Node {
    var value: Element
    var left: PointerSearchTree = .empty
    var right: PointerSearchTree = .empty
  }

  static let empty = PointerSearchTree()

  var root: UnsafeMutablePointer<Node>?

  init() {
    self.root = nil
  }

  init(_root: UnsafeMutablePointer<Node>?) {
    self.root = _root
  }
}

extension PointerSearchTree {
  mutating func deallocate() {
    guard let root = root else { return }
    root.pointee.left.deallocate()
    root.pointee.right.deallocate()
    root = nil
  }
}

extension PointerSearchTree {
  func forEach(_ body: (Element) -> Void) {
    guard let root = root else { return }
    root.pointee.left.forEach(body)
    body(root.pointee.value)
    root.pointee.right.forEach(body)
  }

  func contains(_ value: Element) -> Bool {
    guard let root = root else { return }
    if value == root.pointee.value { return true }
    if value < root.pointee.value { return root.left.contains(value) }
    return root.right.contains(value)
  }

  mutating func insert(_ value: Element) {
    guard let root = root else {
      let node = UnsafeMutablePointer<Node>.allocate(capacity: 1)
      node.initialize(to: Node(value: value))
      root = node
      return
    }
    if value == root.pointee.value {
      return
    } else if value < root.pointee.value {
      root.pointee.left.insert(value)
    } else {
      root.pointee.right.insert(value)
    }
  }
}
