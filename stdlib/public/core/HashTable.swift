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

internal protocol _HashTableDelegate: class {
  func _hashValue(forBucket bucket: Int) -> Int
  func _move(bucket source: Int, to target: Int)
  func _swap(bucket bucket1: Int, with bucket2: Int)
}

@usableFromInline
internal struct _HashTable {
  internal var scale: Int
  internal var count: Int
  internal var map: UnsafeMutablePointer<MapEntry>
  internal var seed: (UInt64, UInt64)
}

extension _HashTable {
  internal struct MapEntry {
    internal static var payloadMask: UInt8 { return 0x7F }

    internal static var unoccupied: MapEntry { return MapEntry(_value: 0) }

    internal var value: UInt8

    private init(_value: UInt8) {
      self.value = _value
    }

    internal init(payload: UInt8) {
      _sanityCheck(payload < 0x80)
      self.init(_value: 0x80 | payload)
    }

    internal var isOccupied: Bool {
      @inline(__always) get { return value & 0x80 }
    }

    internal var payload: UInt8 {
      @inline(__always) get {
        return value & _HashTable.MapEntry.payloadMask
      }
    }
  }
}

extension _HashTable.MapEntry: Equatable {}

extension _HashTable {
  internal var bucketCount: Int {
    return 1 &<< scale
  }

  internal var bucketMask: Int {
    // The bucket count is a positive power of two, so subtracting 1 will never
    // overflow and get us a nice mask.
    return bucketCount &- 1
  }

  /// The next bucket after `bucket`, with wraparound at the end of the table.
  internal func _succ(_ bucket: Int) -> Int {
    // Bucket is less than bucketCount, which is power of two less than
    // Int.max. Therefore adding 1 does not overflow.
    return (bucket &+ 1) & bucketMask
  }

  /// The previous bucket after `bucket`, with wraparound at the beginning of
  /// the table.
  internal func _pred(_ bucket: Int) -> Int {
    // Bucket is not negative. Therefore subtracting 1 does not overflow.
    return (bucket &- 1) & bucketMask
  }

  /// The next unoccupied bucket after `bucket`, with wraparound.
  internal func _nextHole(after bucket: Int) -> Int {
    var bucket = _succ(bucket)
    while map[bucket].isOccupied {
      bucket = _succ(bucket)
    }
    return bucket
  }

  /// The previous unoccupied bucket before `bucket`, with wraparound.
  internal func _prevHole(before bucket: Int) -> Int {
    var bucket = _pred(bucket)
    while map[bucket].isOccupied {
      bucket = _pred(bucket)
    }
    return bucket
  }
}

extension _HashTable {
  @_fixed_layout
  @usableFromInline
  internal struct Index {
    var bucket: Int
  }

  @_effects(readonly)
  internal var startIndex: Index {
    return index(after: Index(bucket: -1))
  }

  @_effects(readonly)
  internal var endIndex: Index {
    return Index(bucket: bucketCount)
  }

  @usableFromInline
  @_effects(readonly)
  internal func index(after i: Index) -> Index {
    _precondition(i != endIndex)
    var bucket = i.bucket + 1
    while bucket < bucketCount && !map[bucket].isOccupied {
      bucket += 1
    }
    return Index(bucket: bucket)
  }

  internal func mapEntry(forHashValue hashValue: Int) -> MapEntry {
    let payload =
      UInt8(truncatingIfNeeded: hashValue &>> scale) & MapEntry.payloadMask
    return MapEntry(payload: payload)
  }

  internal func check(_ i: Index) {
    _precondition(i.bucket >= 0 && i.bucket < bucketCount,
      "Attempting to access Collection elements using an invalid Index")
    _precondition(map[bucket].isOccupied,
      "Attempting to access Collection elements using an invalid Index")
  }

  /// Return the bucket for the first member that may have a matching hash
  /// value, or if there's no such member, return an unoccupied bucket that is
  /// suitable for inserting a new member with the specified hash value.
  @_effects(readonly)
  @usableFromInline
  internal func lookupFirst(hashValue: Int) -> (bucket: Int, found: Bool) {
    let bucket = hashValue & bucketMask
    let entry = mapEntry(forHashValue: hashValue)
    return _lookupChain(startingAt: bucket, lookingFor: entry)
  }

