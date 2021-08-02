//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest

@testable import SignalServiceKit

class OWSErrorTest: SSKBaseTestSwift {

    func testErrorProperties1() {
        enum FooError: Error {
            case bar
        }

        let errorFooBar = FooError.bar
        let errorGeneric = OWSGenericError("Yipes!")
        let error1 = OWSHTTPError.invalidRequest(requestUrl: URL(string: "https://google.com/")!)
        let error2 = OWSHTTPError.networkFailure(requestUrl: URL(string: "https://google.com/")!)

        XCTAssertFalse(errorFooBar.hasIsRetryable)
        XCTAssertTrue(errorFooBar.isRetryable)
        XCTAssertFalse(errorFooBar.shouldBeIgnoredForGroups)
        XCTAssertFalse(errorFooBar.isFatal)
        XCTAssertEqual(errorFooBar.localizedDescription, NSError.localizedDescriptionDefault)
        XCTAssertNotNil(errorFooBar.localizedRecoverySuggestion)

        XCTAssertTrue(errorGeneric.hasIsRetryable)
        XCTAssertFalse(errorGeneric.isRetryable)
        XCTAssertFalse(errorGeneric.shouldBeIgnoredForGroups)
        XCTAssertFalse(errorGeneric.isFatal)
        XCTAssertEqual(errorGeneric.localizedDescription, NSError.localizedDescriptionDefault)
        XCTAssertNotNil(errorGeneric.localizedRecoverySuggestion)
        XCTAssertEqual(errorGeneric.nsDomain, "SignalCoreKit.OWSGenericError")

        XCTAssertTrue(error1.hasIsRetryable)
        XCTAssertFalse(error1.isRetryable)
        XCTAssertFalse(error1.shouldBeIgnoredForGroups)
        XCTAssertFalse(error1.isFatal)
        XCTAssertEqual(error1.localizedDescription, NSError.localizedDescriptionDefault)
        XCTAssertNotNil(error1.localizedRecoverySuggestion)
        XCTAssertEqual(error1.nsDomain, "SignalServiceKit." + OWSHTTPError.errorDomain)

        XCTAssertTrue(error2.hasIsRetryable)
        XCTAssertTrue(error2.isRetryable)
        XCTAssertFalse(error2.shouldBeIgnoredForGroups)
        XCTAssertFalse(error2.isFatal)
        XCTAssertEqual(error2.localizedDescription, NSError.localizedDescriptionDefault)
        //        XCTAssertNotNil(error2.localizedDescription)
        XCTAssertNotNil(error2.localizedRecoverySuggestion)
        XCTAssertEqual(error1.nsDomain, "SignalServiceKit." + OWSHTTPError.errorDomain)
    }

