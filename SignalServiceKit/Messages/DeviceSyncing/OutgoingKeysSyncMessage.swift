//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(OWSSyncKeysMessage)
final class OutgoingKeysSyncMessage: OutgoingSyncMessage {

    let accountEntropyPool: String?
    let mediaRootBackupKey: Data?

    init(
        localThread: TSContactThread,
        accountEntropyPool: AccountEntropyPool?,
        mediaRootBackupKey: MediaRootBackupKey?,
        tx: DBReadTransaction,
    ) {
        self.accountEntropyPool = accountEntropyPool?.rawString
        self.mediaRootBackupKey = mediaRootBackupKey?.serialize()
        super.init(localThread: localThread, tx: tx)
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let accountEntropyPool {
            coder.encode(accountEntropyPool, forKey: "accountEntropyPool")
        }
        if let mediaRootBackupKey {
            coder.encode(mediaRootBackupKey, forKey: "mediaRootBackupKey")
        }
    }

    required init?(coder: NSCoder) {
        self.accountEntropyPool = coder.decodeObject(of: NSString.self, forKey: "accountEntropyPool") as String?
        self.mediaRootBackupKey = coder.decodeObject(of: NSData.self, forKey: "mediaRootBackupKey") as Data?
        super.init(coder: coder)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.accountEntropyPool)
        hasher.combine(self.mediaRootBackupKey)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.accountEntropyPool == object.accountEntropyPool else { return false }
        guard self.mediaRootBackupKey == object.mediaRootBackupKey else { return false }
        return true
    }

    override func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let keysBuilder = SSKProtoSyncMessageKeys.builder()
        if let accountEntropyPool {
            keysBuilder.setAccountEntropyPool(accountEntropyPool)
        }
        if let mediaRootBackupKey {
            keysBuilder.setMediaRootBackupKey(mediaRootBackupKey)
        }

        let builder = SSKProtoSyncMessage.builder()
        builder.setKeys(keysBuilder.buildInfallibly())
        return builder
    }

    override var isUrgent: Bool { false }
}
