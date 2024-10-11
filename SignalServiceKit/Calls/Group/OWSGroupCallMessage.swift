//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension OWSGroupCallMessage {
    private var groupCallEndedMessage: String {
        return OWSLocalizedString(
            "GROUP_CALL_ENDED_MESSAGE",
            comment: "Text in conversation view for a group call that has since ended"
        )
    }

    private var groupCallStartedByYou: String {
        return OWSLocalizedString(
            "GROUP_CALL_STARTED_BY_YOU",
            comment: "Text explaining that you started a group call."
        )
    }

    private func participantName(for address: SignalServiceAddress, tx: SDSAnyReadTransaction) -> String {
        if address.isLocalAddress {
            return OWSLocalizedString("YOU", comment: "Second person pronoun to represent the local user.")
        } else {
            return SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: tx).resolvedValue()
        }
    }

    public func systemText(tx: SDSAnyReadTransaction) -> String {
        if self.hasEnded {
            return self.groupCallEndedMessage
        }

        let threeOrMoreFormat = OWSLocalizedString(
            "GROUP_CALL_MANY_PEOPLE_HERE_%d",
            tableName: "PluralAware",
            comment: "Text explaining that there are three or more people in the group call. Embeds {{ %1$@ participantCount-2, %2$@ participant1, %3$@ participant2 }}"
        )
        let twoFormat = OWSLocalizedString(
            "GROUP_CALL_TWO_PEOPLE_HERE_FORMAT",
            comment: "Text explaining that there are two people in the group call. Embeds {{ %1$@ participant1, %2$@ participant2 }}"
        )
        let onlyCreatorFormat = OWSLocalizedString(
            "GROUP_CALL_STARTED_MESSAGE_FORMAT",
            comment: "Text explaining that someone started a group call. Embeds {{call creator display name}}"
        )
        let onlyYouString = OWSLocalizedString(
            "GROUP_CALL_YOU_ARE_HERE",
            comment: "Text explaining that you are in the group call."
        )
        let onlyOneFormat = OWSLocalizedString(
            "GROUP_CALL_ONE_PERSON_HERE_FORMAT",
            comment: "Text explaining that there is one person in the group call. Embeds {member name}"
        )
        let someoneString = OWSLocalizedString(
            "GROUP_CALL_SOMEONE_STARTED_MESSAGE",
            comment: "Text in conversation view for a group call that someone started. We don't know who"
        )

        let joinedMemberAddresses = self.joinedMemberAcis.map { SignalServiceAddress($0.wrappedValue) }
        let addresses = SSKEnvironment.shared.contactManagerRef.sortSignalServiceAddresses(joinedMemberAddresses, transaction: tx)

        var localAddresses = [SignalServiceAddress]()
        var creatorAddresses = [SignalServiceAddress]()
        var otherAddresses = [SignalServiceAddress]()
        for address in addresses {
            if address.isLocalAddress {
                localAddresses.append(address)
                continue
            }
            if let creatorAci, address.serviceIdObjC == creatorAci {
                creatorAddresses.append(address)
                continue
            }
            otherAddresses.append(address)
        }
        let sortedAddresses = localAddresses + creatorAddresses + otherAddresses

        if sortedAddresses.count >= 3 {
            let firstName = self.participantName(for: sortedAddresses[0], tx: tx)
            let secondName = self.participantName(for: sortedAddresses[1], tx: tx)
            return String.localizedStringWithFormat(threeOrMoreFormat, sortedAddresses.count - 2, firstName, secondName)
        }
        if sortedAddresses.count == 2 {
            let firstName = self.participantName(for: sortedAddresses[0], tx: tx)
            let secondName = self.participantName(for: sortedAddresses[1], tx: tx)
            return String(format: twoFormat, firstName, secondName)
        }
        if sortedAddresses.count == 0 {
            return someoneString
        }
        if let creatorAci, sortedAddresses[0].serviceIdObjC == creatorAci {
            if sortedAddresses[0].isLocalAddress {
                return self.groupCallStartedByYou
            } else {
                let name = self.participantName(for: sortedAddresses[0], tx: tx)
                return String(format: onlyCreatorFormat, name)
            }
        } else {
            if sortedAddresses[0].isLocalAddress {
                return onlyYouString
            } else {
                let name = self.participantName(for: sortedAddresses[0], tx: tx)
                return String(format: onlyOneFormat, name)
            }
        }
    }
}

// MARK: - OWSPreviewText

extension OWSGroupCallMessage: OWSPreviewText {
    public func previewText(transaction: SDSAnyReadTransaction) -> String {
        if hasEnded {
            return self.groupCallEndedMessage
        }
        if let creatorAci, SignalServiceAddress(creatorAci.wrappedAciValue).isLocalAddress {
            return self.groupCallStartedByYou
        }
        if let creatorAci {
            let creatorDisplayName = self.participantName(for: SignalServiceAddress(creatorAci.wrappedAciValue), tx: transaction)
            let formatString = OWSLocalizedString(
                "GROUP_CALL_STARTED_MESSAGE_FORMAT",
                comment: "Text explaining that someone started a group call. Embeds {{call creator display name}}"
            )
            return String(format: formatString, creatorDisplayName)
        }
        return OWSLocalizedString(
            "GROUP_CALL_SOMEONE_STARTED_MESSAGE",
            comment: "Text in conversation view for a group call that someone started. We don't know who"
        )
    }
}

// MARK: - OWSReadTracking

@objc
extension OWSGroupCallMessage: OWSReadTracking {
    public var expireStartedAt: UInt64 {
        return 0
    }

    public func markAsRead(
        atTimestamp readTimestamp: UInt64,
        thread: TSThread,
        circumstance: OWSReceiptCircumstance,
        shouldClearNotifications: Bool,
        transaction tx: SDSAnyWriteTransaction
    ) {
        if wasRead {
            return
        }

        anyUpdateGroupCallMessage(transaction: tx) { groupCallMessage in
            groupCallMessage.wasRead = true
        }

        switch circumstance {
        case .onThisDevice, .onThisDeviceWhilePendingMessageRequest:
            let callRecordStore = DependenciesBridge.shared.callRecordStore
            let missedCallManager = DependenciesBridge.shared.callRecordMissedCallManager

            if
                let sqliteRowId = sqliteRowId,
                let associatedCallRecord = callRecordStore.fetch(
                    interactionRowId: sqliteRowId, tx: tx.asV2Read
                )
            {
                missedCallManager.markUnreadCallsInConversationAsRead(
                    beforeCallRecord: associatedCallRecord,
                    sendSyncMessage: true,
                    tx: tx.asV2Write
                )
            }
        case .onLinkedDevice, .onLinkedDeviceWhilePendingMessageRequest:
            break
        @unknown default:
            break
        }
    }
}
