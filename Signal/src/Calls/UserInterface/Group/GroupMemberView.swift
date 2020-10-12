//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalRingRTC

class GroupMemberView: UIView {
    let noVideoView = UIView()

    let backgroundAvatarView = AvatarImageView()
    let avatarView = AvatarImageView()
    let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    let muteIndicatorImage = UIImageView()

    init() {
        super.init(frame: .zero)

        backgroundColor = .ows_gray90

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

        noVideoView.addSubview(avatarView)
        avatarView.autoCenterInSuperview()
        avatarView.autoSetDimensions(to: CGSize(square: 96))

        muteIndicatorImage.contentMode = .scaleAspectFit
        muteIndicatorImage.setTemplateImage(#imageLiteral(resourceName: "mic-off-solid-28"), tintColor: .ows_white)
        addSubview(muteIndicatorImage)
        muteIndicatorImage.autoPinEdge(toSuperviewEdge: .leading, withInset: 9)
        muteIndicatorImage.autoPinEdge(toSuperviewEdge: .bottom, withInset: 9)
        muteIndicatorImage.autoSetDimension(.width, toSize: 16)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class LocalGroupMemberView: GroupMemberView {
    let videoView = LocalVideoView()

    override init() {
        super.init()

        videoView.contentMode = .scaleAspectFill
        insertSubview(videoView, belowSubview: muteIndicatorImage)
        videoView.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(device: LocalDeviceState, session: AVCaptureSession) {
        muteIndicatorImage.isHidden = !device.audioMuted
        videoView.isHidden = device.videoMuted
        videoView.captureSession = session
        noVideoView.isHidden = !videoView.isHidden

        guard let localAddress = tsAccountManager.localAddress else {
            return owsFailDebug("missing local address")
        }

        let (profileImage, conversationColorName) = databaseStorage.uiRead { transaction in
            return (
                self.profileManager.profileAvatar(for: localAddress, transaction: transaction),
                ConversationColorName(
                    rawValue: self.contactsManager.conversationColorName(for: localAddress, transaction: transaction)
                )
            )
        }

        backgroundAvatarView.image = profileImage

        avatarView.image = OWSContactAvatarBuilder(
            address: localAddress,
            colorName: conversationColorName,
            diameter: 96
        ).build()

        noVideoView.backgroundColor = OWSConversationColor.conversationColorOrDefault(
            colorName: conversationColorName
        ).themeColor
    }
}

class RemoteGroupMemberView: GroupMemberView {
    let videoView = RemoteVideoView()
    var currentTrack: RTCVideoTrack?

    override init() {
        super.init()

        videoView.contentMode = .scaleAspectFill
        insertSubview(videoView, belowSubview: muteIndicatorImage)
        videoView.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(device: RemoteDeviceState) {
        muteIndicatorImage.isHidden = device.audioMuted != true
        videoView.isHidden = device.videoMuted != false
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
            diameter: 96
        ).build()

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
        return SignalServiceAddress(uuid: uuid)
    }
}
