//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalMessaging
import SignalRingRTC
import SignalServiceKit
import SignalUI

// TODO: Before enabling FeatureFlags.useCallMemberComposableViewsForRemoteUsersIn[Group|Individual]Calls,
// show this view while waiting for remote video to be received and displayed.
class CallMemberCameraOffView: UIView, CallMemberComposableView {
    private let backgroundAvatarView = UIImageView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))

    // One of these three is shown depending on the circumstances.
    private var avatarView: ConversationAvatarView?
    private var detailedNoVideoIndicatorView: UIStackView?
    private var noVideoIndicatorImageView: UIImageView?

    init(type: CallMemberView.MemberType) {
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

        createOptionalViews(type: type)
        if let avatarView {
            self.addSubview(avatarView)
            avatarView.autoCenterInSuperview()
        }
        if let detailedNoVideoIndicatorView {
            self.addSubview(detailedNoVideoIndicatorView)
            detailedNoVideoIndicatorView.autoCenterInSuperview()
            detailedNoVideoIndicatorView.isHidden = true
        }
        if let noVideoIndicatorImageView {
            self.addSubview(noVideoIndicatorImageView)
            noVideoIndicatorImageView.isHidden = true
            noVideoIndicatorImageView.autoMatch(.height, to: .width, of: noVideoIndicatorImageView)
            noVideoIndicatorImageView.autoCenterInSuperview()
            let constraint = noVideoIndicatorImageView.autoSetDimension(.width, toSize: videoOffImageIndicatorWidth)
            self.videoOffIndicatorImageWidthConstraint = constraint
            NSLayoutConstraint.activate([constraint])
        }
    }

    /// This method initializes the views that have the potential to be shown
    /// based on whether the call is individual/group and whether the member
    /// is local/remote.
    ///
    /// Spec when camera is off:
    /// - Local Member:
    ///   - Individual call:
    ///     - PIP: N/A because PIP disappears when camera is off.
    ///     - Fullscreen: Circular avatar.
    ///   - Group call:
    ///     - PIP: Camera-off image.
    ///     - Fullscreen: Camera-off image and message.
    /// - Remote Member: Circular avatar.
    private func createOptionalViews(type: CallMemberView.MemberType) {
        switch type {
        case .local(let call):
            if call.isIndividualCall {
                self.avatarView = ConversationAvatarView(localUserDisplayMode: .asUser, badged: false)
            } else if call.isGroupCall {
                self.detailedNoVideoIndicatorView = self.createDetailedVideoOffIndicatorView()
                self.noVideoIndicatorImageView = self.createVideoOffIndicatorImageView()
            }
        case .remote(_):
            self.avatarView = ConversationAvatarView(localUserDisplayMode: .asUser, badged: false)
        }
    }

    func configure(
        call: SignalCall,
        isFullScreen: Bool = false,
        memberType: CallMemberView.ConfigurationType
    ) {
        switch memberType {
        case .local:
            self.isHidden = !call.isOutgoingVideoMuted
        case .remote(let remoteDeviceState, _):
            if let videoMuted = remoteDeviceState.videoMuted {
                self.isHidden = !videoMuted
            } else {
                self.isHidden = true
            }
        }
        if self.isHidden {
            return
        }

        if let detailedNoVideoIndicatorView {
            detailedNoVideoIndicatorView.isHidden = !isFullScreen
        }
        if let noVideoIndicatorImageView {
            noVideoIndicatorImageView.isHidden = isFullScreen
        }

        let backgroundAvatarImage: UIImage?
        var backgroundColor: UIColor?
        switch memberType {
        case .local:
            databaseStorage.read { tx in
                guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aciAddress else {
                    owsFailDebug("missing local address")
                    return
                }
                updateCircularAvatarIfNecessary(
                    address: localAddress,
                    tx: tx
                )
                backgroundColor = AvatarTheme.forAddress(localAddress).backgroundColor
            }
            backgroundAvatarImage = profileManager.localProfileAvatarImage()
        case .remote(let remoteDeviceState, _):
            let profileImage = databaseStorage.read { tx in
                updateCircularAvatarIfNecessary(
                    address: remoteDeviceState.address,
                    tx: tx
                )
                return self.contactsManagerImpl.avatarImage(
                    forAddress: remoteDeviceState.address,
                    shouldValidate: true,
                    transaction: tx
                )
            }
            backgroundAvatarImage = profileImage
            backgroundColor = AvatarTheme.forAddress(remoteDeviceState.address).backgroundColor
        }
        backgroundAvatarView.image = backgroundAvatarImage
        self.backgroundColor = backgroundColor
    }

    func updateDimensions() {
        self.videoOffIndicatorImageWidthConstraint?.constant = videoOffImageIndicatorWidth
        avatarView?.updateWithSneakyTransactionIfNecessary { config in
            config.sizeClass = .customDiameter(avatarDiameter)
        }
    }

    func rotateForPhoneOrientation(_ rotationAngle: CGFloat) {
        /// TODO: Add support for rotating other elements too.
        self.avatarView?.transform = CGAffineTransform(rotationAngle: rotationAngle)
    }

    func clearConfiguration() {
        self.backgroundColor = .ows_black
        backgroundAvatarView.image = nil
        avatarView?.reset()
    }

    // MARK: - Avatar

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

    private func updateCircularAvatarIfNecessary(
        address: SignalServiceAddress,
        tx: SDSAnyReadTransaction
    ) {
        guard let avatarView else {
            OWSLogger.info("Skipping refresh of avatar view in call member view.")
            return
        }
        let updatedSize = avatarDiameter
        avatarView.update(tx) { config in
            config.dataSource = .address(address)
            config.sizeClass = .customDiameter(updatedSize)
        }
    }

    // MARK: - Detailed Video Off Indicator View

    private func createDetailedVideoOffIndicatorView() -> UIStackView {
        let icon = UIImageView()
        icon.contentMode = .scaleAspectFit
        icon.setTemplateImageName("video-slash-fill-28", tintColor: .ows_white)

        let label = UILabel()
        label.font = .dynamicTypeCaption1
        label.text = OWSLocalizedString(
            "CALLING_MEMBER_VIEW_YOUR_CAMERA_IS_OFF",
            comment: "Indicates to the user that their camera is currently off."
        )
        label.textAlignment = .center
        label.textColor = Theme.darkThemePrimaryColor

        let container = UIStackView(arrangedSubviews: [icon, label])
        if UIDevice.current.isIPhone5OrShorter {
            // Use a horizontal layout to save on vertical space.
            // Allow the icon to shrink below its natural size of 28pt...
            icon.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            container.axis = .horizontal
            container.spacing = 4
            // ...by always matching the label's height.
            container.alignment = .fill
        } else {
            // Use a simple vertical layout.
            icon.autoSetDimensions(to: CGSize(square: 28))
            container.axis = .vertical
            container.spacing = 10
            container.alignment = .center
            label.autoPinWidthToSuperview()
        }

        return container
    }

    // MARK: - Video Off Indicator Image

    private var videoOffIndicatorImageWidthConstraint: NSLayoutConstraint?

    private var videoOffImageIndicatorWidth: CGFloat {
        width > 102 ? 28 : 16
    }

    private func createVideoOffIndicatorImageView() -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.setTemplateImageName("video-slash-fill-28", tintColor: .ows_white)
        return imageView
    }

    // MARK: - Required

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
