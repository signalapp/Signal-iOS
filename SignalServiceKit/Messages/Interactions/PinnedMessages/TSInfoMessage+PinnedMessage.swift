//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

@objc
public class PersistablePinnedMessageItem: NSObject, NSCopying, NSSecureCoding {
    let pinnedMessageAuthorAci: Aci
    let originalMessageAuthorAci: Aci
    let timestamp: Int64

    public init(pinnedMessageAuthorAci: Aci, originalMessageAuthorAci: Aci, timestamp: Int64) {
        self.pinnedMessageAuthorAci = pinnedMessageAuthorAci
        self.originalMessageAuthorAci = originalMessageAuthorAci
        self.timestamp = timestamp
    }

    // MARK: - NSCopying

    public func copy(with zone: NSZone? = nil) -> Any {
        self
    }

    // MARK: - NSSecureCoding

    public static var supportsSecureCoding: Bool { true }

    public func encode(with coder: NSCoder) {
        coder.encode(pinnedMessageAuthorAci.serviceIdBinary, forKey: "pinnedMessageAuthor")
        coder.encode(originalMessageAuthorAci.serviceIdBinary, forKey: "originalMessageAuthor")
        coder.encode(timestamp, forKey: "timestamp")
    }

    public required init?(coder: NSCoder) {
        guard
            let pinnedMessageAuthorServiceIdBinary = coder.decodeObject(of: NSData.self, forKey: "pinnedMessageAuthor") as Data?,
            let originalMessageAuthorServiceIdBinary = coder.decodeObject(of: NSData.self, forKey: "originalMessageAuthor") as Data?,
            let _pinnedMessageAuthorAci = try? Aci.parseFrom(serviceIdBinary: pinnedMessageAuthorServiceIdBinary),
            let _originalMessageAuthorAci = try? Aci.parseFrom(serviceIdBinary: originalMessageAuthorServiceIdBinary)
        else {
            return nil
        }

        self.pinnedMessageAuthorAci = _pinnedMessageAuthorAci
        self.originalMessageAuthorAci = _originalMessageAuthorAci
        self.timestamp = coder.decodeInt64(forKey: "timestamp")
    }
}

extension TSInfoMessage {
    public func pinnedMessageUniqueId(transaction: DBReadTransaction) -> String? {
        guard let pinnedMessageItem: PersistablePinnedMessageItem = infoMessageValue(forKey: .pinnedMessage) else {
            return nil
        }

        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aci else {
            Logger.error("User is not registered")
            return nil
        }

        do {
            return try DependenciesBridge.shared.interactionStore.fetchMessage(
                timestamp: UInt64(pinnedMessageItem.timestamp),
                incomingMessageAuthor: localAci == pinnedMessageItem.originalMessageAuthorAci ? nil : pinnedMessageItem.originalMessageAuthorAci,
                transaction: transaction
            )?.uniqueId
        } catch {
            Logger.info("Unable to get target pinned message \(error)")
            return nil
        }
    }

    @objc
    func pinnedMessageDescription(transaction: DBReadTransaction) -> String? {
        guard let pinnedMessageItem: PersistablePinnedMessageItem = infoMessageValue(forKey: .pinnedMessage) else {
            return nil
        }

        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aci else {
            Logger.error("Can't find local ACI")
            return nil
        }

        if localAci == pinnedMessageItem.pinnedMessageAuthorAci {
            return OWSLocalizedString(
                "PINNED_MESSAGE_CHAT_EVENT_SELF",
                comment: "Shown when the local user pins a message."
            )
        }

        let displayName = SSKEnvironment.shared.contactManagerRef.displayName(
            for: SignalServiceAddress(pinnedMessageItem.pinnedMessageAuthorAci),
            tx: transaction
        )

        let formatString = OWSLocalizedString(
            "PINNED_MESSAGE_CHAT_EVENT_OTHER",
            comment: "Shown when another user pins a message. Embeds {{ another user }}."
        )

        return String(format: formatString, displayName.resolvedValue())
    }
}
