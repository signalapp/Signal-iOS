//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit
import SignalMessaging

public class ConversationAvatarView: UIView, CVView, PrimaryImageView {

    public required init(
        sizeClass: Configuration.SizeClass,
        localUserDisplayMode: LocalUserDisplayMode = .asUser,
        badged: Bool = false,
        shape: Configuration.Shape = .circular,
        useAutolayout: Bool = true
    ) {
        var shouldBadgeResolved: Bool
        if case Configuration.SizeClass.custom = sizeClass {
            owsAssertDebug(badged == false, "Badging not supported with custom size classes")
            shouldBadgeResolved = false
        } else {
            shouldBadgeResolved = badged
        }

        self.configuration = Configuration(
            sizeClass: sizeClass,
            dataSource: nil,
            localUserDisplayMode: localUserDisplayMode,
            addBadgeIfApplicable: shouldBadgeResolved,
            shape: shape,
            useAutolayout: useAutolayout)

        super.init(frame: .zero)
        
        addSubview(avatarView)
        addSubview(badgeView)
        autoresizesSubviews = false
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Configuration API

    public struct Configuration: Equatable {
        public enum SizeClass: Equatable {
            case tiny   // 28x28
            case small  // 36x36
            case medium // 56x56
            case large  // 80x80
            case xlarge // 88x88

            // Badges are not available when using a custom size class
            case custom(UInt)
        }

        public enum Shape {
            case rectangular
            case circular
        }

        public var sizeClass: SizeClass
        public var dataSource: ConversationContent?
        public var localUserDisplayMode: LocalUserDisplayMode
        public var addBadgeIfApplicable: Bool

        public var shape: Shape
        public var useAutolayout: Bool
    }

    public private(set) var configuration: Configuration {
        didSet {
            AssertIsOnMainThread()
            if configuration.addBadgeIfApplicable, case Configuration.SizeClass.custom = configuration.sizeClass {
                owsFailDebug("Invalid configuration. Badging not supported with custom size classes")
                configuration.addBadgeIfApplicable = false
            }

            // We may need to update our model, layout, or constraints based on the changes to the configuration
            let sizeClassDidChange = configuration.sizeClass != oldValue.sizeClass
            let dataSourceDidChange = configuration.dataSource != oldValue.dataSource
            let localUserDisplayModeDidChange = configuration.localUserDisplayMode != oldValue.localUserDisplayMode
            let shouldShowBadgeDidChange = configuration.addBadgeIfApplicable != oldValue.addBadgeIfApplicable
            let shapeDidChange = configuration.shape != oldValue.shape
            let autolayoutDidChange = configuration.useAutolayout != oldValue.useAutolayout

            // Any changes to avatar size or provider will trigger a model update
            if sizeClassDidChange || dataSourceDidChange || localUserDisplayModeDidChange || shouldShowBadgeDidChange {
                setNeedsModelUpdate()
            }

            // If autolayout was toggled, or the size changed while autolayout is enabled we need to update our constraints
            if autolayoutDidChange || (configuration.useAutolayout && sizeClassDidChange) {
                setNeedsUpdateConstraints()
            }

            if sizeClassDidChange || shouldShowBadgeDidChange || shapeDidChange {
                setNeedsLayout()
            }
        }
    }

    public enum UpdateBehavior {
        case synchronously
        case asynchronously
    }

    public func updateWithSneakyTransaction(_ block: (inout Configuration) -> UpdateBehavior) {
        databaseStorage.read { update($0, block) }
    }

    /// To reduce the occurrence of unnecessary avatar fetches, updates to the view configuration occur in a closure
    /// Callers can specify a synchronous or asynchronous model update through the closure's return value
    public func update(_ transaction: SDSAnyReadTransaction, _ block: (inout Configuration) -> UpdateBehavior) {
        AssertIsOnMainThread()

        let oldConfiguration = configuration
        var mutableConfig = oldConfiguration
        let updateBehavior = block(&mutableConfig)
        configuration = mutableConfig
        updateModelIfNecessary(updateBehavior, transaction: transaction)
    }

    // Forces a model update
    private func updateModel(_ behavior: UpdateBehavior, transaction readTx: SDSAnyReadTransaction) {
        setNeedsModelUpdate()
        updateModelIfNecessary(behavior, transaction: readTx)
    }

    // If the model has been dirtied, performs an update
    // If an async update is requested, the model is updated immediately with any available chached content
    // followed by enqueueing a full model update on a background thread.
    private func updateModelIfNecessary(_ behavior: UpdateBehavior, transaction readTx: SDSAnyReadTransaction) {
        AssertIsOnMainThread()

        guard nextModelGeneration.get() > currentModelGeneration else { return }
        guard let dataSource = configuration.dataSource else {
            updateViewContent(avatarImage: nil, badgeImage: nil)
            return
        }

        switch behavior {
        case .synchronously:
            let avatarImage = dataSource.buildImage(configuration: configuration, transaction: readTx)
            let badgeImage = dataSource.fetchBadge(configuration: configuration, transaction: readTx)
            updateViewContent(avatarImage: avatarImage, badgeImage: badgeImage)

        case .asynchronously:
            let avatarImage = dataSource.fetchCachedImage(configuration: configuration, transaction: readTx)
            let badgeImage = dataSource.fetchBadge(configuration: configuration, transaction: readTx)
            updateViewContent(avatarImage: avatarImage, badgeImage: badgeImage)

            enqueueAsyncModelUpdate()
        }
    }

    private func updateViewContent(avatarImage: UIImage?, badgeImage: UIImage?) {
        AssertIsOnMainThread()

        self.avatarView.image = avatarImage
        self.badgeView.image = badgeImage
        currentModelGeneration = nextModelGeneration.get()
    }

    // MARK: - Model Tracking

    // Invoking `setNeedsModelUpdate()` increments the next model generation
    // Any updates to the model copy the `nextModelGeneration` to the currentModelGeneration
    // For synchronous updates, these happen in lockstep on the main thread
    // For async model updates, this helps with detecting parallel model changes on another thread
    // `nextModelGeneration` can be read on a background thread, so it needs to be atomic.
    // All updates are performed on the main thread.
    private var currentModelGeneration: UInt = 0
    private var nextModelGeneration = AtomicUInt(0)
    private func setNeedsModelUpdate() {
        AssertIsOnMainThread()
        nextModelGeneration.increment()
    }

    // Load avatars in _reverse_ order in which they are enqueued.
    // Avatars are enqueued as the user navigates (and not cancelled),
    // so the most recently enqueued avatars are most likely to be
    // visible. To put it another way, we don't cancel loads so
    // the oldest loads are most likely to be unnecessary.
    private static let serialQueue = ReverseDispatchQueue(label: "org.signal.ConversationAvatarView")

    private func enqueueAsyncModelUpdate() {
        AssertIsOnMainThread()
        setNeedsModelUpdate()
        let generationAtEnqueue = nextModelGeneration.get()
        let configurationAtEnqueue = configuration

        Self.serialQueue.async { [weak self] in
            guard let self = self, self.nextModelGeneration.get() == generationAtEnqueue else { return }

            let (updatedAvatar, updatedBadge) = Self.databaseStorage.read { transaction -> (UIImage?, UIImage?) in
                let avatarImage = configurationAtEnqueue.dataSource?.buildImage(configuration: configurationAtEnqueue, transaction: transaction)
                let badgeImage = configurationAtEnqueue.dataSource?.fetchBadge(configuration: configurationAtEnqueue, transaction: transaction)
                return (avatarImage, badgeImage)
            }

            DispatchQueue.main.async {
                // Drop stale loads
                guard self.nextModelGeneration.get() == generationAtEnqueue else { return }
                self.updateViewContent(avatarImage: updatedAvatar, badgeImage: updatedBadge)
            }
        }
    }

    // MARK: Subviews and Layout

    private var avatarView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.layer.minificationFilter = .trilinear
        view.layer.magnificationFilter = .trilinear
        return view
    }()

