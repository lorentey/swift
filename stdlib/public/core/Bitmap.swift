//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A simple bitmap of a fixed number of bits, implementing a sorted set of
/// small nonnegative Int values.
///
/// Because `_UnsafeBitset` implements a flat bit vector, it isn't suitable for
/// holding arbitrarily large integers. The maximal element a bitset can store
/// is fixed at its initialization.
@_fixed_layout
@usableFromInline // @testable
internal struct _UnsafeBitset {
  @usableFromInline
  internal let words: UnsafeMutablePointer<Word>

  @usableFromInline
  internal let wordCount: Int

  @inlinable
  @inline(__always)
  internal init(words: UnsafeMutablePointer<Word>, wordCount: Int) {
    self.words = words
    self.wordCount = wordCount
  }
}

extension _UnsafeBitset {
  @inlinable
  @inline(__always)
  internal static func word(for element: Int) -> Int {
    return element / Word.capacity
  }

  @inlinable
  @inline(__always)
  internal static func bit(for element: Int) -> Int {
    // Note: We perform on UInts to get faster unsigned math (masking).
    return Int(UInt(element) % UInt(Word.capacity))
  }

  @inlinable
  @inline(__always)
  internal static func split(_ element: Int) -> (word: Int, bit: Int) {
    return (word(for: element), bit(for: element))
  }

  @inlinable
  @inline(__always)
  internal static func join(word: Int, bit: Int) -> Int {
    _sanityCheck(bit >= 0 && bit < Word.capacity)
    return word * Word.capacity + bit
  }
}

extension _UnsafeBitset {
  @inlinable
  @inline(__always)
  internal static func wordCount(forCapacity capacity: Int) -> Int {
    return (capacity + Word.capacity - 1) / Word.capacity
  }

  @inlinable
  internal var capacity: Int {
    @inline(__always)
    get {
      return wordCount * Word.capacity
    }
  }

  @inlinable
  @inline(__always)
  internal func isValid(_ element: Int) -> Bool {
    return element >= 0 && element <= capacity
  }

  @inlinable
  internal func contains(_ element: Int) -> Bool {
    _precondition(isValid(element), "Value out of bounds")
    return uncheckedContains(element)
  }

  @inlinable
  @inline(__always)
  internal func uncheckedContains(_ element: Int) -> Bool {
    _sanityCheck(isValid(element), "Value out of bounds")
    let (word, bit) = _UnsafeBitset.split(element)
    return words[word].uncheckedContains(bit)
  }

  @inlinable
  @discardableResult
  internal mutating func insert(
    _ element: Int
  ) -> (inserted: Bool, memberAfterInsert: Int) {
    _precondition(isValid(element), "Value out of bounds")
    return (uncheckedInsert(element), element)
  }

  @inlinable
  @inline(__always)
  @discardableResult
  internal mutating func uncheckedInsert(_ element: Int) -> Bool {
    _sanityCheck(isValid(element), "Value out of bounds")
    let (word, bit) = _UnsafeBitset.split(element)
    return words[word].uncheckedInsert(bit)
  }

  @inlinable
  @discardableResult
  internal mutating func remove(_ element: Int) -> Int? {
    _precondition(isValid(element), "Value out of bounds")
    return uncheckedRemove(element) ? element : nil
  }

  @inlinable
  @inline(__always)
  @discardableResult
  internal mutating func uncheckedRemove(_ element: Int) -> Bool {
    _sanityCheck(isValid(element), "Value out of bounds")
    let (word, bit) = _UnsafeBitset.split(element)
    return words[word].uncheckedRemove(bit)
  }

  @inlinable
  @inline(__always)
  internal func removeAll() {
    words.assign(repeating: .empty, count: wordCount)
  }
}

extension _UnsafeBitset: Sequence {
  @usableFromInline
  internal typealias Element = Int

  @inlinable
  internal var count: Int {
    var count = 0
    for w in 0 ..< wordCount {
      count += words[w].count
    }
    return count
  }

  @inlinable
  internal var underestimatedCount: Int {
    return count
  }

