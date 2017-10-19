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

import SwiftShims

#if _runtime(_ObjC)
@_inlineable // FIXME(sil-serialize-all)
@_versioned // FIXME(sil-serialize-all)
@_silgen_name("swift_stdlib_NSStringHashValue")
internal func _stdlib_NSStringHashValue(
  _ str: AnyObject, _ isASCII: Bool) -> Int

@_inlineable // FIXME(sil-serialize-all)
@_versioned // FIXME(sil-serialize-all)
@_silgen_name("swift_stdlib_NSStringHashValuePointer")
internal func _stdlib_NSStringHashValuePointer(
  _ str: OpaquePointer, _ isASCII: Bool) -> Int

@_inlineable // FIXME(sil-serialize-all)
@_versioned // FIXME(sil-serialize-all)
@_silgen_name("swift_stdlib_CFStringHashCString")
internal func _stdlib_CFStringHashCString(
  _ str: OpaquePointer, _ len: Int) -> Int
#endif

extension Unicode {
  // FIXME: cannot be marked @_versioned. See <rdar://problem/34438258>
  // @_inlineable // FIXME(sil-serialize-all)
  // @_versioned // FIXME(sil-serialize-all)
  internal static func hashASCII<Hasher : _Hasher>(
    _ string: UnsafeBufferPointer<UInt8>,
    into hasher: inout Hasher
  ) {
    let collationTable = _swift_stdlib_unicode_getASCIICollationTable()
    for c in string {
      _precondition(c <= 127)
      let element = collationTable[Int(c)]
      // Ignore zero valued collation elements. They don't participate in the
      // ordering relation.
      if element != 0 {
        hasher.append(element)
      }
    }
  }

  // FIXME: cannot be marked @_versioned. See <rdar://problem/34438258>
  // @_inlineable // FIXME(sil-serialize-all)
  // @_versioned // FIXME(sil-serialize-all)
  internal static func hashUTF16<Hasher : _Hasher>(
    _ string: UnsafeBufferPointer<UInt16>,
    into hasher: inout Hasher
  ) {
    let collationIterator = _swift_stdlib_unicodeCollationIterator_create(
      string.baseAddress!,
      UInt32(string.count))
    defer { _swift_stdlib_unicodeCollationIterator_delete(collationIterator) }

    while true {
      var hitEnd = false
      let element =
        _swift_stdlib_unicodeCollationIterator_next(collationIterator, &hitEnd)
      if hitEnd {
        break
      }
      // Ignore zero valued collation elements. They don't participate in the
      // ordering relation.
      if element != 0 {
        hasher.append(element)
      }
    }
  }
}

@_versioned // FIXME(sil-serialize-all)
@inline(never) // Hide the CF dependency
internal func _hashString<Hasher : _Hasher>(
  _ string: String,
  into hasher: inout Hasher
) {
  let core = string._core
#if _runtime(_ObjC)
  // If we have a contiguous string then we can use the stack optimization.
  let isASCII = core.isASCII
  if core.hasContiguousStorage {
    if isASCII {
      hasher.append(_stdlib_CFStringHashCString(OpaquePointer(core.startASCII),
          core.count))
    } else {
      let stackAllocated = _NSContiguousString(core)
      stackAllocated._unsafeWithNotEscapedSelfPointer {
        hasher.append(_stdlib_NSStringHashValuePointer($0, false))
      }
    }
  } else {
    let cocoaString = unsafeBitCast(
      string._bridgeToObjectiveCImpl(), to: _NSStringCore.self)
    hasher.append(_stdlib_NSStringHashValue(cocoaString, isASCII))
  }
#else
  if let asciiBuffer = core.asciiBuffer {
    return Unicode.hashASCII(
      UnsafeBufferPointer(
        start: asciiBuffer.baseAddress!, count: asciiBuffer.count),
      into: &hasher)
  } else {
    return Unicode.hashUTF16(
      UnsafeBufferPointer(start: core.startUTF16, count: core.count),
      into: &hasher)
  }
#endif
}


extension String : Hashable {
  /// The string's hash value.
  ///
  /// Hash values are not guaranteed to be equal across different executions of
  /// your program. Do not save hash values to use during a future execution.
  @_inlineable // FIXME(sil-serialize-all)
  public var hashValue: Int {
    return _hashValue(for: self)
  }

  @_inlineable // FIXME(sil-serialize-all)
  public func _hash<Hasher : _Hasher>(into hasher: inout Hasher) {
    _hashString(self, into: &hasher)
  }
}

