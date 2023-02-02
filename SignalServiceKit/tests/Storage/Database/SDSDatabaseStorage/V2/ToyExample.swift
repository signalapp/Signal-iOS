//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

// In this file I present a toy example of how to use
// V2 DB components, and the code design they encourage.
// (Hereafter referred simply as DB, with "old" database
// types referred to as "SDS" types)

// As of time of writing, DB _does not_ help you test
// things like SQL statements or GRDB functions that
// compose SQL statements for you.
// Instead, its purpose is to encapsulate "storage"
// in general for classes that consume data from
// disk but whose primary business is transforming
// and doing things with that data.

// This is best demonstrated by example.

private class FooBarManager {}

// Here is a class, FooBarManager.
// It does things with Foos and Bars, like
// check their properties and perform network requests.

private struct Foo: Codable {
    let text: String
}

private struct Bar: Codable {
    let num: Int
}

extension FooBarManager {
    func doTheFooBar(foo: Foo, bar: Bar) {
        let newFoo: Foo
        if bar.num == 42 {
            newFoo = Foo(text: "The meaning of life")
        } else {
            newFoo = foo
        }
        issueNetworkRequest(foo: newFoo)
    }

    func issueNetworkRequest(foo: Foo) {
        // TODO
    }
}

// FooBarManager is primarily concerned with what you _do_
// with Foos and Bars, not how they are stored.
// But if it _did_ want to persist them, it would
// delegate that responsibility to another class.

private class FooFinder {

    init() {}

    func getFoo(transaction: SDSAnyReadTransaction) -> Foo? {
        let sql = "SELECT text FROM model_Foo LIMIT 1"
        guard let text = try? String.fetchOne(transaction.unwrapGrdbRead.database, sql: sql) else {
            return nil
        }
        return Foo(text: text)
    }
}

private class BarFinder {

    // This is an static method vs instance method for getFoo above.
    // The reason why will be obvious later on. For now, ignore it.
    static func getBar(transaction: SDSAnyReadTransaction) -> Bar? {
        let sql = "SELECT text FROM model_Foo LIMIT 1"
        guard let num = try? Int.fetchOne(transaction.unwrapGrdbRead.database, sql: sql) else {
            return nil
        }
        return Bar(num: num)
    }
}

// DB _does not_ help you test these Finder classes. Instead,
// it helps you mock out the Finder classes so you can test
// FooBarManager.

// Traditionally, FooBarManager might consume foos and bars from storage like so:

extension FooBarManager {

    // Takes a transaction to ensure foo and bar are read
    // from the same database snapshot and aren't out of sync.
    func doTheFooBar(transaction: SDSAnyReadTransaction) {
        let foo = FooFinder().getFoo(transaction: transaction)!
        let bar = BarFinder.getBar(transaction: transaction)!
        doTheFooBar(foo: foo, bar: bar)
    }
}

// That works in production code, but when you try and test you run into some problems:
private class FooBarManagerTest: SSKBaseTestSwift {

    var fooBarManager: FooBarManager!

    func testGetFooAndBar() throws {
        throw XCTSkip("Don't actually want to run this test")

        // This comes from SSKEnvironment, which by its very creation
        // requires setting up countless managers and running all sorts
        // of database startup tasks.
        let databaseStorage = self.databaseStorage

        // Write a bunch of SQL queries to insert Foo(s) and Bar(s)
        // into the database.

        databaseStorage.read { transaction in
            fooBarManager.doTheFooBar(transaction: transaction)
        }

        // Assert stuff...
    }
}

// You HAD to create the entire SSKEnvironment just to run your measly test.
// That's a lot of overhead for your simple unit test, and it also makes
// things hard to reason about.

// Most importantly, FooBarManager doesn't actually _care_ about any of that. It doesn't
// even care that there is a database; thats FooFinder and BarFinder's problem.
// All it knows is it has this "transaction" object, which is a total black box, that
// it blindly passes along to its dependencies to do the real work.
// It is aware that passing a single transaction around (vs one per operation)
// guarantees transactionality, but that is all.

// NOTE: one option would be to refactor SDSDatabaseStorage to to be more flexible.
// That involves way more refactoring than was required to create DB and other V2 classes,
// so we did that instead.

// Using DB instead, we do this:

extension FooFinder {

    func getFoo(transaction: DBReadTransaction) -> Foo? {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getFoo(transaction: sdsTx)
    }
}

extension BarFinder {

    static func getBar(transaction: DBReadTransaction) -> Bar? {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getBar(transaction: sdsTx)
    }
}

extension FooBarManager {

    func doTheFooBar(transaction: DBReadTransaction) {
        let foo = FooFinder().getFoo(transaction: transaction)!
        let bar = BarFinder.getBar(transaction: transaction)!
        doTheFooBar(foo: foo, bar: bar)
    }
}

// The code you actually write is pretty much identical, except for the types.
// You just have to do one conversion, to unwrap the DBReadTransaction into
// an SDSAnyRead transaction you can actually use.

// Here's the test:

