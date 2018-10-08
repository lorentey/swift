//===--- StringUTF8.swift - A UTF8 view of String -------------------------===//
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

extension String.UTF8View {
  #if !INTERNAL_CHECKS_ENABLED
  @inlinable @inline(__always) internal func _invariantCheck() {}
  #else
  @usableFromInline @inline(never) @_effects(releasenone)
  internal func _invariantCheck() {
    // TODO: Ensure index alignment
  }
  #endif // INTERNAL_CHECKS_ENABLED
}

extension String.UTF8View: BidirectionalCollection {
  public typealias Index = String.Index

  public typealias Element = UTF8.CodeUnit

  /// The position of the first code unit if the UTF-8 view is
  /// nonempty.
  ///
  /// If the UTF-8 view is empty, `startIndex` is equal to `endIndex`.
  @inlinable
  public var startIndex: Index {
    @inline(__always) get { return _guts.startIndex }
  }

  /// The "past the end" position---that is, the position one
  /// greater than the last valid subscript argument.
  ///
  /// In an empty UTF-8 view, `endIndex` is equal to `startIndex`.
  @inlinable
  public var endIndex: Index {
    @inline(__always) get { return _guts.endIndex }
  }

  /// Returns the next consecutive position after `i`.
  ///
  /// - Precondition: The next position is representable.
  @inlinable @inline(__always)
  public func index(after i: Index) -> Index {
    if _fastPath(_guts.isFastUTF8) {
      return i.nextEncoded
    }

    return _foreignIndex(after: i)
  }

  @inlinable @inline(__always)
  public func index(before i: Index) -> Index {
    precondition(!i.isZeroPosition)
    if _fastPath(_guts.isFastUTF8) {
      return i.priorEncoded
    }

    return _foreignIndex(before: i)
  }

  @inlinable @inline(__always)
  public func index(_ i: Index, offsetBy n: Int) -> Index {
    if _fastPath(_guts.isFastUTF8) {
      _precondition(n + i.encodedOffset <= _guts.count)
      return i.encoded(offsetBy: n)
    }

    return _foreignIndex(i, offsetBy: n)
  }

  @inlinable @inline(__always)
  public func index(
    _ i: Index, offsetBy n: Int, limitedBy limit: Index
  ) -> Index? {
    if _fastPath(_guts.isFastUTF8) {
      // Check the limit: ignore limit if it precedes `i` (in the correct
      // direction), otherwise must not be beyond limit (in the correct
      // direction).
      let iOffset = i.encodedOffset
      let result = iOffset + n
      let limitOffset = limit.encodedOffset
      if n >= 0 {
        guard limitOffset < iOffset || result <= limitOffset else { return nil }
      } else {
        guard limitOffset > iOffset || result >= limitOffset else { return nil }
      }
      return Index(encodedOffset: result)
    }

    return _foreignIndex(i, offsetBy: n, limitedBy: limit)
  }

  @inlinable @inline(__always)
  public func distance(from i: Index, to j: Index) -> Int {
    if _fastPath(_guts.isFastUTF8) {
      return j.encodedOffset &- i.encodedOffset
    }
    return _foreignDistance(from: i, to: j)
  }

  /// Accesses the code unit at the given position.
  ///
  /// The following example uses the subscript to print the value of a
  /// string's first UTF-8 code unit.
  ///
  ///     let greeting = "Hello, friend!"
  ///     let i = greeting.utf8.startIndex
  ///     print("First character's UTF-8 code unit: \(greeting.utf8[i])")
  ///     // Prints "First character's UTF-8 code unit: 72"
  ///
  /// - Parameter position: A valid index of the view. `position`
  ///   must be less than the view's end index.
  @inlinable
  public subscript(i: Index) -> UTF8.CodeUnit {
    @inline(__always) get {
      String(_guts)._boundsCheck(i)
      if _fastPath(_guts.isFastUTF8) {
        return _guts.withFastUTF8 { utf8 in utf8[i.encodedOffset] }
      }

      return _foreignSubscript(position: i)
    }
  }
}

extension String.UTF8View: CustomStringConvertible {
 @inlinable
 public var description: String {
   @inline(__always) get { return String(String(_guts)) }
 }
}

extension String.UTF8View: CustomDebugStringConvertible {
 public var debugDescription: String {
   return "UTF8View(\(self.description.debugDescription))"
 }
}


extension String {
  /// A UTF-8 encoding of `self`.
  @inlinable
  public var utf8: UTF8View {
    @inline(__always) get { return UTF8View(self._guts) }
    set {
      unimplemented_utf8()
    }
  }

