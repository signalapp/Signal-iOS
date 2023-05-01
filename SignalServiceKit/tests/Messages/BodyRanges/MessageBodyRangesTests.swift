//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

final class MessageBodyRangesTests: XCTestCase {

    typealias Style = MessageBodyRanges.Style

    // MARK: - Style Collapsing

    func testStyleCollapsing_sequential() {
        // They don't overlap but they're out of order.
        let styles: [(NSRange, Style)] = [
            (NSRange(location: 11, length: 5), .strikethrough),
            (NSRange(location: 0, length: 1), .bold),
            (NSRange(location: 1, length: 2), .italic),
            (NSRange(location: 120, length: 10), .bold.union(.italic)),
            (NSRange(location: 3, length: 3), .monospace),
            (NSRange(location: 6, length: 4), .spoiler)
        ]
        let expectedOutput: [(NSRange, Style)] = [
            (NSRange(location: 0, length: 1), .bold),
            (NSRange(location: 1, length: 2), .italic),
            (NSRange(location: 3, length: 3), .monospace),
            (NSRange(location: 6, length: 4), .spoiler),
            (NSRange(location: 11, length: 5), .strikethrough),
            (NSRange(location: 120, length: 10), .bold.union(.italic))
        ]
        let output = MessageBodyRanges(mentions: [:], styles: styles).styles
        assertStylesEqual(expectedOutput, output)
    }

    func testStyleCollapsing_overlap() {
        var styles: [(NSRange, Style)] = [
            (NSRange(location: 0, length: 3), .bold),
            (NSRange(location: 1, length: 3), .italic)
        ]
        var expectedOutput: [(NSRange, Style)] = [
            (NSRange(location: 0, length: 1), .bold),
            (NSRange(location: 1, length: 2), .bold.union(.italic)),
            (NSRange(location: 3, length: 1), .italic)
        ]
        var output = MessageBodyRanges(mentions: [:], styles: styles).styles
        assertStylesEqual(expectedOutput, output)

        styles = [
            (NSRange(location: 0, length: 5), .bold),
            (NSRange(location: 1, length: 3), .italic)
        ]
        expectedOutput = [
            (NSRange(location: 0, length: 1), .bold),
            (NSRange(location: 1, length: 3), .bold.union(.italic)),
            (NSRange(location: 4, length: 1), .bold)
        ]
        output = MessageBodyRanges(mentions: [:], styles: styles).styles
        assertStylesEqual(expectedOutput, output)

        styles = [
            (NSRange(location: 0, length: 5), .bold),
            (NSRange(location: 4, length: 5), .italic),
            (NSRange(location: 8, length: 5), .spoiler)
        ]
        expectedOutput = [
            (NSRange(location: 0, length: 4), .bold),
            (NSRange(location: 4, length: 1), .bold.union(.italic)),
            (NSRange(location: 5, length: 3), .italic),
            (NSRange(location: 8, length: 1), .italic.union(.spoiler)),
            (NSRange(location: 9, length: 4), .spoiler)
        ]
        output = MessageBodyRanges(mentions: [:], styles: styles).styles
        assertStylesEqual(expectedOutput, output)

        styles = [
            (NSRange(location: 0, length: 6), .bold),
            (NSRange(location: 1, length: 6), .italic),
            (NSRange(location: 2, length: 6), .spoiler),
            (NSRange(location: 3, length: 6), .strikethrough),
            (NSRange(location: 4, length: 6), .monospace)
        ]
        expectedOutput = [
            (NSRange(location: 0, length: 1), .bold),
            (NSRange(location: 1, length: 1), .bold.union(.italic)),
            (NSRange(location: 2, length: 1), .bold.union(.italic).union(.spoiler)),
            (NSRange(location: 3, length: 1), .bold.union(.italic).union(.spoiler).union(.strikethrough)),
            (NSRange(location: 4, length: 2), .bold.union(.italic).union(.spoiler).union(.strikethrough).union(.monospace)),
            (NSRange(location: 6, length: 1), .italic.union(.spoiler).union(.strikethrough).union(.monospace)),
            (NSRange(location: 7, length: 1), .spoiler.union(.strikethrough).union(.monospace)),
            (NSRange(location: 8, length: 1), .strikethrough.union(.monospace)),
            (NSRange(location: 9, length: 1), .monospace)
        ]
        output = MessageBodyRanges(mentions: [:], styles: styles).styles
        assertStylesEqual(expectedOutput, output)
    }

