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

protocol _HashTableDelegate {
  func _swap(bucket bucket1: Int, with bucket2: Int)
  func _move(bucket source: Int, to target: Int)
  func _destroy(bucket bucket: Int)
  func _hashValue(forBucket bucket: Int) -> Int
}

internal struct _HashTable {
  internal var bucketCount: Int
  internal var count: Int
  internal var bucketMap: UnsafeMutablePointer<MapEntry>
  internal var seed: (UInt64, UInt64)
}

extension _HashTable {
  internal struct MapEntry {
    var value: UInt8

    internal init(occupiedWithPayload payload: UInt8) {
      _sanityCheck(payload < 0x80)
      self.value = 0x80 | payload
    }

    internal init(unoccupied: Void) {
      self.value = 0
    }

    internal var isOccupied: Bool {
      @inline(__always) get { return value & 0x80 }
    }

    internal var payload: UInt8 {
      @inline(__always) get { return value & 0x7F }
    }
  }
}

extension _HashTable {
  internal var _bucketMask: Int {
    // The bucket count is a positive power of two, so subtracting 1 will never
    // overflow and get us a nice mask.
    return bucketCount &- 1
  }

  /// The next bucket after `bucket`, with wraparound at the end of the table.
  internal func _succ(_ bucket: Int) -> Int {
    // Bucket is less than bucketCount, which is power of two less than
    // Int.max. Therefore adding 1 does not overflow.
    return (bucket &+ 1) & _bucketMask
  }

  /// The previous bucket after `bucket`, with wraparound at the beginning of
  /// the table.
  internal func _pred(_ bucket: Int) -> Int {
    // Bucket is not negative. Therefore subtracting 1 does not overflow.
    return (bucket &- 1) & _bucketMask
  }

  /// The next unoccupied bucket after bucket, with wraparound.
  internal func _nextHole(after bucket: Int) -> Int {
    var bucket = _succ(bucket)
    while _bucketMap[bucket].isOccupied {
      bucket = _succ(bucket)
    }
    return bucket
  }

  /// The previous unoccupied bucket before bucket, with wraparound.
  internal func _prevHole(before bucket: Int) -> Int {
    var bucket = _pred(bucket)
    while _bucketMap[bucket].isOccupied {
      bucket = _pred(bucket)
    }
    return bucket
  }
}

extension _HashTable {
  @_fixed_layout
  internal struct Index {
    var bucket: Int
  }

  internal var startIndex: Index {
    return index(after: Index(bucket: -1))
  }

  internal var endIndex: Index {
    return Index(bucket: bucketCount)
  }

  internal func index(after i: Index) -> Index {
    _precondition(i != endIndex)
    var bucket = i.bucket + 1
    while bucket < bucketCount && !bucketMap[bucket].isOccupied {
      bucket += 1
    }
    return Index(bucket: bucket)
  }

  internal func check(_ i: Index) {
    _precondition(i.bucket >= 0 && i.bucket < bucketCount,
      "Attempting to access Collection elements using an invalid Index")
    _precondition(bucketMap[bucket].isOccupied,
      "Attempting to access Collection elements using an invalid Index")
  }

  internal func lookup(
    hashValue: Int,
    checkCandidate: (Int) -> Bool
  ) -> (bucket: Int, found: Bool) {
    var bucket = hashValue & bucketMask
    let payload = UInt8(truncatingIfNeeded:
      UInt(bitPattern: hashValue) >> (UInt.bitWidth - 7))

    // We guarantee there's always a hole in the table, so we just loop until we
    // find one.
    while true {
      let entry = bucketMap[bucket]
      if !entry.isOccupied {
        return false
      }
      if entry.payload == payload, checkCandidate(bucket) {
        return true
      }
      bucket = (bucket &+ 1) & bucketMask
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
