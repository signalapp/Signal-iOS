//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit
import XCTest

class FactoryInitializationTests: XCTestCase {
    func testFactoryInitialization_SuccessFromHardcodedData() throws {
        class BaseClass: NeedsFactoryInitializationFromRecordType {
            enum CodingKeys: CodingKey { case recordType; case base; case foo; case bar }

            static var recordTypeCodingKey: CodingKeys { .recordType }

            static func classToInitialize(
                forRecordType recordType: UInt
            ) -> (FactoryInitializableFromRecordType.Type)? {
                switch recordType {
                case 1:
                    return FooClass.self
                case 2:
                    return BarClass.self
                default:
                    return nil
                }
            }

            let base: String

            init(baseClassFromDecoder decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                base = try container.decode(String.self, forKey: .base)
            }
        }

        class FooClass: BaseClass, FactoryInitializableFromRecordType {
            static var recordType: UInt { 1 }

            let foo: String

            required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                foo = try container.decode(String.self, forKey: .foo)
                try super.init(baseClassFromDecoder: container.superDecoder())
            }
        }

        class BarClass: BaseClass, FactoryInitializableFromRecordType {
            static var recordType: UInt { 2 }

            let bar: String

            required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                bar = try container.decode(String.self, forKey: .bar)
                try super.init(baseClassFromDecoder: container.superDecoder())
            }
        }

        let fooJsonData: Data = """
            {
                "super": {
                    "recordType": 1,
                    "base": "spaceship"
                },
                "foo": "millenium falcon"
            }
        """.data(using: .utf8)!

        let barJsonData: Data = """
            {
                "super": {
                    "recordType": 2,
                    "base": "crystal"
                },
                "bar": "kyber"
            }
        """.data(using: .utf8)!

        let fooInstance = try JSONDecoder().decode(BaseClass.self, from: fooJsonData)
        let barInstance = try JSONDecoder().decode(BaseClass.self, from: barJsonData)

        guard let foo = fooInstance as? FooClass else {
            XCTFail("Failed to cast foo instance!")
            return
        }

        guard let bar = barInstance as? BarClass else {
            XCTFail("Failed to cast bar instance!")
            return
        }

        XCTAssertEqual(foo.base, "spaceship")
        XCTAssertEqual(foo.foo, "millenium falcon")

        XCTAssertEqual(bar.base, "crystal")
        XCTAssertEqual(bar.bar, "kyber")
    }

    func testFactoryInitialization_ThrowsForBadRecordType() throws {
        class BaseClassThatMisinterpretsRecordTypes: NeedsFactoryInitializationFromRecordType {
            enum CodingKeys: CodingKey { case recordType }

            static var recordTypeCodingKey: CodingKeys { .recordType }

            static func classToInitialize(
                forRecordType recordType: UInt
            ) -> (FactoryInitializableFromRecordType.Type)? {
                switch recordType {
                case 1:
                    return BarClass.self
                case 2:
                    return FooClass.self
                default:
                    return nil
                }
            }
        }

        class FooClass: BaseClassThatMisinterpretsRecordTypes, FactoryInitializableFromRecordType {
            static var recordType: UInt { 1 }

            required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
                XCTFail("Initializer should never have been called!")
                fatalError("")
            }
        }

        class BarClass: BaseClassThatMisinterpretsRecordTypes, FactoryInitializableFromRecordType {
            static var recordType: UInt { 2 }

            required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
                XCTFail("Initializer should never have been called!")
                fatalError("")
            }
        }

        let invalidJsonData: Data = #"{ "super": { "recordType": 3 } }"#.data(using: .utf8)!
        let fooJsonData: Data = #"{ "super": { "recordType": 1 } }"#.data(using: .utf8)!
        let barJsonData: Data = #"{ "super": { "recordType": 2 } }"#.data(using: .utf8)!

        func decodeAndCatchDecodingError(fromData data: Data) throws {
            do {
                _ = try JSONDecoder().decode(BaseClassThatMisinterpretsRecordTypes.self, from: data)
                XCTFail("Should have thrown while decoding!")
            } catch let DecodingError.dataCorrupted(context) {
                XCTAssertEqual(
                    (context.codingPath.first! as! BaseClassThatMisinterpretsRecordTypes.CodingKeys),
                    .recordType
                )
            }
        }

        try decodeAndCatchDecodingError(fromData: invalidJsonData)
        try decodeAndCatchDecodingError(fromData: fooJsonData)
        try decodeAndCatchDecodingError(fromData: barJsonData)
    }
}
