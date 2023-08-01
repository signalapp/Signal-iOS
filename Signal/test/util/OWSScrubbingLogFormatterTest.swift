//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import CocoaLumberjack
import SignalCoreKit
import SignalServiceKit
@testable import SignalMessaging

final class OWSScrubbingLogFormatterTest: XCTestCase {
    private var formatter: OWSScrubbingLogFormatter { OWSScrubbingLogFormatter() }

    private func message(with string: String) -> DDLogMessage {
        DDLogMessage(
            message: string,
            level: .info,
            flag: [],
            context: 0,
            file: "mock file name",
            function: "mock function name",
            line: 0,
            tag: nil,
            options: [],
            timestamp: Date.init(timeIntervalSinceNow: 0)
        )
    }

    private lazy var datePrefixLength: Int = {
        // Other formatters add a dynamic date prefix to log lines. We truncate that when comparing our expected output.
        formatter.format(message: message(with: ""))!.count
    }()

    private func format(_ input: String) -> String {
        formatter.format(message: message(with: input)) ?? ""
    }

    private func stripDate(fromRawMessage rawMessage: String) -> String {
        rawMessage.substring(from: datePrefixLength)
    }

    func testAttachmentPathScrubbed() {
        let testCases: [String] = [
            "/Attachments/",
            "/foo/bar/Attachments/abc123.txt",
            "Something /foo/bar/Attachments/abc123.txt Something"
        ]

        for testCase in testCases {
            XCTAssertEqual(format(testCase), "[ REDACTED_CONTAINS_USER_PATH ]")
        }
    }

    func testDataScrubbed_preformatted() {
        let testCases: [String: String] = [
            "<01>": "[ REDACTED_DATA:01... ]",
            "<0123>": "[ REDACTED_DATA:01... ]",
            "<012345>": "[ REDACTED_DATA:01... ]",
            "<01234567>": "[ REDACTED_DATA:01... ]",
            "<01234567 89>": "[ REDACTED_DATA:01... ]",
            "<01234567 89a2>": "[ REDACTED_DATA:01... ]",
            "<01234567 89a23d>": "[ REDACTED_DATA:01... ]",
            "<01234567 89a23def>": "[ REDACTED_DATA:01... ]",
            "<01234567 89a23def 23>": "[ REDACTED_DATA:01... ]",
            "<01234567 89a23def 2323>": "[ REDACTED_DATA:01... ]",
            "<01234567 89a23def 232345>": "[ REDACTED_DATA:01... ]",
            "<01234567 89a23def 23234567>": "[ REDACTED_DATA:01... ]",
            "<01234567 89a23def 23234567 89>": "[ REDACTED_DATA:01... ]",
            "<01234567 89a23def 23234567 89ab>": "[ REDACTED_DATA:01... ]",
            "<01234567 89a23def 23234567 89ab12>": "[ REDACTED_DATA:01... ]",
            "<01234567 89a23def 23234567 89ab1234>": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0xaa}": "[ REDACTED_DATA:aa... ]",
            "{length = 32, bytes = 0xaaaaaaaa}": "[ REDACTED_DATA:aa... ]",
            "{length = 32, bytes = 0xff}": "[ REDACTED_DATA:ff... ]",
            "{length = 32, bytes = 0xffff}": "[ REDACTED_DATA:ff... ]",
            "{length = 32, bytes = 0x00}": "[ REDACTED_DATA:00... ]",
            "{length = 32, bytes = 0x0000}": "[ REDACTED_DATA:00... ]",
            "{length = 32, bytes = 0x99}": "[ REDACTED_DATA:99... ]",
            "{length = 32, bytes = 0x999999}": "[ REDACTED_DATA:99... ]",
            "{length = 32, bytes = 0x00010203 44556677 89898989 abcdef01 ... aabbccdd eeff1234 }":
                "[ REDACTED_DATA:00... ]",
            "My data is: <01234567 89a23def 23234567 89ab1223>": "My data is: [ REDACTED_DATA:01... ]",
            "My data is <12345670 89a23def 23234567 89ab1223> their data is <87654321 89ab1234>":
                "My data is [ REDACTED_DATA:12... ] their data is [ REDACTED_DATA:87... ]"
        ]