  @inlinable
  func makeIterator() -> Iterator {
    return Iterator(self)
  }

  @usableFromInline
  @_fixed_layout
  internal struct Iterator: IteratorProtocol {
    @usableFromInline
    internal let bitmap: _UnsafeBitset
    @usableFromInline
    internal var index: Int
    @usableFromInline
    internal var word: Word

    @inlinable
    internal init(_ bitmap: _UnsafeBitset) {
      self.bitmap = bitmap
      self.index = 0
      self.word = bitmap.wordCount > 0 ? bitmap.words[0] : .empty
    }

    @inlinable
    internal mutating func next() -> Int? {
      if let bit = word.next() {
        return _UnsafeBitset.join(word: index, bit: bit)
      }
      while (index + 1) < bitmap.wordCount {
        index += 1
        word = bitmap.words[index]
        if let bit = word.next() {
          return _UnsafeBitset.join(word: index, bit: bit)
        }
      }
      return nil
    }
  }
}

////////////////////////////////////////////////////////////////////////////////

extension _UnsafeBitset {
  @_fixed_layout
  @usableFromInline
  internal struct Word {
    @usableFromInline
    internal var value: UInt

    @inlinable
    internal init(_ value: UInt) {
      self.value = value
    }
  }
}

extension _UnsafeBitset.Word {
  @inlinable
  internal static var capacity: Int {
    @inline(__always)
    get {
      return UInt.bitWidth
    }
  }

  @inlinable
  @inline(__always)
  internal func uncheckedContains(_ bit: Int) -> Bool {
    _sanityCheck(bit >= 0 && bit < UInt.bitWidth)
    return value & (1 &<< bit) != 0
  }

  @inlinable
  @inline(__always)
  @discardableResult
  internal mutating func uncheckedInsert(_ bit: Int) -> Bool {
    _sanityCheck(bit >= 0 && bit < UInt.bitWidth)
    let mask: UInt = 1 &<< bit
    let inserted = value & mask == 0
    value |= mask
    return inserted
  }

  @inlinable
  @inline(__always)
  @discardableResult
  internal mutating func uncheckedRemove(_ bit: Int) -> Bool {
    _sanityCheck(bit >= 0 && bit < UInt.bitWidth)
    let mask: UInt = 1 &<< bit
    let removed = value & mask != 0
    value &= ~mask
    return removed
  }
}

extension _UnsafeBitset.Word {
  @inlinable
  var minimum: Int? {
    @inline(__always)
    get {
      guard value != 0 else { return nil }
      return value.trailingZeroBitCount
    }
  }

  @inlinable
  var maximum: Int? {
    @inline(__always)
    get {
      guard value != 0 else { return nil }
      return _UnsafeBitset.Word.capacity &- 1 &- value.leadingZeroBitCount
    }
  }

  @inlinable
  var complement: _UnsafeBitset.Word {
    @inline(__always)
    get {
      return _UnsafeBitset.Word(~value)
    }
  }

  @inlinable
  @inline(__always)
  internal func subtracting(elementsBelow bit: Int) -> _UnsafeBitset.Word {
    _sanityCheck(bit >= 0 && bit < _UnsafeBitset.Word.capacity)
    let mask = UInt.max &<< bit
    return _UnsafeBitset.Word(value & mask)
  }

  @inlinable
  @inline(__always)
  internal func intersecting(elementsBelow bit: Int) -> _UnsafeBitset.Word {
    _sanityCheck(bit >= 0 && bit < _UnsafeBitset.Word.capacity)
    let mask: UInt = (1 as UInt &<< bit) &- 1
    return _UnsafeBitset.Word(value & mask)
  }

  @inlinable
  @inline(__always)
  internal func intersecting(elementsAbove bit: Int) -> _UnsafeBitset.Word {
    _sanityCheck(bit >= 0 && bit < _UnsafeBitset.Word.capacity)
    let mask = (UInt.max &<< bit) &<< 1
    return _UnsafeBitset.Word(value & mask)
  }
}

