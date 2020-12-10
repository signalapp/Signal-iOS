//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// Caching builder used for a single CVC load.
// CVC loads often build the same avatars over and over.
//
// TODO: There should be real benefits to extracting a token that
//       describes the avatar content and caching avatars across
//       db transactions and updates.
//       It might help ensure that CVComponentState equality
//       works correctly.
public class CVAvatarBuilder {

    // MARK: - Dependencies

    // TODO: Audit all usage of avatars, contactsManager, profileManager in CV classes.
    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    // MARK: -

    private let transaction: SDSAnyReadTransaction

    private var cache = [String: UIImage]()

    required init(transaction: SDSAnyReadTransaction) {
        self.transaction = transaction
    }

    func buildAvatar(forAddress address: SignalServiceAddress, diameter: UInt) -> UIImage? {
        guard let cacheKey = address.serviceIdentifier else {
            owsFailDebug("Invalid address.")
            return nil
        }
        if let avatar = cache[cacheKey] {
            return avatar
        }
        let colorName = contactsManager.conversationColorName(for: address, transaction: transaction)
        guard let avatar = OWSContactAvatarBuilder(address: address,
                                                   colorName: colorName,
                                                   diameter: diameter,
                                                   transaction: transaction).build(with: transaction) else {
            owsFailDebug("Could build avatar image")
            return nil
        }
        cache[cacheKey] = avatar
        return avatar
    }

    func buildAvatar(forGroupThread groupThread: TSGroupThread, diameter: UInt) -> UIImage? {
        let cacheKey = groupThread.uniqueId
        if let avatar = cache[cacheKey] {
            return avatar
        }
        let avatarBuilder = OWSGroupAvatarBuilder(thread: groupThread, diameter: diameter)
        let avatar = avatarBuilder.build(with: transaction)
        cache[cacheKey] = avatar
        return avatar
    }

    func buildAvatar(forThread thread: TSThread, diameter: UInt) -> UIImage? {
        if let groupThread = thread as? TSGroupThread {
            return buildAvatar(forGroupThread: groupThread, diameter: diameter)
        } else if let contactThread = thread as? TSContactThread {
            return buildAvatar(forAddress: contactThread.contactAddress, diameter: diameter)
        } else {
            owsFailDebug("Invalid thread.")
            return nil
        }
    }
}
