//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalRingRTC
import SignalServiceKit
import SignalUI

// MARK: - RemoteMuteToast

class RemoteMuteToast: UIView {

    // MARK: Properties

    struct Dependencies {
        let db: SDSDatabaseStorage
        let contactsManager: any ContactManager
        let tsAccountManager: any TSAccountManager
    }

    private let deps = Dependencies(
        db: SSKEnvironment.shared.databaseStorageRef,
        contactsManager: SSKEnvironment.shared.contactManagerRef,
        tsAccountManager: DependenciesBridge.shared.tsAccountManager,
    )

    private var call: GroupCall
    private var pendingNotifications = [String]()

    // MARK: Init

    init(call: GroupCall) {
        self.call = call
        super.init(frame: .zero)

        isUserInteractionEnabled = false

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: State

    func displaySelfMuted(muteSource: Aci) {
        let muteSourceName = self.deps.db.read { tx -> String in
            self.deps.contactsManager.displayName(
                for: SignalServiceAddress(muteSource),
                tx: tx,
            ).resolvedValue(useShortNameIfAvailable: true)
        }
        let toastText: String
        let localAci = self.deps.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!.aci
        if muteSource == localAci {
            toastText = String(
                format: OWSLocalizedString(
                    "REMOTE_MUTE_TOAST_YOU_MUTED_YOURSELF",
                    comment: "A message that displays when you joined a call on two devices and mute one from the other.",
                ),
            )
        } else {
            toastText = String(
                format: OWSLocalizedString(
                    "REMOTE_MUTE_TOAST_SOMEONE_MUTED_YOU",
                    comment:
                    "A message that displays when your microphone is remotely muted by another call participant. Embeds {{name}}",
                ),
                muteSourceName,
            )
        }

        pendingNotifications.append(toastText)
        presentNextNotificationIfNecessary()
    }

    func displayOtherMuted(source: Aci, target: Aci) {
        let toastText: String
        let localAci = self.deps.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!.aci
        if source == localAci {
            if target == localAci {
                // Don't display a toast if you muted your other device.
                return
            }
            let muteTargetName = self.deps.db.read { tx -> String in
                self.deps.contactsManager.displayName(
                    for: SignalServiceAddress(target),
                    tx: tx,
                ).resolvedValue(useShortNameIfAvailable: true)
            }

            toastText = String(
                format: OWSLocalizedString(
                    "REMOTE_MUTE_TOAST_YOU_MUTED_SOMEONE",
                    comment:
                    "A message that displays when you remotely muted another call participant's microphone. Embeds {{name}}",
                ),
                muteTargetName,
            )
        } else {
            if source == target {
                // Don't display toast for self-mutes.
                return
            }
            let (muteSourceName, muteTargetName) = self.deps.db.read { tx -> (String, String) in
                (
                    self.deps.contactsManager.displayName(
                        for: SignalServiceAddress(source),
                        tx: tx,
                    ).resolvedValue(useShortNameIfAvailable: true),
                    self.deps.contactsManager.displayName(
                        for: SignalServiceAddress(target),
                        tx: tx,
                    ).resolvedValue(useShortNameIfAvailable: true),
                )
            }

            toastText = String(
                format: OWSLocalizedString(
                    "REMOTE_MUTE_TOAST_A_MUTED_B",
                    comment:
                    "A message that displays when one person in a call remotely muted another participant. Embeds {{name}} {{name}}",
                ),
                muteSourceName,
                muteTargetName,
            )
        }

        pendingNotifications.append(toastText)
        presentNextNotificationIfNecessary()
    }

    private var isPresentingNotification = false
    private func presentNextNotificationIfNecessary() {
        guard !isPresentingNotification else { return }
        guard let text = pendingNotifications.popLast() else { return }

        let bannerView = RemoteMuteBannerView(text: text)

        isPresentingNotification = true

        addSubview(bannerView)
        bannerView.autoHCenterInSuperview()

        // Prefer to be full width, but don't exceed the maximum width
        bannerView.autoSetDimension(.width, toSize: 512, relation: .lessThanOrEqual)
        bannerView.autoMatch(
            .width,
            to: .width,
            of: self,
            withOffset: -(layoutMargins.left + layoutMargins.right),
            relation: .lessThanOrEqual,
        )
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            bannerView.autoPinWidthToSuperviewMargins()
        }

        let onScreenConstraint = bannerView.autoPinEdge(toSuperviewMargin: .top)
        onScreenConstraint.isActive = false

        let offScreenConstraint = bannerView.autoPinEdge(.bottom, to: .top, of: self)

        layoutIfNeeded()

        UIView.animate(withDuration: 0.35, delay: 0) {
            offScreenConstraint.isActive = false
            onScreenConstraint.isActive = true

            self.layoutIfNeeded()
        } completion: { _ in
            UIView.animate(withDuration: 0.35, delay: 4, options: .curveEaseInOut) {
                onScreenConstraint.isActive = false
                offScreenConstraint.isActive = true

                self.layoutIfNeeded()
            } completion: { _ in
                bannerView.removeFromSuperview()
                self.isPresentingNotification = false
                self.presentNextNotificationIfNecessary()
            }
        }
    }
}

private class RemoteMuteBannerView: UIView {

    init(text: String) {
        super.init(frame: .zero)

        autoSetDimension(.height, toSize: 64, relation: .greaterThanOrEqual)
        layer.cornerRadius = 8
        clipsToBounds = true

        let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        addSubview(blurEffectView)
        blurEffectView.autoPinEdgesToSuperviewEdges()
        backgroundColor = .ows_blackAlpha40

        let hStack = UIStackView()
        hStack.spacing = 12
        hStack.axis = .horizontal
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.layoutMargins = UIEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)

        addSubview(hStack)
        hStack.autoPinEdgesToSuperviewEdges()

        let mutedIcon = UILabel()
        mutedIcon.attributedText = .with(
            image: UIImage(named: "mic-slash")!,
            font: .dynamicTypeTitle3,
            attributes: [.foregroundColor: UIColor.ows_white],
        )
        mutedIcon.setContentCompressionResistancePriority(
            .required,
            for: .horizontal,
        )
        mutedIcon.contentMode = .scaleAspectFit
        mutedIcon.tintColor = .ows_white
        mutedIcon.setContentHuggingHorizontalHigh()
        mutedIcon.setCompressionResistanceVerticalHigh()

        hStack.addArrangedSubview(mutedIcon)

        let label = UILabel()
        hStack.addArrangedSubview(label)
        label.setCompressionResistanceHorizontalHigh()
        label.numberOfLines = 0
        label.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
        label.textColor = .ows_white
        label.text = text

        hStack.addArrangedSubview(.hStretchingSpacer())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