extension _UnsafeBitset.Word {
  @inlinable
  internal static var empty: _UnsafeBitset.Word {
    @inline(__always)
    get {
      return _UnsafeBitset.Word(0)
    }
  }

  @inlinable
  internal static var allBits: _UnsafeBitset.Word {
    @inline(__always)
    get {
      return _UnsafeBitset.Word(UInt.max)
    }
  }
}

// Word implements Sequence by using a copy of itself as its Iterator.
// Iteration with `next()` destroys the word's value; however, this won't cause
// problems in normal use, because `next()` is usually called on a separate
// iterator, not the original word.
extension _UnsafeBitset.Word: Sequence, IteratorProtocol {
  @inlinable
  internal var count: Int {
    return value.nonzeroBitCount
  }

  @inlinable
  internal var underestimatedCount: Int {
    return count
  }

  @inlinable
  internal var isEmpty: Bool {
    @inline(__always)
    get {
      return value == 0
    }
  }

  /// Return the index of the lowest set bit in this word,
  /// and also destructively clear it.
  @inlinable
  internal mutating func next() -> Int? {
    guard value != 0 else { return nil }
    let bit = value.trailingZeroBitCount
    value &= value &- 1       // Clear lowest nonzero bit.
    return bit
  }
}


/// A simple bitmap of a fixed number of bits, implementing a partial SetAlgebra
/// of small nonnegative Int values.
///
/// Because `_Bitset` implements a flat bit vector, it isn't suitable for
/// holding arbitrarily large integers. The maximal element a bitset can store
/// is fixed at its initialization; it uses this to determine how much space it
/// needs to allocate for storage. Storage is allocated up front.
///
@_fixed_layout
@usableFromInline
internal struct _Bitset {
  /// FIXME: Conform to the full SetAlgebra protocol. Allow resizing after init.
  @usableFromInline
  typealias Word = _UnsafeBitset.Word

  @usableFromInline
  internal var _count: Int

  @usableFromInline
  internal var _word0: Word

  @usableFromInline
  internal var _storage: Storage?

  @inlinable
  internal init(capacity: Int) {
    _sanityCheck(capacity >= 0)
    _count = 0
    _word0 = 0
    let wordCount = _UnsafeBitset.wordCount(forCapacity: capacity)
    _storage = wordCount > 1 ? Storage.allocate(wordCount: wordCount - 1) : nil
  }
}

extension _Bitset {
  @inlinable
  @inline(__always)
  internal func _isValid(_ element: Int) -> Bool {
    return element >= 0 && element <= _bitCount
  }

  @inlinable
  @inline(__always)
  internal mutating func isUniquelyReferenced() -> Bool {
    return _isUnique_native(&_storage)
  }
  @inlinable
  @inline(__always)
  internal mutating func ensureUnique() {
    let isUnique = isUniquelyReferenced()
    if !isUnique, let storage = _storage {
      _storage = storage.copy()
    }
  }
}

extension _Bitset {
  @inlinable
  internal var capacity: Int {
    @inline(__always) get {
      return Word.capacity + (storage?.bitset.capacity ?? 0)
    }
  }

  @inlinable
  @inline(__always)
  internal func uncheckedContains(_ element: Int) -> Bool {
    _sanityCheck(_isValid(element))
    if element < Word.capacity {
      return _word0.uncheckedContains(element)
    }
    defer { _fixLifetime(_storage) }
    return _storage!.bitmap.uncheckedContains(element &- Word.capacity)
  }

  @inlinable
  @inline(__always)
  @discardableResult
  internal mutating func uncheckedInsert(_ element: Int) -> Bool {
    _sanityCheck(_isValid(element))
    let inserted: Bool
    if element < Word.capacity {
      inserted = _word0.uncheckedInsert(element)
    } else {
      ensureUnique()
      defer { _fixLifetime(_storage) }
      inserted = _storage!.bitmap.uncheckedInsert(element &- Word.capacity)
    }
    if inserted {
      _count += 1
      _sanityCheck(_count <= capacity)
    }
    return inserted
  }

