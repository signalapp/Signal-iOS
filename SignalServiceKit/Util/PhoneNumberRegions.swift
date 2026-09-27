//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct PhoneNumberRegions {
    private let regions: Set<String.SubSequence>
    private let regionCounts: Set<Int>

    public init(_ regions: some Sequence<String>) {
        self.regions = Set(regions.map { $0[...] })
        self.regionCounts = Set(self.regions.lazy.map(\.count))
    }

    static func parseRemoteConfigRegions(_ remoteConfigValue: String) -> some Sequence<String> {
        return remoteConfigValue
            .components(separatedBy: ",")
            .lazy
            .compactMap { $0.asciiDigitsOnly.nilIfEmpty }
    }

    public var isEmpty: Bool { regions.isEmpty }

    public func contains(e164: String) -> Bool {
        guard let e164 = E164(e164) else {
            owsFailDebug("Invalid e164: \(e164)")
            return false
        }
        let e164WithoutPrefix = e164.withoutPrefix()
        for regionCount in self.regionCounts {
            if self.regions.contains(e164WithoutPrefix.prefix(regionCount)) {
                return true
            }
        }
        return false
    }
}
