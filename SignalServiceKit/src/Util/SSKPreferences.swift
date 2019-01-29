//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SSKPreferences: NSObject {
    // Never instantiate this class.
    private override init() {}

    private static let collection = "SSKPreferences"
    private static let areLinkPreviewsEnabledKey = "areLinkPreviewsEnabled"

    @objc
    public class func areLinkPreviewsEnabled() -> Bool {
        return OWSPrimaryStorage.dbReadConnection().bool(forKey: areLinkPreviewsEnabledKey,
                                                         inCollection: collection,
                                                         defaultValue: true)
    }

    @objc
    public class func setAreLinkPreviewsEnabled(value: Bool) {
        OWSPrimaryStorage.dbReadWriteConnection().setBool(value,
                                                          forKey: areLinkPreviewsEnabledKey,
                                                          inCollection: collection)
        SSKEnvironment.shared.syncManager.sendConfigurationSyncMessage()
    }
}