    private var badgeView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        return view
    }()

    private var sizeConstraints: (width: NSLayoutConstraint, height: NSLayoutConstraint)? = nil
    override public func updateConstraints() {
        let targetSize = configuration.sizeClass.avatarSize

        switch (configuration.useAutolayout, sizeConstraints) {
        case (true, let constraints?):
            constraints.width.constant = targetSize.width
            constraints.height.constant = targetSize.height
        case (true, nil):
            sizeConstraints = (width: autoSetDimension(.width, toSize: targetSize.width),
                               height: autoSetDimension(.height, toSize: targetSize.height))
        case (false, _):
            if let sizeConstraints = sizeConstraints {
                NSLayoutConstraint.deactivate([sizeConstraints.width, sizeConstraints.height])
            }
            sizeConstraints = nil
        }

        super.updateConstraints()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        switch configuration.sizeClass {
        case .tiny, .small, .medium, .large, .xlarge:
            // If we're using a predefined size class, we can layout the avatar and badge based on its parameters
            // Everything is aligned to the top left, and that's okay because of the sizing contract asserted below
            avatarView.frame = CGRect(origin: .zero, size: configuration.sizeClass.avatarSize)
            badgeView.frame = CGRect(origin: configuration.sizeClass.badgeOffset, size: configuration.sizeClass.badgeSize)
            badgeView.isHidden = (badgeView.image == nil)

            // The superview is responsibile for ensuring our size is correct. If it's not, layout may appear incorrect
            owsAssertDebug(bounds.size == configuration.sizeClass.avatarSize)

        case .custom:
            // With a custom size, we will layout everything to fit our superview's layout
            // Badge views will always be hidden
            avatarView.frame = bounds
            badgeView.frame = .zero
            badgeView.isHidden = true
        }

        switch configuration.shape {
        case .circular:
            avatarView.layer.cornerRadius = (avatarView.bounds.height / 2)
            avatarView.layer.masksToBounds = true
        case .rectangular:
            avatarView.layer.cornerRadius = 0
            avatarView.layer.masksToBounds = false
        }
    }

    @objc
    public override var intrinsicContentSize: CGSize { configuration.sizeClass.avatarSize }

    @objc
    public override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    // MARK: Notifications

    private func ensureObservers() {
        // TODO: Badges — Notify on an updated badge asset?

        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: .ThemeDidChange,
                                               object: nil)

        guard let dataSource = configuration.dataSource else { return }
        switch dataSource {
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
        case .other: break
        }
    }

    @objc
    private func themeDidChange() {
        AssertIsOnMainThread()

        databaseStorage.read { readTx in
            updateModel(.asynchronously, transaction: readTx)
        }
    }

    @objc
    private func handleSignalAccountsChanged(notification: Notification) {
        AssertIsOnMainThread()

        // PERF: It would be nice if we could do this only if *this* user's SignalAccount changed,
        // but currently this is only a course grained notification.
        databaseStorage.read { readTx in
            updateModel(.asynchronously, transaction: readTx)
        }
    }

    @objc
    private func otherUsersProfileDidChange(notification: Notification) {
        AssertIsOnMainThread()
        guard let changedAddress = notification.userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress, changedAddress.isValid else {
            owsFailDebug("changedAddress was unexpectedly nil")
            return
        }
        handleUpdatedAddressNotification(address: changedAddress)
    }

    @objc
    private func skipContactAvatarBlurDidChange(notification: Notification) {
        AssertIsOnMainThread()
        guard let address = notification.userInfo?[OWSContactsManager.skipContactAvatarBlurAddressKey] as? SignalServiceAddress, address.isValid else {
            owsFailDebug("Missing address.")
            return
        }
        handleUpdatedAddressNotification(address: address)
    }

    private func handleUpdatedAddressNotification(address: SignalServiceAddress) {
        AssertIsOnMainThread()
        guard let dataSource = configuration.dataSource else { return }
        guard let providerAddress = dataSource.contactAddress else {
            // Should always be set for non-group thread avatar providers
            owsFailDebug("contactAddress was unexpectedly nil")
            return
        }

        if providerAddress == address {
            databaseStorage.read { updateModel(.asynchronously, transaction: $0) }
        }
    }

    @objc
    private func handleGroupAvatarChanged(notification: Notification) {
        AssertIsOnMainThread()
        guard let changedGroupThreadId = notification.userInfo?[TSGroupThread_NotificationKey_UniqueId] as? String else {
            owsFailDebug("groupThreadId was unexpectedly nil")
            return
        }
        handleUpdatedGroupThreadNotification(changedThreadId: changedGroupThreadId)
    }

    @objc
    private func skipGroupAvatarBlurDidChange(notification: Notification) {
        AssertIsOnMainThread()
        guard let groupThreadId = notification.userInfo?[OWSContactsManager.skipGroupAvatarBlurGroupUniqueIdKey] as? String else {
            owsFailDebug("Missing groupId.")
            return
        }
        handleUpdatedGroupThreadNotification(changedThreadId: groupThreadId)
    }

    private func handleUpdatedGroupThreadNotification(changedThreadId: String) {
        AssertIsOnMainThread()
        guard let dataSource = configuration.dataSource else { return }
        guard let contentThreadId = dataSource.groupThreadId else {
            // Should always be set for non-group thread avatar providers
            owsFailDebug("contactAddress was unexpectedly nil")
            return
        }

        if contentThreadId == changedThreadId {
            databaseStorage.read {
                configuration.dataSource = dataSource.reload(transaction: $0)
                updateModel(.asynchronously, transaction: $0)
            }
        }
    }

    // MARK: - <CVView>

    public func reset() {
        badgeView.image = nil
        avatarView.image = nil
        configuration.dataSource = nil
    }

    // MARK: - <PrimaryImageView>

    public var primaryImage: UIImage? { avatarView.image }
}

