//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class PhoneNumberRegions: Equatable, ExpressibleByArrayLiteral, CustomDebugStringConvertible {
    private let regions: Set<String>
    private var previousCachedResult: (e164: String, result: Bool)?

    public required init(arrayLiteral: String...) {
        self.regions = Set(arrayLiteral)
    }

    init(fromRemoteConfig remoteConfigValue: String) {
        let regions = remoteConfigValue
            .components(separatedBy: ",")
            .lazy
            .compactMap { $0.asciiDigitsOnly.nilIfEmpty }
        self.regions = Set(regions)
    }

    public var isEmpty: Bool { regions.isEmpty }

    public func contains(e164: String) -> Bool {
        // We usually expect this to be called with the same E164, so we cache
        // the previous result. We could probably optimize this whole class
        // further, but this simple solution should be good enough.
        if let previousCachedResult, previousCachedResult.e164 == e164 {
            return previousCachedResult.result
        }

        let e164Prefix = "+"
        guard e164.hasPrefix(e164Prefix) else {
            owsFailDebug("Invalid e164: \(e164).")
            return false
        }
        let e164WithoutPrefix = e164.substring(from: e164Prefix.count)
        if e164WithoutPrefix.isEmpty {
            owsFailDebug("Invalid e164: \(e164).")
            return false
        }

        let result = regions.contains { region in
            e164WithoutPrefix.hasPrefix(region)
        }
        previousCachedResult = (e164, result)
        return result
    }

    public static func == (lhs: PhoneNumberRegions, rhs: PhoneNumberRegions) -> Bool {
        lhs.regions == rhs.regions
    }

    public var debugDescription: String { regions.debugDescription }
}
