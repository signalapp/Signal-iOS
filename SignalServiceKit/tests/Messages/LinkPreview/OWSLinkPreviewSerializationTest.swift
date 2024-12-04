//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

class OWSLinkPreviewSerializationTest: XCTestCase {

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
            for (idx, (constant, _, _)) in OWSLinkPreview.constants.enumerated() {
                let serializedArchiver = try! NSKeyedArchiver.archivedData(
                    withRootObject: constant,
                    requiringSecureCoding: false
                )
                print("\(Self.self) constant \(idx) keyed archiver: \(serializedArchiver.base64EncodedString())")

                let serializedJson = try! JSONEncoder().encode(constant)
                print("\(Self.self) constant \(idx) codable json: \(serializedJson.base64EncodedString())")
            }

        case .runTest:
            for (idx, (constant, archiverData, jsonData)) in OWSLinkPreview.constants.enumerated() {
                do {
                    let deserialized = try NSKeyedUnarchiver.unarchivedObject(
                        ofClass: OWSLinkPreview.self,
                        from: archiverData,
                        requiringSecureCoding: false
                    )!
                    try deserialized.validate(against: constant)
                } catch ValidatableModelError.failedToValidate {
                    XCTFail("Failed to validate NSKeyedArchiver-decoded model for constant \(idx)")
                } catch {
                    XCTFail("Unexpected error for constant \(idx)")
                }

                do {
                    let deserialized = try JSONDecoder().decode(OWSLinkPreview.self, from: jsonData)
                    try deserialized.validate(against: constant)
                } catch ValidatableModelError.failedToValidate {
                    XCTFail("Failed to validate JSON-decoded model for constant \(idx)")
                } catch {
                    XCTFail("Unexpected error for constant \(idx)")
                }
            }
        }
    }
}