// MARK: -

// Represents a real or potential conversation.
public enum ConversationContent: Equatable, Dependencies {
    // TODO: Badges — This isn't necessarily converation only. This should all be renamed to drop
    // the "conversation" prefix
    case contact(contactThread: TSContactThread)
    case group(groupThread: TSGroupThread)
    case unknownContact(contactAddress: SignalServiceAddress)
    case other(avatar: UIImage?, badge: UIImage?)

    static public func forThread(_ thread: TSThread) -> ConversationContent {
        if let contactThread = thread as? TSContactThread {
            return .contact(contactThread: contactThread)
        } else if let groupThread = thread as? TSGroupThread {
            return .group(groupThread: groupThread)
        } else {
            owsFail("Invalid thread.")
        }
    }

    static public func forAddress(_ address: SignalServiceAddress,
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
        case .other:
            return nil
        }
    }

    fileprivate var groupThreadId: String? {
        switch self {
        case .contact:
            return nil
        case .group(let groupThread):
            return groupThread.uniqueId
        case .unknownContact:
            return nil
        case .other:
            return nil
        }
    }

    fileprivate var thread: TSThread? {
        switch self {
        case .contact(let contactThread):
            return contactThread
        case .group(let groupThread):
            return groupThread
        case .unknownContact:
            return nil
        case .other:
            return nil
        }
    }

    fileprivate func reload(transaction: SDSAnyReadTransaction) -> ConversationContent {
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

    // TODO: Badges — Should this be async?
    fileprivate func fetchBadge(configuration: ConversationAvatarView.Configuration, transaction: SDSAnyReadTransaction) -> UIImage? {
        if case let .other(_, badge) = self {
            return badge
        }

        guard let profileAddress = self.contactAddress else { return nil }
        guard configuration.addBadgeIfApplicable else { return nil }

        let userProfile: OWSUserProfile?
        if profileAddress.isLocalAddress {
            // TODO: Badges — Expose badge info about local user profile on OWSUserProfile
            userProfile = OWSProfileManager.shared.localUserProfile()
        } else {
            userProfile = AnyUserProfileFinder().userProfile(for: profileAddress, transaction: transaction)
        }
        let primaryBadge = userProfile?.primaryBadge?.fetchBadgeContent(transaction: transaction)
        guard let badgeAssets = primaryBadge?.assets else { return nil }

        switch configuration.sizeClass {
        case .tiny, .small:
            return Theme.isDarkThemeEnabled ? badgeAssets.dark16 : badgeAssets.light16
        case .medium:
            return Theme.isDarkThemeEnabled ? badgeAssets.dark24 : badgeAssets.light24
        case .large, .xlarge:
            return Theme.isDarkThemeEnabled ? badgeAssets.dark36 : badgeAssets.light36
        case .custom:
            // We never vend badges if it's not one of the blessed sizes
            owsFailDebug("")
            return nil
        }
    }

    fileprivate func buildImage(configuration: ConversationAvatarView.Configuration, transaction: SDSAnyReadTransaction) -> UIImage? {
        switch self {
        case .contact(contactThread: let thread):
            return Self.avatarBuilder.avatarImage(
                forAddress: thread.contactAddress,
                diameterPoints: UInt(configuration.sizeClass.avatarSize.largerAxis),
                localUserDisplayMode: configuration.localUserDisplayMode,
                transaction: transaction)

        case .unknownContact(contactAddress: let address):
            return Self.avatarBuilder.avatarImage(
                forAddress: address,
                diameterPoints: UInt(configuration.sizeClass.avatarSize.largerAxis),
                localUserDisplayMode: configuration.localUserDisplayMode,
                transaction: transaction)

        case .group(groupThread: let thread):
            return Self.avatarBuilder.avatarImage(
                forGroupThread: thread,
                diameterPoints: UInt(configuration.sizeClass.avatarSize.largerAxis),
                transaction: transaction)
        case .other(let avatar, _):
            return avatar
        }
    }

    fileprivate func fetchCachedImage(configuration: ConversationAvatarView.Configuration, transaction: SDSAnyReadTransaction) -> UIImage? {
        switch self {
        case .contact(contactThread: let thread):
            return Self.avatarBuilder.precachedAvatarImage(
                forAddress: thread.contactAddress,
                diameterPoints: UInt(configuration.sizeClass.avatarSize.largerAxis),
                localUserDisplayMode: configuration.localUserDisplayMode,
                transaction: transaction)

        case .unknownContact(contactAddress: let address):
            return Self.avatarBuilder.precachedAvatarImage(
                forAddress: address,
                diameterPoints: UInt(configuration.sizeClass.avatarSize.largerAxis),
                localUserDisplayMode: configuration.localUserDisplayMode,
                transaction: transaction)

        case .group(groupThread: let thread):
            return Self.avatarBuilder.precachedAvatarImage(
                forGroupThread: thread,
                diameterPoints: UInt(configuration.sizeClass.avatarSize.largerAxis),
                transaction: transaction)
        case .other(let avatar, _):
            return avatar
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
        case .other(let avatarLHS, let badgeLHS):
            switch rhs {
            case .other(let avatarRHS, let badgeRHS):
                return avatarLHS == avatarRHS && badgeLHS == badgeRHS
            default:
                return false
            }
        }
    }
}

extension ConversationAvatarView.Configuration.SizeClass {
    /// The size of the avatar image and the target size of the AvatarImageView
    public var avatarSize: CGSize {
        switch self {
        case .tiny: return CGSize(square: 28)
        case .small: return CGSize(square: 36)
        case .medium: return CGSize(square: 56)
        case .large: return CGSize(square: 80)
        case .xlarge: return CGSize(square: 88)
        case .custom(let diameter): return CGSize(square: CGFloat(diameter))
        }
    }

    /// The badge offset from its frame origin. Design has specified these points so the badge sits right alongside the circular avatar edge
    var badgeOffset: CGPoint {
        switch self {
        case .tiny: return CGPoint(x: 14, y: 16)
        case .small: return CGPoint(x: 20, y: 23)
        case .medium: return CGPoint(x: 32, y: 38)
        case .large: return CGPoint(x: 44, y: 52)
        case .xlarge: return CGPoint(x: 49, y: 56)
        case .custom: return .zero
        }
    }

    /// The badge size
    var badgeSize: CGSize {
        switch self {
        case .tiny, .small: return CGSize(square: 16)
        case .medium: return CGSize(square: 24)
        case .large, .xlarge: return CGSize(square: 36)
        case .custom: return .zero
        }
    }
}
