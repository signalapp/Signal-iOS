//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import XCTest

import SignalServiceKit
import SwiftProtobuf

class SSKProtoEnvelopeTest: SignalBaseTest {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testParse_EmptyData() {
        let data = Data()
        XCTAssertThrowsError(try SSKProtoEnvelope.parseData(data))
    }

    func testParse_UnparseableData() {
        let data = "asdf".data(using: .utf8)!
        XCTAssertThrowsError(try SSKProtoEnvelope.parseData(data)) { error in
            XCTAssert(error is SwiftProtobuf.BinaryDecodingError)
        }
    }

    func testParse_ValidData() {
        // `encodedData` was derived thus:
        //     let builder = SSKProtoEnvelopeBuilder()
        //     builder.setTimestamp(NSDate.ows_millisecondTimeStamp())
        //     builder.setSource("+15551231234")
        //     builder.setSourceDevice(1)
        //     builder.setType(SSKProtoEnvelopeType.ciphertext)
        //     let encodedData = builder.build().data()!.base64EncodedString()
        let encodedData = "CAESDCsxNTU1MTIzMTIzNCjKm4WazSw4AQ=="
        let data = Data(base64Encoded: encodedData)!

        XCTAssertNoThrow(try SSKProtoEnvelope.parseData(data))
    }

    func testParse_invalidData() {
        // `encodedData` was derived thus:
        //     let builder = SSKProtoEnvelopeBuilder()
        //     builder.setTimestamp(NSDate.ows_millisecondTimeStamp())
        //     builder.setSource("+15551231234")
        //     builder.setSourceDevice(1)
        //     // MISSING TYPE!
        //     let encodedData = builder.build().data()!.base64EncodedString()
        let encodedData = "EgwrMTU1NTEyMzEyMzQojdmOms0sOAE="
        let data = Data(base64Encoded: encodedData)!

        XCTAssertThrowsError(try SSKProtoEnvelope.parseData(data)) { (error) -> Void in
            switch error {
            case SSKProtoError.invalidProtobuf:
                break
            default:
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testParse_buildVsRequired() {
        let builder = SSKProtoEnvelope.SSKProtoEnvelopeBuilder()

        XCTAssertThrowsError(try builder.build()) { (error) -> Void in
            switch error {
            case SSKProtoError.invalidProtobuf:
                break
            default:
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testParse_roundtrip() {
        let builder = SSKProtoEnvelope.SSKProtoEnvelopeBuilder()

        let phonyContent = "phony data".data(using: .utf8)!

        builder.setType(SSKProtoEnvelope.SSKProtoEnvelopeType.prekeyBundle)
        builder.setTimestamp(123)
        builder.setSource("+13213214321")
        builder.setSourceDevice(1)
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
            envelope = try SSKProtoEnvelope.parseData(envelopeData)
        } catch {
            XCTFail("Couldn't serialize data.")
            return
        }

        XCTAssertEqual(envelope.type, SSKProtoEnvelope.SSKProtoEnvelopeType.prekeyBundle)
        XCTAssertEqual(envelope.timestamp, 123)
        XCTAssertEqual(envelope.source, "+13213214321")
        XCTAssertEqual(envelope.sourceDevice, 1)
        XCTAssertTrue(envelope.hasContent)
        XCTAssertEqual(envelope.content, phonyContent)
        XCTAssertFalse(envelope.hasLegacyMessage)
    }
}
