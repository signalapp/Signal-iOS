//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class AvatarImageView: UIImageView {

    private let shadowLayer = CAShapeLayer()

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

    override init(image: UIImage?) {
        super.init(image: image)
        self.configureView()
    }

    func configureView() {
        self.autoPinToSquareAspectRatio()

        self.layer.minificationFilter = kCAFilterTrilinear
        self.layer.magnificationFilter = kCAFilterTrilinear
        self.layer.masksToBounds = true

        self.layer.addSublayer(self.shadowLayer)

        self.contentMode = .scaleToFill
    }

    override public func layoutSubviews() {
        self.layer.cornerRadius = self.frame.size.width / 2

        // Inner shadow.
        // This should usually not be visible; it is used to distinguish
        // profile pics from the background if they are similar.
        self.shadowLayer.frame = self.bounds
        self.shadowLayer.masksToBounds = true
        let shadowBounds = self.bounds
        let shadowPath = UIBezierPath(ovalIn: shadowBounds)
        // This can be any value large enough to cast a sufficiently large shadow.
        let shadowInset: CGFloat = -3
        shadowPath.append(UIBezierPath(rect: shadowBounds.insetBy(dx: shadowInset, dy: shadowInset)))
        // This can be any color since the fill should be clipped.
        self.shadowLayer.fillColor = UIColor.black.cgColor
        self.shadowLayer.path = shadowPath.cgPath
        self.shadowLayer.fillRule = kCAFillRuleEvenOdd
        self.shadowLayer.shadowColor = (Theme.isDarkThemeEnabled ? UIColor.white : UIColor.black).cgColor
        self.shadowLayer.shadowRadius = 0.5
        self.shadowLayer.shadowOpacity = 0.15
        self.shadowLayer.shadowOffset = .zero
    }
}

/// Avatar View which updates itself as necessary when the profile, contact, or group picture changes.
@objc
public class ConversationAvatarImageView: AvatarImageView {

    let thread: TSThread
    let diameter: UInt
    let contactsManager: OWSContactsManager

    // nil if group avatar
    let recipientId: String?

    // nil if contact avatar
    let groupThreadId: String?

    required public init(thread: TSThread, diameter: UInt, contactsManager: OWSContactsManager) {
        self.thread = thread
        self.diameter = diameter
        self.contactsManager = contactsManager

        switch thread {
        case let contactThread as TSContactThread:
            self.recipientId = contactThread.contactIdentifier()
            self.groupThreadId = nil
        case let groupThread as TSGroupThread:
            self.recipientId = nil
            self.groupThreadId = groupThread.uniqueId
        default:
            owsFailDebug("unexpected thread type: \(thread)")
            self.recipientId = nil
            self.groupThreadId = nil
        }

        super.init(frame: .zero)

        if recipientId != nil {
            NotificationCenter.default.addObserver(self, selector: #selector(handleOtherUsersProfileChanged(notification:)), name: NSNotification.Name(rawValue: kNSNotificationName_OtherUsersProfileDidChange), object: nil)

            NotificationCenter.default.addObserver(self, selector: #selector(handleSignalAccountsChanged(notification:)), name: NSNotification.Name.OWSContactsManagerSignalAccountsDidChange, object: nil)
        }

        if groupThreadId != nil {
            NotificationCenter.default.addObserver(self, selector: #selector(handleGroupAvatarChanged(notification:)), name: .TSGroupThreadAvatarChanged, object: nil)
        }

        // TODO group avatar changed
        self.updateImage()
    }

    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc func handleSignalAccountsChanged(notification: Notification) {
        Logger.debug("")

        // PERF: It would be nice if we could do this only if *this* user's SignalAccount changed,
        // but currently this is only a course grained notification.

        self.updateImage()
    }

    @objc func handleOtherUsersProfileChanged(notification: Notification) {
        Logger.debug("")

        guard let changedRecipientId = notification.userInfo?[kNSNotificationKey_ProfileRecipientId] as? String else {
            owsFailDebug("recipientId was unexpectedly nil")
            return
        }

        guard let recipientId = self.recipientId else {
            // shouldn't call this for group threads
            owsFailDebug("contactId was unexpectedly nil")
            return
        }

        guard recipientId == changedRecipientId else {
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

        thread.reload()

        self.updateImage()
    }

    public func updateImage() {
        Logger.debug("updateImage")

        self.image = OWSAvatarBuilder.buildImage(thread: thread, diameter: diameter)
    }
}
