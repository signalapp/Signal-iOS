//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class AvatarImageView: UIImageView {

    public init() {
        super.init(frame: .zero)
        self.configureView()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.configureView()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.configureView()
    }

    public override init(image: UIImage?) {
        super.init(image: image)
        self.configureView()
    }

    func configureView() {
        self.autoPinToSquareAspectRatio()

        self.layer.minificationFilter = .trilinear
        self.layer.magnificationFilter = .trilinear
        self.layer.masksToBounds = true

        self.contentMode = .scaleToFill
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = frame.size.width / 2
    }
}

/// Avatar View which updates itself as necessary when the profile, contact, or group picture changes.
@objc
public class ConversationAvatarImageView: AvatarImageView {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    let thread: TSThread
    let diameter: UInt
    let contactsManager: OWSContactsManager

    // nil if group avatar
    let recipientAddress: SignalServiceAddress?

    // nil if contact avatar
    let groupThreadId: String?

    required public init(thread: TSThread, diameter: UInt, contactsManager: OWSContactsManager) {
        self.thread = thread
        self.diameter = diameter
        self.contactsManager = contactsManager

        switch thread {
        case let contactThread as TSContactThread:
            self.recipientAddress = contactThread.contactAddress
            self.groupThreadId = nil
        case let groupThread as TSGroupThread:
            self.recipientAddress = nil
            self.groupThreadId = groupThread.uniqueId
        default:
            owsFailDebug("unexpected thread type: \(thread)")
            self.recipientAddress = nil
            self.groupThreadId = nil
        }

        super.init(frame: .zero)

        if recipientAddress != nil {
            NotificationCenter.default.addObserver(self, selector: #selector(handleOtherUsersProfileChanged(notification:)), name: .otherUsersProfileDidChange, object: nil)

            NotificationCenter.default.addObserver(self, selector: #selector(handleSignalAccountsChanged(notification:)), name: .OWSContactsManagerSignalAccountsDidChange, object: nil)
        }

        if groupThreadId != nil {
            NotificationCenter.default.addObserver(self, selector: #selector(handleGroupAvatarChanged(notification:)), name: .TSGroupThreadAvatarChanged, object: nil)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .ThemeDidChange, object: nil)

        // TODO group avatar changed
        self.updateImage()
    }

    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc func themeDidChange() {
        updateImage()
    }

    @objc func handleSignalAccountsChanged(notification: Notification) {
        Logger.debug("")

        // PERF: It would be nice if we could do this only if *this* user's SignalAccount changed,
        // but currently this is only a course grained notification.

        self.updateImage()
    }

    @objc func handleOtherUsersProfileChanged(notification: Notification) {
        Logger.debug("")

        guard let changedAddress = notification.userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress else {
            owsFailDebug("changedAddress was unexpectedly nil")
            return
        }

        guard let recipientAddress = self.recipientAddress else {
            // shouldn't call this for group threads
            owsFailDebug("recipientAddress was unexpectedly nil")
            return
        }

        guard recipientAddress == changedAddress else {
            // not this avatar
            return
        }

        self.updateImage()
    }

    @objc func handleGroupAvatarChanged(notification: Notification) {
        Logger.debug("")

        guard let changedGroupThreadId = notification.userInfo?[TSGroupThread_NotificationKey_UniqueId] as? String else {
            owsFailDebug("groupThreadId was unexpectedly nil")
            return
        }

        guard let groupThreadId = self.groupThreadId else {
            // shouldn't call this for contact threads
            owsFailDebug("groupThreadId was unexpectedly nil")
            return
        }

        guard groupThreadId == changedGroupThreadId else {
            // not this avatar
            return
        }

        databaseStorage.read { transaction in
            self.thread.anyReload(transaction: transaction)
        }

        self.updateImage()
    }

    public func updateImage() {
        Logger.debug("updateImage")

        self.image = OWSAvatarBuilder.buildImage(thread: thread, diameter: diameter)
    }
}

@objc
public class AvatarImageButton: UIButton {

    // MARK: - Button Overrides

    override public func layoutSubviews() {
        super.layoutSubviews()

        layer.cornerRadius = frame.size.width / 2
    }

    override public func setImage(_ image: UIImage?, for state: UIControl.State) {
        ensureViewConfigured()
        super.setImage(image, for: state)
    }

    // MARK: Private

    var hasBeenConfigured = false
    func ensureViewConfigured() {
        guard !hasBeenConfigured else {
            return
        }
        hasBeenConfigured = true

        autoPinToSquareAspectRatio()

        layer.minificationFilter = .trilinear
        layer.magnificationFilter = .trilinear
        layer.masksToBounds = true

        contentMode = .scaleToFill
    }
}
