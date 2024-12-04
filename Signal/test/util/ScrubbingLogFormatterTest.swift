//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CocoaLumberjack
import SignalRingRTC
import XCTest

@testable import SignalServiceKit

final class ScrubbingLogFormatterTest: XCTestCase {
    private let formatter = ScrubbingLogFormatter()

    private func format(_ input: String) -> String {
        return formatter.redactMessage(input)
    }

    func testDataScrubbed_preformatted() {
        let testCases: [String: String] = [
            "<01>": "<01…>",
            "<0123>": "<01…>",
            "<012345>": "<01…>",
            "<01234567>": "<01…>",
            "<01234567 89>": "<01…>",
            "<01234567 89a2>": "<01…>",
            "<01234567 89a23d>": "<01…>",
            "<01234567 89a23def>": "<01…>",
            "<01234567 89a23def 23>": "<01…>",
            "<01234567 89a23def 2323>": "<01…>",
            "<01234567 89a23def 232345>": "<01…>",
            "<01234567 89a23def 23234567>": "<01…>",
            "<01234567 89a23def 23234567 89>": "<01…>",
            "<01234567 89a23def 23234567 89ab>": "<01…>",
            "<01234567 89a23def 23234567 89ab12>": "<01…>",
            "<01234567 89a23def 23234567 89ab1234>": "<01…>",
            "{length = 32, bytes = 0xaa}": "<aa…>",
            "{length = 32, bytes = 0xaaaaaaaa}": "<aa…>",
            "{length = 32, bytes = 0xff}": "<ff…>",
            "{length = 32, bytes = 0xffff}": "<ff…>",
            "{length = 32, bytes = 0x00}": "<00…>",
            "{length = 32, bytes = 0x0000}": "<00…>",
            "{length = 32, bytes = 0x99}": "<99…>",
            "{length = 32, bytes = 0x999999}": "<99…>",
            "{length = 32, bytes = 0x00010203 44556677 89898989 abcdef01 ... aabbccdd eeff1234 }":
                "<00…>",
            "My data is: <01234567 89a23def 23234567 89ab1223>": "My data is: <01…>",
            "My data is <12345670 89a23def 23234567 89ab1223> their data is <87654321 89ab1234>":
                "My data is <12…> their data is <87…>"
        ]

        for (input, expectedOutput) in testCases {
            XCTAssertEqual(
                format(input),
                expectedOutput,
                "Failed redaction: \(input)"
            )
        }
    }

    func testIOS13AndHigherDataScrubbed() {
        let testCases: [String: String] = [
            "{length = 32, bytes = 0x01}": "<01…>",
            "{length = 32, bytes = 0x0123}": "<01…>",
            "{length = 32, bytes = 0x012345}": "<01…>",
            "{length = 32, bytes = 0x01234567}": "<01…>",
            "{length = 32, bytes = 0x0123456789}": "<01…>",
            "{length = 32, bytes = 0x0123456789a2}": "<01…>",
            "{length = 32, bytes = 0x0123456789a23d}": "<01…>",
            "{length = 32, bytes = 0x0123456789a23def}": "<01…>",
            "{length = 32, bytes = 0x0123456789a23def23}": "<01…>",
            "{length = 32, bytes = 0x0123456789a23def2323}": "<01…>",
            "{length = 32, bytes = 0x0123456789a23def232345}": "<01…>",
            "{length = 32, bytes = 0x0123456789a23def23234567}": "<01…>",
            "{length = 32, bytes = 0x0123456789a23def2323456789}": "<01…>",
            "{length = 32, bytes = 0x0123456789a23def2323456789ab}": "<01…>",
            "{length = 32, bytes = 0x0123456789a23def2323456789ab12}": "<01…>",
            "{length = 32, bytes = 0x0123456789a23def2323456789ab1234}": "<01…>",
            "{length = 32, bytes = 0xaa}": "<aa…>",
            "{length = 32, bytes = 0xaaaaaaaa}": "<aa…>",
            "{length = 32, bytes = 0xff}": "<ff…>",
            "{length = 32, bytes = 0xffff}": "<ff…>",
            "{length = 32, bytes = 0x00}": "<00…>",
            "{length = 32, bytes = 0x0000}": "<00…>",
            "{length = 32, bytes = 0x99}": "<99…>",
            "{length = 32, bytes = 0x999999}": "<99…>",
            "My data is: {length = 32, bytes = 0x0123456789a23def2323456789ab1223}":
                "My data is: <01…>",
            "My data is {length = 32, bytes = 0x1234567089a23def2323456789ab1223} their data is {length = 16, bytes = 0x8765432189ab1234}":
                "My data is <12…> their data is <87…>"
        ]

        for (input, expectedOutput) in testCases {
            XCTAssertEqual(
                format(input),
                expectedOutput,
                "Failed redaction: \(input)"
            )
        }
    }

