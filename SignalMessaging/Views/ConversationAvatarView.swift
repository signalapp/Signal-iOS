//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit

/// Avatar View which updates itself as necessary when the profile, contact, or group picture changes.
@objc
public class ConversationAvatarView: AvatarImageView {

    private struct Configuration: Equatable {
        let diameterPoints: UInt
        let localUserDisplayMode: LocalUserDisplayMode

        var diameterPixels: CGFloat {
            CGFloat(diameterPoints).pointsAsPixels
        }
    }
    private var configuration: Configuration

    // TODO: We eventually may be able to eliminate this property
    //       and always load async.
    @objc
    public var shouldLoadAsync: Bool

    @objc
    public var diameterPoints: UInt {
        configuration.diameterPoints
    }

    @objc
    public var localUserDisplayMode: LocalUserDisplayMode {
        configuration.localUserDisplayMode
    }

    private var content: ConversationContent? {
        didSet {
            ensureObservers()
        }
    }

    @objc
    public override var intrinsicContentSize: CGSize {
        .square(CGFloat(diameterPoints))
    }

    @objc
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        .square(CGFloat(diameterPoints))
    }

    private var heightConstraint: NSLayoutConstraint?
    private var widthConstraint: NSLayoutConstraint?

    @objc
    public required init(diameterPoints: UInt,
                         localUserDisplayMode: LocalUserDisplayMode,
                         shouldLoadAsync: Bool = true) {
        self.configuration = Configuration(diameterPoints: diameterPoints,
                                           localUserDisplayMode: localUserDisplayMode)
        self.shouldLoadAsync = shouldLoadAsync

        super.init(frame: .zero)

        self.heightConstraint = autoSetDimension(.height, toSize: CGFloat(diameterPoints))
        self.widthConstraint = autoSetDimension(.width, toSize: CGFloat(diameterPoints))
        setContentHuggingHigh()
        setCompressionResistanceHigh()
    }

    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    deinit {
        AssertIsOnMainThread()
    }

    // MARK: -

    // To avoid redundant/sneaky transctions, we want to apply all changes to
    // this view in a single go.  If we need to change the content and/or configuration
    // we should make sure those changes call this method just once.
    private func configure(content: ConversationContent,
                           configuration: Configuration,
                           transaction: SDSAnyReadTransaction) {
        AssertIsOnMainThread()

        let didDiameterChange = self.configuration.diameterPoints != configuration.diameterPoints
        let didLocalUserDisplayModeChange = self.configuration.localUserDisplayMode != configuration.localUserDisplayMode
        var shouldUpdateImage = self.content != content

        self.configuration = configuration
        self.content = content

        if didDiameterChange {
            DispatchMainThreadSafe { [weak self] in
                guard let self = self else { return }
                self.widthConstraint?.constant = CGFloat(configuration.diameterPoints)
                self.heightConstraint?.constant = CGFloat(configuration.diameterPoints)
                self.invalidateIntrinsicContentSize()
                self.setNeedsLayout()
            }
            shouldUpdateImage = true
        }

        if didLocalUserDisplayModeChange {
            shouldUpdateImage = true
        }

        if shouldUpdateImage {
            updateImage(transaction: transaction)
        }
    }

    private func configure(content: ConversationContent,
                           transaction: SDSAnyReadTransaction) {
        configure(content: content,
                  configuration: self.configuration,
                  transaction: transaction)
    }

    private func configureWithSneakyTransaction(content: ConversationContent) {
        databaseStorage.read { transaction in
            configure(content: content, transaction: transaction)
        }
    }

    @objc
    public func configureWithSneakyTransaction(thread: TSThread) {
        configureWithSneakyTransaction(content: ConversationContent.forThread(thread))
    }

    @objc
    public func configure(thread: TSThread, transaction: SDSAnyReadTransaction) {
        configure(content: ConversationContent.forThread(thread), transaction: transaction)
    }

    @objc
    public func configureWithSneakyTransaction(address: SignalServiceAddress) {
        databaseStorage.read { transaction in
            self.configure(address: address, transaction: transaction)
        }
    }

    @objc
    public func configure(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) {
        configure(address: address,
                  diameterPoints: diameterPoints,
                  localUserDisplayMode: localUserDisplayMode,
                  transaction: transaction)
    }

    @objc
    public func configure(address: SignalServiceAddress,
                          diameterPoints: UInt,
                          localUserDisplayMode: LocalUserDisplayMode,
                          transaction: SDSAnyReadTransaction) {
        configure(content: ConversationContent.forAddress(address, transaction: transaction),
                  diameterPoints: diameterPoints,
                  localUserDisplayMode: localUserDisplayMode,
                  transaction: transaction)
    }

    @objc
    public func configure(thread: TSThread,
                          diameterPoints: UInt,
                          localUserDisplayMode: LocalUserDisplayMode,
                          transaction: SDSAnyReadTransaction) {
        configure(content: ConversationContent.forThread(thread),
                  diameterPoints: diameterPoints,
                  localUserDisplayMode: localUserDisplayMode,
                  transaction: transaction)
    }

    public func configure(content: ConversationContent,
                          diameterPoints: UInt,
                          localUserDisplayMode: LocalUserDisplayMode,
                          transaction: SDSAnyReadTransaction) {
        let configuration = Configuration(diameterPoints: diameterPoints,
                                          localUserDisplayMode: localUserDisplayMode)
        configure(content: content,
                  configuration: configuration,
                  transaction: transaction)
    }

    // MARK: - Notifications

    private func ensureObservers() {
        NotificationCenter.default.removeObserver(self)

        guard let content = content else {
            return
        }

        switch content {
        case .contact, .unknownContact:
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(otherUsersProfileDidChange(notification:)),
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
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: .ThemeDidChange,
                                               object: nil)
    }

    @objc
    private func themeDidChange() {
        AssertIsOnMainThread()

        updateImageWithSneakyTransaction()
    }

    @objc
    private func handleSignalAccountsChanged(notification: Notification) {
        AssertIsOnMainThread()

        // PERF: It would be nice if we could do this only if *this* user's SignalAccount changed,
        // but currently this is only a course grained notification.

        updateImageWithSneakyTransaction()
    }

    @objc
    private func otherUsersProfileDidChange(notification: Notification) {
        AssertIsOnMainThread()

        guard let content = self.content else {
            return
        }
        guard let changedAddress = notification.userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress,
              changedAddress.isValid else {
            owsFailDebug("changedAddress was unexpectedly nil")
            return
        }
        guard let contactAddress = content.contactAddress else {
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

    @objc
    private func handleGroupAvatarChanged(notification: Notification) {
        AssertIsOnMainThread()

        guard let content = self.content else {
            return
        }
        guard let changedGroupThreadId = notification.userInfo?[TSGroupThread_NotificationKey_UniqueId] as? String else {
            owsFailDebug("groupThreadId was unexpectedly nil")
            return
        }
        guard let groupThreadId = content.groupThreadId else {
            // shouldn't call this for contact threads
            owsFailDebug("groupThreadId was unexpectedly nil")
            return
        }
        guard groupThreadId == changedGroupThreadId else {
            // not this avatar
            return
        }

        databaseStorage.read { transaction in
            self.content = content.reload(transaction: transaction)
            self.updateImage(transaction: transaction)
        }
    }

    @objc
    private func skipContactAvatarBlurDidChange(notification: Notification) {
        AssertIsOnMainThread()

        guard let content = self.content else {
            return
        }
        guard let address = notification.userInfo?[OWSContactsManager.skipContactAvatarBlurAddressKey] as? SignalServiceAddress,
              address.isValid else {
            owsFailDebug("Missing address.")
            return
        }
        guard address == content.contactAddress else {
            return
        }
        updateImageWithSneakyTransaction()
    }

    @objc
    private func skipGroupAvatarBlurDidChange(notification: Notification) {
        AssertIsOnMainThread()

        guard let groupUniqueId = notification.userInfo?[OWSContactsManager.skipGroupAvatarBlurGroupUniqueIdKey] as? String else {
            owsFailDebug("Missing groupId.")
            return
        }
        guard groupUniqueId == content?.groupThreadId else {
            return
        }
        updateImageWithSneakyTransaction()
    }

    // MARK: -

    public func updateImageWithSneakyTransaction() {
        updateImageAsync()
    }

    public func updateImage(transaction: SDSAnyReadTransaction) {
        AssertIsOnMainThread()

        if shouldLoadAsync {
            updateImageAsync()
        } else {
            self.image = Self.buildImage(configuration: configuration,
                                         content: content,
                                         transaction: transaction)
        }
    }

    private static let serialQueue = DispatchQueue(label: "org.signal.ConversationAvatarView")

    public func updateImageAsync() {
        AssertIsOnMainThread()

        let configuration = self.configuration
        guard configuration.diameterPoints > 0,
              let content = self.content else {
            self.image = nil
            return
        }
        Self.serialQueue.async { [weak self] in
            let image: UIImage? = Self.databaseStorage.read { transaction in
                Self.buildImage(configuration: configuration, content: content, transaction: transaction)
            }
            DispatchQueue.main.async {
                guard let self = self else {
                    return
                }
                guard self.configuration == configuration,
                      self.content == content else {
                    // Discard stale loads.
                    return
                }
                guard let image = image else {
                    self.image = nil
                    return
                }
                self.image = image
            }
        }
    }

    private static func buildImage(configuration: Configuration,
                                   content: ConversationContent?,
                                   transaction: SDSAnyReadTransaction) -> UIImage? {
        let diameterPoints = configuration.diameterPoints
        guard diameterPoints > 0,
              let content = content else {
            return nil
        }

        guard let image = { () -> UIImage? in
            switch content {
            case .contact(let contactThread):
                return buildContactAvatar(address: contactThread.contactAddress,
                                          configuration: configuration,
                                          transaction: transaction)
            case .group(let groupThread):
                return buildGroupAvatar(groupThread: groupThread,
                                        configuration: configuration,
                                        transaction: transaction)
            case .unknownContact(let contactAddress):
                return buildContactAvatar(address: contactAddress,
                                          configuration: configuration,
                                          transaction: transaction)
            }
        }() else {
            owsFailDebug("Could not build avatar image.")
            return nil
        }
        let targetSizePixels = configuration.diameterPixels
        guard CGFloat(image.pixelWidth) <= targetSizePixels,
              CGFloat(image.pixelHeight) <= targetSizePixels else {
            let resizedImage = image.resizedImage(toFillPixelSize: .square(targetSizePixels))
            return resizedImage
        }
        return image
    }

    private static func buildContactAvatar(address: SignalServiceAddress,
                                           configuration: Configuration,
                                           transaction: SDSAnyReadTransaction) -> UIImage? {
        Self.avatarBuilder.avatarImage(forAddress: address,
                                       diameterPoints: configuration.diameterPoints,
                                       localUserDisplayMode: configuration.localUserDisplayMode,
                                       transaction: transaction)
    }

    private static func buildGroupAvatar(groupThread: TSGroupThread,
                                         configuration: Configuration,
                                         transaction: SDSAnyReadTransaction) -> UIImage? {
        Self.avatarBuilder.avatarImage(forGroupThread: groupThread,
                                       diameterPoints: configuration.diameterPoints,
                                       transaction: transaction)
    }

    @objc
    public func reset() {
        AssertIsOnMainThread()

        self.content = nil
        self.image = nil
    }
}

// MARK: -

// Represents a real or potential conversation.
public enum ConversationContent: Equatable, Dependencies {
    case contact(contactThread: TSContactThread)
    case group(groupThread: TSGroupThread)
    case unknownContact(contactAddress: SignalServiceAddress)

    static func forThread(_ thread: TSThread) -> ConversationContent {
        if let contactThread = thread as? TSContactThread {
            return .contact(contactThread: contactThread)
        } else if let groupThread = thread as? TSGroupThread {
            return .group(groupThread: groupThread)
        } else {
            owsFail("Invalid thread.")
        }
    }

    static func forAddress(_ address: SignalServiceAddress,
                           transaction: SDSAnyReadTransaction) -> ConversationContent {
        if let contactThread = TSContactThread.getWithContactAddress(address,
                                                                     transaction: transaction) {
            return .contact(contactThread: contactThread)
        } else {
            return .unknownContact(contactAddress: address)
        }
    }

    public var contactAddress: SignalServiceAddress? {
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

    func reloadWithSneakyTransaction() -> ConversationContent {
        databaseStorage.read { transaction in
            reload(transaction: transaction)
        }
    }

    func reload(transaction: SDSAnyReadTransaction) -> ConversationContent {
        if let contactAddress = self.contactAddress {
            return Self.forAddress(contactAddress, transaction: transaction)
        } else {
            guard let thread = self.thread else {
                return self
            }
            guard let latestThread = TSThread.anyFetch(uniqueId: thread.uniqueId,
                                                       transaction: transaction) else {
                owsFailDebug("Missing thread.")
                return self
            }
            return ConversationContent.forThread(latestThread)
        }
    }

    // MARK: - Equatable

    public static func == (lhs: ConversationContent, rhs: ConversationContent) -> Bool {
        switch lhs {
        case .contact(let contactThreadLhs):
            switch rhs {
            case .contact(let contactThreadRhs):
                return contactThreadLhs.contactAddress == contactThreadRhs.contactAddress
            default:
                return false
            }
        case .group(let groupThreadLhs):
            switch rhs {
            case .group(let groupThreadRhs):
                return groupThreadLhs.groupId == groupThreadRhs.groupId
            default:
                return false
            }
        case .unknownContact(let contactAddressLhs):
            switch rhs {
            case .unknownContact(let contactAddressRhs):
                return contactAddressLhs == contactAddressRhs
            default:
                return false
            }
        }
    }
}