extension OWSLinkPreview {
    static let constants: [(OWSLinkPreview, base64NSArchiverData: Data, jsonData: Data)] = [
        (
            OWSLinkPreview(
                urlString: "https://wikipedia.org",
                title: "Title"
            ),
            Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGnCwwXGBkaG1UkbnVsbNUNDg8QERITFBUWViRjbGFzc1V0aXRsZV8QD01UTE1vZGVsVmVyc2lvbl8QHnVzZXNWMkF0dGFjaG1lbnRSZWZlcmVuY2VWYWx1ZVl1cmxTdHJpbmeABoAEgAKABYADEABfEBVodHRwczovL3dpa2lwZWRpYS5vcmdVVGl0bGUJ0hwdHh9aJGNsYXNzbmFtZVgkY2xhc3Nlc18QH1NpZ25hbFNlcnZpY2VLaXQuT1dTTGlua1ByZXZpZXejICEiXxAfU2lnbmFsU2VydmljZUtpdC5PV1NMaW5rUHJldmlld1hNVExNb2RlbFhOU09iamVjdAAIABEAGgAkACkAMgA3AEkATABRAFMAWwBhAGwAcwB5AIsArAC2ALgAugC8AL4AwADCANoA4ADhAOYA8QD6ARwBIAFCAUsAAAAAAAACAQAAAAAAAAAjAAAAAAAAAAAAAAAAAAABVA==")!,
            Data(#"{"usesV2AttachmentReferenceValue":1,"urlString":"https:\/\/wikipedia.org","title":"Title"}"#.utf8)
        ),
        (
            OWSLinkPreview(
                urlString: "https://somewebsite.org",
                title: "Hello"
            ),
            Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGoCwwZGhscHR5VJG51bGzWDQ4PEBESExQVFhcYXxARaW1hZ2VBdHRhY2htZW50SWRWJGNsYXNzVXRpdGxlXxAPTVRMTW9kZWxWZXJzaW9uXxAedXNlc1YyQXR0YWNobWVudFJlZmVyZW5jZVZhbHVlWXVybFN0cmluZ4AEgAeABYACgAaAAxAAXxAXaHR0cHM6Ly9zb21ld2Vic2l0ZS5vcmdUYWJjZFVIZWxsbwjSHyAhIlokY2xhc3NuYW1lWCRjbGFzc2VzXxAfU2lnbmFsU2VydmljZUtpdC5PV1NMaW5rUHJldmlld6MjJCVfEB9TaWduYWxTZXJ2aWNlS2l0Lk9XU0xpbmtQcmV2aWV3WE1UTE1vZGVsWE5TT2JqZWN0AAgAEQAaACQAKQAyADcASQBMAFEAUwBcAGIAbwCDAIoAkACiAMMAzQDPANEA0wDVANcA2QDbAPUA+gEAAQEBBgERARoBPAFAAWIBawAAAAAAAAIBAAAAAAAAACYAAAAAAAAAAAAAAAAAAAF0")!,
            Data(#"{"title":"Hello","usesV2AttachmentReferenceValue":0,"imageAttachmentId":"abcd","urlString":"https:\/\/somewebsite.org"}"#.utf8)
        ),
        (
            OWSLinkPreview(
                urlString: "https://signal.org",
                title: "Some Title"
            ),
            Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGnCwwXGBkaG1UkbnVsbNUNDg8QERITFBUWXxARaW1hZ2VBdHRhY2htZW50SWRWJGNsYXNzVXRpdGxlXxAPTVRMTW9kZWxWZXJzaW9uWXVybFN0cmluZ4AEgAaABYACgAMQAF8QEmh0dHBzOi8vc2lnbmFsLm9yZ1QxMjM0WlNvbWUgVGl0bGXSHB0eH1okY2xhc3NuYW1lWCRjbGFzc2VzXxAfU2lnbmFsU2VydmljZUtpdC5PV1NMaW5rUHJldmlld6MgISJfEB9TaWduYWxTZXJ2aWNlS2l0Lk9XU0xpbmtQcmV2aWV3WE1UTE1vZGVsWE5TT2JqZWN0AAgAEQAaACQAKQAyADcASQBMAFEAUwBbAGEAbACAAIcAjQCfAKkAqwCtAK8AsQCzALUAygDPANoA3wDqAPMBFQEZATsBRAAAAAAAAAIBAAAAAAAAACMAAAAAAAAAAAAAAAAAAAFN")!,
            Data(#"{"imageAttachmentId":"1234","urlString":"https:\/\/signal.org","title":"Some Title"}"#.utf8)
        ),
        (
            OWSLinkPreview(
                urlString: "https://signal.org",
                title: "Some Title"
            ),
            Data(base64Encoded: "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGmCwwVFhcYVSRudWxs1A0ODxAREhMUViRjbGFzc1V0aXRsZV8QD01UTE1vZGVsVmVyc2lvbll1cmxTdHJpbmeABYAEgAKAAxAAXxASaHR0cHM6Ly9zaWduYWwub3JnWlNvbWUgVGl0bGXSGRobHFokY2xhc3NuYW1lWCRjbGFzc2VzXxAfU2lnbmFsU2VydmljZUtpdC5PV1NMaW5rUHJldmlld6MdHh9fEB9TaWduYWxTZXJ2aWNlS2l0Lk9XU0xpbmtQcmV2aWV3WE1UTE1vZGVsWE5TT2JqZWN0AAgAEQAaACQAKQAyADcASQBMAFEAUwBaAGAAaQBwAHYAiACSAJQAlgCYAJoAnACxALwAwQDMANUA9wD7AR0BJgAAAAAAAAIBAAAAAAAAACAAAAAAAAAAAAAAAAAAAAEv")!,
            Data(#"{"urlString":"https:\/\/signal.org","title":"Some Title"}"#.utf8)
        )
    ]

    func validate(against: OWSLinkPreview) throws {
        guard
            urlString == against.urlString,
            title == against.title,
            previewDescription == against.previewDescription,
            date == against.date
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}