    func testDataScrubbed_lazyFormatted() {
        let testCases: [Data: String] = [
            .init([0]): "<00…>",
            .init([0, 0, 0]): "<00…>",
            .init([1]): "<01…>",
            .init([1, 2, 3, 0x10, 0x20]): "<01…>",
            .init([0xff]): "<ff…>",
            .init([0xff, 0xff, 0xff]): "<ff…>"
        ]

        for (inputData, expectedOutput) in testCases {
            let input = (inputData as NSData).description
            XCTAssertEqual(
                format(input),
                expectedOutput,
                "Failed redaction: \(input)"
            )
        }
    }

    func testPhoneNumbersScrubbed() {
        let testCases: [(String, String)] = [
            ("my phone is +15557340123", "my phone is +x…123"),
            ("your phone is +447700900124", "your phone is +x…124"),
            ("+15557340123 something +15557340123", "+x…123 something +x…123"),
        ]

        for (inputValue, expectedValue) in testCases {
            let actualOutput = format(inputValue)
            XCTAssertEqual(actualOutput, expectedValue)
        }
    }

    func testGroupIdScrubbed() {
        for _ in 1...100 {
            let isGV1 = Bool.random()
            let groupIdCount = isGV1 ? kGroupIdLengthV1 : kGroupIdLengthV2
            let paddingCount = isGV1 ? 2 : 1
            let groupId = Randomness.generateRandomBytes(groupIdCount)
            let groupIdString = TSGroupThread.defaultThreadId(forGroupId: groupId)

            let expectedOutput = "Hello g…\(groupIdString.suffix(3 + paddingCount))!"
            let actualOutput = format("Hello \(groupIdString)!")

            XCTAssertEqual(actualOutput, expectedOutput, groupIdString)
        }
    }

    func testThingsThatLookLikeGroupIdNotScrubbed() {
        for _ in 1...1024 {
            let fakeGroupIdCount = UInt.random(in: 1...(kGroupIdLengthV2 * 2))
            let fakeGroupId = Randomness.generateRandomBytes(fakeGroupIdCount)
            let fakeGroupIdString = TSGroupThread.defaultThreadId(forGroupId: fakeGroupId)
            let input = "Hello \(fakeGroupIdString)!"

            let result = format(input)
            if result == input {
                return
            }
            // It got scrubbed. Maybe it's
            // - a group ID (≈1/16 chance)
            // - a value that happens to look like a base64 UUID in a path (≈1/192 chance)
            // - a value that happens to have many adjacent hex characters (??? chance)
        }
        XCTFail("Too many things that aren't group IDs are being treated as group IDs.")
    }

    func testCallLinkScrubbed() {
        XCTAssertEqual(
            format("https://signal.link/call/#key=bcdf-ghkm-npqr-stxz-bcdf-ghkm-npqr-stxz"),
            "https://signal.link/call/#key=bcdf-…-xxxx"
        )
    }

    func testNotScrubbed() {
        let input = "Some unfiltered string"
        let result = format(input)
        XCTAssertEqual(result, input)
    }

