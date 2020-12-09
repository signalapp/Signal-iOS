//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalRingRTC

protocol GroupCallMemberViewDelegate: class {
    func memberView(_: GroupCallMemberView, userRequestedInfoAboutError: GroupCallMemberView.ErrorState)
}

class GroupCallMemberView: UIView {
    weak var delegate: GroupCallMemberViewDelegate?
    let noVideoView = UIView()

    let backgroundAvatarView = UIImageView()
    let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    let muteIndicatorImage = UIImageView()

    lazy var muteLeadingConstraint = muteIndicatorImage.autoPinEdge(toSuperviewEdge: .leading, withInset: muteInsets)
    lazy var muteBottomConstraint = muteIndicatorImage.autoPinEdge(toSuperviewEdge: .bottom, withInset: muteInsets)
    lazy var muteHeightConstraint = muteIndicatorImage.autoSetDimension(.height, toSize: muteHeight)

    var muteInsets: CGFloat {
        layoutIfNeeded()

        if width > 102 {
            return 9
        } else {
            return 4
        }
    }

    var muteHeight: CGFloat {
        layoutIfNeeded()

        if width > 200 && UIDevice.current.isIPad {
            return 20
        } else {
            return 16
        }
    }

    init() {
        super.init(frame: .zero)

        backgroundColor = .ows_gray90
        clipsToBounds = true

        addSubview(noVideoView)
        noVideoView.autoPinEdgesToSuperviewEdges()

        let overlayView = UIView()
        overlayView.backgroundColor = .ows_blackAlpha40
        noVideoView.addSubview(overlayView)
        overlayView.autoPinEdgesToSuperviewEdges()

        backgroundAvatarView.contentMode = .scaleAspectFill
        noVideoView.addSubview(backgroundAvatarView)
        backgroundAvatarView.autoPinEdgesToSuperviewEdges()

        noVideoView.addSubview(blurView)
        blurView.autoPinEdgesToSuperviewEdges()

        muteIndicatorImage.contentMode = .scaleAspectFit
        muteIndicatorImage.setTemplateImage(#imageLiteral(resourceName: "mic-off-solid-28"), tintColor: .ows_white)
        addSubview(muteIndicatorImage)
        muteIndicatorImage.autoMatch(.width, to: .height, of: muteIndicatorImage)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    enum ErrorState {
        case blocked(SignalServiceAddress)
        case noMediaKeys(SignalServiceAddress)
    }
}

class GroupCallLocalMemberView: GroupCallMemberView {
    let videoView = LocalVideoView()

    let videoOffIndicatorImage = UIImageView()
    let videoOffLabel = UILabel()

    var videoOffIndicatorWidth: CGFloat {
        if width > 102 {
            return 28
        } else {
            return 16
        }
    }

    override var bounds: CGRect {
        didSet { updateDimensions() }
    }

    override var frame: CGRect {
        didSet { updateDimensions() }
    }

    lazy var videoOffIndicatorWidthConstraint = videoOffIndicatorImage.autoSetDimension(.width, toSize: videoOffIndicatorWidth)

    lazy var callFullLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.font = .ows_dynamicTypeSubheadline
        label.textAlignment = .center
        label.textColor = Theme.darkThemePrimaryColor
        return label
    }()

    lazy var callFullStack: UIStackView = {
        let callFullStack = UIStackView()
        callFullStack.axis = .vertical
        callFullStack.spacing = 8

        let imageView = UIImageView(image: #imageLiteral(resourceName: "sad-cat"))
        imageView.contentMode = .scaleAspectFit
        imageView.autoSetDimensions(to: CGSize(square: 200))
        callFullStack.addArrangedSubview(imageView)

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString(
            "GROUP_CALL_IS_FULL",
            comment: "Text explaining the group call is full"
        )
        titleLabel.font = UIFont.ows_dynamicTypeSubheadline.ows_semibold
        titleLabel.textAlignment = .center
        titleLabel.textColor = Theme.darkThemePrimaryColor
        callFullStack.addArrangedSubview(titleLabel)

        callFullStack.addArrangedSubview(callFullLabel)

        return callFullStack
    }()

    override init() {
        super.init()

        videoOffIndicatorImage.contentMode = .scaleAspectFit
        videoOffIndicatorImage.setTemplateImage(#imageLiteral(resourceName: "video-off-solid-28"), tintColor: .ows_white)
        noVideoView.addSubview(videoOffIndicatorImage)
        videoOffIndicatorImage.autoMatch(.height, to: .width, of: videoOffIndicatorImage)
        videoOffIndicatorImage.autoCenterInSuperview()

        videoOffLabel.font = .ows_dynamicTypeSubheadline
        videoOffLabel.text = NSLocalizedString("CALLING_MEMBER_VIEW_YOUR_CAMERA_IS_OFF",
                                               comment: "Indicates to the user that their camera is currently off.")
        videoOffLabel.textAlignment = .center
        videoOffLabel.textColor = Theme.darkThemePrimaryColor
        noVideoView.addSubview(videoOffLabel)
        videoOffLabel.autoPinWidthToSuperview()
        videoOffLabel.autoPinEdge(.top, to: .bottom, of: videoOffIndicatorImage, withOffset: 10)

        videoView.contentMode = .scaleAspectFill
        insertSubview(videoView, belowSubview: muteIndicatorImage)
        videoView.frame = bounds

        addSubview(callFullStack)
        callFullStack.autoAlignAxis(.horizontal, toSameAxisOf: self, withOffset: -30)
        callFullStack.autoPinWidthToSuperview(withMargin: 16)

        layer.shadowOffset = .zero
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 4
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var hasBeenConfigured = false
    func configure(call: SignalCall, isFullScreen: Bool = false) {
        hasBeenConfigured = true

        videoView.isHidden = call.groupCall.isOutgoingVideoMuted
        videoView.captureSession = call.videoCaptureController.captureSession
        noVideoView.isHidden = !videoView.isHidden

        if isFullScreen,
           call.groupCall.isFull,
           case .notJoined = call.groupCall.localDeviceState.joinState {

            let text: String
            if let maxDevices = call.groupCall.maxDevices {
                let formatString = NSLocalizedString(
                    "GROUP_CALL_HAS_MAX_DEVICES_FORMAT",
                    comment: "An error displayed to the user when the group call ends because it has exceeded the max devices. Embeds {{max device count}}."
                )
                text = String(format: formatString, maxDevices)
            } else {
                text = NSLocalizedString(
                    "GROUP_CALL_HAS_MAX_DEVICES_UNKNOWN_COUNT",
                    comment: "An error displayed to the user when the group call ends because it has exceeded the max devices."
                )
            }

            callFullLabel.text = text
            callFullStack.isHidden = false
            videoOffLabel.isHidden = true
            videoOffIndicatorImage.isHidden = true
        } else {
            callFullStack.isHidden = true
            videoOffLabel.isHidden = !videoView.isHidden || !isFullScreen
            videoOffIndicatorImage.isHidden = !videoView.isHidden
        }

        guard let localAddress = tsAccountManager.localAddress else {
            return owsFailDebug("missing local address")
        }

        let conversationColorName = databaseStorage.uiRead { transaction in
            return self.contactsManager.conversationColorName(for: localAddress, transaction: transaction)
        }

        backgroundAvatarView.image = profileManager.localProfileAvatarImage()

        muteIndicatorImage.isHidden = isFullScreen || !call.groupCall.isOutgoingAudioMuted
        muteLeadingConstraint.constant = muteInsets
        muteBottomConstraint.constant = -muteInsets
        muteHeightConstraint.constant = muteHeight

        videoOffIndicatorWidthConstraint.constant = videoOffIndicatorWidth

        noVideoView.backgroundColor = OWSConversationColor.conversationColorOrDefault(
            colorName: conversationColorName
        ).themeColor

        layer.cornerRadius = isFullScreen ? 0 : 10
        clipsToBounds = true
    }

    private func updateDimensions() {
        guard hasBeenConfigured else { return }
        videoView.frame = bounds
        muteLeadingConstraint.constant = muteInsets
        muteBottomConstraint.constant = -muteInsets
        muteHeightConstraint.constant = muteHeight
        videoOffIndicatorWidthConstraint.constant = videoOffIndicatorWidth
    }
}

class GroupCallRemoteMemberView: GroupCallMemberView {
    private weak var videoView: GroupCallRemoteVideoView?

    var deferredReconfigTimer: Timer?
    let errorView = GroupCallErrorView()
    let avatarView = AvatarImageView()
    let spinner = UIActivityIndicatorView(style: .whiteLarge)
    lazy var avatarWidthConstraint = avatarView.autoSetDimension(.width, toSize: CGFloat(avatarDiameter))

    var isCallMinimized: Bool = false {
        didSet {
            // Currently only updated for the speaker view, since that's the only visible cell
            // while minimized.
            errorView.forceCompactAppearance = isCallMinimized
            errorView.isUserInteractionEnabled = !isCallMinimized
        }
    }

    override var bounds: CGRect {
        didSet { updateDimensions() }
    }

    override var frame: CGRect {
        didSet { updateDimensions() }
    }

    var avatarDiameter: UInt {
        layoutIfNeeded()

        if width > 180 {
            return 112
        } else if width > 102 {
            return 96
        } else if width > 36 {
            return UInt(width) - 36
        } else {
            return 16
        }
    }

    let mode: Mode
    enum Mode: Equatable {
        case videoGrid, videoOverflow, speaker
    }

    init(mode: Mode) {
        self.mode = mode
        super.init()

        noVideoView.insertSubview(avatarView, belowSubview: muteIndicatorImage)
        noVideoView.insertSubview(errorView, belowSubview: muteIndicatorImage)
        noVideoView.insertSubview(spinner, belowSubview: muteIndicatorImage)

        avatarView.autoCenterInSuperview()
        errorView.autoPinEdgesToSuperviewEdges()
        spinner.autoCenterInSuperview()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var hasBeenConfigured = false
    func configure(call: SignalCall, device: RemoteDeviceState) {
        hasBeenConfigured = true
        deferredReconfigTimer?.invalidate()

        let (profileImage, conversationColorName) = databaseStorage.uiRead { transaction in
            return (
                self.contactsManager.image(for: device.address, transaction: transaction),
                self.contactsManager.conversationColorName(for: device.address, transaction: transaction)
            )
        }

        backgroundAvatarView.image = profileImage

        let avatarBuilder = OWSContactAvatarBuilder(
            address: device.address,
            colorName: conversationColorName,
            diameter: avatarDiameter
        )

        if device.address.isLocalAddress {
            avatarView.image = OWSProfileManager.shared().localProfileAvatarImage() ?? avatarBuilder.buildDefaultImage()
        } else {
            avatarView.image = avatarBuilder.build()
        }

        avatarWidthConstraint.constant = CGFloat(avatarDiameter)

        muteIndicatorImage.isHidden = mode == .speaker || device.audioMuted != true
        muteLeadingConstraint.constant = muteInsets
        muteBottomConstraint.constant = -muteInsets
        muteHeightConstraint.constant = muteHeight

        noVideoView.backgroundColor = OWSConversationColor.conversationColorOrDefault(
            colorName: conversationColorName
        ).themeColor

        configureRemoteVideo(device: device)
        let isRemoteDeviceBlocked = OWSBlockingManager.shared().isAddressBlocked(device.address)
        let errorDeferralInterval: TimeInterval = 5.0
        let addedDate = Date(millisecondsSince1970: device.addedTime)
        let connectionDuration = -addedDate.timeIntervalSinceNow

        // Hide these views. They'll be unhidden below.
        [errorView, avatarView, videoView, spinner].forEach { $0?.isHidden = true }

        if !device.mediaKeysReceived, !isRemoteDeviceBlocked, connectionDuration < errorDeferralInterval {
            // No media keys, but that's expected since we just joined the call.
            // Schedule a timer to re-check and show a spinner in the meantime
            spinner.isHidden = false
            if !spinner.isAnimating { spinner.startAnimating() }

            let configuredDemuxId = device.demuxId
            let scheduledInterval = errorDeferralInterval - connectionDuration
            deferredReconfigTimer = Timer.scheduledTimer(
                withTimeInterval: scheduledInterval,
                repeats: false,
                block: { [weak self] _ in
                guard let self = self else { return }
                guard call.isGroupCall, let groupCall = call.groupCall else { return }
                guard let updatedState = groupCall.remoteDeviceStates.values
                        .first(where: { $0.demuxId == configuredDemuxId }) else { return }
                self.configure(call: call, device: updatedState)
            })

        } else if !device.mediaKeysReceived {
            // No media keys. Display error view
            errorView.isHidden = false
            configureErrorView(for: device.address, isBlocked: isRemoteDeviceBlocked)

        } else if let videoView = videoView, device.videoTrack != nil {
            // We have a video track! If we don't know the mute state, show both.
            // Otherwise, show one or the other.
            videoView.isHidden = (device.videoMuted == true)
            avatarView.isHidden = (device.videoMuted == false)

        } else {
            // No video. Display avatar
            avatarView.isHidden = false
        }
    }

    func clearConfiguration() {
        deferredReconfigTimer?.invalidate()

        cleanupVideoViews()

        noVideoView.backgroundColor = .ows_black
        backgroundAvatarView.image = nil
        avatarView.image = nil

        [errorView, spinner, muteIndicatorImage].forEach { $0.isHidden = true }
    }

    private func updateDimensions() {
        guard hasBeenConfigured else { return }
        videoView?.frame = bounds
        muteLeadingConstraint.constant = muteInsets
        muteBottomConstraint.constant = -muteInsets
        muteHeightConstraint.constant = muteHeight
        avatarWidthConstraint.constant = CGFloat(avatarDiameter)
    }

    func cleanupVideoViews() {
        if videoView?.superview == self { videoView?.removeFromSuperview() }
        videoView = nil
    }

    func configureRemoteVideo(device: RemoteDeviceState) {
        if videoView?.superview == self { videoView?.removeFromSuperview() }
        let newVideoView = callService.groupCallRemoteVideoManager.remoteVideoView(for: device, mode: mode)
        insertSubview(newVideoView, belowSubview: muteIndicatorImage)
        newVideoView.frame = bounds
        videoView = newVideoView

        owsAssertDebug(videoView != nil, "Missing remote video view")
    }

    func configureErrorView(for address: SignalServiceAddress, isBlocked: Bool) {
        let displayName: String
        if address.isLocalAddress {
            displayName = NSLocalizedString(
                "GROUP_CALL_YOU_ON_ANOTHER_DEVICE",
                comment: "Text describing the local user in the group call members sheet when connected from another device.")
        } else {
            displayName = self.contactsManager.displayName(for: address)
        }

        let blockFormat = NSLocalizedString(
            "GROUP_CALL_BLOCKED_USER_FORMAT",
            comment: "String displayed in group call grid cell when a user is blocked. Embeds {user's name}")
        let missingKeyFormat = NSLocalizedString(
            "GROUP_CALL_MISSING_MEDIA_KEYS_FORMAT",
            comment: "String displayed in cell when media from a user can't be displayed in group call grid. Embeds {user's name}")

        let labelFormat = isBlocked ? blockFormat : missingKeyFormat
        let label = String(format: labelFormat, arguments: [displayName])
        let image = isBlocked ? UIImage(named: "block-24") : UIImage(named: "error-solid-24")

        errorView.iconImage = image
        errorView.labelText = label
        errorView.userTapAction = { [weak self] _ in
            guard let self = self else { return }

            if isBlocked {
                self.delegate?.memberView(self, userRequestedInfoAboutError: .blocked(address))
            } else {
                self.delegate?.memberView(self, userRequestedInfoAboutError: .noMediaKeys(address))
            }
        }
    }
}

extension RemoteDeviceState {
    var address: SignalServiceAddress {
        return SignalServiceAddress(uuid: userId)
    }
}
