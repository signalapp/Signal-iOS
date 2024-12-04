//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

class MessageStickerSerializationTest: XCTestCase {

    // MARK: - Hardcoded constant data

    enum HardcodedDataTestMode {
        case runTest
        case printStrings

        /// Toggle this to use ``testHardcodedArchiverDataDecodes()`` to print
        /// hardcoded strings, for example when adding new constants.
        static let mode: Self = .runTest
    }

    func testHardcodedArchiverDataDecodes() {
        switch HardcodedDataTestMode.mode {
        case .printStrings:
            for (idx, (constant, _)) in MessageSticker.constants.enumerated() {
                let serializedArchiver = try! NSKeyedArchiver.archivedData(
                    withRootObject: constant,
                    requiringSecureCoding: false
                )
                print("\(Self.self) constant \(idx) keyed archiver: \(serializedArchiver.base64EncodedString())")
            }

        case .runTest:
            for (idx, (constant, archiverData)) in MessageSticker.constants.enumerated() {
                do {
                    let deserialized = try NSKeyedUnarchiver.unarchivedObject(
                        ofClass: MessageSticker.self,
                        from: archiverData,
                        requiringSecureCoding: false
                    )!
                    try deserialized.validate(against: constant)
                } catch ValidatableModelError.failedToValidate {
                    XCTFail("Failed to validate NSKeyedArchiver-decoded model for constant \(idx)")
                } catch {
                    XCTFail("Unexpected error for constant \(idx)")
                }
            }
        }
    }
}

extension MessageSticker {

    static let packId1 = Randomness.generateRandomBytes(16)
    static let packKey1 = Randomness.generateRandomBytes(StickerManager.packKeyLength)

    static let packId2 = Randomness.generateRandomBytes(16)
    static let packKey2 = Randomness.generateRandomBytes(StickerManager.packKeyLength)

    static let constants: [(MessageSticker, base64NSArchiverData: Data)] = [
        // A simple one
        (
            MessageSticker(
                info: StickerInfo(
                    packId: Data(base64Encoded: "ByAo5vOcOnEljMtdQZKbjw==")!,
                    packKey: Data(base64Encoded: "LA/Rzmg5N+24+IUifBszxD2f+7jRGIPRX9PnrhubNl4=")!,
                    stickerId: 1
                ),
                emoji: nil
            ),
            Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGqCwwVFh8gISIpKlUkbnVsbNQNDg8QERITFFxhdHRhY2htZW50SWRUaW5mb18QD01UTE1vZGVsVmVyc2lvblYkY2xhc3OACIADgAKACRAA1RAXGBkPGhscHRNZc3RpY2tlcklkV3BhY2tLZXlWcGFja0lkgAeABoAEgAWAAk8QICwP0c5oOTftuPiFInwbM8Q9n/u40RiD0V/T564bmzZeTxAQByAo5vOcOnEljMtdQZKbjxAB0iMkJSZaJGNsYXNzbmFtZVgkY2xhc3Nlc1tTdGlja2VySW5mb6MlJyhYTVRMTW9kZWxYTlNPYmplY3RUMTIzNNIjJCssXxAfU2lnbmFsU2VydmljZUtpdC5NZXNzYWdlU3RpY2tlcqMtJyhfEB9TaWduYWxTZXJ2aWNlS2l0Lk1lc3NhZ2VTdGlja2VyAAgAEQAaACQAKQAyADcASQBMAFEAUwBeAGQAbQB6AH8AkQCYAJoAnACeAKAAogCtALcAvwDGAMgAygDMAM4A0ADzAQYBCAENARgBIQEtATEBOgFDAUgBTQFvAXMAAAAAAAACAQAAAAAAAAAuAAAAAAAAAAAAAAAAAAABlQ==")!
        ),
        // Empty attachment id
        (
            MessageSticker(
                info: StickerInfo(
                    packId: Data(base64Encoded: "XWpgH3HGIDpohoaH7oDBng==")!,
                    packKey: Data(base64Encoded: "xl88Kghch7SIC/Qa85m65XI5ehzN6djU4E3nc/fGHSU=")!,
                    stickerId: 3
                ),
                emoji: "a"
            ),
            Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGrCwwXGBkiIyQlLC1VJG51bGzVDQ4PEBESExQVFlRpbmZvVWVtb2ppXxAPTVRMTW9kZWxWZXJzaW9uXGF0dGFjaG1lbnRJZFYkY2xhc3OABIADgAKACYAKEABRYdURGhscDx0eHyAUWXN0aWNrZXJJZFdwYWNrS2V5VnBhY2tJZIAIgAeABYAGgAJPECDGXzwqCFyHtIgL9Brzmbrlcjl6HM3p2NTgTedz98YdJU8QEF1qYB9xxiA6aIaGh+6AwZ4QA9ImJygpWiRjbGFzc25hbWVYJGNsYXNzZXNbU3RpY2tlckluZm+jKCorWE1UTE1vZGVsWE5TT2JqZWN0UNImJy4vXxAfU2lnbmFsU2VydmljZUtpdC5NZXNzYWdlU3RpY2tlcqMwKitfEB9TaWduYWxTZXJ2aWNlS2l0Lk1lc3NhZ2VTdGlja2VyAAgAEQAaACQAKQAyADcASQBMAFEAUwBfAGUAcAB1AHsAjQCaAKEAowClAKcAqQCrAK0ArwC6AMQAzADTANUA1wDZANsA3QEAARMBFQEaASUBLgE6AT4BRwFQAVEBVgF4AXwAAAAAAAACAQAAAAAAAAAxAAAAAAAAAAAAAAAAAAABng==")!
        ),
        // Nil attachment id
        (
            MessageSticker(
                info: StickerInfo(
                    packId: Data(base64Encoded: "XWpgH3HGIDpohoaH7oDBng==")!,
                    packKey: Data(base64Encoded: "xl88Kghch7SIC/Qa85m65XI5ehzN6djU4E3nc/fGHSU=")!,
                    stickerId: 3
                ),
                emoji: "b"
            ),
            Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGqCwwVFhcgISIjKlUkbnVsbNQNDg8QERITFFRpbmZvVWVtb2ppXxAPTVRMTW9kZWxWZXJzaW9uViRjbGFzc4AEgAOAAoAJEABRYtUQGBkaDxscHR4TWXN0aWNrZXJJZFdwYWNrS2V5VnBhY2tJZIAIgAeABYAGgAJPECDGXzwqCFyHtIgL9Brzmbrlcjl6HM3p2NTgTedz98YdJU8QEF1qYB9xxiA6aIaGh+6AwZ4QA9IkJSYnWiRjbGFzc25hbWVYJGNsYXNzZXNbU3RpY2tlckluZm+jJigpWE1UTE1vZGVsWE5TT2JqZWN00iQlKyxfEB9TaWduYWxTZXJ2aWNlS2l0Lk1lc3NhZ2VTdGlja2Vyoy0oKV8QH1NpZ25hbFNlcnZpY2VLaXQuTWVzc2FnZVN0aWNrZXIACAARABoAJAApADIANwBJAEwAUQBTAF4AZABtAHIAeACKAJEAkwCVAJcAmQCbAJ0AqACyALoAwQDDAMUAxwDJAMsA7gEBAQMBCAETARwBKAEsATUBPgFDAWUBaQAAAAAAAAIBAAAAAAAAAC4AAAAAAAAAAAAAAAAAAAGL")!
        ),
    ]

    func validate(against: MessageSticker) throws {
        guard
            info == against.info,
            emoji == against.emoji
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}
