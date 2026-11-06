//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
@testable import SignalServiceKit

struct InheritableRecordTest {
    @Test
    func testFactoryInitialization_SuccessFromHardcodedData() throws {
        class BaseClass: InheritableRecord {
            static func concreteType(forRecordType recordType: UInt) -> (any InheritableRecord.Type)? {
                switch recordType {
                case 1:
                    return FooClass.self
                case 2:
                    return BarClass.self
                default:
                    return nil
                }
            }

            enum CodingKeys: String, CodingKey {
                case base
            }

            let base: String

            required init(inheritableDecoder decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                base = try container.decode(String.self, forKey: .base)
            }
        }

        class FooClass: BaseClass {
            enum CodingKeys: String, CodingKey {
                case foo
            }

            let foo: String

            required init(inheritableDecoder decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                foo = try container.decode(String.self, forKey: .foo)
                try super.init(inheritableDecoder: decoder)
            }
        }

        class BarClass: FooClass {
            static var recordType: UInt { 2 }

            enum CodingKeys: String, CodingKey {
                case bar
            }

            let bar: String

            required init(inheritableDecoder decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                bar = try container.decode(String.self, forKey: .bar)
                try super.init(inheritableDecoder: decoder)
            }
        }

        let fooJsonData: Data = """
            {
                "recordType": 1,
                "base": "spaceship",
                "foo": "millenium falcon"
            }
        """.data(using: .utf8)!

        let barJsonData: Data = """
            {
                "recordType": 2,
                "base": "crystal",
                "foo": "kem",
                "bar": "kyber"
            }
        """.data(using: .utf8)!

        // Decoding via BaseClass works as expected.
        do {
            let foo = try JSONDecoder().decode(BaseClass.self, from: fooJsonData) as! FooClass
            let bar = try JSONDecoder().decode(BaseClass.self, from: barJsonData) as! BarClass

            #expect(foo.base == "spaceship")
            #expect(foo.foo == "millenium falcon")

            #expect(bar.base == "crystal")
            #expect(bar.foo == "kem")
            #expect(bar.bar == "kyber")
        }

        // Decoding via a subclass works if the resulting type is valid.
        _ = try JSONDecoder().decode(BarClass.self, from: barJsonData)

        // Decoding via a subclass fails if the runtime type mismatches.
        #expect(throws: DecodingError.self, performing: {
            _ = try JSONDecoder().decode(BarClass.self, from: fooJsonData)
        })
    }
}
