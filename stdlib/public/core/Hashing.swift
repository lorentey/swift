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

//
// This file implements helpers for hashing collections.
//

import SwiftShims // For _SwiftNSFastEnumerationState

/// The inverse of the default hash table load factor.  Factored out so that it
/// can be used in multiple places in the implementation and stay consistent.
/// Should not be used outside `Dictionary` implementation.
@usableFromInline @_transparent
internal var _hashContainerDefaultMaxLoadFactorInverse: Double {
  return 1.0 / 0.75
}

#if _runtime(_ObjC)
/// Call `[lhs isEqual: rhs]`.
///
/// This function is part of the runtime because `Bool` type is bridged to
/// `ObjCBool`, which is in Foundation overlay.
@_silgen_name("swift_stdlib_NSObject_isEqual")
internal func _stdlib_NSObject_isEqual(_ lhs: AnyObject, _ rhs: AnyObject) -> Bool
#endif


/// A temporary view of an array of AnyObject as an array of Unmanaged<AnyObject>
/// for fast iteration and transformation of the elements.
///
/// Accesses the underlying raw memory as Unmanaged<AnyObject> using untyped
/// memory accesses. The memory remains bound to managed AnyObjects.
internal struct _UnmanagedAnyObjectArray {
  /// Underlying pointer.
  internal var value: UnsafeMutableRawPointer

  internal init(_ up: UnsafeMutablePointer<AnyObject>) {
    self.value = UnsafeMutableRawPointer(up)
  }

  internal init?(_ up: UnsafeMutablePointer<AnyObject>?) {
    guard let unwrapped = up else { return nil }
    self.init(unwrapped)
  }

  internal subscript(i: Int) -> AnyObject {
    get {
      let unmanaged = value.load(
        fromByteOffset: i * MemoryLayout<AnyObject>.stride,
        as: Unmanaged<AnyObject>.self)
      return unmanaged.takeUnretainedValue()
    }
    nonmutating set(newValue) {
      let unmanaged = Unmanaged.passUnretained(newValue)
      value.storeBytes(of: unmanaged,
        toByteOffset: i * MemoryLayout<AnyObject>.stride,
        as: Unmanaged<AnyObject>.self)
    }
  }
}


#if _runtime(_ObjC)
/// An NSEnumerator implementation returning zero elements. This is useful when
/// a concrete element type is not recoverable from the empty singleton.
final internal class _SwiftEmptyNSEnumerator
  : _SwiftNativeNSEnumerator, _NSEnumerator {
  internal override required init() {
    _sanityCheckFailure("don't call this designated initializer")
  }

  @objc
  internal func nextObject() -> AnyObject? {
    return nil
  }

  @objc(countByEnumeratingWithState:objects:count:)
  internal func countByEnumerating(
    with state: UnsafeMutablePointer<_SwiftNSFastEnumerationState>,
    objects: UnsafeMutablePointer<AnyObject>,
    count: Int
  ) -> Int {
    // Even though we never do anything in here, we need to update the
    // state so that callers know we actually ran.
    var theState = state.pointee
    if theState.state == 0 {
      theState.state = 1 // Arbitrary non-zero value.
      theState.itemsPtr = AutoreleasingUnsafeMutablePointer(objects)
      theState.mutationsPtr = _fastEnumerationStorageMutationsPtr
    }
    state.pointee = theState
    return 0
  }
}
#endif

#if _runtime(_ObjC)
/// This is a minimal class holding a single tail-allocated flat buffer,
/// representing hash table storage for AnyObject elements. This is used to
/// store bridged elements in deferred bridging scenarios. Lacking a _HashTable,
/// instances of this class don't know which of their elements are initialized,
/// so they can't be used on their own.
///
/// Using a dedicated class for this rather than a _HeapBuffer makes it easy to
/// recognize these in heap dumps etc.
internal final class _BridgingHashBuffer {
  internal var _bucketCount: Int

  // This type is made with allocWithTailElems, so no init is ever called.
  // But we still need to have an init to satisfy the compiler.
  private init(_doNotUse: ()) {
    _sanityCheckFailure("This class cannot be directly initialized")
  }

  internal static func create(bucketCount: Int) -> _BridgingHashBuffer {
    let object = Builtin.allocWithTailElems_1(
      _BridgingHashBuffer.self,
      bucketCount._builtinWordValue, AnyObject.self)
    object._bucketCount = bucketCount
    return object
  }

  deinit {
    _sanityCheck(_bucketCount == -1)
  }

  private var _baseAddress: UnsafeMutablePointer<AnyObject> {
    let ptr = Builtin.projectTailElems(self, AnyObject.self)
    return UnsafeMutablePointer(ptr)
  }

  internal subscript(index: _HashTable.Index) -> AnyObject {
    _sanityCheck(index.bucket >= 0 && index.bucket < _bucketCount)
    return _baseAddress[index.bucket]
  }

  internal func initialize(at index: _HashTable.Index, to object: AnyObject) {
    _sanityCheck(index.bucket >= 0 && index.bucket < _bucketCount)
    (_baseAddress + index.bucket).initialize(to: object)
  }

  internal func invalidate(with indices: _HashTable.OccupiedIndices) {
    for index in indices {
      (_baseAddress + index.bucket).deinitialize(count: 1)
    }
    _bucketCount = -1
  }
}
#endif
