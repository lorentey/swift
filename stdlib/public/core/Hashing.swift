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
// This file implements the non-cryptographic hash function used for Hashable
// types in Swift.
//

import SwiftShims

// NOT @_fixed_layout
public // Used in synthesized Hashable implementations
struct _Hasher {
  internal typealias Core = _SipHash13

  // NOT @_versioned
  internal var _core: Core

  // NOT @_inlineable
  @effects(releasenone)
  public init() {
    self._core = Core(key: _Hasher._secretKey)
  }

  // NOT @_inlineable
  @effects(releasenone)
  public init(key: (UInt64, UInt64)) {
    self._core = Core(key: key)
  }

  // FIXME(ABI)#41 : make this an actual public API.
  @_inlineable // FIXME(sil-serialize-all)
  public // SPI
  static var _secretKey: (UInt64, UInt64) {
    get {
      // The variable itself is defined in C++ code so that it is initialized
      // during static construction.  Almost every Swift program uses hash
      // tables, so initializing the secret key during the startup seems to be
      // the right trade-off.
      return (
        _swift_stdlib_Hashing_secretKey.key0,
        _swift_stdlib_Hashing_secretKey.key1)
    }
    set {
      // FIXME(hasher) Replace setter with some override mechanism inside 
      // the runtime
      (_swift_stdlib_Hashing_secretKey.key0,
       _swift_stdlib_Hashing_secretKey.key1) = newValue
    }
  }

  @inline(__always)
  public mutating func append<H: Hashable>(_ value: H) {
    value._hash(into: &self)
  }

  // NOT @_inlineable
  @effects(releasenone)
  public mutating func append(bits: UInt) {
    _core.append(bits)
  }
  // NOT @_inlineable
  @effects(releasenone)
  public mutating func append(bits: UInt32) {
    _core.append(bits)
  }
  // NOT @_inlineable
  @effects(releasenone)
  public mutating func append(bits: UInt64) {
    _core.append(bits)
  }

  // NOT @_inlineable
  @effects(releasenone)
  public mutating func append(bits: Int) {
    _core.append(UInt(bitPattern: bits))
  }
  // NOT @_inlineable
  @effects(releasenone)
  public mutating func append(bits: Int32) {
    _core.append(UInt32(bitPattern: bits))
  }
  // NOT @_inlineable
  @effects(releasenone)
  public mutating func append(bits: Int64) {
    _core.append(UInt64(bitPattern: bits))
  }

  // NOT @_inlineable
  @effects(releasenone)
  public mutating func finalize() -> Int {
    return Int(truncatingIfNeeded: _core.finalize())
  }
}