        for (input, expectedOutput) in testCases {
            XCTAssertEqual(
                stripDate(fromRawMessage: format(input)),
                expectedOutput,
                "Failed redaction: \(input)"
            )
        }
    }

    func testIOS13AndHigherDataScrubbed() {
        let testCases: [String: String] = [
            "{length = 32, bytes = 0x01}": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0x0123}": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0x012345}": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0x01234567}": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0x0123456789}": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0x0123456789a2}": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0x0123456789a23d}": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0x0123456789a23def}": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0x0123456789a23def23}": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0x0123456789a23def2323}": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0x0123456789a23def232345}": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0x0123456789a23def23234567}": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0x0123456789a23def2323456789}": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0x0123456789a23def2323456789ab}": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0x0123456789a23def2323456789ab12}": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0x0123456789a23def2323456789ab1234}": "[ REDACTED_DATA:01... ]",
            "{length = 32, bytes = 0xaa}": "[ REDACTED_DATA:aa... ]",
            "{length = 32, bytes = 0xaaaaaaaa}": "[ REDACTED_DATA:aa... ]",
            "{length = 32, bytes = 0xff}": "[ REDACTED_DATA:ff... ]",
            "{length = 32, bytes = 0xffff}": "[ REDACTED_DATA:ff... ]",
            "{length = 32, bytes = 0x00}": "[ REDACTED_DATA:00... ]",
            "{length = 32, bytes = 0x0000}": "[ REDACTED_DATA:00... ]",
            "{length = 32, bytes = 0x99}": "[ REDACTED_DATA:99... ]",
            "{length = 32, bytes = 0x999999}": "[ REDACTED_DATA:99... ]",
            "My data is: {length = 32, bytes = 0x0123456789a23def2323456789ab1223}":
                "My data is: [ REDACTED_DATA:01... ]",
            "My data is {length = 32, bytes = 0x1234567089a23def2323456789ab1223} their data is {length = 16, bytes = 0x8765432189ab1234}":
                "My data is [ REDACTED_DATA:12... ] their data is [ REDACTED_DATA:87... ]"
        ]

        for (input, expectedOutput) in testCases {
            XCTAssertEqual(
                stripDate(fromRawMessage: format(input)),
                expectedOutput,
                "Failed redaction: \(input)"
            )
        }
    }

    func testDataScrubbed_lazyFormatted() {
        let testCases: [Data: String] = [
            .init([0]): "[ REDACTED_DATA:00... ]",
            .init([0, 0, 0]): "[ REDACTED_DATA:00... ]",
            .init([1]): "[ REDACTED_DATA:01... ]",
            .init([1, 2, 3, 0x10, 0x20]): "[ REDACTED_DATA:01... ]",
            .init([0xff]): "[ REDACTED_DATA:ff... ]",
            .init([0xff, 0xff, 0xff]): "[ REDACTED_DATA:ff... ]"
        ]

        for (inputData, expectedOutput) in testCases {
            let input = (inputData as NSData).description
            XCTAssertEqual(
                stripDate(fromRawMessage: format(input)),
                expectedOutput,
                "Failed redaction: \(input)"
            )
        }
    }

    func testPhoneNumbersScrubbed() {
        let phoneStrings: [String] = [
            "+15557340123",
            "+447700900123",
            "+15557340123 somethingsomething +15557340123"
        ]
        let expectedOutput = "My phone number is [ REDACTED_PHONE_NUMBER:xxx123 ]"

        for phoneString in phoneStrings {
            let result = format("My phone number is \(phoneString)")
            XCTAssertTrue(result.contains(expectedOutput), "Failed to redact phone string: \(phoneString)")
            XCTAssertFalse(result.contains(phoneString), "Failed to redact phone string: \(phoneString)")
        }
    }

    func testGroupIdScrubbed() {
        for _ in 1...100 {
            let groupIdCount = Bool.random() ? kGroupIdLengthV1 : kGroupIdLengthV2
            let groupId = Randomness.generateRandomBytes(groupIdCount)
            let groupIdString = TSGroupThread.defaultThreadId(forGroupId: groupId)

            let expectedOutput = "Hello [ REDACTED_GROUP_ID:...\(groupIdString.suffix(2)) ]!"

            let result = format("Hello \(groupIdString)!")

            XCTAssertTrue(
                result.contains(expectedOutput),
                "Failed to redact group ID: \(groupIdString). Result was \(result)"
            )
        }
    }

    func testThingsThatLookLikeGroupIdNotScrubbed() {
        let forbiddenBase64Lengths = Set([
            kGroupIdLengthV1.base64Length,
            kGroupIdLengthV2.base64Length
        ])

        for _ in 1...100 {
            let fakeGroupIdCount: Int32 = {
                while true {
                    let result = Int32.random(in: 1...(kGroupIdLengthV2 * 2))
                    if !forbiddenBase64Lengths.contains(result.base64Length) {
                        return result
                    }
                }
            }()
            let fakeGroupId = Randomness.generateRandomBytes(fakeGroupIdCount)
            let fakeGroupIdString = TSGroupThread.defaultThreadId(forGroupId: fakeGroupId)
            // Unfortunately, a portion of the fake groupID can look like a base64-encoded
            // uuid. For example:
            // "SAFsdfdsafSDGHJ/SggGREgAFhGEWRGCDSFfds=="
            // Is that a long group id, or a segment of a url with one path segment being
            // "SAFsdfdsafSDGHJ" and another path segment being the 22 char length + 2 char
            // padding of a base64 encoded uuid? We can't know with a simple regex.
            // Just stop that case here.
            if fakeGroupIdString.hasSuffix("=="), fakeGroupIdString.suffix(25).starts(with: "/") {
                continue
            }
            let input = "Hello \(fakeGroupIdString)!"

            let result = format(input)
            XCTAssertEqual(
                stripDate(fromRawMessage: result),
                input,
                "Should not be affected"
            )
        }
    }

    func testNotScrubbed() {
        let input = "Some unfiltered string"
        let result = format(input)
        XCTAssertEqual(stripDate(fromRawMessage: result), input, "Shouldn't touch this string")
    }

    func testIPv4AddressesScrubbed() {
        let valueMap: [String: String] = [
            "0.0.0.0": "[ REDACTED_IPV4_ADDRESS:...0 ]",
            "127.0.0.1": "[ REDACTED_IPV4_ADDRESS:...1 ]",
            "255.255.255.255": "[ REDACTED_IPV4_ADDRESS:...255 ]",
            "1.2.3.4": "[ REDACTED_IPV4_ADDRESS:...4 ]"
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
                XCTAssertEqual(
                    stripDate(fromRawMessage: result),
                    expectedOutput,
                    "Failed to redact IP address input: \(input)"
                )
                XCTAssertFalse(
                    result.contains(ipAddress),
                    "Failed to redact IP address input: \(input)"
                )
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
            let expectedOutput = messageFormat.replacingOccurrences(of: "%@", with: "[ REDACTED_IPV6_ADDRESS ]")

            let result = format(input)

            XCTAssertEqual(
                stripDate(fromRawMessage: result),
                expectedOutput,
                "Failed to redact IP address input: \(input)"
            )
            XCTAssertFalse(
                result.contains(ipAddress),
                "Failed to redact IP address input: \(input)"
            )
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
        let expectedOutput = "My UUID is [ REDACTED_UUID:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxx"

        for _ in (1...10) {
            let uuid = UUID().uuidString
            let result = format("My UUID is \(uuid)")
            XCTAssertTrue(result.contains(expectedOutput), "Failed to redact UUID string: \(uuid)")
            XCTAssertFalse(result.contains(uuid), "Failed to redact UUID string: \(uuid)")
        }
    }

    func testUUIDsScrubbed_Specific() {
        let uuid = "BAF1768C-2A25-4D8F-83B7-A89C59C98748"
        let result = format("My UUID is \(uuid)")
        XCTAssertEqual(
            stripDate(fromRawMessage: result),
            "My UUID is [ REDACTED_UUID:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxx748 ]",
            "Failed to redact UUID string: \(uuid)"
        )
        XCTAssertFalse(result.contains(uuid), "Failed to redact UUID string: \(uuid)")
    }

    func testTimestampsNotScrubbed() {
        // A couple sample messages from our logs
        let timestamp = Date.ows_millisecondTimestamp()
        let testCases: [String: String] = [
            // No change:
            "Sending message: TSOutgoingMessage, timestamp: \(timestamp)": "Sending message: TSOutgoingMessage, timestamp: \(timestamp)",
            // Leave timestamp, but UUID and phone number should be redacted
            "attempting to send message: TSOutgoingMessage, timestamp: \(timestamp), recipient: <SignalServiceAddress phoneNumber: +12345550123, uuid: BAF1768C-2A25-4D8F-83B7-A89C59C98748>":
                "attempting to send message: TSOutgoingMessage, timestamp: \(timestamp), recipient: <SignalServiceAddress phoneNumber: [ REDACTED_PHONE_NUMBER:xxx123 ], uuid: [ REDACTED_UUID:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxx748 ]>"
        ]

        for (input, expectedOutput) in testCases {
            XCTAssertEqual(
                stripDate(fromRawMessage: format(input)),
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
            "01020304050607": "[ REDACTED_HEX:...607 ]",
            "0102030405060708": "[ REDACTED_HEX:...708 ]",
            "010203040506070809": "[ REDACTED_HEX:...809 ]",
            "010203040506070809ab": "[ REDACTED_HEX:...9ab ]",
            "010203040506070809abcd": "[ REDACTED_HEX:...bcd ]"
        ]

        for (input, expectedOutput) in testCases {
            XCTAssertEqual(
                stripDate(fromRawMessage: format(input)),
                expectedOutput,
                "Failed redaction: \(input)"
            )
        }
    }

    func testBase64UUIDsScrubbed_Random() {
        let expectedOutputPrefix = "My base64 UUID is [ REDACTED_BASE64_UUID:"
        let expectedOutputSuffix = "... ]"
        let expectedOutputLength = expectedOutputPrefix.count + 3 + expectedOutputSuffix.count

        for _ in (1...10) {
            let uuid = UUID().data.base64EncodedString()
            let result = stripDate(fromRawMessage: format("My base64 UUID is \(uuid)"))
            XCTAssertTrue(result.hasPrefix(expectedOutputPrefix), "Failed to redact base64 UUID string: \(result)")
            XCTAssertTrue(result.hasSuffix(expectedOutputSuffix), "Failed to redact base64 UUID string: \(result)")
            XCTAssertEqual(result.count, expectedOutputLength, "Failed to redact base64 UUID string: \(result)")
            XCTAssertFalse(result.contains(uuid), "Failed to redact base64 UUID string: \(result)")
        }
    }

    func testBase64UUIDsScrubbed_Specific() {
        let uuid = "GW/VMbPjTiyr5cSoblKBmQ=="
        let result = format("My base64 UUID is \(uuid)")
        XCTAssertEqual(
            stripDate(fromRawMessage: result),
            "My base64 UUID is [ REDACTED_BASE64_UUID:GW/... ]",
            "Failed to redact base64 UUID string: \(uuid)"
        )
        XCTAssertFalse(result.contains(uuid), "Failed to redact base64 UUID string: \(uuid)")
    }

    func testBase64UUIDsScrubbed_SpecificInURL() {
        var uuid = "sdfssAFFDSAFdsFFsdaFfg=="
        var result = format("http://signal.org/\(uuid)")
        XCTAssertEqual(
            stripDate(fromRawMessage: result),
            "http://signal.org/[ REDACTED_BASE64_UUID:sdf... ]",
            "Failed to redact base64 UUID string: \(uuid)"
        )
        XCTAssertFalse(result.contains(uuid), "Failed to redact base64 UUID string: \(uuid)")

        // Do one with a leading / in itself.
        uuid = "/dfssAFFDSAFdsFFsdaFfg=="
        result = format("http://signal.org/\(uuid)")
        XCTAssertEqual(
            stripDate(fromRawMessage: result),
            "http://signal.org/[ REDACTED_BASE64_UUID:/df... ]",
            "Failed to redact base64 UUID string: \(uuid)"
        )
        XCTAssertFalse(result.contains(uuid), "Failed to redact base64 UUID string: \(uuid)")
    }

    func testBase64UUIDsScrubbed_dontScrubDifferentLengths() {
        for byteLength in [15, 17, 32, 1] {
            for _ in (1...10) {
                let uuid = Data.secRngGenBytes(byteLength).base64EncodedString()
                let result = stripDate(fromRawMessage: format("My not base64 UUID is \(uuid)"))
                XCTAssert(result.contains(uuid), "Incorrectly redacted non base64 UUID string: \(result)")
            }
        }
    }
}

private extension Int32 {
    var base64Length: Int32 { Int32(4 * ceil(Double(self) / 3)) }
}