  /// Return the next bucket after `bucket` in the collision chain for the
  /// specified hash value. `bucket` must have been returned by `lookupFirst` or
  /// `lookupNext`, with `found == true`.
  @_effects(readonly)
  @usableFromInline
  internal func lookupNext(
    hashValue: Int,
    after bucket: Int
  ) -> (bucket: Int, found: Bool) {
    let bucket = _succ(bucket)
    let entry = mapEntry(forHashValue: hashValue)
    return _lookupChain(startingAt: bucket, lookingFor: entry)
  }

  internal func _lookupChain(
    startingAt bucket: Int,
    lookingFor entry: MapEntry
  ) -> (bucket: Int, found: Bool) {
    var bucket = bucket
    // We guarantee there's always a hole in the table, so we just loop until we
    // find one.
    while true {
      switch map[bucket] {
      case entry:
        return (bucket, true)
      case MapEntry.unoccupied:
        return (bucket, false)
      default:
        bucket = _succ(bucket)
      }
    }
  }

  /// Insert a new entry for an element with the specified hash value at
  /// `bucket`. The bucket must have been returned by `lookupFirst` or
  /// `lookupNext` for the same hash value, with `found == false`.
  @_effects(releasenone)
  @usableFromInline
  internal func insert(hashValue: Int, at bucket: Int) {
    _sanityCheck(!map[bucket].isOccupied)
    let entry = mapEntry(forHashValue: hashValue)
    map[bucket] = entry
  }

  @_effects(releasenone)
  @usableFromInline
  internal func delete(
    hashValue: Int,
    at bucket: Int
    with delegate: _HashTableDelegate
  ) {
    _sanityCheck(map[bucket] == mapEntry(forHashValue: hashValue))

    let idealBucket = hashValue & bucketMask
    map[bucket] = .unoccupied
    self.count -= 1

    // If we've put a hole in a chain of contiguous elements, some element after
    // the hole may belong where the new hole is.
    var hole = bucket

    // Find the first and last buckets in the contiguous chain containing hole.
    let start = _prevHole(before: idealBucket)
    let end = _pred(_nextHole(after: hole))

    // Relocate out-of-place elements in the chain, repeating until none are
    // found.
    while hole != end {
      // Walk backwards from the end of the chain looking for
      // something out-of-place.
      var b = end
      while b != hole {
        let idealB = delegate._hashValue(forBucket: b) & _bucketMask

        // Does this element belong between start and hole?  We need
        // two separate tests depending on whether [start, hole] wraps
        // around the end of the storage.
        let c0 = idealB >= start
        let c1 = idealB <= hole
        if start <= hole ? (c0 && c1) : (c0 || c1) {
          break // Found it
        }
        b = _pred(b)
      }

      if b == hole { // No out-of-place elements found; we're done adjusting.
        break
      }

      // Move the found element into the hole.
      delegate._move(bucket: b, to: hole)
      hole = b
    }
  }

  internal func delete(
    hashValue: Int,
    delegate: _HashTableDelegate,
    checkCandidate: (Int) -> Bool
  ) -> Bool {
    let (bucket, found) = lookup(
      hashValue: hashValue,
      checkCandidate: checkCandidate)
    if !found { return false }
    delete(
      idealBucket: hashValue & bucketMask,
      bucket: bucket,
      delegate: delegate)
    return true
  }

  internal func delete(
    idealBucket: Int,
    bucket: Int,
    delegate: _HashTableDelegate) {
    // Remove the element.
    delegate._destroy(bucket: bucket)
    self.count -= 1

    // If we've put a hole in a chain of contiguous elements, some element after
    // the hole may belong where the new hole is.
    var hole = bucket

    // Find the first and last buckets in the contiguous chain containing hole.
    let start = _prevHole(before: idealBucket)
    let end = _pred(_nextHole(after: hole))

    // Relocate out-of-place elements in the chain, repeating until none are
    // found.
    while hole != end {
      // Walk backwards from the end of the chain looking for
      // something out-of-place.
      var b = end
      while b != hole {
        let idealB = delegate._hashValue(forBucket: b) & _bucketMask

        // Does this element belong between start and hole?  We need
        // two separate tests depending on whether [start, hole] wraps
        // around the end of the storage.
        let c0 = idealB >= start
        let c1 = idealB <= hole
        if start <= hole ? (c0 && c1) : (c0 || c1) {
          break // Found it
        }
        b = _pred(b)
      }

      if b == hole { // No out-of-place elements found; we're done adjusting.
        break
      }

      // Move the found element into the hole.
      delegate._move(bucket: b, to: hole)
      hole = b
    }
  }
}
