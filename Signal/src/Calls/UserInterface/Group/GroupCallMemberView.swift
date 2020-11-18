//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalRingRTC

class GroupCallMemberView: UIView {
    let noVideoView = UIView()

    let backgroundAvatarView = UIImageView()
    let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    let muteIndicatorImage = UIImageView()

    lazy var muteLeadingConstraint = muteIndicatorImage.autoPinEdge(toSuperviewEdge: .leading, withInset: muteInsets)
    lazy var muteBottomConstraint = muteIndicatorImage.autoPinEdge(toSuperviewEdge: .bottom, withInset: muteInsets)

    var muteInsets: CGFloat {
        layoutIfNeeded()

        if width > 102 {
            return 9
        } else {
            return 4
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
        muteIndicatorImage.autoSetDimensions(to: CGSize(square: 16))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        videoOffLabel.isHidden = !videoView.isHidden || !isFullScreen

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
        videoOffIndicatorWidthConstraint.constant = videoOffIndicatorWidth
    }
}

class GroupCallRemoteMemberView: GroupCallMemberView {
    private weak var videoView: GroupCallRemoteVideoView?

    let avatarView = AvatarImageView()
    lazy var avatarWidthConstraint = avatarView.autoSetDimension(.width, toSize: CGFloat(avatarDiameter))

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
        avatarView.autoCenterInSuperview()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var hasBeenConfigured = false
    func configure(call: SignalCall, device: RemoteDeviceState) {
        hasBeenConfigured = true

        let (profileImage, conversationColorName) = databaseStorage.uiRead { transaction in
            return (
                self.profileManager.profileAvatar(for: device.address, transaction: transaction),
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

        noVideoView.backgroundColor = OWSConversationColor.conversationColorOrDefault(
            colorName: conversationColorName
        ).themeColor

        if videoView?.superview == self { videoView?.removeFromSuperview() }
        let newVideoView = callService.groupCallRemoteVideoManager.remoteVideoView(for: device, mode: mode)
        insertSubview(newVideoView, belowSubview: muteIndicatorImage)
        newVideoView.frame = bounds
        videoView = newVideoView

        guard let videoView = videoView else {
            return owsFailDebug("Missing remote video view")
        }

        avatarView.isHidden = !(device.videoMuted ?? true)
        videoView.isHidden = device.videoMuted ?? false || device.videoTrack == nil
    }

    private func updateDimensions() {
        guard hasBeenConfigured else { return }
        videoView?.frame = bounds
        avatarWidthConstraint.constant = CGFloat(avatarDiameter)
    }
}

extension RemoteDeviceState {
    var address: SignalServiceAddress {
        return SignalServiceAddress(uuid: userId)
    }
}
