//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class OWSAttachmentInfoSerializationTest: XCTestCase {

    // MARK: - Hardcoded constant data

    enum HardcodedDataTestMode {
        case runTest
        case printStrings

        /// Toggle this to use ``testHardcodedJsonDataDecodes()`` to print
        /// hardcoded strings, for example when adding new constants.
        static let mode: Self = .runTest
    }

    func testHardcodedArchiverDataDecodes() {
        switch HardcodedDataTestMode.mode {
        case .printStrings:
            for (idx, (constant, _)) in OWSAttachmentInfo.constants.enumerated() {
                let serializedArchiver = try! NSKeyedArchiver.archivedData(
                    withRootObject: constant,
                    requiringSecureCoding: true,
                )
                print("\(Self.self) constant \(idx) keyed archiver: \(serializedArchiver.base64EncodedString())")
            }

        case .runTest:
            for (idx, (constant, archiverData)) in OWSAttachmentInfo.constants.enumerated() {
                do {
                    let deserialized = try NSKeyedUnarchiver.unarchivedObject(
                        ofClass: OWSAttachmentInfo.self,
                        from: archiverData,
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

extension OWSAttachmentInfo {
    static let constants: [(OWSAttachmentInfo, base64NSArchiverData: Data)] = [
        (
            OWSAttachmentInfo(
                originalAttachmentMimeType: "jpeg",
                originalAttachmentSourceFilename: "somefile.jpg",
                originalAttachmentRenderingFlag: nil,
            ),
            Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGpCwwbHB0eHyAhVSRudWxs1w0ODxAREhMUFRYXGBkaViRjbGFzc11zY2hlbWFWZXJzaW9uXxAPcmF3QXR0YWNobWVudElkXnNvdXJjZUZpbGVuYW1lXxAPTVRMTW9kZWxWZXJzaW9uW2NvbnRlbnRUeXBlXmF0dGFjaG1lbnRUeXBlgAiABYAEgAOAAoAGgAcQAFxzb21lZmlsZS5qcGdUMTIzNBABVGpwZWcQAtIiIyQlWiRjbGFzc25hbWVYJGNsYXNzZXNfEBFPV1NBdHRhY2htZW50SW5mb6MmJyhfEBFPV1NBdHRhY2htZW50SW5mb1hNVExNb2RlbFhOU09iamVjdAAIABEAGgAkACkAMgA3AEkATABRAFMAXQBjAHIAeQCHAJkAqAC6AMYA1QDXANkA2wDdAN8A4QDjAOUA8gD3APkA/gEAAQUBEAEZAS0BMQFFAU4AAAAAAAACAQAAAAAAAAApAAAAAAAAAAAAAAAAAAABVw==")!,
        ),
        (
            OWSAttachmentInfo(
                originalAttachmentMimeType: nil,
                originalAttachmentSourceFilename: nil,
                originalAttachmentRenderingFlag: nil,
            ),
            Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGmCwwXGBkaVSRudWxs1Q0ODxAREhMUEhZdc2NoZW1hVmVyc2lvbl8QD3Jhd0F0dGFjaG1lbnRJZF8QD01UTE1vZGVsVmVyc2lvbl5hdHRhY2htZW50VHlwZVYkY2xhc3OABIADgAKABIAFEABUMTIzNBAB0hscHR5aJGNsYXNzbmFtZVgkY2xhc3Nlc18QEU9XU0F0dGFjaG1lbnRJbmZvox8gIV8QEU9XU0F0dGFjaG1lbnRJbmZvWE1UTE1vZGVsWE5TT2JqZWN0AAgAEQAaACQAKQAyADcASQBMAFEAUwBaAGAAawB5AIsAnQCsALMAtQC3ALkAuwC9AL8AxADGAMsA1gDfAPMA9wELARQAAAAAAAACAQAAAAAAAAAiAAAAAAAAAAAAAAAAAAABHQ==")!,
        ),
        (
            OWSAttachmentInfo(
                originalAttachmentMimeType: "mp4",
                originalAttachmentSourceFilename: "file.mp4",
                originalAttachmentRenderingFlag: nil,
            ),
            Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGoCwwZGhscHR5VJG51bGzWDQ4PEBESExQVFhcYXnNvdXJjZUZpbGVuYW1lViRjbGFzc11zY2hlbWFWZXJzaW9uXxAPTVRMTW9kZWxWZXJzaW9uW2NvbnRlbnRUeXBlXmF0dGFjaG1lbnRUeXBlgAOAB4AEgAKABYAGEABYZmlsZS5tcDQQAVNtcDQQBdIfICEiWiRjbGFzc25hbWVYJGNsYXNzZXNfEBFPV1NBdHRhY2htZW50SW5mb6MjJCVfEBFPV1NBdHRhY2htZW50SW5mb1hNVExNb2RlbFhOU09iamVjdAAIABEAGgAkACkAMgA3AEkATABRAFMAXABiAG8AfgCFAJMApQCxAMAAwgDEAMYAyADKAMwAzgDXANkA3QDfAOQA7wD4AQwBEAEkAS0AAAAAAAACAQAAAAAAAAAmAAAAAAAAAAAAAAAAAAABNg==")!,
        ),
        (
            OWSAttachmentInfo(
                originalAttachmentMimeType: nil,
                originalAttachmentSourceFilename: nil,
                originalAttachmentRenderingFlag: nil,
            ),
            Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGmCwwVFhcYVSRudWxs1A0ODxAREhMUXXNjaGVtYVZlcnNpb25fEA9NVExNb2RlbFZlcnNpb25eYXR0YWNobWVudFR5cGVWJGNsYXNzgAOAAoAEgAUQABABEAXSGRobHFokY2xhc3NuYW1lWCRjbGFzc2VzXxART1dTQXR0YWNobWVudEluZm+jHR4fXxART1dTQXR0YWNobWVudEluZm9YTVRMTW9kZWxYTlNPYmplY3QACAARABoAJAApADIANwBJAEwAUQBTAFoAYABpAHcAiQCYAJ8AoQCjAKUApwCpAKsArQCyAL0AxgDaAN4A8gD7AAAAAAAAAgEAAAAAAAAAIAAAAAAAAAAAAAAAAAAAAQQ=")!,
        ),
        (
            OWSAttachmentInfo(
                originalAttachmentMimeType: "png",
                originalAttachmentSourceFilename: "image.png",
                originalAttachmentRenderingFlag: nil,
            ),
            Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGnCwwZGhscHVUkbnVsbNYNDg8QERITFBUWFxZec291cmNlRmlsZW5hbWVWJGNsYXNzXXNjaGVtYVZlcnNpb25fEA9NVExNb2RlbFZlcnNpb25bY29udGVudFR5cGVeYXR0YWNobWVudFR5cGWAA4AGgASAAoAFgAIQAFlpbWFnZS5wbmcQAVNwbmfSHh8gIVokY2xhc3NuYW1lWCRjbGFzc2VzXxART1dTQXR0YWNobWVudEluZm+jIiMkXxART1dTQXR0YWNobWVudEluZm9YTVRMTW9kZWxYTlNPYmplY3QACAARABoAJAApADIANwBJAEwAUQBTAFsAYQBuAH0AhACSAKQAsAC/AMEAwwDFAMcAyQDLAM0A1wDZAN0A4gDtAPYBCgEOASIBKwAAAAAAAAIBAAAAAAAAACUAAAAAAAAAAAAAAAAAAAE0")!,
        ),
    ]

    func validate(against: OWSAttachmentInfo) throws {
        guard
            originalAttachmentMimeType == against.originalAttachmentMimeType,
            originalAttachmentSourceFilename == against.originalAttachmentSourceFilename
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}
