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
        didSet { videoView.frame = bounds }
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
        videoOffLabel.text = "Your video is off"
        videoOffLabel.textAlignment = .center
        videoOffLabel.textColor = Theme.darkThemePrimaryColor
        noVideoView.addSubview(videoOffLabel)
        videoOffLabel.autoPinWidthToSuperview()
        videoOffLabel.autoPinEdge(.top, to: .bottom, of: videoOffIndicatorImage, withOffset: 10)

        videoView.contentMode = .scaleAspectFill
        insertSubview(videoView, belowSubview: muteIndicatorImage)
        videoView.frame = bounds
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(device: LocalDeviceState, session: AVCaptureSession, isFullScreen: Bool = false) {
        videoView.isHidden = device.videoMuted
        videoView.captureSession = session
        noVideoView.isHidden = !videoView.isHidden
        videoOffLabel.isHidden = !videoView.isHidden || !isFullScreen

        guard let localAddress = tsAccountManager.localAddress else {
            return owsFailDebug("missing local address")
        }

        let conversationColorName = databaseStorage.uiRead { transaction in
            return ConversationColorName(
                rawValue: self.contactsManager.conversationColorName(for: localAddress, transaction: transaction)
            )
        }

        backgroundAvatarView.image = profileManager.localProfileAvatarImage()

        muteIndicatorImage.isHidden = isFullScreen || !device.audioMuted
        muteLeadingConstraint.constant = muteInsets
        muteBottomConstraint.constant = -muteInsets

        videoOffIndicatorWidthConstraint.constant = videoOffIndicatorWidth

        noVideoView.backgroundColor = OWSConversationColor.conversationColorOrDefault(
            colorName: conversationColorName
        ).themeColor

        layer.cornerRadius = isFullScreen ? 0 : 10
        clipsToBounds = true
    }
}

class GroupCallRemoteMemberView: GroupCallMemberView {
    let videoView = RemoteVideoView()
    var currentTrack: RTCVideoTrack?

    let avatarView = AvatarImageView()
    lazy var avatarWidthConstraint = avatarView.autoSetDimension(.width, toSize: CGFloat(avatarDiameter))

    override var bounds: CGRect {
        didSet { videoView.frame = bounds }
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

    override init() {
        super.init()

        noVideoView.insertSubview(avatarView, belowSubview: muteIndicatorImage)
        avatarView.autoCenterInSuperview()

        insertSubview(videoView, belowSubview: muteIndicatorImage)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(device: RemoteDeviceState, isFullScreen: Bool = false) {
        videoView.isHidden = device.videoMuted ?? false
        noVideoView.isHidden = !videoView.isHidden

        let (profileImage, conversationColorName) = databaseStorage.uiRead { transaction in
            return (
                self.profileManager.profileAvatar(for: device.address, transaction: transaction),
                ConversationColorName(
                    rawValue: self.contactsManager.conversationColorName(for: device.address, transaction: transaction)
                )
            )
        }

        backgroundAvatarView.image = profileImage

        avatarView.image = OWSContactAvatarBuilder(
            address: device.address,
            colorName: conversationColorName,
            diameter: avatarDiameter
        ).build()
        avatarWidthConstraint.constant = CGFloat(avatarDiameter)

        muteIndicatorImage.isHidden = isFullScreen || device.audioMuted != true
        muteLeadingConstraint.constant = muteInsets
        muteBottomConstraint.constant = -muteInsets

        noVideoView.backgroundColor = OWSConversationColor.conversationColorOrDefault(
            colorName: conversationColorName
        ).themeColor

        currentTrack?.remove(videoView)
        currentTrack = nil

        if let track = device.videoTrack {
            track.add(videoView)
            currentTrack = track
        }
    }
}

extension RemoteDeviceState {
    var address: SignalServiceAddress {
        return SignalServiceAddress(uuid: userId)
    }
}
