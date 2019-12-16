//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public protocol GroupsV2: AnyObject {
    func createNewGroupV2OnService(groupModel: TSGroupModel) -> Promise<Void>

    func generateGroupSecretParamsData() throws -> Data
}

public class MockGroupsV2: NSObject, GroupsV2 {
    public func createNewGroupV2OnService(groupModel: TSGroupModel) -> Promise<Void> {
        owsFail("Not implemented.")
    }

    public func generateGroupSecretParamsData() throws -> Data {
        owsFail("Not implemented.")
    }
}
