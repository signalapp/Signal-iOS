//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Bundle {

    private enum InfoPlistKey: String {
        case bundleIdPrefix = "OWSBundleIDPrefix"
        case merchantId = "OWSMerchantID"
    }

    private func infoPlistString(for key: InfoPlistKey) -> String? {
        object(forInfoDictionaryKey: key.rawValue) as? String
    }

    /// Returns the value of the OWSBundleIDPrefix from current executable's Info.plist
    /// Note: This does not parse the executable's bundleID. This only returns the value of OWSBundleIDPrefix
    /// (which the bundleID should be derived from)
    @objc
    public var bundleIdPrefix: String {
        if let prefix = infoPlistString(for: Self.InfoPlistKey.bundleIdPrefix) {
            return prefix
        } else {
            owsFailDebug("Missing Info.plist entry for OWSBundleIDPrefix")
            return "org.whispersystems"
        }
    }

    /// Returns the value of the OWSMerchantID from current executable's Info.plist
    @objc
    public var merchantId: String {
        if let prefix = infoPlistString(for: Self.InfoPlistKey.merchantId) {
            return prefix
        } else {
            owsFailDebug("Missing Info.plist entry for OWSMerchantID")
            return "org.signalfoundation"
        }
    }
}
