//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
open class AvatarImageView: UIImageView {

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

    var thread: TSThread
    let diameter: UInt

    // nil if group avatar
    let recipientAddress: SignalServiceAddress?

    // nil if contact avatar
    let groupThreadId: String?

    required public init(thread: TSThread, diameter: UInt) {
        self.thread = thread
        self.diameter = diameter

        switch thread {
        case let contactThread as TSContactThread:
            self.recipientAddress = contactThread.contactAddress
            self.groupThreadId = nil
        case let groupThread as TSGroupThread:
            self.recipientAddress = nil
            self.groupThreadId = groupThread.uniqueId
        default:
            owsFailDebug("unexpected thread type: \(thread.uniqueId)")
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
        self.updateImageWithSneakyTransaction()
    }

    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc func themeDidChange() {
        updateImageWithSneakyTransaction()
    }

    @objc func handleSignalAccountsChanged(notification: Notification) {
        Logger.debug("")

        // PERF: It would be nice if we could do this only if *this* user's SignalAccount changed,
        // but currently this is only a course grained notification.

        self.updateImageWithSneakyTransaction()
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

        self.updateImageWithSneakyTransaction()
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

        guard let latestThread = (databaseStorage.read { transaction in
            TSThread.anyFetch(uniqueId: self.thread.uniqueId, transaction: transaction)
        }) else {
            owsFailDebug("Missing thread.")
            return
        }
        self.thread = latestThread

        self.updateImageWithSneakyTransaction()
    }

    public func updateImageWithSneakyTransaction() {
        databaseStorage.read { transaction in
            self.updateImage(transaction: transaction)
        }
    }

    public func updateImage(transaction: SDSAnyReadTransaction) {
        Logger.debug("updateImage")

        self.image = OWSAvatarBuilder.buildImage(thread: thread,
                                                 diameter: diameter,
                                                 transaction: transaction)
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
