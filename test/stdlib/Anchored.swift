// RUN: %target-run-simple-swift | %FileCheck %s
// REQUIRES: executable_test

import os

// CHECK: testing...
print("testing...")

public struct Errno: Error, CustomStringConvertible, RawRepresentable {
  public let rawValue: Int32

  public init(rawValue: Int32) { self.rawValue = rawValue }

  public var description: String {
    // FIXME: Use String's unsafeUninitializedCapacity initializer.
    let buffer = UnsafeMutableBufferPointer<CChar>.allocate(capacity: 512)
    defer { buffer.deallocate() }
    buffer.initialize(repeating: 0)
    guard strerror_r(rawValue, buffer.baseAddress, buffer.count) == 0 else {
      return "Unknown error \(rawValue)"
    }
    return String(cString: buffer.baseAddress!)
  }
}

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, *)
public struct PthreadMutex: Anchored {
  public struct Value {
    internal var _mutex = pthread_mutex_t()
    internal init() {}
  }

  let _anchor: AnyObject
  let _address: UnsafeMutablePointer<pthread_mutex_t>

  public static var defaultInitialValue: Value { Value() }

  public init(at address: UnsafeMutablePointer<Value>, in anchor: AnyObject) {
    _anchor = anchor
    // pthread_mutex_t is the first (and only) component of Value so
    // it pthread_mutex_t is a related type in the sense of SE-0107.
    _address = UnsafeMutableRawPointer(address)
      .assumingMemoryBound(to: pthread_mutex_t.self)
  }

  public func initialize(attributes: pthread_mutexattr_t? = nil) throws {
    let r: Int32
    if var attributes = attributes {
      r = pthread_mutex_init(_address, &attributes)
    } else {
      r = pthread_mutex_init(_address, nil)
    }
    guard r == 0 else { throw Errno(rawValue: r) }
  }

  public func lock() throws {
    let r = pthread_mutex_lock(_address)
    guard r == 0 else { throw Errno(rawValue: r) }
  }

  public func unlock() throws {
    let r = pthread_mutex_unlock(_address)
    guard r == 0 else { throw Errno(rawValue: r) }
  }
}

@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, *)
class Foo {
  @Anchoring var mutex: PthreadMutex
}

if #available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, *) {
  do {
    let foo = Foo()
    try foo.mutex.initialize()
    try foo.mutex.lock()
    // CHECK: LOCKED
    print("LOCKED")
    try foo.mutex.unlock()
    // CHECK: DONE
    print("DONE")
  }
  catch {
    print(error)
  }
}
