//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit
import SwiftProtobuf

class SSKProtoEnvelopeTest: SignalBaseTest {
    func testParse_EmptyData() {
        let data = Data()
        XCTAssertThrowsError(try SSKProtoEnvelope(serializedData: data))
    }

    func testParse_UnparseableData() {
        let data = "asdf".data(using: .utf8)!
        XCTAssertThrowsError(try SSKProtoEnvelope(serializedData: data)) { error in
            XCTAssert(error is SwiftProtobuf.BinaryDecodingError)
        }
    }

    func testParse_ValidData() {
        // `encodedData` was derived thus:
        //     let builder = SSKProtoEnvelopeBuilder()
        //     builder.setTimestamp(NSDate.ows_millisecondTimeStamp())
        //     builder.setSourceUuid(UUID().uuidString)
        //     builder.setSourceDevice(1)
        //     builder.setType(SSKProtoEnvelopeType.ciphertext)
        //     let encodedData = try! builder.build().serializedData().base64EncodedString()
        let encodedData = "CAEo/ovqh7gwOAFaJENFNTk5RjlCLThDNjQtNEM1OC1CNUQwLUU4MDE0NTAxQzhBMw=="
        let data = Data(base64Encoded: encodedData)!

        XCTAssertNoThrow(try SSKProtoEnvelope(serializedData: data))
    }

    func testParse_invalidData() {
        // `encodedData` was derived thus:
        // var proto = SignalServiceKit.SignalServiceProtos_Envelope()
        // proto.sourceUuid = UUID().uuidString
        // proto.sourceDevice = 1
        // // MISSING TIMESTAMP!
        //
        // let encodedData = try! proto.serializedData().base64EncodedString()
        let encodedData = "OAFaJEZEMkU1M0RELUJEQjAtNDg1Qi04OUFELTlBRTA3RTYxRjUzMw=="
        let data = Data(base64Encoded: encodedData)!

        XCTAssertThrowsError(try SSKProtoEnvelope(serializedData: data)) { (error) -> Void in
            switch error {
            case SSKProtoError.invalidProtobuf:
                break
            default:
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testParse_roundtrip() {
        let builder = SSKProtoEnvelope.builder(timestamp: 123)
        builder.setType(SSKProtoEnvelopeType.prekeyBundle)
        builder.setSourceUuid("CE599F9B-8C64-4C58-B5D0-E8014501C8A3")
        builder.setSourceDevice(1)

        let phonyContent = "phony data".data(using: .utf8)!

        builder.setContent(phonyContent)

        var envelopeData: Data
        do {
            envelopeData = try builder.buildSerializedData()
        } catch {
            XCTFail("Couldn't serialize data.")
            return
        }

        var envelope: SSKProtoEnvelope
        do {
            envelope = try SSKProtoEnvelope(serializedData: envelopeData)
        } catch {
            XCTFail("Couldn't serialize data.")
            return
        }

        XCTAssertEqual(envelope.type, SSKProtoEnvelopeType.prekeyBundle)
        XCTAssertEqual(envelope.timestamp, 123)
        XCTAssertEqual(envelope.sourceUuid, "CE599F9B-8C64-4C58-B5D0-E8014501C8A3")
        XCTAssertEqual(envelope.sourceDevice, 1)
        XCTAssertTrue(envelope.hasContent)
        XCTAssertEqual(envelope.content, phonyContent)
    }
}