  /// A contiguously stored null-terminated UTF-8 representation of the string.
  ///
  /// To access the underlying memory, invoke `withUnsafeBufferPointer` on the
  /// array.
  ///
  ///     let s = "Hello!"
  ///     let bytes = s.utf8CString
  ///     print(bytes)
  ///     // Prints "[72, 101, 108, 108, 111, 33, 0]"
  ///
  ///     bytes.withUnsafeBufferPointer { ptr in
  ///         print(strlen(ptr.baseAddress!))
  ///     }
  ///     // Prints "6"
  public var utf8CString: ContiguousArray<CChar> {
    if _fastPath(_guts.isFastUTF8) {
      var result = _guts.withFastUTF8 { return ContiguousArray($0._asCChar) }
      result.append(0)
      return result
    }

    return _slowUTF8CString()
  }

  @usableFromInline @inline(never) // slow-path
  internal func _slowUTF8CString() -> ContiguousArray<CChar> {
    var result = ContiguousArray<CChar>()
    result.reserveCapacity(self._guts.count + 1)
    for c in self.utf8 {
      result.append(CChar(bitPattern: c))
    }
    result.append(0)
    return result
  }

  /// Creates a string corresponding to the given sequence of UTF-8 code units.
  @available(swift, introduced: 4.0, message:
  "Please use failable String.init?(_:UTF8View) when in Swift 3.2 mode")
  @inlinable @inline(__always)
  public init(_ utf8: UTF8View) {
    self = String(utf8._guts)
  }
}

// TODO(UTF8): design specialized iterator, rather than default indexing one
//extension String.UTF8View {
//  @_fixed_layout // FIXME(sil-serialize-all)
//  public struct Iterator {
//    // TODO(UTF8):
//  }
//
//  public func makeIterator() -> Iterator {
//    unimplemented_utf8()
//  }
//}
//
//extension String.UTF8View.Iterator : IteratorProtocol {
//  public typealias Element = String.UTF8View.Element
//
//  @inlinable @inline(__always)
//  public mutating func next() -> Unicode.UTF8.CodeUnit? {
//    unimplemented_utf8()
//  }
//}

extension String.UTF8View {
  @inlinable
  public var count: Int {
    @inline(__always) get {
      if _fastPath(_guts.isFastUTF8) {
        return _guts.count
      }
      return _foreignCount()
    }
  }
}

// Index conversions
extension String.UTF8View.Index {
  /// Creates an index in the given UTF-8 view that corresponds exactly to the
  /// specified `UTF16View` position.
  ///
  /// The following example finds the position of a space in a string's `utf16`
  /// view and then converts that position to an index in the string's
  /// `utf8` view.
  ///
  ///     let cafe = "Café 🍵"
  ///
  ///     let utf16Index = cafe.utf16.firstIndex(of: 32)!
  ///     let utf8Index = String.UTF8View.Index(utf16Index, within: cafe.utf8)!
  ///
  ///     print(Array(cafe.utf8[..<utf8Index]))
  ///     // Prints "[67, 97, 102, 195, 169]"
  ///
  /// If the position passed in `utf16Index` doesn't have an exact
  /// corresponding position in `utf8`, the result of the initializer is
  /// `nil`. For example, because UTF-8 and UTF-16 represent high Unicode code
  /// points differently, an attempt to convert the position of the trailing
  /// surrogate of a UTF-16 surrogate pair fails.
  ///
  /// The next example attempts to convert the indices of the two UTF-16 code
  /// points that represent the teacup emoji (`"🍵"`). The index of the lead
  /// surrogate is successfully converted to a position in `utf8`, but the
  /// index of the trailing surrogate is not.
  ///
  ///     let emojiHigh = cafe.utf16.index(after: utf16Index)
  ///     print(String.UTF8View.Index(emojiHigh, within: cafe.utf8))
  ///     // Prints "Optional(String.Index(...))"
  ///
  ///     let emojiLow = cafe.utf16.index(after: emojiHigh)
  ///     print(String.UTF8View.Index(emojiLow, within: cafe.utf8))
  ///     // Prints "nil"
  ///
  /// - Parameters:
  ///   - sourcePosition: A position in a `String` or one of its views.
  ///   - target: The `UTF8View` in which to find the new position.
  @inlinable
  public init?(_ idx: String.Index, within target: String.UTF8View) {
    if _slowPath(target._guts.isForeign) {
      guard idx._foreignIsWithin(target) else { return nil }
    } else {
      // All indices, except sub-scalar UTF-16 indices pointing at trailing
      // surrogates, are valid.
      guard idx.transcodedOffset == 0 else { return nil }
    }

    self = idx
  }
}

// Reflection
extension String.UTF8View : CustomReflectable {
  /// Returns a mirror that reflects the UTF-8 view of a string.
  public var customMirror: Mirror {
    return Mirror(self, unlabeledChildren: self)
  }
}

// TODO(UTF8): Can we just unify this view?
//===--- Slicing Support --------------------------------------------------===//
/// In Swift 3.2, in the absence of type context,
///
///   someString.utf8[someString.utf8.startIndex..<someString.utf8.endIndex]
///
/// was deduced to be of type `String.UTF8View`.  Provide a more-specific
/// Swift-3-only `subscript` overload that continues to produce
/// `String.UTF8View`.
extension String.UTF8View {
  public typealias SubSequence = Substring.UTF8View

