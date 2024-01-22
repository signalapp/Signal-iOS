//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal final class MessageBackupGroupUpdateSwiftToProtoConverter {

    private init() {}

    internal static func archiveGroupUpdate(
        groupUpdate: TSInfoMessage.PersistableGroupUpdateItem,
        // We should never be putting our pni in the backup as it can change,
        // we only ever insert our aci and use special cases for our pni.
        localUserAci: Aci,
        chatItemId: MessageBackup.ChatItemId
    ) -> MessageBackup.ArchiveInteractionResult<BackupProtoGroupChangeChatUpdateUpdate> {
        var localAciData = localUserAci.rawUUID.data
        func aciData(_ aci: AciUuid) -> Data {
            return aci.wrappedValue.rawUUID.data
        }
        func pniData(_ pni: Pni) -> Data {
            return pni.rawUUID.data
        }
        func serviceIdData(_ serviceId: ServiceIdUppercaseString) -> Data {
            return serviceId.wrappedValue.serviceIdBinary.asData
        }

        let updateBuilder = BackupProtoGroupChangeChatUpdateUpdate.builder()

        var protoBuildError: Error?

        func setUpdate<Proto, Builder>(
            _ builder: Builder,
            setOptionalFields: ((Builder) -> Void)? = nil,
            build: (Builder) -> () throws -> Proto,
            set: (BackupProtoGroupChangeChatUpdateUpdateBuilder) -> (Proto) -> Void
        ) {
            do {
                setOptionalFields?(builder)
                let proto = try build(builder)()
                set(updateBuilder)(proto)
            } catch let error {
                protoBuildError = error
            }
        }
        switch groupUpdate {
        case .sequenceOfInviteLinkRequestAndCancels(let requester, let count, _):
            // Note: isTail is dropped from the backup.
            // It is reconstructed at restore time from the presence, or lack thereof,
            // of a subsequent join request.
            setUpdate(
                BackupProtoGroupSequenceOfRequestsAndCancelsUpdate.builder(
                    requestorAci: aciData(requester),
                    count: .init(clamping: count)
                ),
                build: { $0.build },
                set: { $0.setGroupSequenceOfRequestsAndCancelsUpdate }
            )
        // TODO: add other cases
        default:
            fatalError()
        }

        if let protoBuildError {
            return .messageFailure([
                .init(
                    objectId: chatItemId,
                    error: .protoSerializationError(protoBuildError)
                )
            ])
        }

        let update: BackupProtoGroupChangeChatUpdateUpdate
        do {
            update = try updateBuilder.build()
        } catch let error {
            return .messageFailure([
                .init(
                    objectId: chatItemId,
                    error: .protoSerializationError(error)
                )
            ])
        }

        return .success(update)
    }
}
