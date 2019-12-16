//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import SignalMetadataKit
import ZKGroup

@objc
public class GroupsV2Impl: NSObject, GroupsV2 {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: - Create Group v2

    public func createNewGroupV2OnService(groupModel: TSGroupModel) -> Promise<Void> {
        // TODO: Should we make sure we have a local profile credential?
        return Promise(error: OWSAssertionError("Not yet implemented."))
    }

    public func generateGroupSecretParamsData() throws -> Data {
        let sroupSecretParams = try GroupSecretParams.generate()
        let bytes = sroupSecretParams.serialize()
        return bytes.asData
    }
}