  @inlinable
  @inline(__always)
  @discardableResult
  internal mutating func uncheckedRemove(_ element: Int) -> Bool {
    _sanityCheck(_isValid(element))
    let removed: Bool
    if element < Word.capacity {
      removed = _word0.uncheckedRemove(element)
    } else {
      ensureUnique()
      defer { _fixLifetime(_storage) }
      removed = _storage!.bitmap.uncheckedRemove(element &- Word.capacity)
    }
    if removed {
      _count -= 1
      _sanityCheck(_count >= 0)
    }
    return removed
  }
}

extension _Bitset: Sequence {
  @usableFromInline
  internal typealias Element = Int

  @inlinable
  internal var count: Int {
    @inline(__always) get { return _count }
  }

  @inlinable
  internal var underestimatedCount: Int {
    @inline(__always) get { return _count }
  }

  @inlinable
  func makeIterator() -> Iterator {
    return Iterator(self)
  }

  @usableFromInline
  @_fixed_layout
  internal struct Iterator: IteratorProtocol {
    @usableFromInline
    internal var _word: Word
    @usableFromInline
    internal var _wordIndex: Int
    @usableFromInline
    internal let _storage: Storage?

    @inlinable
    internal init(_ bitmap: _Bitmap) {
      self._word = bitmap._word0
      self._wordIndex = 0
      self._storage = bitmap._storage
    }

    @inlinable
    internal mutating func next() -> Int? {
      if let v = _word.next() {
        return _wordIndex * Word.bitWidth + v
      }
      guard let storage = _storage else { return nil }
      while _wordIndex < storage._wordCount {
        _word = storage._words[_wordIndex]
        // Note that _wordIndex is offset by 1 due to word0;
        // this is why the index needs to be incremented at exactly this point.
        _wordIndex += 1
        if let v = _word.next() {
          return _wordIndex * Word.bitWidth + v
        }
      }
      return nil
    }
  }
}

////////////////////////////////////////////////////////////////////////////////

extension _Bitset {
  /// A simple bitmap storage class with room for a specific number of
  /// tail-allocated bits.
  @_fixed_layout
  @usableFromInline
  internal final class Storage {
    @usableFromInline
    internal fileprivate(set) var _wordCount: Int

    internal init(_doNotCall: ()) {
      _sanityCheckFailure("This class cannot be directly initialized")
    }
  }
}

extension _Bitset.Storage {
  @usableFromInline
  internal typealias Word = _Bitmap.Word

  internal static func _allocateUninitialized(
    wordCount: Int
  ) -> _Bitset.Storage {
    let storage = Builtin.allocWithTailElems_1(
      _Bitset.Storage.self,
      wordCount._builtinWordValue, Word.self)
    storage._wordCount = wordCount
    return storage
  }

  @usableFromInline
  @_effects(releasenone)
  internal static func allocate(bitCount: Int) -> _Bitset.Storage {
    let wordCount = _Bitset.Storage.wordCount(forBitCount: bitCount)
    let storage = _allocateUninitialized(wordCount: wordCount)
    storage._words.initialize(repeating: .empty, count: storage._wordCount)
    return storage
  }

  @usableFromInline
  @_effects(releasenone)
  internal func copy() -> _Bitset.Storage {
    let storage = _Bitset.Storage._allocateUninitialized(wordCount: _wordCount)
    storage._words.initialize(from: self._words, count: storage._wordCount)
    return storage
  }

  @inlinable
  internal var _words: UnsafeMutablePointer<Word> {
    @inline(__always)
    get {
      let addr = Builtin.projectTailElems(self, Word.self)
      return UnsafeMutablePointer(addr)
    }
  }

  @inlinable
  internal var bitset: _UnsafeBitset {
    @inline(__always) get {
      return _UnsafeBitset(words: _words, wordCount: _wordCount)
    }
  }

  @inlinable
  @inline(__always)
  internal func _isValid(_ word: Int) -> Bool {
    return word >= 0 && word < _wordCount
  }
}
