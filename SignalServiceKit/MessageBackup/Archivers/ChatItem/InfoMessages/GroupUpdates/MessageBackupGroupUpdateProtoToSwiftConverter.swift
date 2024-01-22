//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal final class MessageBackupGroupUpdateProtoToSwiftConverter {

    private init() {}

    typealias PersistableGroupUpdateItem = TSInfoMessage.PersistableGroupUpdateItem

    internal static func restoreGroupUpdates(
        groupUpdates: [BackupProtoGroupChangeChatUpdateUpdate],
        // We should never be comparing our pni as it can change,
        // we only ever want to compare our unchanging aci.
        localUserAci: Aci,
        partialErrors: inout [MessageBackup.RestoringFrameError]
    ) -> MessageBackup.RestoreInteractionResult<[PersistableGroupUpdateItem]> {
        var persistableUpdates = [PersistableGroupUpdateItem]()
        for updateProto in groupUpdates {
            let result = Self.restoreGroupUpdate(
                groupUpdate: updateProto,
                localUserAci: localUserAci
            )
            if let persistableItems = result.unwrap(partialErrors: &partialErrors) {
                persistableUpdates.append(contentsOf: persistableItems)
            } else {
                return .messageFailure(partialErrors)
            }
        }
        return .success(persistableUpdates)
    }

    private static func restoreGroupUpdate(
        groupUpdate: BackupProtoGroupChangeChatUpdateUpdate,
        localUserAci: Aci
    ) -> MessageBackup.RestoreInteractionResult<[PersistableGroupUpdateItem]> {
        enum UnwrappedAci {
            case localUser
            case otherUser(AciUuid)
            case invalidAci(MessageBackup.RestoringFrameError)
        }
        enum UnwrappedOptionalAci {
            case unknown
            case localUser
            case otherUser(AciUuid)
            case invalidAci(MessageBackup.RestoringFrameError)
        }

        func unwrap(_ aciData: Data) -> UnwrappedAci {
            guard let aciUuid = UUID(data: aciData) else {
                return .invalidAci(.invalidProtoData)
            }
            let aci = Aci(fromUUID: aciUuid)
            if aci == localUserAci {
                return .localUser
            } else {
                return .otherUser(aci.codableUuid)
            }
        }
        func unwrap(_ aciData: Data?) -> UnwrappedOptionalAci {
            guard let aciRaw = aciData else {
                return .unknown
            }
            switch unwrap(aciRaw) {
            case .localUser:
                return .localUser
            case .otherUser(let aci):
                return .otherUser(aci)
            case .invalidAci(let error):
                return .invalidAci(error)
            }
        }

        switch groupUpdate.updateType {
        case .genericGroupUpdate(let proto):
            switch unwrap(proto.updaterAci) {
            case .unknown:
                return .success([.genericUpdateByUnknownUser])
            case .localUser:
                return .success([.genericUpdateByLocalUser])
            case .otherUser(let aci):
                return .success([.genericUpdateByOtherUser(updaterAci: aci)])
            case .invalidAci(let error):
                return .messageFailure([error])
            }
        }
    }
}

extension BackupProtoGroupChangeChatUpdateUpdate {

    fileprivate enum UpdateType {
        case genericGroupUpdate(BackupProtoGenericGroupUpdate)
        // TODO: add other cases
    }

    fileprivate var updateType: UpdateType {
        if let genericGroupUpdate {
            return .genericGroupUpdate(genericGroupUpdate)
        }
        fatalError("TODO: add other cases")
    }
}