    func testAssociatedStrings() {
        enum FooError: Error {
            case bar
        }
        var key: UInt8 = 0
        let value1: String = "a"
        let value2: String = "b"
        let value3: String = "c"

        let error0 = FooError.bar
        XCTAssertNil((error0 as NSError).ows_getAssociatedString(&key))

        (error0 as NSError).ows_setAssociatedString(&key, value: value1)
        XCTAssertNil((error0 as NSError).ows_getAssociatedString(&key))

        let error1: Error = error0
        XCTAssertNil((error0 as NSError).ows_getAssociatedString(&key))
        XCTAssertNil((error1 as NSError).ows_getAssociatedString(&key))

        (error1 as NSError).ows_setAssociatedString(&key, value: value1)
        XCTAssertNil((error0 as NSError).ows_getAssociatedString(&key))
        XCTAssertEqual((error1 as NSError).ows_getAssociatedString(&key), value1)
        let error2: NSError = error1 as NSError
        XCTAssertNil((error0 as NSError).ows_getAssociatedString(&key))
        XCTAssertEqual((error1 as NSError).ows_getAssociatedString(&key), value1)
        XCTAssertEqual(error2.ows_getAssociatedString(&key), value1)

        error2.ows_setAssociatedString(&key, value: value2)
        XCTAssertNil((error0 as NSError).ows_getAssociatedString(&key))
        XCTAssertEqual((error1 as NSError).ows_getAssociatedString(&key), value2)
        XCTAssertEqual(error2.ows_getAssociatedString(&key), value2)
        let error3: Error = error2 as Error
        XCTAssertNil((error0 as NSError).ows_getAssociatedString(&key))
        XCTAssertEqual((error1 as NSError).ows_getAssociatedString(&key), value2)
        XCTAssertEqual(error2.ows_getAssociatedString(&key), value2)
        XCTAssertEqual((error3 as NSError).ows_getAssociatedString(&key), value2)
        let error4: NSError = error3 as NSError
        let error5: Error = error4 as Error
        XCTAssertNil((error0 as NSError).ows_getAssociatedString(&key))
        XCTAssertEqual((error1 as NSError).ows_getAssociatedString(&key), value2)
        XCTAssertEqual(error2.ows_getAssociatedString(&key), value2)
        XCTAssertEqual((error3 as NSError).ows_getAssociatedString(&key), value2)
        XCTAssertEqual(error4.ows_getAssociatedString(&key), value2)
        XCTAssertEqual((error5 as NSError).ows_getAssociatedString(&key), value2)

        (error5 as NSError).ows_setAssociatedString(&key, value: value3)
        XCTAssertNil((error0 as NSError).ows_getAssociatedString(&key))
        XCTAssertEqual((error1 as NSError).ows_getAssociatedString(&key), value3)
        XCTAssertEqual(error2.ows_getAssociatedString(&key), value3)
        XCTAssertEqual((error3 as NSError).ows_getAssociatedString(&key), value3)
        XCTAssertEqual(error4.ows_getAssociatedString(&key), value3)
        XCTAssertEqual((error5 as NSError).ows_getAssociatedString(&key), value3)
    }

    func testAssociatedNSNumber() {
        enum FooError: Error {
            case bar
        }
        var key: UInt8 = 0
        let value1: NSNumber = NSNumber(value: true)
        let value2: NSNumber = NSNumber(value: false)
        let value3: NSNumber = NSNumber(value: UInt64(3))

        let error0 = FooError.bar
        XCTAssertNil((error0 as NSError).ows_getAssociatedNSNumber(&key))

        (error0 as NSError).ows_setAssociatedNSNumber(&key, value: value1)
        XCTAssertNil((error0 as NSError).ows_getAssociatedNSNumber(&key))

        let error1: Error = error0
        XCTAssertNil((error0 as NSError).ows_getAssociatedNSNumber(&key))
        XCTAssertNil((error1 as NSError).ows_getAssociatedNSNumber(&key))

        (error1 as NSError).ows_setAssociatedNSNumber(&key, value: value1)
        XCTAssertNil((error0 as NSError).ows_getAssociatedNSNumber(&key))
        XCTAssertEqual((error1 as NSError).ows_getAssociatedNSNumber(&key), value1)
        let error2: NSError = error1 as NSError
        XCTAssertNil((error0 as NSError).ows_getAssociatedNSNumber(&key))
        XCTAssertEqual((error1 as NSError).ows_getAssociatedNSNumber(&key), value1)
        XCTAssertEqual(error2.ows_getAssociatedNSNumber(&key), value1)

        error2.ows_setAssociatedNSNumber(&key, value: value2)
        XCTAssertNil((error0 as NSError).ows_getAssociatedNSNumber(&key))
        XCTAssertEqual((error1 as NSError).ows_getAssociatedNSNumber(&key), value2)
        XCTAssertEqual(error2.ows_getAssociatedNSNumber(&key), value2)
        let error3: Error = error2 as Error
        XCTAssertNil((error0 as NSError).ows_getAssociatedNSNumber(&key))
        XCTAssertEqual((error1 as NSError).ows_getAssociatedNSNumber(&key), value2)
        XCTAssertEqual(error2.ows_getAssociatedNSNumber(&key), value2)
        XCTAssertEqual((error3 as NSError).ows_getAssociatedNSNumber(&key), value2)
        let error4: NSError = error3 as NSError
        let error5: Error = error4 as Error
        XCTAssertNil((error0 as NSError).ows_getAssociatedNSNumber(&key))
        XCTAssertEqual((error1 as NSError).ows_getAssociatedNSNumber(&key), value2)
        XCTAssertEqual(error2.ows_getAssociatedNSNumber(&key), value2)
        XCTAssertEqual((error3 as NSError).ows_getAssociatedNSNumber(&key), value2)
        XCTAssertEqual(error4.ows_getAssociatedNSNumber(&key), value2)
        XCTAssertEqual((error5 as NSError).ows_getAssociatedNSNumber(&key), value2)

        (error5 as NSError).ows_setAssociatedNSNumber(&key, value: value3)
        XCTAssertNil((error0 as NSError).ows_getAssociatedNSNumber(&key))
        XCTAssertEqual((error1 as NSError).ows_getAssociatedNSNumber(&key), value3)
        XCTAssertEqual(error2.ows_getAssociatedNSNumber(&key), value3)
        XCTAssertEqual((error3 as NSError).ows_getAssociatedNSNumber(&key), value3)
        XCTAssertEqual(error4.ows_getAssociatedNSNumber(&key), value3)
        XCTAssertEqual((error5 as NSError).ows_getAssociatedNSNumber(&key), value3)

        //        error.obj
        //
        //        fileprivate func ows_getAssociatedNSNumber(_ key: UnsafeRawPointer) -> NSNumber? {
        //            ows_getAssociatedObject(key)
        //        }
        //
        //        fileprivate func ows_getAssociatedObject<T>(_ key: UnsafeRawPointer) -> T? {
        //            if let rawValue = objc_getAssociatedObject(self, key) {
        //                if let value = rawValue as? T {
        //                    return value
        //                } else {
        //                    owsFailDebug("Invalid value: \(type(of: rawValue))")
        //                }
        //            }
        //            return nil
        //        }
        //
        //        fileprivate func ows_setAssociatedObject(_ key: UnsafeRawPointer,
        //                                                 _ value: Any?,
        //                                                 _ policy: objc_AssociationPolicy = .OBJC_ASSOCIATION_COPY) {
        //            objc_setAssociatedObjec
        //
        //        if let rawValue = objc_getAssociatedObject(self, &kErrorKey_IsRetryable) {
    }

