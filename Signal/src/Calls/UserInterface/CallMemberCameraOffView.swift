//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalMessaging
import SignalRingRTC
import SignalUI

// TODO: Before enabling FeatureFlags.useCallMemberComposableViewsForRemoteUsersIn[Group|Individual]Calls,
// show this view while waiting for remote video to be received and displayed.
class CallMemberCameraOffView: UIView, CallMemberComposableView {
    private let backgroundAvatarView = UIImageView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let avatarView = ConversationAvatarView(localUserDisplayMode: .asUser, badged: false)

    private var avatarDiameter: UInt {
        if width > 180 {
            return 112
        } else if width > 102 {
            return 96
        } else if width > 48 {
            return UInt(width) - 36
        } else {
            return 16
        }
    }

    init() {
        super.init(frame: .zero)

        let overlayView = UIView()
        overlayView.backgroundColor = .ows_blackAlpha40
        self.addSubview(overlayView)
        overlayView.autoPinEdgesToSuperviewEdges()

        backgroundAvatarView.contentMode = .scaleAspectFill
        self.addSubview(backgroundAvatarView)
        backgroundAvatarView.autoPinEdgesToSuperviewEdges()

        self.addSubview(blurView)
        blurView.autoPinEdgesToSuperviewEdges()

        self.addSubview(avatarView)
        avatarView.autoCenterInSuperview()
    }

    func configure(
        call: SignalCall,
        isFullScreen: Bool = false,
        memberType: CallMemberView.ConfigurationType
    ) {
        self.isHidden = !call.isOutgoingVideoMuted
        self.avatarView.isHidden = isFullScreen

        let backgroundAvatarImage: UIImage?
        let backgroundColor: UIColor?
        switch memberType {
        case .local:
            let avatar = profileManager.localProfileAvatarImage()
            backgroundAvatarImage = avatar
            let localAddress: SignalServiceAddress? = databaseStorage.read { tx in
                guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aciAddress else {
                    owsFailDebug("missing local address")
                    return nil
                }
                let updatedSize = avatarDiameter
                avatarView.update(tx) { config in
                    config.dataSource = .address(localAddress)
                    config.sizeClass = .customDiameter(updatedSize)
                }
                return localAddress
            }
            if let localAddress {
                backgroundColor = AvatarTheme.forAddress(localAddress).backgroundColor
            } else {
                backgroundColor = nil
            }
        case .remote(let remoteDeviceState, _):
            let profileImage = databaseStorage.read { tx in
                let updatedSize = avatarDiameter
                avatarView.update(tx) { config in
                    config.dataSource = .address(remoteDeviceState.address)
                    config.sizeClass = .customDiameter(updatedSize)
                }

                let profileImage = self.contactsManagerImpl.avatarImage(
                    forAddress: remoteDeviceState.address,
                    shouldValidate: true,
                    transaction: tx
                )
                return profileImage
            }
            backgroundAvatarImage = profileImage
            backgroundColor = AvatarTheme.forAddress(remoteDeviceState.address).backgroundColor
        }
        backgroundAvatarView.image = backgroundAvatarImage
        self.backgroundColor = backgroundColor
    }

    func updateDimensions() {
        // Will this be a problem being called from layout subviews?
        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.sizeClass = .customDiameter(avatarDiameter)
        }
    }

    func rotateForPhoneOrientation(_ rotationAngle: CGFloat) {
        /// TODO: Add support for rotating other elements too.
        self.avatarView.transform = CGAffineTransform(rotationAngle: rotationAngle)
    }

    func clearConfiguration() {
        self.backgroundColor = .ows_black
        backgroundAvatarView.image = nil
        avatarView.reset()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
