//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

@objc
public class PersistableEndPollItem: NSObject, NSCopying, NSSecureCoding {
    var question: String?
    var authorServiceIdBinary: Data
    var timestamp: Int64

    public init(question: String?, authorServiceIdBinary: Data, timestamp: Int64) {
        self.question = question
        self.authorServiceIdBinary = authorServiceIdBinary
        self.timestamp = timestamp
    }

    // MARK: - NSCopying

    public func copy(with zone: NSZone? = nil) -> Any {
        self
    }

    // MARK: - NSSecureCoding

    public static var supportsSecureCoding: Bool { true }

    public func encode(with coder: NSCoder) {
        coder.encode(question, forKey: "question")
        coder.encode(authorServiceIdBinary, forKey: "authorServiceIdBinary")
        coder.encode(timestamp, forKey: "timestamp")
    }

    public required init?(coder: NSCoder) {
        guard
            let question = coder.decodeObject(of: NSString.self, forKey: "question") as String?,
            let authorServiceIdBinary = coder.decodeObject(of: NSData.self, forKey: "authorServiceIdBinary") as? Data
        else {
            return nil
        }

        self.question = question
        self.authorServiceIdBinary = authorServiceIdBinary
        self.timestamp = coder.decodeInt64(forKey: "timestamp")
    }
}

extension TSInfoMessage {
    public func pollInteractionUniqueId(transaction: DBReadTransaction) -> String? {
        guard let endPollItem: PersistableEndPollItem = infoMessageValue(forKey: .endPoll) else {
            return nil
        }

        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aci else {
            Logger.error("User is not registered")
            return nil
        }

        do {
            let incomingMessageAuthor = try Aci.parseFrom(serviceIdBinary: endPollItem.authorServiceIdBinary)

            return try DependenciesBridge.shared.interactionStore.fetchMessage(
                timestamp: UInt64(endPollItem.timestamp),
                incomingMessageAuthor: localAci == incomingMessageAuthor ? nil : incomingMessageAuthor,
                transaction: transaction,
            )?.uniqueId
        } catch {
            Logger.info("Unable to get target poll \(error)")
            return nil
        }
    }

    @objc
    func endPollDescription(transaction: DBReadTransaction) -> String? {
        guard let endPollItem: PersistableEndPollItem = infoMessageValue(forKey: .endPoll) else {
            return nil
        }

        guard let question = endPollItem.question else {
            return nil
        }

        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aci else {
            Logger.error("Can't find local ACI")
            return nil
        }

        var pollTerminateAci: Aci?
        do {
            pollTerminateAci = try Aci.parseFrom(serviceIdBinary: endPollItem.authorServiceIdBinary)
        } catch {
            Logger.error("Couldn't parse ACI from service ID binary: \(error)")
            return nil
        }

        guard let pollTerminateAci else {
            Logger.error("Couldn't parse ACI from service ID binary")
            return nil
        }

        if localAci == pollTerminateAci {
            let formatString = OWSLocalizedString(
                "POLL_ENDED_BY_YOU_CHAT_LIST_UPDATE",
                comment: "Shown when the local user ends a poll. Embeds {{ poll question }}.",
            )
            return String(format: formatString, question)
        }

        let displayName = SSKEnvironment.shared.contactManagerRef.displayName(
            for: SignalServiceAddress(pollTerminateAci),
            tx: transaction,
        )

        let formatString = OWSLocalizedString(
            "POLL_ENDED_BY_OTHER_CHAT_LIST_UPDATE",
            comment: "Shown when another user ends a poll. Embeds {{ another user }} and {{ poll question }}.",
        )

        return String(format: formatString, displayName.resolvedValue(), question)
    }
}
