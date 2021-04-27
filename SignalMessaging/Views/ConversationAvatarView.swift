//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit

/// Avatar View which updates itself as necessary when the profile, contact, or group picture changes.
@objc
public class ConversationAvatarView: AvatarImageView {

    @objc
    public var diameter: UInt {
        didSet {
            if oldValue != diameter {
                invalidateIntrinsicContentSize()
                setNeedsLayout()
                updateImageWithSneakyTransaction()
            }
        }
    }

    @objc
    public var localUserAvatarMode: LocalUserAvatarMode {
        didSet {
            if oldValue != localUserAvatarMode {
                updateImageWithSneakyTransaction()
            }
        }
    }

    private enum State {
        case contact(contactThread: TSContactThread)
        case group(groupThread: TSGroupThread)
        case unknownContact(contactAddress: SignalServiceAddress)

        static func forThread(_ thread: TSThread) -> State {
            if let contactThread = thread as? TSContactThread {
                return .contact(contactThread: contactThread)
            } else if let groupThread = thread as? TSGroupThread {
                return .group(groupThread: groupThread)
            } else {
                owsFail("Invalid thread.")
            }
        }

        var contactAddress: SignalServiceAddress? {
            switch self {
            case .contact(let contactThread):
                return contactThread.contactAddress
            case .group:
                return nil
            case .unknownContact(let contactAddress):
                return contactAddress
            }
        }

        var groupThreadId: String? {
            switch self {
            case .contact:
                return nil
            case .group(let groupThread):
                return groupThread.uniqueId
            case .unknownContact:
                return nil
            }
        }

        var thread: TSThread? {
            switch self {
            case .contact(let contactThread):
                return contactThread
            case .group(let groupThread):
                return groupThread
            case .unknownContact:
                return nil
            }
        }

        func reloadWithSneakyTransaction() -> State {
            databaseStorage.read { transaction in
                reload(transaction: transaction)
            }
        }

        func reload(transaction: SDSAnyReadTransaction) -> State {
            if let contactAddress = self.contactAddress {
                if let contactThread = TSContactThread.getWithContactAddress(contactAddress,
                                                                             transaction: transaction) {
                    return .contact(contactThread: contactThread)
                } else {
                    return .unknownContact(contactAddress: contactAddress)
                }
            } else {
                guard let thread = self.thread else {
                    return self
                }
                guard let latestThread = TSThread.anyFetch(uniqueId: thread.uniqueId,
                                                           transaction: transaction) else {
                    owsFailDebug("Missing thread.")
                    return self
                }
                return State.forThread(latestThread)
            }
        }
    }

    private var state: State? {
        didSet {
            ensureObservers()
        }
    }

    @objc
    public override var intrinsicContentSize: CGSize {
        .square(CGFloat(diameter))
    }

