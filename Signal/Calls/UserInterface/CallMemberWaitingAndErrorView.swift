//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC
import SignalServiceKit

/// Only used for group calls currently; adjust if individual calls come to need it.
class CallMemberWaitingAndErrorView: UIView, CallMemberComposableView {
    weak var errorPresenter: CallMemberErrorPresenter?

    private let blurredAvatarBackgroundView = BlurredAvatarBackgroundView()

    private let errorView = GroupCallErrorView()
    private let spinner = UIActivityIndicatorView(style: .large)

    private var deferredReconfigTimer: Timer?

    private let type: CallMemberView.MemberType

    var isCallMinimized: Bool = false {
        didSet {
            self.errorView.callMinimizedStateDidChange(isCallMinimized: isCallMinimized)
        }
    }

    init(type: CallMemberView.MemberType) {
        self.type = type
        super.init(frame: .zero)

        self.addSubview(blurredAvatarBackgroundView)
        blurredAvatarBackgroundView.autoPinEdgesToSuperviewEdges()
        blurredAvatarBackgroundView.isHidden = true

        self.addSubview(errorView)
        errorView.autoPinEdgesToSuperviewEdges()
        errorView.isHidden = true

        self.addSubview(spinner)
        spinner.autoCenterInSuperview()
        spinner.isHidden = true
    }

    func configure(
        call: SignalCall,
        isFullScreen: Bool = false,
        remoteGroupMemberDeviceState: RemoteDeviceState?
    ) {
        switch type {
        case .local, .remoteInIndividual:
            owsFailDebug("CallMemberWaitingAndErrorView should not be in the view hierarchy!")
        case .remoteInGroup:
            deferredReconfigTimer?.invalidate()

            guard let remoteGroupMemberDeviceState else { return }

            let ringRtcCall: SignalRingRTC.GroupCall
            switch call.mode {
            case .individual:
                owsFail("Can't configure remoteInGroup for individual call.")
            case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
                ringRtcCall = call.ringRtcCall
            }

            let isRemoteDeviceBlocked = SSKEnvironment.shared.databaseStorageRef.read { tx in
                return SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(remoteGroupMemberDeviceState.address, transaction: tx)
            }

            let errorDeferralInterval: TimeInterval = 5.0
            let addedDate = Date(millisecondsSince1970: remoteGroupMemberDeviceState.addedTime)
            let connectionDuration = -addedDate.timeIntervalSinceNow

            if !remoteGroupMemberDeviceState.mediaKeysReceived, !isRemoteDeviceBlocked, connectionDuration < errorDeferralInterval {
                // No media keys, but that's expected since we just joined the call.
                // Schedule a timer to re-check and show a spinner in the meantime
                spinner.isHidden = false
                blurredAvatarBackgroundView.isHidden = false
                if !spinner.isAnimating { spinner.startAnimating() }

                let configuredDemuxId = remoteGroupMemberDeviceState.demuxId
                let scheduledInterval = errorDeferralInterval - connectionDuration
                deferredReconfigTimer = Timer.scheduledTimer(
                    withTimeInterval: scheduledInterval,
                    repeats: false,
                    block: { [weak self] _ in
                        guard let self = self else { return }
                        guard let updatedState = ringRtcCall.remoteDeviceStates.values
                            .first(where: { $0.demuxId == configuredDemuxId }) else { return }
                        self.configure(call: call, remoteGroupMemberDeviceState: updatedState)
                    }
                )
            } else if !remoteGroupMemberDeviceState.mediaKeysReceived {
                // No media keys. Display error view
                errorView.isHidden = false
                if isRemoteDeviceBlocked {
                    configureErrorView(errorState: .blocked(remoteGroupMemberDeviceState.address))
                } else {
                    configureErrorView(errorState: .noMediaKeys(remoteGroupMemberDeviceState.address))
                }
                blurredAvatarBackgroundView.isHidden = false
            } else {
                spinner.isHidden = true
                errorView.isHidden = true
                blurredAvatarBackgroundView.isHidden = true
            }
        }

        self.blurredAvatarBackgroundView.update(
            type: self.type,
            remoteGroupMemberDeviceState: remoteGroupMemberDeviceState
        )
    }

    private func displayName(address: SignalServiceAddress) -> String {
        if address.isLocalAddress {
            return OWSLocalizedString(
                "GROUP_CALL_YOU_ON_ANOTHER_DEVICE",
                comment: "Text describing the local user in the group call members sheet when connected from another device.")
        } else {
            return SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: tx).resolvedValue() }
        }
    }

    private func configureErrorView(errorState: CallMemberErrorState) {
        let label: String
        let image: UIImage?
        switch errorState {
        case .blocked(let addr):
            let blockFormat = OWSLocalizedString(
                "GROUP_CALL_BLOCKED_USER_FORMAT",
                comment: "String displayed in group call grid cell when a user is blocked. Embeds {user's name}"
            )
            let displayName = displayName(address: addr)
            label = String(format: blockFormat, arguments: [displayName])
            image = UIImage(named: "block")
        case .noMediaKeys(let addr):
            let missingKeyFormat = OWSLocalizedString(
                "GROUP_CALL_MISSING_MEDIA_KEYS_FORMAT",
                comment: "String displayed in cell when media from a user can't be displayed in group call grid. Embeds {user's name}"
            )
            let displayName = displayName(address: addr)
            label = String(format: missingKeyFormat, arguments: [displayName])
            image = UIImage(named: "error-circle-fill")
        }

        let (errorSheetTitle, errorSheetMessage) = errorSheetContents(errorState: errorState)

        errorView.iconImage = image
        errorView.labelText = label
        errorView.userTapAction = { [weak self] _ in
            guard let self = self else { return }
            self.errorPresenter?.presentErrorSheet(
                title: errorSheetTitle,
                message: errorSheetMessage
            )
        }
    }

    private func errorSheetContents(errorState: CallMemberErrorState) -> (String, String) {
        let title: String
        let message: String

        switch errorState {
        case let .blocked(address):
            message = OWSLocalizedString(
                "GROUP_CALL_BLOCKED_ALERT_MESSAGE",
                comment: "Message body for alert explaining that a group call participant is blocked")

            let titleFormat = OWSLocalizedString(
                "GROUP_CALL_BLOCKED_ALERT_TITLE_FORMAT",
                comment: "Title for alert explaining that a group call participant is blocked. Embeds {{ user's name }}")
            let displayName = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: tx).resolvedValue() }
            title = String(format: titleFormat, displayName)

        case let .noMediaKeys(address):
            message = OWSLocalizedString(
                "GROUP_CALL_NO_KEYS_ALERT_MESSAGE",
                comment: "Message body for alert explaining that a group call participant cannot be displayed because of missing keys")

            let titleFormat = OWSLocalizedString(
                "GROUP_CALL_NO_KEYS_ALERT_TITLE_FORMAT",
                comment: "Title for alert explaining that a group call participant cannot be displayed because of missing keys. Embeds {{ user's name }}")
            let displayName = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: tx).resolvedValue() }
            title = String(format: titleFormat, displayName)
        }

        return (title, message)
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
        blurredAvatarBackgroundView.isHidden = true
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        if view == self.errorView.button {
            return view
        }
        return nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

enum CallMemberErrorState {
    case blocked(SignalServiceAddress)
    case noMediaKeys(SignalServiceAddress)
}

protocol CallMemberErrorPresenter: AnyObject {
    func presentErrorSheet(title: String, message: String)
}
