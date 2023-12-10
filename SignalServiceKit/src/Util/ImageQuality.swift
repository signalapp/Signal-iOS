//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public enum ImageQualityLevel: UInt, Comparable {
    case one = 1
    case two = 2
    case three = 3

    public static let high: ImageQualityLevel = .three

    // We calculate the "standard" media quality remotely
    // based on country code. For some regions, we use
    // a lower "standard" quality than others. High quality
    // is always level three. If not remotely specified,
    // standard uses quality level two.
    public static func remoteDefault(localPhoneNumber: String?) -> ImageQualityLevel {
        return RemoteConfig.standardMediaQualityLevel(localPhoneNumber: localPhoneNumber) ?? .two
    }

    public var startingTier: ImageQualityTier {
        switch self {
        case .one: return .four
        case .two: return .five
        case .three: return .seven
        }
    }

    public var maxFileSize: UInt {
        switch self {
        case .one: // 1MiB
            return 1024 * 1024
        case .two: // 1.5MiB
            return UInt(1.5 * 1024 * 1024)
        case .three: // 3.0MiB
            return 3 * 1024 * 1024
        }
    }

    public var maxOriginalFileSize: UInt {
        switch self {
        case .one: // 200KiB
            return 200 * 1024
        case .two: // 300KiB
            return 300 * 1024
        case .three: // 400KiB
            return 400 * 1024
        }
    }

    public static var maximumForCurrentAppContext: ImageQualityLevel {
        if CurrentAppContext().isMainApp {
            return .three
        } else {
            // Outside of the main app (like in the share extension)
            // we have very tight memory restrictions, and cannot
            // allow sending high quality media.
            return .one
        }
    }

    private static let keyValueStore = SDSKeyValueStore(collection: "ImageQualityLevel")
    private static var userSelectedHighQualityKey: String { "defaultQuality" }

    public static func resolvedQuality(tx: SDSAnyReadTransaction) -> ImageQualityLevel {
        // If the max quality we allow is less than the stored preference,
        // we have to restrict ourselves to the max allowed.
        return min(_resolvedQuality(tx: tx), maximumForCurrentAppContext)
    }

    private static func _resolvedQuality(tx: SDSAnyReadTransaction) -> ImageQualityLevel {
        let isHighQuality: Bool = {
            // All that matters is "did the user choose high quality explicity?". If
            // they didn't, we always fall back to the current server-provided value
            // for standard quality. In the past, we stored low/medium values
            // explicitly, but this was wrong.
            guard let rawValue = keyValueStore.getUInt(userSelectedHighQualityKey, transaction: tx) else {
                return false
            }
            return ImageQualityLevel(rawValue: rawValue) == .high
        }()
        if isHighQuality {
            return .high
        }
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let localPhoneNumber = tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.phoneNumber
        return remoteDefault(localPhoneNumber: localPhoneNumber)
    }

    public static func setUserSelectedHighQuality(_ isHighQuality: Bool, tx: SDSAnyWriteTransaction) {
        if isHighQuality {
            keyValueStore.setUInt(ImageQualityLevel.three.rawValue, key: userSelectedHighQualityKey, transaction: tx)
        } else {
            keyValueStore.removeValue(forKey: userSelectedHighQualityKey, transaction: tx)
        }
    }

    public var localizedString: String {
        switch self {
        case .one, .two:
            return OWSLocalizedString("SENT_MEDIA_QUALITY_STANDARD", comment: "String describing standard quality sent media")
        case .three:
            return OWSLocalizedString("SENT_MEDIA_QUALITY_HIGH", comment: "String describing high quality sent media")
        }
    }

    public static func < (lhs: ImageQualityLevel, rhs: ImageQualityLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

@objc
public enum ImageQualityTier: UInt {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case seven = 7

    public var maxEdgeSize: CGFloat {
        switch self {
        case .one: return 512
        case .two: return 768
        case .three: return 1024
        case .four: return 1600
        case .five: return 2048
        case .six: return 3072
        case .seven: return 4096
        }
    }

    public var reduced: ImageQualityTier? { .init(rawValue: rawValue - 1) }
    public var increased: ImageQualityTier? { .init(rawValue: rawValue + 1) }
}