    @objc
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        .square(CGFloat(diameter))
    }

    @objc
    public required init(diameter: UInt, localUserAvatarMode: LocalUserAvatarMode) {
        self.diameter = diameter
        self.localUserAvatarMode = localUserAvatarMode

        super.init(frame: .zero)

        setContentHuggingHigh()
        setCompressionResistanceHigh()
    }

    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: -

    private func configure(state: State, transaction: SDSAnyReadTransaction) {
        self.state = state
        self.updateImage(transaction: transaction)
    }

    @objc
    public func configureWithSneakyTransaction(thread: TSThread) {
        databaseStorage.read { transaction in
            configure(state: State.forThread(thread), transaction: transaction)
        }
    }

    @objc
    public func configure(thread: TSThread, transaction: SDSAnyReadTransaction) {
        configure(state: State.forThread(thread), transaction: transaction)
    }

    @objc
    public func configureWithSneakyTransaction(address: SignalServiceAddress) {
        databaseStorage.read { transaction in
            self.configure(address: address, transaction: transaction)
        }
    }

    @objc
    public func configure(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) {
        if let thread = TSContactThread.getWithContactAddress(address, transaction: transaction) {
            configure(state: State.forThread(thread), transaction: transaction)
        } else {
            configure(state: .unknownContact(contactAddress: address),
                      transaction: transaction)
        }
    }

    // MARK: - Notifications

    private func ensureObservers() {
        NotificationCenter.default.removeObserver(self)

        guard let state = state else {
            return
        }

        switch state {
        case .contact:
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(handleOtherUsersProfileChanged(notification:)),
                                                   name: .otherUsersProfileDidChange,
                                                   object: nil)

            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(handleSignalAccountsChanged(notification:)),
                                                   name: .OWSContactsManagerSignalAccountsDidChange,
                                                   object: nil)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(skipContactAvatarBlurDidChange(notification:)),
                                                   name: OWSContactsManager.skipContactAvatarBlurDidChange,
                                                   object: nil)
        case .group:
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(handleGroupAvatarChanged(notification:)),
                                                   name: .TSGroupThreadAvatarChanged,
                                                   object: nil)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(skipGroupAvatarBlurDidChange(notification:)),
                                                   name: OWSContactsManager.skipGroupAvatarBlurDidChange,
                                                   object: nil)
        case .unknownContact:
            break
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: .ThemeDidChange,
                                               object: nil)
    }

    @objc func themeDidChange() {
        updateImageWithSneakyTransaction()
    }

    @objc func handleSignalAccountsChanged(notification: Notification) {
        // PERF: It would be nice if we could do this only if *this* user's SignalAccount changed,
        // but currently this is only a course grained notification.

        updateImageWithSneakyTransaction()
    }

    @objc func handleOtherUsersProfileChanged(notification: Notification) {
        guard let state = self.state else {
            return
        }
        guard let changedAddress = notification.userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress else {
            owsFailDebug("changedAddress was unexpectedly nil")
            return
        }
        guard let contactAddress = state.contactAddress else {
            // shouldn't call this for group threads
            owsFailDebug("contactAddress was unexpectedly nil")
            return
        }
        guard contactAddress == changedAddress else {
            // not this avatar
            return
        }

        updateImageWithSneakyTransaction()
    }

    @objc func handleGroupAvatarChanged(notification: Notification) {
        guard let state = self.state else {
            return
        }
        guard let changedGroupThreadId = notification.userInfo?[TSGroupThread_NotificationKey_UniqueId] as? String else {
            owsFailDebug("groupThreadId was unexpectedly nil")
            return
        }
        guard let groupThreadId = state.groupThreadId else {
            // shouldn't call this for contact threads
            owsFailDebug("groupThreadId was unexpectedly nil")
            return
        }
        guard groupThreadId == changedGroupThreadId else {
            // not this avatar
            return
        }

        databaseStorage.read { transaction in
            self.state = state.reload(transaction: transaction)
            self.updateImage(transaction: transaction)
        }
    }

    @objc
    func skipContactAvatarBlurDidChange(notification: Notification) {
        guard let address = notification.userInfo?[OWSContactsManager.skipContactAvatarBlurAddressKey] as? SignalServiceAddress else {
            owsFailDebug("Missing address.")
            return
        }
        guard address == state?.contactAddress else {
            return
        }
        updateImageWithSneakyTransaction()
    }

    @objc
    func skipGroupAvatarBlurDidChange(notification: Notification) {
        guard let groupUniqueId = notification.userInfo?[OWSContactsManager.skipGroupAvatarBlurGroupUniqueIdKey] as? String else {
            owsFailDebug("Missing groupId.")
            return
        }
        guard groupUniqueId == state?.groupThreadId else {
            return
        }
        updateImageWithSneakyTransaction()
    }

    // MARK: -

    public func updateImageWithSneakyTransaction() {
        guard diameter > 0,
              nil != self.state else {
            self.image = nil
            return
        }
        databaseStorage.read { transaction in
            self.updateImage(transaction: transaction)
        }
    }

    public func updateImage(transaction: SDSAnyReadTransaction) {
        guard diameter > 0,
              let state = self.state else {
            self.image = nil
            return
        }

        let image = { () -> UIImage? in
            switch state {
            case .contact(let contactThread):
                return buildContactAvatar(address: contactThread.contactAddress,
                                          conversationColorName: contactThread.conversationColorName,
                                          transaction: transaction)
            case .group(let groupThread):
                return buildGroupAvatar(groupThread: groupThread, transaction: transaction)
            case .unknownContact(let contactAddress):
                let conversationColorName = TSContactThread.conversationColorName(forContactAddress: contactAddress,
                                                                                  transaction: transaction)
                return buildContactAvatar(address: contactAddress,
                                          conversationColorName: conversationColorName,
                                          transaction: transaction)
            }
        }()
        owsAssertDebug(image != nil)
        self.image = image
    }

    private func buildContactAvatar(address: SignalServiceAddress,
                                    conversationColorName: ConversationColorName,
                                    transaction: SDSAnyReadTransaction) -> UIImage? {
        let builder = OWSContactAvatarBuilder(address: address,
                                              colorName: conversationColorName,
                                              diameter: diameter,
                                              localUserAvatarMode: localUserAvatarMode,
                                              transaction: transaction)
        let shouldBlurAvatar = contactsManagerImpl.shouldBlurContactAvatar(address: address,
                                                                           transaction: transaction)
        return buildAvatar(avatarBuilder: builder,
                           shouldBlurAvatar: shouldBlurAvatar,
                           transaction: transaction)
    }

    private func buildGroupAvatar(groupThread: TSGroupThread,
                                  transaction: SDSAnyReadTransaction) -> UIImage? {
        let builder = OWSGroupAvatarBuilder(thread: groupThread,
                                            diameter: diameter)
        let shouldBlurAvatar = contactsManagerImpl.shouldBlurGroupAvatar(groupThread: groupThread,
                                                                           transaction: transaction)
        return buildAvatar(avatarBuilder: builder,
                           shouldBlurAvatar: shouldBlurAvatar,
                           transaction: transaction)
    }

    private func buildAvatar(avatarBuilder: OWSAvatarBuilder,
                             shouldBlurAvatar: Bool,
                             transaction: SDSAnyReadTransaction) -> UIImage? {
        guard let image = avatarBuilder.build(with: transaction) else {
            owsFailDebug("Could not build contact avatar.")
            return nil
        }
        if shouldBlurAvatar {
            return contactsManagerImpl.blurAvatar(image)
        } else {
            return image
        }
    }

    @objc
    public func reset() {
        self.state = nil
        self.image = nil
    }
}