  @inlinable
  @available(swift, introduced: 4)
  public subscript(r: Range<Index>) -> String.UTF8View.SubSequence {
    return Substring.UTF8View(self, _bounds: r)
  }
}

extension String.UTF8View {
  /// Copies `self` into the supplied buffer.
  ///
  /// - Precondition: The memory in `self` is uninitialized. The buffer must
  ///   contain sufficient uninitialized memory to accommodate
  ///   `source.underestimatedCount`.
  ///
  /// - Postcondition: The `Pointee`s at `buffer[startIndex..<returned index]`
  ///   are initialized.
  @inlinable @inline(__always)
  public func _copyContents(
    initializing buffer: UnsafeMutableBufferPointer<Iterator.Element>
  ) -> (Iterator, UnsafeMutableBufferPointer<Iterator.Element>.Index) {
    guard buffer.baseAddress != nil else {
        _preconditionFailure(
          "Attempt to copy string contents into nil buffer pointer")
    }
    guard let written = _guts.copyUTF8(into: buffer) else {
      _preconditionFailure(
        "Insufficient space allocated to copy string contents")
    }

    let it = String().utf8.makeIterator()
    return (it, buffer.index(buffer.startIndex, offsetBy: written))
  }
}

// Foreign string support
extension String.UTF8View {
  @usableFromInline @inline(never)
  @_effects(releasenone)
  internal func _foreignIndex(after i: Index) -> Index {
    _sanityCheck(_guts.isForeign)

    let (scalar, scalarLen) = _guts.foreignErrorCorrectedScalar(
      startingAt: i.strippingTranscoding)
    let utf8Len = _numUTF8CodeUnits(scalar)

    if utf8Len == 1 {
      _sanityCheck(i.transcodedOffset == 0)
      return i.nextEncoded
    }

    // Check if we're still transcoding sub-scalar
    if i.transcodedOffset < utf8Len - 1 {
      return i.nextTranscoded
    }

    // Skip to the next scalar
    return i.encoded(offsetBy: scalarLen)
  }

  @usableFromInline @inline(never)
  @_effects(releasenone)
  internal func _foreignIndex(before i: Index) -> Index {
    _sanityCheck(_guts.isForeign)
    if i.transcodedOffset != 0 {
      _sanityCheck((1...3) ~= i.transcodedOffset)
      return i.priorTranscoded
    }

    let (scalar, scalarLen) = _guts.foreignErrorCorrectedScalar(
      endingAt: i)
    let utf8Len = _numUTF8CodeUnits(scalar)
    return i.encoded(offsetBy: -scalarLen).transcoded(withOffset: utf8Len &- 1)
  }

  @usableFromInline @inline(never)
  @_effects(releasenone)
  internal func _foreignSubscript(position i: Index) -> UTF8.CodeUnit {
    _sanityCheck(_guts.isForeign)

    let scalar = _guts.foreignErrorCorrectedScalar(
      startingAt: _guts.scalarAlign(i)).0
    let encoded = Unicode.UTF8.encode(scalar)._unsafelyUnwrappedUnchecked
    _sanityCheck(i.transcodedOffset < 1+encoded.count)

    return encoded[
      encoded.index(encoded.startIndex, offsetBy: i.transcodedOffset)]
  }

  @usableFromInline @inline(never)
  @_effects(releasenone)
  internal func _foreignIndex(_ i: Index, offsetBy n: Int) -> Index {
    _sanityCheck(_guts.isForeign)
    return _index(i, offsetBy: n)
  }

  @usableFromInline @inline(never)
  @_effects(releasenone)
  internal func _foreignIndex(
    _ i: Index, offsetBy n: Int, limitedBy limit: Index
  ) -> Index? {
    _sanityCheck(_guts.isForeign)
    return _index(i, offsetBy: n, limitedBy: limit)
  }

  @usableFromInline @inline(never)
  @_effects(releasenone)
  internal func _foreignDistance(from i: Index, to j: Index) -> Int {
    _sanityCheck(_guts.isForeign)
    return _distance(from: i, to: j)
  }

  @usableFromInline @inline(never)
  @_effects(releasenone)
  internal func _foreignCount() -> Int {
    _sanityCheck(_guts.isForeign)
    return _distance(from: startIndex, to: endIndex)
  }
}

extension String.Index {
  @usableFromInline @inline(never) // opaque slow-path
  @_effects(releasenone)
  internal func _foreignIsWithin(_ target: String.UTF8View) -> Bool {
    _sanityCheck(target._guts.isForeign)
    // Currently, foreign means UTF-16.

    // If we're transcoding, we're already a UTF8 view index.
    if self.transcodedOffset != 0 { return true }

    // Otherwise, we must be scalar-aligned, i.e. not pointing at a trailing
    // surrogate.
    return target._guts.isOnUnicodeScalarBoundary(self)
  }
}