    func testIPv4AddressesScrubbed() {
        let valueMap: [String: String] = [
            "0.0.0.0": "x.x.x.0",
            "127.0.0.1": "x.x.x.1",
            "255.255.255.255": "x.x.x.255",
            "1.2.3.4": "x.x.x.4"
        ]
        let messageFormats: [String] = [
            "a%@b",
            "http://%@",
            "http://%@/",
            "%@ and %@ and %@",
            "%@",
            "%@ %@",
            "no ip address!",
            ""
        ]

        for (ipAddress, redactedIpAddress) in valueMap {
            for messageFormat in messageFormats {
                let input = messageFormat.replacingOccurrences(of: "%@", with: ipAddress)
                let result = format(input)
                let expectedOutput = messageFormat.replacingOccurrences(of: "%@", with: redactedIpAddress)
                XCTAssertEqual(result, expectedOutput, input)
            }
        }
    }

    /// IPv6 addresses are _hard_.
    ///
    /// The test cases here were borrowed from RingRTC:
    /// - https://github.com/signalapp/ringrtc/blob/cfe07c57888d930d1114ddccbdd73d3f556b3b40/src/rust/src/core/util.rs#L149-L197
    /// - https://github.com/signalapp/ringrtc/blob/cfe07c57888d930d1114ddccbdd73d3f556b3b40/src/rust/src/core/util.rs#L364-L413
    func testIPv6AddressesScrubbed() {
        func runTest(messageFormat: String, ipAddress: String) {
            let input = messageFormat.replacingOccurrences(of: "%@", with: ipAddress)
            let expectedOutput = messageFormat.replacingOccurrences(of: "%@", with: "[IPV6]")
            let result = format(input)
            XCTAssertEqual(result, expectedOutput, input)
        }

        let testAddresses: [String] = [
            "Fe80::2d8:61ff:fe57:83f6",
            "fE80::2d8:61ff:fe57:83f6",
            "fe80::2d8:61ff:fe57:83f6",
            "2001:db8:3:4::192.0.2.33",
            "2021:0db8:85a3:0000:0000:8a2e:0370:7334",
            "2301:db8:85a3::8a2e:370:7334",
            "4601:746:9600:dec1:2d8:61ff:fe57:83f6",
            "64:ff9b::192.0.2.33",
            "1:2:3:4:5:6:7:8",
            "1::3:4:5:6:7:8",
            "1::4:5:6:7:8",
            "1::5:6:7:8",
            "1::6:7:8",
            "1::7:8",
            "1::8",
            "1::",
            "1:2::8",
            "1:2:3::8",
            "1:2:3:4::8",
            "1:2:3:4:5::8",
            "1:2:3:4:5:6::8",
            "1:2:3:4:5:6:7::",
            "1::3:4:5:6:7:8",
            "1:2::4:5:6:7:8",
            "1:2:3::5:6:7:8",
            "1:2:3:4::6:7:8",
            "1:2:3:4:5::7:8",
            "1:2:3:4:5:6::8",
            "::255.255.255.255",
            "::ffff:255.255.255.255",
            "::ffff:0:255.255.255.255",
            "::ffff:192.0.2.128",
            "::ffff:0:192.0.2.128",
            "::2:3:4:5:6:7:8",
            "::2:3:4:5:6:7:8",
            "::",
            "::0",
            "::1",
            "::8",
        ]

        // IPv6 addresses with a zone index will absorb any trailing characters
        // into the zone index, so we need to test them slightly differently.
        let testAddressesWithZoneIndex: [String] = [
            "fe80::7:8%eth0",
            "fe80::7:8%1",
        ]

        let messageFormats: [String] = [
            "http://[%@]",
            "http://[%@]/",
            "%@ and %@ and %@",
            "%@",
            "%@ %@",
            "no ip address!",
            ""
        ]

        for ipAddress in testAddresses {
            for messageFormat in (messageFormats + ["x%@y"]) {
                runTest(messageFormat: messageFormat, ipAddress: ipAddress)
            }
        }

        for ipAddress in testAddressesWithZoneIndex {
            for messageFormat in (messageFormats + ["x%@"]) {
                runTest(messageFormat: messageFormat, ipAddress: ipAddress)
            }
        }
    }

    func testUUIDsScrubbed_Random() {
        for _ in (1...10) {
            let uuidString = UUID().uuidString
            let result = format("My UUID is \(uuidString)")
            XCTAssertEqual(result, "My UUID is xxxx-xx-xx-xxx\(uuidString.suffix(3))")
        }
    }

