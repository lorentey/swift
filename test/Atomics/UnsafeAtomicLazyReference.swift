// RUN: %target-run-simple-swift
// REQUIRES: executable_test

import StdlibUnittest
import Atomics

let suite = TestSuite("UnsafePointerToAtomicLazyReference")
defer { runAllTests() }

suite.test("UnsafePointerToAtomicLazyReference<${type}>.create-destroy") {
  guard #available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, *) else {
    return
  }

  let v = UnsafePointerToAtomicLazyReference<LifetimeTracked>.create()
  defer { v.destroy() }
  expectNil(v.load())
}

suite.test("UnsafePointerToAtomicLazyReference<${type}>.storeIfNil") {
  guard #available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, *) else {
    return
  }

  do {
    let v = UnsafePointerToAtomicLazyReference<LifetimeTracked>.create()
    expectNil(v.load())

    let ref = LifetimeTracked(42)
    expectTrue(v.storeIfNil(ref) === ref)
    expectTrue(v.load() === ref)

    let ref2 = LifetimeTracked(23)
    expectTrue(v.storeIfNil(ref2) === ref)
    expectTrue(v.load() === ref)

    v.destroy()
  }
  expectEqual(LifetimeTracked.instances, 0)
}
