//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public class OWS115EnsureProfileAvatars: YDBDatabaseMigration {

    // MARK: - Dependencies

    // MARK: -

    // Increment a similar constant for each migration.
    @objc
    public override class var migrationId: String {
        return "115"
    }

    var fileManager: FileManager {
        return FileManager.default
    }

    override public func runUp(with transaction: YapDatabaseReadWriteTransaction) {
        Bench(title: "\(self.logTag)") {
            var profilesWithMissingAvatars: [String] = []
            OWSUserProfile.anyEnumerate(transaction: transaction.asAnyWrite,
                                        batched: true) { profile, _ in
                guard let filename = profile.avatarFileName else {
                    return
                }

                let filepath = OWSUserProfile.profileAvatarFilepath(withFilename: filename)
                guard !self.fileManager.fileExists(atPath: filepath) else {
                    return
                }
                profilesWithMissingAvatars.append(profile.uniqueId)
            }

            for uniqueId in profilesWithMissingAvatars {
                guard let profile = OWSUserProfile.anyFetch(uniqueId: uniqueId, transaction: transaction.asAnyRead) else {
                    owsFailDebug("profile was unexpectedly nil")
                    continue
                }
                Logger.info("removing reference to non-existant avatar file")
                profile.update(withAvatarFileName: nil, transaction: transaction.asAnyWrite)
            }
        }
    }
}
