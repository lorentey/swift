//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A type that provides an integer hash value.
///
/// You can use any type that conforms to the `Hashable` protocol in a set or
/// as a dictionary key. Many types in the standard library conform to
/// `Hashable`: Strings, integers, floating-point and Boolean values, and even
/// sets provide a hash value by default. Your own custom types can be
/// hashable as well. When you define an enumeration without associated
/// values, it gains `Hashable` conformance automatically, and you can add
/// `Hashable` conformance to your other custom types by adding a single
/// `hashValue` property.
///
/// A hash value, provided by a type's `hashValue` property, is an integer that
/// is the same for any two instances that compare equally. That is, for two
/// instances `a` and `b` of the same type, if `a == b`, then
/// `a.hashValue == b.hashValue`. The reverse is not true: Two instances with
/// equal hash values are not necessarily equal to each other.
///
/// - Important: Hash values are not guaranteed to be equal across different
///   executions of your program. Do not save hash values to use in a future
///   execution.
///
/// Conforming to the Hashable Protocol
/// ===================================
///
/// To use your own custom type in a set or as the key type of a dictionary,
/// add `Hashable` conformance to your type. The `Hashable` protocol inherits
/// from the `Equatable` protocol, so you must also satisfy that protocol's
/// requirements.
///
/// A custom type's `Hashable` and `Equatable` requirements are automatically
/// synthesized by the compiler when you declare `Hashable` conformance in the
/// type's original declaration and your type meets these criteria:
///
/// - For a `struct`, all its stored properties must conform to `Hashable`.
/// - For an `enum`, all its associated values must conform to `Hashable`. (An
///   `enum` without associated values has `Hashable` conformance even without
///   the declaration.)
///
/// To customize your type's `Hashable` conformance, to adopt `Hashable` in a
/// type that doesn't meet the criteria listed above, or to extend an existing
/// type to conform to `Hashable`, implement the `hashValue` property in your
/// custom type. To ensure that your type meets the semantic requirements of
/// the `Hashable` and `Equatable` protocols, it's a good idea to also
/// customize your type's `Equatable` conformance to match.
///
/// As an example, consider a `GridPoint` type that describes a location in a
/// grid of buttons. Here's the initial declaration of the `GridPoint` type:
///
///     /// A point in an x-y coordinate system.
///     struct GridPoint {
///         var x: Int
///         var y: Int
///     }
///
/// You'd like to create a set of the grid points where a user has already
/// tapped. Because the `GridPoint` type is not hashable yet, it can't be used
/// as the `Element` type for a set. To add `Hashable` conformance, provide an
/// `==` operator function and a `hashValue` property.
///
///     extension GridPoint: Hashable {
///         var hashValue: Int {
///             return x.hashValue ^ y.hashValue &* 16777619
///         }
///
///         static func == (lhs: GridPoint, rhs: GridPoint) -> Bool {
///             return lhs.x == rhs.x && lhs.y == rhs.y
///         }
///     }
///
/// The `hashValue` property in this example combines the hash value of a grid
/// point's `x` property with the hash value of its `y` property multiplied by
/// a prime constant.
///
/// - Note: The above example above is a reasonably good hash function for a
///   simple type. If you're writing a hash function for a custom type, choose
///   a hashing algorithm that is appropriate for the kinds of data your type
///   comprises. Set and dictionary performance depends on hash values that
///   minimize collisions for their associated element and key types,
///   respectively.
///
/// Now that `GridPoint` conforms to the `Hashable` protocol, you can create a
/// set of previously tapped grid points.
///
///     var tappedPoints: Set = [GridPoint(x: 2, y: 3), GridPoint(x: 4, y: 1)]
///     let nextTap = GridPoint(x: 0, y: 1)
///     if tappedPoints.contains(nextTap) {
///         print("Already tapped at (\(nextTap.x), \(nextTap.y)).")
///     } else {
///         tappedPoints.insert(nextTap)
///         print("New tap detected at (\(nextTap.x), \(nextTap.y)).")
///     }
///     // Prints "New tap detected at (0, 1).")
public protocol Hashable : Equatable {
  /// The hash value.
  ///
  /// Hash values are not guaranteed to be equal across different executions of
  /// your program. Do not save hash values to use during a future execution.
  var hashValue: Int { get }

  func _hash(into hasher: _Hasher) -> _Hasher
}

@_versioned
@_inlineable
@inline(__always)
internal func _defaultHashValue<T : Hashable>(for value: T) -> Int {
  return _Hasher(_inlineable: ()).appending(value).finalized()
}

extension Hashable {
  @_inlineable
  @inline(__always)
  public func _hash(into hasher: _Hasher) -> _Hasher {
    return hasher.appending(self.hashValue)
  }
}

// Called by the SwiftValue implementation.
@_silgen_name("_swift_stdlib_Hashable_isEqual_indirect")
internal func Hashable_isEqual_indirect<T : Hashable>(
  _ lhs: UnsafePointer<T>,
  _ rhs: UnsafePointer<T>
) -> Bool {
  return lhs.pointee == rhs.pointee
}

// Called by the SwiftValue implementation.
@_silgen_name("_swift_stdlib_Hashable_hashValue_indirect")
internal func Hashable_hashValue_indirect<T : Hashable>(
  _ value: UnsafePointer<T>
) -> Int {
  return value.pointee.hashValue
}

// FIXME: This is purely for benchmarking; to be removed.
@_fixed_layout
public struct _QuickHasher {
  @_versioned
  internal var _hash: Int

  @inline(never)
  public init() {
    _hash = 0
  }

  @_inlineable
  @_versioned
  internal init(_inlineable: Void) {
    _hash = 0
  }

  @inline(never)
  @effects(readonly)
  public func appending(_ value: Int) -> _QuickHasher {
    var hasher = self
    hasher._append_alwaysInline(value)
    return hasher
  }

  //@inline(__always)
  @_inlineable
  @_transparent
  public func appending<H: Hashable>(_ value: H) -> _QuickHasher {
    return value._hash(into: self)
  }

  @inline(never)
  public mutating func append(_ value: Int) {
    _append_alwaysInline(value)
  }

  @_inlineable
  @_versioned
  @inline(__always)
  internal mutating func _append_alwaysInline(_ value: Int) {
    if _hash == 0 {
      _hash = value
      return
    }
    _hash = _combineHashValues(_hash, value)
  }

  @_inlineable // FIXME(sil-serialize-all)
  public func finalized() -> Int {
    var hasher = self
    return hasher._finalize_alwaysInline()
  }

  @inline(never)
  public mutating func finalize() -> Int {
    return _finalize_alwaysInline()
  }

  @_inlineable // FIXME(sil-serialize-all)
  @_versioned
  @inline(__always)
  internal mutating func _finalize_alwaysInline() -> Int {
    return _mixInt(_hash)
  }
}

public typealias _Hasher = _QuickHasher