    func testDeserializeV1() throws {
        let encodedDataBase64 = "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvEBALDB0lJictMTQWODs/QEFEVSRudWxs2A0ODxAREhMUFRYXGBkaGxxfEBBtZW50aW9ucy5yYW5nZS4wXW1lbnRpb25zQ291bnRWJGNsYXNzXxAPbWVudGlvbnMudXVpZC4yXxAQbWVudGlvbnMucmFuZ2UuMV8QEG1lbnRpb25zLnJhbmdlLjJfEA9tZW50aW9ucy51dWlkLjFfEA9tZW50aW9ucy51dWlkLjCAAhADgA+ADoAIgAuACoAG1B4fIA8hIiMkXxASTlMucmFuZ2V2YWwubGVuZ3RoXxAUTlMucmFuZ2V2YWwubG9jYXRpb25aTlMuc3BlY2lhbIADgAQQBIAFEAEQANIoKSorWiRjbGFzc25hbWVYJGNsYXNzZXNXTlNWYWx1ZaIqLFhOU09iamVjdNIuDy8wXE5TLnV1aWRieXRlc08QEDRv6bLICE9hkgPhkjjFju2AB9IoKTIzVk5TVVVJRKIyLNQeHyAPITYjJIADgAmABdIuDzkwTxAQ4Vl38Lg2TAKkc40D+J1IxoAH1B4fIA88PSMkgAyADYAFEAcQBdIuD0IwTxAQhC0Fz6D1SSiY4rfoa5AXlIAH0igpRUZfECJTaWduYWxTZXJ2aWNlS2l0Lk1lc3NhZ2VCb2R5UmFuZ2VzokcsXxAiU2lnbmFsU2VydmljZUtpdC5NZXNzYWdlQm9keVJhbmdlcwAIABEAGgAkACkAMgA3AEkATABRAFMAZgBsAH0AkACeAKUAtwDKAN0A7wEBAQMBBQEHAQkBCwENAQ8BEQEaAS8BRgFRAVMBVQFXAVkBWwFdAWIBbQF2AX4BgQGKAY8BnAGvAbEBtgG9AcAByQHLAc0BzwHUAecB6QHyAfQB9gH4AfoB/AIBAhQCFgIbAkACQwAAAAAAAAIBAAAAAAAAAEgAAAAAAAAAAAAAAAAAAAJo"
        let expectedResult = MessageBodyRanges(
            mentions: [
                NSRange(location: 0, length: 1): UUID(uuidString: "346FE9B2-C808-4F61-9203-E19238C58EED")!,
                NSRange(location: 3, length: 1): UUID(uuidString: "E15977F0-B836-4C02-A473-8D03F89D48C6")!,
                NSRange(location: 5, length: 7): UUID(uuidString: "842D05CF-A0F5-4928-98E2-B7E86B901794")!
            ],
            styles: []
        )

        let data = Data(base64Encoded: encodedDataBase64)!
        let decoded = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: MessageBodyRanges.self,
            from: data
        )
        XCTAssertEqual(expectedResult, decoded)
    }

    func testDeserializeV2() throws {
        let encodedDataBase64 = "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvEBoLDDc+P0BGSk0iUVJVJVlcYDBkaCZscCd0dVUkbnVsbN8QFQ0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Nl5zdHlsZXMuc3R5bGUuMF5zdHlsZXMucmFuZ2UuNV5zdHlsZXMucmFuZ2UuMl1tZW50aW9uc0NvdW50XnN0eWxlcy5zdHlsZS41W3N0eWxlc0NvdW50ViRjbGFzc18QEG1lbnRpb25zLnJhbmdlLjFec3R5bGVzLnN0eWxlLjJfEA9tZW50aW9ucy51dWlkLjBec3R5bGVzLnJhbmdlLjRec3R5bGVzLnJhbmdlLjFec3R5bGVzLnN0eWxlLjRfEA9tZW50aW9ucy51dWlkLjFec3R5bGVzLnN0eWxlLjFfEBBtZW50aW9ucy5yYW5nZS4yXnN0eWxlcy5yYW5nZS4zXxAQbWVudGlvbnMucmFuZ2UuMF8QD21lbnRpb25zLnV1aWQuMl5zdHlsZXMucmFuZ2UuMF5zdHlsZXMuc3R5bGUuMxABgBaAEhADEAQQBoAZgAgQGoAGgBWAEBAUgAsQAoAMgBOAAoAOgA8QEtQ4OToTOzwmPV8QEk5TLnJhbmdldmFsLmxlbmd0aF8QFE5TLnJhbmdldmFsLmxvY2F0aW9uWk5TLnNwZWNpYWyAA4AEgAUQBxAF0kFCQ0RaJGNsYXNzbmFtZVgkY2xhc3Nlc1dOU1ZhbHVlokNFWE5TT2JqZWN00kcTSElcTlMudXVpZGJ5dGVzTxAQrp7/WnBvRr6+oaToYla4x4AH0kFCS0xWTlNVVUlEoktF1Dg5OhNOTyY9gAmACoAFEADSRxNTSU8QEK9AYjOzRE5Ame2tCAuLGs+AB9Q4OToTTlcmPYAJgA2ABdJHE1pJTxAQAXRH4MWkRWykwR7H+RrAcIAH1Dg5OhNOTyY9gAmACoAF1Dg5OhNOYiY9gAmAEYAF1Dg5OhNOVyY9gAmADYAF1Dg5OhNOaiY9gAmAFIAF1Dg5OhM7PCY9gAOABIAF1Dg5OhNxciY9gBeAGIAFEAzSQUJ2d18QIlNpZ25hbFNlcnZpY2VLaXQuTWVzc2FnZUJvZHlSYW5nZXOieEVfECJTaWduYWxTZXJ2aWNlS2l0Lk1lc3NhZ2VCb2R5UmFuZ2VzAAgAEQAaACQAKQAyADcASQBMAFEAUwBwAHYAowCyAMEA0ADeAO0A+QEAARMBIgE0AUMBUgFhAXMBggGVAaQBtwHJAdgB5wHpAesB7QHvAfEB8wH1AfcB+QH7Af0B/wIBAgMCBQIHAgkCCwINAg8CEQIaAi8CRgJRAlMCVQJXAlkCWwJgAmsCdAJ8An8CiAKNApoCrQKvArQCuwK+AscCyQLLAs0CzwLUAucC6QLyAvQC9gL4Av0DEAMSAxsDHQMfAyEDKgMsAy4DMAM5AzsDPQM/A0gDSgNMA04DVwNZA1sDXQNmA2gDagNsA24DcwOYA5sAAAAAAAACAQAAAAAAAAB5AAAAAAAAAAAAAAAAAAADwA=="

        let expectedResult = MessageBodyRanges(
            mentions: [
                NSRange(location: 0, length: 1): UUID(uuidString: "AF406233-B344-4E40-99ED-AD080B8B1ACF")!,
                NSRange(location: 3, length: 1): UUID(uuidString: "017447E0-C5A4-456C-A4C1-1EC7F91AC070")!,
                NSRange(location: 5, length: 7): UUID(uuidString: "AE9EFF5A-706F-46BE-BEA1-A4E86256B8C7")!
            ],
            styles: [
                (NSRange(location: 0, length: 1), .bold),
                (NSRange(location: 2, length: 1), .italic),
                (NSRange(location: 3, length: 1), .italic.union(.monospace).union(.strikethrough)),
                (NSRange(location: 4, length: 1), .italic.union(.monospace)),
                (NSRange(location: 5, length: 2), .monospace),
                (NSRange(location: 8, length: 10), .spoiler)
            ]
        )

        let data = Data(base64Encoded: encodedDataBase64)!
        let decoded = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: MessageBodyRanges.self,
            from: data
        )
        XCTAssertEqual(expectedResult, decoded)
    }

    // MARK: - Helpers

    private func assertStylesEqual(
        _ lhs: [(NSRange, Style)],
        _ rhs: [(NSRange, Style)],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        for i in 0..<lhs.count {
            XCTAssertEqual(lhs[i].0, rhs[i].0)
            XCTAssertEqual(lhs[i].1, rhs[i].1)
        }
    }

}
