//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class MessageBodyRangesTests: XCTestCase {

    typealias Style = MessageBodyRanges.Style
    typealias SingleStyle = MessageBodyRanges.SingleStyle
    typealias CollapsedStyle = MessageBodyRanges.CollapsedStyle

    // MARK: - Style Collapsing

    func testStyleCollapsing_sequential() {
        // They don't overlap but they're out of order.
        let styles: [NSRangedValue<SingleStyle>] = [
            .init(.strikethrough, range: NSRange(location: 11, length: 5)),
            .init(.bold, range: NSRange(location: 0, length: 1)),
            .init(.italic, range: NSRange(location: 1, length: 2)),
            .init(.bold, range: NSRange(location: 120, length: 10)),
            .init(.italic, range: NSRange(location: 120, length: 10)),
            .init(.monospace, range: NSRange(location: 3, length: 3)),
            .init(.spoiler, range: NSRange(location: 6, length: 4))
        ]
        let expectedOutput: [NSRangedValue<CollapsedStyle>] = [
            .init(.bold, mergedRange: NSRange(location: 0, length: 1)),
            .init(.italic, mergedRange: NSRange(location: 1, length: 2)),
            .init(.monospace, mergedRange: NSRange(location: 3, length: 3)),
            .init(.spoiler, mergedRange: NSRange(location: 6, length: 4)),
            .init(.strikethrough, mergedRange: NSRange(location: 11, length: 5)),
            .init(
                .init([
                    .bold: NSRange(location: 120, length: 10),
                    .italic: NSRange(location: 120, length: 10)
                ]),
                range: NSRange(location: 120, length: 10)
            )
        ]
        let output = MessageBodyRanges(mentions: [:], styles: styles).collapsedStyles
        assertStylesEqual(expectedOutput, output)
    }

    func testStyleCollapsing_overlap() {
        var styles: [NSRangedValue<SingleStyle>] = [
            .init(.bold, range: NSRange(location: 0, length: 3)),
            .init(.italic, range: NSRange(location: 1, length: 3))
        ]
        var expectedOutput: [NSRangedValue<CollapsedStyle>] = [
            .init(.bold, mergedRange: NSRange(location: 0, length: 3), appliedRange: NSRange(location: 0, length: 1)),
            .init(
                .init([
                    .bold: NSRange(location: 0, length: 3),
                    .italic: NSRange(location: 1, length: 3)
                ]),
                range: NSRange(location: 1, length: 2)
            ),
            .init(.italic, mergedRange: NSRange(location: 1, length: 3), appliedRange: NSRange(location: 3, length: 1))
        ]
        var output = MessageBodyRanges(mentions: [:], styles: styles).collapsedStyles
        assertStylesEqual(expectedOutput, output)

        styles = [
            .init(.bold, range: NSRange(location: 0, length: 5)),
            .init(.italic, range: NSRange(location: 1, length: 3))
        ]
        expectedOutput = [
            .init(.bold, mergedRange: NSRange(location: 0, length: 5), appliedRange: NSRange(location: 0, length: 1)),
            .init(
                .init([
                    .bold: NSRange(location: 0, length: 5),
                    .italic: NSRange(location: 1, length: 3)
                ]),
                range: NSRange(location: 1, length: 3)
            ),
            .init(.bold, mergedRange: NSRange(location: 0, length: 5), appliedRange: NSRange(location: 4, length: 1))
        ]
        output = MessageBodyRanges(mentions: [:], styles: styles).collapsedStyles
        assertStylesEqual(expectedOutput, output)

        styles = [
            .init(.bold, range: NSRange(location: 0, length: 5)),
            .init(.italic, range: NSRange(location: 4, length: 5)),
            .init(.spoiler, range: NSRange(location: 8, length: 5))
        ]
        expectedOutput = [
            .init(.bold, mergedRange: NSRange(location: 0, length: 5), appliedRange: NSRange(location: 0, length: 4)),
            .init(
                .init([
                    .bold: NSRange(location: 0, length: 5),
                    .italic: NSRange(location: 4, length: 5)
                ]),
                range: NSRange(location: 4, length: 1)
            ),
            .init(.italic, mergedRange: NSRange(location: 4, length: 5), appliedRange: NSRange(location: 5, length: 3)),
            .init(
                .init([
                    .italic: NSRange(location: 4, length: 5),
                    .spoiler: NSRange(location: 8, length: 5)
                ]),
                range: NSRange(location: 8, length: 1)
            ),
            .init(.spoiler, mergedRange: NSRange(location: 8, length: 5), appliedRange: NSRange(location: 9, length: 4))
        ]
        output = MessageBodyRanges(mentions: [:], styles: styles).collapsedStyles
        assertStylesEqual(expectedOutput, output)

        styles = [
            .init(.bold, range: NSRange(location: 0, length: 6)),
            .init(.italic, range: NSRange(location: 1, length: 6)),
            .init(.spoiler, range: NSRange(location: 2, length: 6)),
            .init(.strikethrough, range: NSRange(location: 3, length: 6)),
            .init(.monospace, range: NSRange(location: 4, length: 6))
        ]
        expectedOutput = [
            .init(.bold, mergedRange: NSRange(location: 0, length: 6), appliedRange: NSRange(location: 0, length: 1)),
            .init(
                .init([
                    .bold: NSRange(location: 0, length: 6),
                    .italic: NSRange(location: 1, length: 6)
                ]),
                range: NSRange(location: 1, length: 1)
            ),
            .init(
                .init([
                    .bold: NSRange(location: 0, length: 6),
                    .italic: NSRange(location: 1, length: 6),
                    .spoiler: NSRange(location: 2, length: 6)
                ]),
                range: NSRange(location: 2, length: 1)
            ),
            .init(
                .init([
                    .bold: NSRange(location: 0, length: 6),
                    .italic: NSRange(location: 1, length: 6),
                    .spoiler: NSRange(location: 2, length: 6),
                    .strikethrough: NSRange(location: 3, length: 6)
                ]),
                range: NSRange(location: 3, length: 1)
            ),
            .init(
                .init([
                    .bold: NSRange(location: 0, length: 6),
                    .italic: NSRange(location: 1, length: 6),
                    .spoiler: NSRange(location: 2, length: 6),
                    .strikethrough: NSRange(location: 3, length: 6),
                    .monospace: NSRange(location: 4, length: 6)
                ]),
                range: NSRange(location: 4, length: 2)
            ),
            .init(
                .init([
                    .italic: NSRange(location: 1, length: 6),
                    .spoiler: NSRange(location: 2, length: 6),
                    .strikethrough: NSRange(location: 3, length: 6),
                    .monospace: NSRange(location: 4, length: 6)
                ]),
                range: NSRange(location: 6, length: 1)
            ),
            .init(
                .init([
                    .spoiler: NSRange(location: 2, length: 6),
                    .strikethrough: NSRange(location: 3, length: 6),
                    .monospace: NSRange(location: 4, length: 6)
                ]),
                range: NSRange(location: 7, length: 1)
            ),
            .init(
                .init([
                    .strikethrough: NSRange(location: 3, length: 6),
                    .monospace: NSRange(location: 4, length: 6)
                ]),
                range: NSRange(location: 8, length: 1)
            ),
            .init(.monospace, mergedRange: NSRange(location: 4, length: 6), appliedRange: NSRange(location: 9, length: 1))
        ]
        output = MessageBodyRanges(mentions: [:], styles: styles).collapsedStyles
        assertStylesEqual(expectedOutput, output)
    }

    func testStyleCollapsing_overlappingMentions() {
        // The two bolds don't overlap, but they both overlap
        // with a mention, so they do overlap after extending through the whole mention
        let mentions: [NSRange: Aci] = [
            NSRange(location: 2, length: 5): Aci.randomForTesting()
        ]
        let styles: [NSRangedValue<SingleStyle>] = [
            .init(.bold, range: NSRange(location: 0, length: 3)),
            .init(.bold, range: NSRange(location: 5, length: 3)),
            .init(.italic, range: NSRange(location: 1, length: 2))
        ]
        let expectedOutput: [NSRangedValue<CollapsedStyle>] = [
            .init(.bold, mergedRange: NSRange(location: 0, length: 8), appliedRange: NSRange(location: 0, length: 1)),
            .init(
                .init([
                    .bold: NSRange(location: 0, length: 8),
                    .italic: NSRange(location: 1, length: 6)
                ]),
                range: NSRange(location: 1, length: 6)
            ),
            .init(.bold, mergedRange: NSRange(location: 0, length: 8), appliedRange: NSRange(location: 7, length: 1))
        ]
        let output = MessageBodyRanges(mentions: mentions, styles: styles).collapsedStyles
        assertStylesEqual(expectedOutput, output)
    }

    func testDeserializeV1() throws {
        let encodedDataBase64 = "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvEBALDB0lJictMTQWODs/QEFEVSRudWxs2A0ODxAREhMUFRYXGBkaGxxfEBBtZW50aW9ucy5yYW5nZS4wXW1lbnRpb25zQ291bnRWJGNsYXNzXxAPbWVudGlvbnMudXVpZC4yXxAQbWVudGlvbnMucmFuZ2UuMV8QEG1lbnRpb25zLnJhbmdlLjJfEA9tZW50aW9ucy51dWlkLjFfEA9tZW50aW9ucy51dWlkLjCAAhADgA+ADoAIgAuACoAG1B4fIA8hIiMkXxASTlMucmFuZ2V2YWwubGVuZ3RoXxAUTlMucmFuZ2V2YWwubG9jYXRpb25aTlMuc3BlY2lhbIADgAQQBIAFEAEQANIoKSorWiRjbGFzc25hbWVYJGNsYXNzZXNXTlNWYWx1ZaIqLFhOU09iamVjdNIuDy8wXE5TLnV1aWRieXRlc08QEDRv6bLICE9hkgPhkjjFju2AB9IoKTIzVk5TVVVJRKIyLNQeHyAPITYjJIADgAmABdIuDzkwTxAQ4Vl38Lg2TAKkc40D+J1IxoAH1B4fIA88PSMkgAyADYAFEAcQBdIuD0IwTxAQhC0Fz6D1SSiY4rfoa5AXlIAH0igpRUZfECJTaWduYWxTZXJ2aWNlS2l0Lk1lc3NhZ2VCb2R5UmFuZ2VzokcsXxAiU2lnbmFsU2VydmljZUtpdC5NZXNzYWdlQm9keVJhbmdlcwAIABEAGgAkACkAMgA3AEkATABRAFMAZgBsAH0AkACeAKUAtwDKAN0A7wEBAQMBBQEHAQkBCwENAQ8BEQEaAS8BRgFRAVMBVQFXAVkBWwFdAWIBbQF2AX4BgQGKAY8BnAGvAbEBtgG9AcAByQHLAc0BzwHUAecB6QHyAfQB9gH4AfoB/AIBAhQCFgIbAkACQwAAAAAAAAIBAAAAAAAAAEgAAAAAAAAAAAAAAAAAAAJo"
        let expectedResult = MessageBodyRanges(
            mentions: [
                NSRange(location: 0, length: 1): Aci.constantForTesting("346FE9B2-C808-4F61-9203-E19238C58EED"),
                NSRange(location: 3, length: 1): Aci.constantForTesting("E15977F0-B836-4C02-A473-8D03F89D48C6"),
                NSRange(location: 5, length: 7): Aci.constantForTesting("842D05CF-A0F5-4928-98E2-B7E86B901794")
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

        let mentions: [NSRange: Aci] = [
            NSRange(location: 0, length: 1): Aci.constantForTesting("AF406233-B344-4E40-99ED-AD080B8B1ACF"),
            NSRange(location: 3, length: 1): Aci.constantForTesting("017447E0-C5A4-456C-A4C1-1EC7F91AC070"),
            NSRange(location: 5, length: 7): Aci.constantForTesting("AE9EFF5A-706F-46BE-BEA1-A4E86256B8C7")
        ]
        let expectedResult = MessageBodyRanges(
            mentions: mentions,
            orderedMentions: mentions.lazy
                .sorted(by: { $0.key.location < $1.key.location })
                .map { return NSRangedValue($0.value, range: $0.key) },
            collapsedStyles: [
                .init(.bold, mergedRange: NSRange(location: 0, length: 1)),
                .init(.italic, mergedRange: NSRange(location: 2, length: 3), appliedRange: NSRange(location: 2, length: 1)),
                .init(
                    .init([
                        .italic: NSRange(location: 2, length: 3),
                        .monospace: NSRange(location: 3, length: 9),
                        .strikethrough: NSRange(location: 3, length: 1)
                    ]),
                    range: NSRange(location: 3, length: 1)
                ),
                .init(
                    .init([
                        .italic: NSRange(location: 2, length: 3),
                        .monospace: NSRange(location: 3, length: 9)
                    ]),
                    range: NSRange(location: 4, length: 1)
                ),
                .init(
                    .init([
                        .monospace: NSRange(location: 3, length: 9),
                        .spoiler: NSRange(location: 5, length: 13)
                    ]),
                    range: NSRange(location: 5, length: 7)
                ),
                .init(.spoiler, mergedRange: NSRange(location: 5, length: 13), appliedRange: NSRange(location: 12, length: 6))
            ]
        )

        let data = Data(base64Encoded: encodedDataBase64)!
        let decoded = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: MessageBodyRanges.self,
            from: data
        )
        XCTAssertEqual(expectedResult, decoded)
    }

    func testDeserializeV3() throws {
        let encodedDataBase64 = "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvECYLDEtSU1RaXmEtZWZpMG1wdHhBfICEiImNkTyVmZ2hpaaqMq6vs1UkbnVsbN8QHw0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKXxAbc3R5bGVzLnN0eWxlLm9yaWdpbmFscy4xNi4yXnN0eWxlcy5zdHlsZS4wXnN0eWxlcy5yYW5nZS41XnN0eWxlcy5yYW5nZS4yXW1lbnRpb25zQ291bnRfEBtzdHlsZXMuc3R5bGUub3JpZ2luYWxzLjE2LjNbc3R5bGVzQ291bnRfEBpzdHlsZXMuc3R5bGUub3JpZ2luYWxzLjQuNF8QEG1lbnRpb25zLnJhbmdlLjFec3R5bGVzLnN0eWxlLjJfEA9tZW50aW9ucy51dWlkLjBfEBpzdHlsZXMuc3R5bGUub3JpZ2luYWxzLjIuMl8QGnN0eWxlcy5zdHlsZS5vcmlnaW5hbHMuMS4wXxAac3R5bGVzLnN0eWxlLm9yaWdpbmFscy44LjJec3R5bGVzLnJhbmdlLjRfEBtzdHlsZXMuc3R5bGUub3JpZ2luYWxzLjE2LjRec3R5bGVzLnN0eWxlLjVWJGNsYXNzXnN0eWxlcy5yYW5nZS4xXxAPbWVudGlvbnMudXVpZC4xXnN0eWxlcy5zdHlsZS40XnN0eWxlcy5zdHlsZS4xXxAQbWVudGlvbnMucmFuZ2UuMl8QGnN0eWxlcy5zdHlsZS5vcmlnaW5hbHMuMi4xXnN0eWxlcy5yYW5nZS4zXxAQbWVudGlvbnMucmFuZ2UuMF8QD21lbnRpb25zLnV1aWQuMl8QGnN0eWxlcy5zdHlsZS5vcmlnaW5hbHMuNC41XnN0eWxlcy5yYW5nZS4wXnN0eWxlcy5zdHlsZS4zXxAac3R5bGVzLnN0eWxlLm9yaWdpbmFscy4yLjOAFRABgCGAFBADgBsQBoAegAgQGoAGgBiAEIAXgB2AIBAEgCWAEYALEBQQAoAMgBOAGYACgA6AJIAPEBKAHNRMTU4eT1A8UV8QEk5TLnJhbmdldmFsLmxlbmd0aF8QFE5TLnJhbmdldmFsLmxvY2F0aW9uWk5TLnNwZWNpYWyAA4AEgAUQBxAF0lVWV1haJGNsYXNzbmFtZVgkY2xhc3Nlc1dOU1ZhbHVloldZWE5TT2JqZWN00lseXF1cTlMudXVpZGJ5dGVzTxAQrp7/WnBvRr6+oaToYla4x4AH0lVWX2BWTlNVVUlEol9Z1ExNTh5iYzxRgAmACoAFEADSWx5nXU8QEK9AYjOzRE5Ame2tCAuLGs+AB9RMTU4eYms8UYAJgA2ABdJbHm5dTxAQAXRH4MWkRWykwR7H+RrAcIAH1ExNTh5iYzxRgAmACoAF1ExNTh5iYzxRgAmACoAF1ExNTh5iejxRgAmAEoAF1ExNTh5rejxRgA2AEoAF1ExNTh5iazxRgAmADYAF1ExNTh6FazxRgBaADYAFEAnUTE1OHmJrPFGACYANgAXUTE1OHmt6PFGADYASgAXUTE1OHmKTPFGACYAagAXUTE1OHoVrPFGAFoANgAXUTE1OHmt6PFGADYASgAXUTE1OHk9QPFGAA4AEgAXUTE1OHqJQPFGAH4AEgAUQDdRMTU4ehWs8UYAWgA2ABdRMTU4eq6w8UYAigCOABRAM1ExNTh6iUDxRgB+ABIAF0lVWtLVfECJTaWduYWxTZXJ2aWNlS2l0Lk1lc3NhZ2VCb2R5UmFuZ2VzorZZXxAiU2lnbmFsU2VydmljZUtpdC5NZXNzYWdlQm9keVJhbmdlcwAIABEAGgAkACkAMgA3AEkATABRAFMAfACCAMMA4QDwAP8BDgEcAToBRgFjAXYBhQGXAbQB0QHuAf0CGwIqAjECQAJSAmECcAKDAqACrwLCAtQC8QMAAw8DLAMuAzADMgM0AzYDOAM6AzwDPgNAA0IDRANGA0gDSgNMA04DUANSA1QDVgNYA1oDXANeA2ADYgNkA2YDaANqA3MDiAOfA6oDrAOuA7ADsgO0A7kDxAPNA9UD2APhA+YD8wQGBAgEDQQUBBcEIAQiBCQEJgQoBC0EQARCBEsETQRPBFEEVgRpBGsEdAR2BHgEegSDBIUEhwSJBJIElASWBJgEoQSjBKUEpwSwBLIEtAS2BL8EwQTDBMUExwTQBNIE1ATWBN8E4QTjBOUE7gTwBPIE9AT9BP8FAQUDBQwFDgUQBRIFGwUdBR8FIQUqBSwFLgUwBTIFOwU9BT8FQQVKBUwFTgVQBVIFWwVdBV8FYQVmBYsFjgAAAAAAAAIBAAAAAAAAALcAAAAAAAAAAAAAAAAAAAWz"

        let mentions: [NSRange: Aci] = [
            NSRange(location: 0, length: 1): Aci.constantForTesting("AF406233-B344-4E40-99ED-AD080B8B1ACF"),
            NSRange(location: 3, length: 1): Aci.constantForTesting("017447E0-C5A4-456C-A4C1-1EC7F91AC070"),
            NSRange(location: 5, length: 7): Aci.constantForTesting("AE9EFF5A-706F-46BE-BEA1-A4E86256B8C7")
        ]
        let expectedResult = MessageBodyRanges(
            mentions: mentions,
            orderedMentions: mentions.lazy
                .sorted(by: { $0.key.location < $1.key.location })
                .map { return NSRangedValue($0.value, range: $0.key) },
            collapsedStyles: [
                .init(.bold, mergedRange: NSRange(location: 0, length: 1)),
                .init(.italic, mergedRange: NSRange(location: 2, length: 3), appliedRange: NSRange(location: 2, length: 1)),
                .init(
                    .init([
                        .italic: NSRange(location: 2, length: 3),
                        .monospace: NSRange(location: 3, length: 9),
                        .strikethrough: NSRange(location: 3, length: 1)
                    ]),
                    range: NSRange(location: 3, length: 1)
                ),
                .init(
                    .init([
                        .italic: NSRange(location: 2, length: 3),
                        .monospace: NSRange(location: 3, length: 9)
                    ]),
                    range: NSRange(location: 4, length: 1)
                ),
                .init(
                    .init([
                        .monospace: NSRange(location: 3, length: 9),
                        .spoiler: NSRange(location: 5, length: 13)
                    ]),
                    range: NSRange(location: 5, length: 7)
                ),
                .init(.spoiler, mergedRange: NSRange(location: 5, length: 13), appliedRange: NSRange(location: 12, length: 6))
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
        _ lhs: [NSRangedValue<CollapsedStyle>],
        _ rhs: [NSRangedValue<CollapsedStyle>],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        for i in 0..<lhs.count {
            XCTAssertEqual(lhs[i].value, rhs[i].value)
            XCTAssertEqual(lhs[i].range, rhs[i].range)
        }
    }
}

extension MessageBodyRanges.CollapsedStyle {

    init(_ singleStyle: MessageBodyRanges.SingleStyle, mergedRange: NSRange) {
        self.init(
            style: .init(rawValue: singleStyle.rawValue),
            originals: [
                singleStyle: MessageBodyRanges.MergedSingleStyle(style: singleStyle, mergedRange: mergedRange)
            ]
        )
    }

    init(_ mergedRanges: [MessageBodyRanges.SingleStyle: NSRange]) {
        var finalStyle = MessageBodyRanges.Style()
        var originals = [MessageBodyRanges.SingleStyle: MessageBodyRanges.MergedSingleStyle]()
        for (style, range) in mergedRanges {
            finalStyle.insert(style: style)
            originals[style] = .init(style: style, mergedRange: range)
        }
        self.init(style: finalStyle, originals: originals)
    }
}

extension NSRangedValue where T == MessageBodyRanges.CollapsedStyle {

    init(_ singleStyle: MessageBodyRanges.SingleStyle, mergedRange: NSRange, appliedRange: NSRange? = nil) {
        self.init(.init(singleStyle, mergedRange: mergedRange), range: appliedRange ?? mergedRange)
    }
}
