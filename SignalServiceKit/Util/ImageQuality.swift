//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The user-selected quality for images. Users are offered a choice between
/// "standard" and "high" quality. The former may correspond to level "one"
/// or "two" (depending on a remote config); the latter always corresponds
/// to level "three". Most callers should use ImageQuality; typically only
/// the compression logic needs access to ImageQualityLevel.
public enum ImageQuality {
    /// Indirectly translates to ImageQualityLevel.one or ImageQualityLevel.two.
    case standard

    /// Always translates to ImageQualityLevel.three.
    case high

    private static let keyValueStore = KeyValueStore(collection: "ImageQualityLevel")
    private static let userSelectedHighQualityKey = "defaultQuality"
    private static let userSelectedHighQualityValue = 3 as UInt

    public static func fetchValue(tx: DBReadTransaction) -> Self {
        let highQualityValue = keyValueStore.getUInt(userSelectedHighQualityKey, transaction: tx)
        return highQualityValue == userSelectedHighQualityValue ? .high : .standard
    }

    public static func setValue(_ imageQuality: Self, tx: DBWriteTransaction) {
        switch imageQuality {
        case .high:
            keyValueStore.setUInt(userSelectedHighQualityValue, key: userSelectedHighQualityKey, transaction: tx)
        case .standard:
            keyValueStore.removeValue(forKey: userSelectedHighQualityKey, transaction: tx)
        }
    }

    public var localizedString: String {
        switch self {
        case .standard:
            return OWSLocalizedString("SENT_MEDIA_QUALITY_STANDARD", comment: "String describing standard quality sent media")
        case .high:
            return OWSLocalizedString("SENT_MEDIA_QUALITY_HIGH", comment: "String describing high quality sent media")
        }
    }
}

public enum ImageQualityLevel: UInt, Comparable {
    case one = 1
    case two = 2
    case three = 3

    // We calculate the "standard" media quality remotely based on country
    // code. For some regions, we use a lower "standard" quality than others.
    // High quality is always level three. If not remotely specified, standard
    // uses quality level two.
    public static func standardQualityLevel(
        remoteConfig: RemoteConfig = .current,
        callingCode: Int? = { () -> Int? in
            let phoneNumberUtil = SSKEnvironment.shared.phoneNumberUtilRef
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            let localIdentifiers = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction
            return localIdentifiers.flatMap({ phoneNumberUtil.parseE164($0.phoneNumber) })?.getCallingCode()
        }(),
    ) -> ImageQualityLevel {
        return remoteConfig.standardMediaQualityLevel(callingCode: callingCode) ?? .two
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

    public static func maximumForCurrentAppContext(_ currentAppContext: any AppContext = CurrentAppContext()) -> Self {
        if currentAppContext.isMainApp {
            return .three
        } else {
            // Outside of the main app (like in the share extension)
            // we have very tight memory restrictions, and cannot
            // allow sending high quality media.
            return .one
        }
    }

    public static func resolvedValue(
        imageQuality: ImageQuality,
        standardQualityLevel: @autoclosure () -> Self = .standardQualityLevel(),
        maximumForCurrentAppContext: Self = .maximumForCurrentAppContext(),
    ) -> ImageQualityLevel {
        let targetQualityLevel: Self
        switch imageQuality {
        case .high:
            targetQualityLevel = .three
        case .standard:
            targetQualityLevel = standardQualityLevel()
        }
        // If the max quality we allow is less than the stored preference,
        // we have to restrict ourselves to the max allowed.
        return min(targetQualityLevel, maximumForCurrentAppContext)
    }

    public static func < (lhs: ImageQualityLevel, rhs: ImageQualityLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

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
