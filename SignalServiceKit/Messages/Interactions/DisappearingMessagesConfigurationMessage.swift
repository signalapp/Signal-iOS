//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(OWSDisappearingMessagesConfigurationMessage)
final class DisappearingMessagesConfigurationMessage: TransientOutgoingMessage {

    private let configuration: DisappearingMessagesConfiguration

    override var isUrgent: Bool { false }

    init(
        configuration: DisappearingMessagesConfigurationRecord,
        contactThread: TSContactThread,
        tx: DBReadTransaction,
    ) {
        owsAssertDebug(configuration.timerVersion >= 1)

        self.configuration = DisappearingMessagesConfiguration(
            isEnabled: configuration.isEnabled,
            durationSeconds: configuration.durationSeconds,
            timerVersion: configuration.timerVersion,
        )
        super.init(
            outgoingMessageWith: TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: contactThread),
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(configuration, forKey: "configuration")
    }

    required init?(coder: NSCoder) {
        guard let configuration = coder.decodeObject(of: DisappearingMessagesConfiguration.self, forKey: "configuration") else {
            return nil
        }
        self.configuration = configuration
        super.init(coder: coder)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.configuration)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.configuration == object.configuration else { return false }
        return true
    }

    override func dataMessageBuilder(with thread: TSThread, transaction: DBReadTransaction) -> SSKProtoDataMessageBuilder? {
        let dataMessageBuilder = super.dataMessageBuilder(with: thread, transaction: transaction)
        guard let dataMessageBuilder else {
            return nil
        }
        dataMessageBuilder.setTimestamp(self.timestamp)
        dataMessageBuilder.setFlags(UInt32(SSKProtoDataMessageFlags.expirationTimerUpdate.rawValue))
        dataMessageBuilder.setExpireTimer(self.configuration.durationSeconds)
        dataMessageBuilder.setExpireTimerVersion(self.configuration.timerVersion)
        return dataMessageBuilder
    }
}

// MARK: -

@objc(OWSDisappearingMessagesConfiguration)
private final class DisappearingMessagesConfiguration: NSObject, NSSecureCoding {
    let isEnabled: Bool
    let durationSeconds: UInt32
    let timerVersion: UInt32

    init(isEnabled: Bool, durationSeconds: UInt32, timerVersion: UInt32) {
        self.isEnabled = isEnabled
        self.durationSeconds = isEnabled ? durationSeconds : 0
        self.timerVersion = timerVersion
    }

    static var supportsSecureCoding: Bool { true }

    func encode(with coder: NSCoder) {
        coder.encode(NSNumber(value: self.durationSeconds), forKey: "durationSeconds")
        coder.encode(NSNumber(value: self.isEnabled), forKey: "enabled")
        coder.encode(NSNumber(value: self.timerVersion), forKey: "timerVersion")
    }

    init?(coder: NSCoder) {
        self.isEnabled = coder.decodeObject(of: NSNumber.self, forKey: "enabled")?.boolValue ?? false
        let durationSeconds = coder.decodeObject(of: NSNumber.self, forKey: "durationSeconds")?.uint32Value ?? 0
        self.durationSeconds = self.isEnabled ? durationSeconds : 0
        self.timerVersion = coder.decodeObject(of: NSNumber.self, forKey: "timerVersion")?.uint32Value ?? 0
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(self.durationSeconds)
        hasher.combine(self.isEnabled)
        hasher.combine(self.timerVersion)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard self.isEnabled == object.isEnabled else { return false }
        guard self.durationSeconds == object.durationSeconds else { return false }
        guard self.timerVersion == object.timerVersion else { return false }
        return true
    }
}