    func testIsRetryable() {
        enum FooError: Error {
            case bar
        }

        let error1: Error = FooError.bar

        XCTAssertFalse(error1.hasIsRetryable)
        XCTAssertTrue(error1.isRetryable)

        let error2: Error = error1.with(isRetryable: false)

        Logger.verbose("---- error1: \(error1)")
        Logger.verbose("---- error1: \((error1 as NSError).userInfo)")
        Logger.verbose("---- error2: \(error2)")
        Logger.verbose("---- error2: \((error2 as NSError).userInfo)")
        Logger.flush()

        XCTAssertFalse(error1.hasIsRetryable)
        XCTAssertTrue(error1.isRetryable)
        XCTAssertTrue(error2.hasIsRetryable)
        XCTAssertFalse(error2.isRetryable)

        let error3 = error2.with(isRetryable: true)

        XCTAssertFalse(error1.hasIsRetryable)
        XCTAssertTrue(error1.isRetryable)
        XCTAssertTrue(error2.hasIsRetryable)
        XCTAssertFalse(error2.isRetryable)
        XCTAssertTrue(error3.hasIsRetryable)
        XCTAssertTrue(error3.isRetryable)

        XCTAssertFalse((error1 as NSError) === (error1 as NSError))
        XCTAssertTrue((error2 as NSError) === (error2 as NSError))
        XCTAssertTrue((error3 as NSError) === (error3 as NSError))
        XCTAssertFalse((error1 as NSError) === (error2 as NSError))
        XCTAssertFalse((error1 as NSError) === (error3 as NSError))
        XCTAssertFalse((error2 as NSError) === (error3 as NSError))
        XCTAssertNotEqual((error2 as NSError).debugPointerName, (error1 as NSError).debugPointerName)
        XCTAssertEqual((error2 as NSError).debugPointerName, (error3 as NSError).debugPointerName)

        //        XCTAssertTrue(errorGeneric.hasIsRetryable)
        //        XCTAssertFalse(errorGeneric.isRetryable)
        //        XCTAssertFalse(errorGeneric.shouldBeIgnoredForGroups)
        //        XCTAssertFalse(errorGeneric.isFatal)
        //        XCTAssertEqual(errorGeneric.localizedDescription, NSError.localizedDescriptionDefault)
        //        XCTAssertNotNil(errorGeneric.localizedRecoverySuggestion)
        //        XCTAssertEqual(errorGeneric.nsDomain, "SignalCoreKit.OWSGenericError")
        //
        //        XCTAssertTrue(error1.hasIsRetryable)
        //        XCTAssertFalse(error1.isRetryable)
        //        XCTAssertFalse(error1.shouldBeIgnoredForGroups)
        //        XCTAssertFalse(error1.isFatal)
        //        XCTAssertEqual(error1.localizedDescription, NSError.localizedDescriptionDefault)
        //        XCTAssertNotNil(error1.localizedRecoverySuggestion)
        //        XCTAssertEqual(error1.nsDomain, "SignalServiceKit." + OWSHTTPError.errorDomain)
        //
        //        XCTAssertTrue(error2.hasIsRetryable)
        //        XCTAssertTrue(error2.isRetryable)
        //        XCTAssertFalse(error2.shouldBeIgnoredForGroups)
        //        XCTAssertFalse(error2.isFatal)
        //        XCTAssertEqual(error2.localizedDescription, NSError.localizedDescriptionDefault)
        //        XCTAssertNotNil(error2.localizedRecoverySuggestion)
        //        XCTAssertEqual(error1.nsDomain, "SignalServiceKit." + OWSHTTPError.errorDomain)

        let error1a = error1.with(isRetryable: true)

        //        public var hasIsRetryable: Bool { (self as NSError).hasIsRetryableImpl }
        //
        //        public var isRetryable: Bool { (self as NSError).isRetryableImpl }
        //        public func with(isRetryable: Bool) -> Error {
        //            let error = self as NSError
        //            error.isRetryableImpl = isRetryable
        //            return error
        //        }
        //
        //        public var shouldBeIgnoredForGroups: Bool { (self as NSError).shouldBeIgnoredForGroupsImpl }
        //        public func with(shouldBeIgnoredForGroups: Bool) -> Error {
        //            let error = self as NSError
        //            error.shouldBeIgnoredForGroupsImpl = shouldBeIgnoredForGroups
        //            return error
        //        }
        //
        //        public var isFatal: Bool { (self as NSError).isFatalImpl }
        //        public func with(isFatal: Bool) -> Error {
        //            let error = self as NSError
        //            error.isFatalImpl = isFatal
        //            return error
        //        }
        //
        //        // TODO:
        //        //    public var localizedDescription: String { (self as NSError).localizedDescriptionImpl }
        //        public func with(localizedDescription: String) -> Error {
        //            let error = self as NSError
        //            error.localizedDescriptionImpl = localizedDescription
        //            return error
        //        }
        //
        //        // TODO:
        //        public var localizedRecoverySuggestion: String { (self as NSError).localizedRecoverySuggestionImpl }
        //        public func with(localizedRecoverySuggestion: String) -> Error {
        //            let error = self as NSError
        //            error.localizedRecoverySuggestionImpl = localizedRecoverySuggestion
        //            return error
        //        }
        //
        //        public var nsDomain: String { (self as NSError).domain }
        //        public var nsCode: Int { (self as NSError).code }
        //
        //        //    /// NSError bridging: the domain of the error.
        //        //    /// :nodoc:
        //        //    public static var errorDomain: String {
        //        //        return "GRDB.DatabaseError"
        //        //    }
        //        //
        //        //    /// NSError bridging: the error code within the given domain.
        //        //    /// :nodoc:
        //        //    public var errorCode: Int {
        //        //        return Int(extendedResultCode.rawValue)
        //        //    }
        //
        //        /// NSError bridging: the user-info dictionary.
        //        /// :nodoc:
        //        public var errorUserInfo: [String: Any] {
        //            var result = [String: Any]()
        //            // TODO:
        //            //        if let responseError = self.responseError {
        //            //            result[NSUnderlyingErrorKey] = responseError
        //            //        }
        //            result[NSLocalizedDescriptionKey] = (self as NSError).localizedDescriptionImpl
        //            result[NSLocalizedRecoverySuggestionErrorKey] = (self as NSError).localizedRecoverySuggestionImpl
        //            return result
        //        }
        //    }
    }
}

// MARK: -

extension Error {
    var debugPointerName: String {
        String(describing: Unmanaged<AnyObject>.passUnretained(self as AnyObject).toOpaque())
    }
}
