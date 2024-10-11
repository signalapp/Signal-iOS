//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

extension TSInfoMessage {
    static func paymentsActivatedMessage(
        thread: TSThread,
        timestamp: UInt64 = MessageTimestampGenerator.sharedInstance.generateTimestamp(),
        senderAci: Aci
    ) -> TSInfoMessage {
        return TSInfoMessage(
            thread: thread,
            messageType: .paymentsActivated,
            timestamp: timestamp,
            infoMessageUserInfo: [
                .paymentActivatedAci: senderAci.serviceIdString
            ]
        )
    }

    static func paymentsActivationRequestMessage(
        thread: TSThread,
        timestamp: UInt64 = MessageTimestampGenerator.sharedInstance.generateTimestamp(),
        senderAci: Aci
    ) -> TSInfoMessage {
        return TSInfoMessage(
            thread: thread,
            messageType: .paymentsActivationRequest,
            timestamp: timestamp,
            infoMessageUserInfo: [
                .paymentActivationRequestSenderAci: senderAci.serviceIdString
            ]
        )
    }
}

extension TSInfoMessage {
    public enum PaymentsInfoMessageAuthor: Hashable, Equatable {
        case localUser
        case otherUser(Aci)
    }

    public func paymentsActivationRequestAuthor(localIdentifiers: LocalIdentifiers) -> PaymentsInfoMessageAuthor? {
        guard
            let requestSenderAciString: String = infoMessageValue(forKey: .paymentActivationRequestSenderAci),
            let requestSenderAci = Aci.parseFrom(aciString: requestSenderAciString)
        else { return nil }

        return paymentsInfoMessageAuthor(
            identifyingAci: requestSenderAci,
            localIdentifiers: localIdentifiers
        )
    }

    public func paymentsActivatedAuthor(localIdentifiers: LocalIdentifiers) -> PaymentsInfoMessageAuthor? {
        guard
            let authorAciString: String = infoMessageValue(forKey: .paymentActivatedAci),
            let authorAci = Aci.parseFrom(aciString: authorAciString)
        else { return nil }

        return paymentsInfoMessageAuthor(
            identifyingAci: authorAci,
            localIdentifiers: localIdentifiers
        )
    }

    private func paymentsInfoMessageAuthor(
        identifyingAci: Aci?,
        localIdentifiers: LocalIdentifiers
    ) -> PaymentsInfoMessageAuthor? {
        guard let identifyingAci else { return nil }

        if identifyingAci == localIdentifiers.aci {
            return .localUser
        } else {
            return .otherUser(identifyingAci)
        }
    }

    // MARK: -

    private enum PaymentsInfoMessageType {
        case incoming(from: Aci)
        case outgoing(to: Aci)
    }

    private func paymentsActivationRequestType(transaction tx: SDSAnyReadTransaction) -> PaymentsInfoMessageType? {
        return paymentsInfoMessageType(
            authorBlock: self.paymentsActivationRequestAuthor(localIdentifiers:),
            tx: tx.asV2Read
        )
    }

    private func paymentsActivatedType(transaction tx: SDSAnyReadTransaction) -> PaymentsInfoMessageType? {
        return paymentsInfoMessageType(
            authorBlock: self.paymentsActivatedAuthor(localIdentifiers:),
            tx: tx.asV2Read
        )
    }

    private func paymentsInfoMessageType(
        authorBlock: (LocalIdentifiers) -> PaymentsInfoMessageAuthor?,
        tx: any DBReadTransaction
    ) -> PaymentsInfoMessageType? {
        guard let localIdentiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx) else {
            return nil
        }

        switch authorBlock(localIdentiers) {
        case nil:
            return nil
        case .localUser:
            guard
                let contactThread = DependenciesBridge.shared.threadStore
                    .fetchThreadForInteraction(self, tx: tx) as? TSContactThread,
                let contactAci = contactThread.contactAddress.aci
            else { return nil }

            return .outgoing(to: contactAci)
        case .otherUser(let authorAci):
            return .incoming(from: authorAci)
        }
    }

    public func isIncomingPaymentsActivationRequest(_ tx: SDSAnyReadTransaction) -> Bool {
        switch paymentsActivationRequestType(transaction: tx) {
        case .none, .outgoing:
            return false
        case .incoming:
            return true
        }
    }

    public func isIncomingPaymentsActivated(_ tx: SDSAnyReadTransaction) -> Bool {
        switch paymentsActivatedType(transaction: tx) {
        case .none, .outgoing:
            return false
        case .incoming:
            return true
        }
    }

    @objc
    func paymentsActivationRequestDescription(transaction: SDSAnyReadTransaction) -> String? {
        let aci: Aci
        let formatString: String
        switch paymentsActivationRequestType(transaction: transaction) {
        case .none:
            return nil
        case .incoming(let fromAci):
            aci = fromAci
            formatString = OWSLocalizedString(
                "INFO_MESSAGE_PAYMENTS_ACTIVATION_REQUEST_RECEIVED",
                comment: "Shown when a user receives a payment activation request. Embeds: {{ the user's name}}"
            )
        case .outgoing(let toAci):
            aci = toAci
            formatString = OWSLocalizedString(
                "INFO_MESSAGE_PAYMENTS_ACTIVATION_REQUEST_SENT",
                comment: "Shown when requesting a user activates payments. Embeds: {{ the user's name}}"
            )
        }

        let displayName = SSKEnvironment.shared.contactManagerRef.displayName(for: SignalServiceAddress(aci), tx: transaction)
        return String(format: formatString, displayName.resolvedValue())
    }

    @objc
    func paymentsActivatedDescription(transaction: SDSAnyReadTransaction) -> String? {
        switch paymentsActivatedType(transaction: transaction) {
        case .none:
            return nil
        case .outgoing:
            return OWSLocalizedString(
                "INFO_MESSAGE_PAYMENTS_ACTIVATED",
                comment: "Shown when a user activates payments from a chat"
            )
        case .incoming(let aci):
            let displayName = SSKEnvironment.shared.contactManagerRef.displayName(for: SignalServiceAddress(aci), tx: transaction)
            let format = OWSLocalizedString(
                "INFO_MESSAGE_PAYMENTS_ACTIVATION_REQUEST_FINISHED",
                comment: "Shown when a user activates payments from a chat. Embeds: {{ the user's name}}"
            )
            return String(format: format, displayName.resolvedValue())
        }
    }
}