    func testUUIDsScrubbed_Specific() {
        let uuidString = "BAF1768C-2A25-4D8F-83B7-A89C59C98748"
        let result = format("My UUID is \(uuidString)")
        XCTAssertEqual(result, "My UUID is xxxx-xx-xx-xxx748")
    }

    func testTimestampsNotScrubbed() {
        // A couple sample messages from our logs
        let timestamp = Date.ows_millisecondTimestamp()
        let testCases: [String: String] = [
            // No change:
            "Sending message: TSOutgoingMessage, timestamp: \(timestamp)": "Sending message: TSOutgoingMessage, timestamp: \(timestamp)",
            // Leave timestamp, but UUID and phone number should be redacted
            "attempting to send message: TSOutgoingMessage, timestamp: \(timestamp), recipient: <SignalServiceAddress phoneNumber: +12345550123, uuid: BAF1768C-2A25-4D8F-83B7-A89C59C98748>":
                "attempting to send message: TSOutgoingMessage, timestamp: \(timestamp), recipient: <SignalServiceAddress phoneNumber: +x…123, uuid: xxxx-xx-xx-xxx748>"
        ]

        for (input, expectedOutput) in testCases {
            XCTAssertEqual(
                format(input),
                expectedOutput,
                "Failed redaction: \(input)"
            )
        }
    }

    func testLongHexStrings() {
        let testCases: [String: String] = [
            "": "",
            "01": "01",
            "0102": "0102",
            "010203": "010203",
            "01020304": "01020304",
            "0102030405": "0102030405",
            "010203040506": "010203040506",
            "01020304050607": "…607",
            "0102030405060708": "…708",
            "010203040506070809": "…809",
            "010203040506070809ab": "…9ab",
            "010203040506070809abcd": "…bcd"
        ]

        for (input, expectedOutput) in testCases {
            XCTAssertEqual(
                format(input),
                expectedOutput,
                "Failed redaction: \(input)"
            )
        }
    }

    func testBase64UUIDsScrubbed_Random() {
        for _ in (1...10) {
            let uuid = UUID().data.base64EncodedString()
            let result = format("My base64 UUID is \(uuid)")
            XCTAssertEqual(result, "My base64 UUID is …\(uuid.suffix(5))")
        }
    }

    func testBase64UUIDsScrubbed_Specific() {
        let uuidString = "GW/VMbPjTiyr5cSoblKBmQ=="
        let result = format("My base64 UUID is \(uuidString)")
        XCTAssertEqual(result, "My base64 UUID is …BmQ==")
    }

    func testBase64UUIDsScrubbed_SpecificInURL() {
        var uuidString = "sdfssAFFDSAFdsFFsdaFfg=="
        var result = format("http://signal.org/\(uuidString)")
        XCTAssertEqual(result, "http://signal.org/…Ffg==")

        // Do one with a leading / in itself.
        uuidString = "/dfssAFFDSAFdsFFsdaFfg=="
        result = format("http://signal.org/\(uuidString)")
        XCTAssertEqual(result, "http://signal.org/…Ffg==")
    }

    func testBase64UUIDsScrubbed_dontScrubDifferentLengths() {
        for byteLength in [15, 17, 1] {
            for _ in (1...10) {
                let stringValue = Randomness.generateRandomBytes(UInt(byteLength)).base64EncodedString()
                let result = format("My base64 UUID is not \(stringValue)")
                XCTAssert(result.contains(stringValue), "Incorrectly redacted non UUID base64 string: \(result)")
            }
        }
    }

    func testBase64RoomId() {
        let roomIdString = CallLinkRootKey.generate().deriveRoomId().base64EncodedString()
        let result = format("The room is \(roomIdString)")
        XCTAssertEqual(result, "The room is …\(roomIdString.suffix(4))")
    }

    func testHexRoomId() {
        let roomIdString = CallLinkRootKey.generate().deriveRoomId().hexadecimalString
        let result = format("The room is \(roomIdString)")
        XCTAssertEqual(result, "The room is …\(roomIdString.suffix(3))")
    }
}