extension FooBarManagerTest {

    func testGetFooAndBar_2() throws {
        throw XCTSkip("Don't actually want to run this test")

        // This is a dumb, simple class with no dependencies.
        // It has no overhead, no startup jobs, nothing.
        // All it does is give you things that _look_
        // like transactions, but crash if you try and
        // actually use them to read from a database.
        let db = MockDB()

        // Here goes state we set up for our test, e.g. creating
        // the Foo(s) and Bar(s) we expect to "read" from the "db".
        // We will get to how to do that later, hold tight.
        // No SQL queries, though.

        db.read { transaction in
            fooBarManager.doTheFooBar(transaction: transaction)
        }

        // Assert stuff...
    }
}

// Our unit test is now _truly_ isolated. There are no other dependencies
// or implicit startup jobs running around. What happens is what the test
// says happens. No more flakes because an unrelated component is flaky and
// crashes on startup every once in a while.

// The only problem is that this test will crash and fail as written.
// That's because it uses FooFinder and BarFinder, and we made it so they
// would accept a DBReadTransaction, but as soon as we give them the fake
// transactions MockDB generates, they will crash when they call SDSDB.shimOnlyBridge.

// This is a good thing; the test _should_ fail because we have made a mistake:
// we have not mocked out FooFinder, BarFinder, or any other dependencies FooBarManager has.
// We _must_ define our dependencies in our test, and tell them how they should behave,
// so that we can isolate FooBarManager and test its logic independently of its dependencies.

// So how do we mock out FooFinder and BarFinder?

// FooFinder is easier; its a simple class and uses instance methods, so we can
// easily wrap it in a protocol with an alternate mock implementation.

private protocol FooFinderProtocol {

    func getFoo(transaction: DBReadTransaction) -> Foo?
}

extension FooFinder: FooFinderProtocol {}

private class FooFinderMock: FooFinderProtocol {

    init() {}

    var fooToReturn: Foo?

    func getFoo(transaction: DBReadTransaction) -> Foo? {
        // Ignore the transaction! This mock is only used
        // in tests which pass around fake transactions that
        // crash if you try and unwrap them.
        return fooToReturn
    }
}

// I took a shortcut earlier and had FooBarManager instantiate a FooFinder inline
// where it was needed. We'd now instead update the initializer to take a FooFinderProtocol:

private class FooBarManager2 {
    let fooFinder: FooFinderProtocol

    init(fooFinder: FooFinderProtocol) {
        self.fooFinder = fooFinder
    }

    func doTheFooBar(transaction: DBReadTransaction) {
        let foo = fooFinder.getFoo(transaction: transaction)!
        let bar = BarFinder.getBar(transaction: transaction)!
        // doTheFooBar(foo: foo, bar: bar)
    }
}

// We'd create a "real" instance like so:
func ex() {
    _ = FooBarManager2(fooFinder: FooFinder())
}

// And in tests we pass a FooFinderMock:

class FooBarManagerTest2: XCTestCase {

    private var fooFinderMock: FooFinderMock!

    private var fooBarManager: FooBarManager2!

    override func setUp() {
        fooFinderMock = FooFinderMock()
        fooBarManager = FooBarManager2(fooFinder: fooFinderMock)
    }

    func testGetFooAndBar_2() throws {
        throw XCTSkip("Don't actually want to run this test")
        let db = MockDB()

        // Setting and returning this value doesn't go through
        // the db, doesn't rely on the schema being set up, etc.
        // FooBarManager wants a Foo and doesn't care how it was stored;
        // this test now better matches that without getting into
        // implementation details like SQL.
        fooFinderMock.fooToReturn = Foo(text: "Hello, world!")

        db.read { transaction in
            fooBarManager.doTheFooBar(transaction: transaction)
        }

        // Assert stuff...
    }
}

// We are one step closer now, but this test will still fail.
// The FooBarManager instance in our test will still call the static method on
// BarFinder, which crashes if its given a fake MockDB-generated transaction.

// BarFinder is a little bit tricker than FooFinder. It uses class methods, not instance
// methods, so we can't create a mock instance with different behavior.
// Since this is just an example, you can imagine that BarFinder has other
// complications:
//
// * It might be enormous with tons of methods you don't want to stub out 1 by 1
//   for your little basic unit test.
// * It might get called from objc classes, or be written in objc itself,
//   and you don't want to migrate a bunch of objc code for you basic test.
// * It might be badly designed, doing ten thousand things which should
//   be broken up into smaller, more directed classes.
//
// In any case, while refactoring BarFinder would be ideal, the worst
// outcome is giving up due to the overhead and not writing a test for
// FooBarManager at all _because_ of BarFinder's ugliness.

// There is a shortcut, which is just "shimming" out the few things
// your specific class needs from BarFinder, like so:

private protocol FooBarManager_BarFinderShim {

    // BarFinder might have TONS of other methods on it that
    // FooBarManager never invokes, so we can exclude them
    // from the FooBarManager-scoped shim. No other class should
    // use this shim, so it only needs what FooBarManager uses.
    func getBar(transaction: DBReadTransaction) -> Bar?
}

