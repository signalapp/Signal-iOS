//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

/// Only used for group calls currently; adjust if individual calls come to need it.
class CallMemberWaitingAndErrorView: UIView, CallMemberComposableView {
    weak var delegate: GroupCallMemberViewDelegate?

    enum ErrorState {
        case blocked(SignalServiceAddress)
        case noMediaKeys(SignalServiceAddress)
    }

    private let errorView = GroupCallErrorView()
    private let spinner = UIActivityIndicatorView(style: .large)

    private var deferredReconfigTimer: Timer?

    var isCallMinimized: Bool = false {
        didSet {
            // Currently only updated for the speaker view, since that's the only visible cell
            // while minimized.
            errorView.forceCompactAppearance = isCallMinimized
            errorView.isUserInteractionEnabled = !isCallMinimized
        }
    }

    init() {
        super.init(frame: .zero)
        self.addSubview(errorView)
        self.addSubview(spinner)
        errorView.autoPinEdgesToSuperviewEdges()
        errorView.isHidden = true
        spinner.autoCenterInSuperview()
        spinner.isHidden = true
    }

    func configure(
        call: SignalCall,
        isFullScreen: Bool = false,
        memberType: CallMemberView.ConfigurationType
    ) {
        switch memberType {
        case .local:
            owsFailDebug("CallMemberWaitingAndErrorView should not be in the view hierarchy for individual calls!")
        case .remote(let remoteDeviceState, let context):
            deferredReconfigTimer?.invalidate()

            let isRemoteDeviceBlocked = databaseStorage.read { tx in
                return blockingManager.isAddressBlocked(remoteDeviceState.address, transaction: tx)
            }

            let errorDeferralInterval: TimeInterval = 5.0
            let addedDate = Date(millisecondsSince1970: remoteDeviceState.addedTime)
            let connectionDuration = -addedDate.timeIntervalSinceNow

            if !remoteDeviceState.mediaKeysReceived, !isRemoteDeviceBlocked, connectionDuration < errorDeferralInterval {
                // No media keys, but that's expected since we just joined the call.
                // Schedule a timer to re-check and show a spinner in the meantime
                spinner.isHidden = false
                if !spinner.isAnimating { spinner.startAnimating() }

                let configuredDemuxId = remoteDeviceState.demuxId
                let scheduledInterval = errorDeferralInterval - connectionDuration
                deferredReconfigTimer = Timer.scheduledTimer(
                    withTimeInterval: scheduledInterval,
                    repeats: false,
                    block: { [weak self] _ in
                    guard let self = self else { return }
                    guard call.isGroupCall, let groupCall = call.groupCall else { return }
                    guard let updatedState = groupCall.remoteDeviceStates.values
                            .first(where: { $0.demuxId == configuredDemuxId }) else { return }
                    self.configure(call: call, memberType: .remote(updatedState, context))
                })
            } else if !remoteDeviceState.mediaKeysReceived {
                // No media keys. Display error view
                errorView.isHidden = false
                configureErrorView(for: remoteDeviceState.address, isBlocked: isRemoteDeviceBlocked)
            } else {
                spinner.isHidden = true
                errorView.isHidden = true
            }
        }
    }

    private func configureErrorView(for address: SignalServiceAddress, isBlocked: Bool) {
        let displayName: String
        if address.isLocalAddress {
            displayName = OWSLocalizedString(
                "GROUP_CALL_YOU_ON_ANOTHER_DEVICE",
                comment: "Text describing the local user in the group call members sheet when connected from another device.")
        } else {
            displayName = self.contactsManager.displayName(for: address)
        }

        let blockFormat = OWSLocalizedString(
            "GROUP_CALL_BLOCKED_USER_FORMAT",
            comment: "String displayed in group call grid cell when a user is blocked. Embeds {user's name}")
        let missingKeyFormat = OWSLocalizedString(
            "GROUP_CALL_MISSING_MEDIA_KEYS_FORMAT",
            comment: "String displayed in cell when media from a user can't be displayed in group call grid. Embeds {user's name}")

        let labelFormat = isBlocked ? blockFormat : missingKeyFormat
        let label = String(format: labelFormat, arguments: [displayName])
        let image = isBlocked ? UIImage(named: "block") : UIImage(named: "error-circle-fill")

        errorView.iconImage = image
        errorView.labelText = label
        errorView.userTapAction = { [weak self] _ in
            guard let self = self else { return }

            if isBlocked {
                self.delegate?.memberView(userRequestedInfoAboutError: .blocked(address))
            } else {
                self.delegate?.memberView(userRequestedInfoAboutError: .noMediaKeys(address))
            }
        }
    }

    func rotateForPhoneOrientation(_ rotationAngle: CGFloat) {
        /// TODO: Add support for rotating.
    }

    func updateDimensions() {
        /// TODO: Add support for updating dimensions.
    }

    func clearConfiguration() {
        deferredReconfigTimer?.invalidate()
        errorView.isHidden = true
        spinner.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
