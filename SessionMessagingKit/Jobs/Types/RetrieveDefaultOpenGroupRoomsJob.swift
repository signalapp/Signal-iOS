// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SignalCoreKit
import SessionUtilitiesKit

public enum RetrieveDefaultOpenGroupRoomsJob: JobExecutor {
    public static let maxFailureCount: Int = -1
    public static let requiresThreadId: Bool = false
    public static let requiresInteractionId: Bool = false
    
    public static func run(
        _ job: Job,
        queue: DispatchQueue,
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    ) {
        // Don't run when inactive or not in main app
        guard (UserDefaults.sharedLokiProject?[.isMainAppActive]).defaulting(to: false) else {
            deferred(job) // Don't need to do anything if it's not the main app
            return
        }
        
        // The OpenGroupAPI won't make any API calls if there is no entry for an OpenGroup
        // in the database so we need to create a dummy one to retrieve the default room data
        let defaultGroupId: String = OpenGroup.idFor(roomToken: "", server: OpenGroupAPI.defaultServer)
        
        Storage.shared.write { db in
            guard try OpenGroup.exists(db, id: defaultGroupId) == false else { return }
            
            _ = try OpenGroup(
                server: OpenGroupAPI.defaultServer,
                roomToken: "",
                publicKey: OpenGroupAPI.defaultServerPublicKey,
                isActive: false,
                name: "",
                userCount: 0,
                infoUpdates: 0
            )
            .saved(db)
        }
        
        OpenGroupManager.getDefaultRoomsIfNeeded()
            .done(on: queue) { _ in success(job, false) }
            .catch(on: queue) { error in failure(job, error, false) }
            .retainUntilComplete()
    }
}