private class FooBarManager_BarFinderWrapper: FooBarManager_BarFinderShim {
    func getBar(transaction: DBReadTransaction) -> Bar? {
        // In our toy example, we already modified BarFinder to
        // take a DBReadTransaction instead of an SDSAnyReadTransaction.
        // In the real world, BarFinder would be an existing class that doesn't
        // have that, and the Wrapper is the place to do the bridging.
        // Hence the name "shimOnlyBridge".
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return BarFinder.getBar(transaction: sdsTx)
    }
}

private class FooBarManager_BarFinderMock: FooBarManager_BarFinderShim {

    init() {}

    var barToReturn: Bar?

    func getBar(transaction: DBReadTransaction) -> Bar? {
        // Again we ignore the transaction, like in FooFinderMock.
        return barToReturn
    }
}

// Aside: Holy TeenageMutantNinjaTurtles Batman! Those are some long and ugly names!
// Some namespacing can make things easier to read. Swift doesn't allow protocols
// inside other declarations (they have to live at the top level) but we can
// use typealias to get the same result:

// enum with no cases is a great way to create a no-op name for namespace purposes only.
private enum FooBar {
    enum Shims {
        typealias BarFinder = FooBarManager_BarFinderShim
    }
    enum Wrappers {
        typealias BarFinder = FooBarManager_BarFinderWrapper
    }
    enum Mocks {
        typealias BarFinder = FooBarManager_BarFinderMock
    }
}

// Now finally we can update FooBarManager to accept a mockable dependency on
// FooFinder, like it does for FooFinder:

private class FooBarManager3 {
    let fooFinder: FooFinderProtocol
    let barFinder: FooBar.Shims.BarFinder

    init(
        fooFinder: FooFinderProtocol,
        barFinder: FooBar.Shims.BarFinder
    ) {
        self.fooFinder = fooFinder
        self.barFinder = barFinder
    }

    func doTheFooBar(transaction: DBReadTransaction) {
        let foo = fooFinder.getFoo(transaction: transaction)!
        let bar = barFinder.getBar(transaction: transaction)!
        // doTheFooBar(foo: foo, bar: bar)
    }
}

// We create a "real" instance like so:
func ex2() {
    _ = FooBarManager3(
        fooFinder: FooFinder(),
        barFinder: FooBar.Wrappers.BarFinder()
    )
}

// And everything is stubbed out in tests, with no dependencies
// we don't control:

class FooBarManagerTest3: XCTestCase {

    private var fooFinderMock: FooFinderMock!
    private var barFinderMock: FooBar.Mocks.BarFinder!

    private var fooBarManager: FooBarManager3!

    override func setUp() {
        fooFinderMock = FooFinderMock()
        barFinderMock = FooBar.Mocks.BarFinder()
        fooBarManager = FooBarManager3(fooFinder: fooFinderMock, barFinder: barFinderMock)
    }

    func testGetFooAndBar_2() throws {
        throw XCTSkip("Don't actually want to run this test")
        let db = MockDB()

        fooFinderMock.fooToReturn = Foo(text: "Hello, world!")
        barFinderMock.barToReturn = Bar(num: 42)

        db.read { transaction in
            fooBarManager.doTheFooBar(transaction: transaction)
        }

        // Assert stuff...
    }
}

// To reiterate:

// We used DB and its transaction classes instead of SDS classes,
// so that we can easily generate fake instances with the lightweight,
// dependency-free MockDB.

// We use SDSDB.shimOnlyBridge to convert between our db-agnostic code
// that talks in DB types, and dependencies that talk in SDS types.
// These dependencies can be:
//
// * New classes, like FooFinder, that are the final point of use that
//   unwrap the transaction to utilize the db connection.
//
// * Old classes, not explicitly demonstrated here, but these would
//   be things like TSAccountManager (at time of writing) which may not
//   access the db connection themselves, but which haven't been refactored
//   to use the new types yet.

// In either case, we need to mock out those classes so that we never call
// SDSDB.shimOnlyBridge in tests; doing so will cause a crash.
// There are two options for this, depending on how much effort is required
// and the time available to undergo that effort:
//
//
// The Good Way: avoid static methods, always wrap your classes in a protocol,
// andd avoid objective-C compatibility requirements.
// This lets you accept DB transaction types and create simple Mock implementations.
//
// This is how FooFinder works in this example.
//
//
// The Shortcut Way: create a {ClassName}_{DependencyName}Shim protocol and Wrapper class
// that are used only by your class and which contain only those methods your class invokes.
// This keeps the scope of changes smaller, leaving the original class entirely untouched.
//
// This is how BarFinder works in this example.
//
// The Good Way is _always_ preferred, but requires more time to refactor existing code to do it.
// Depending on the class, and how intertwined it is with objc code, it might require
// a LOT more time.
// In those cases, the Shortcut Way is at least better than giving up on testing entirely.
// Use at your discretion, and lean on code review to get feedback on the right approach.
