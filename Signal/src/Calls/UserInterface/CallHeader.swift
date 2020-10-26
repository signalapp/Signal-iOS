//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalRingRTC

@objc
protocol CallHeaderDelegate: class {
    func didTapBackButton()
    func didTapMembersButton()
}

class CallHeader: UIView {
    // MARK: - Views

    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")!
        dateFormatter.locale = Locale(identifier: "en_US")
        return dateFormatter
    }()

    private var callDurationTimer: Timer?
    private let callTitleLabel = MarqueeLabel()
    private let callStatusLabel = UILabel()
    private let groupMembersButton = UIButton()
    private let groupMembersButtonPlaceholder = UIView.spacer(withWidth: 50)
    private var isBlinkingReconnectLabel = false

    private let call: SignalCall
    private weak var delegate: CallHeaderDelegate!

    init(call: SignalCall, delegate: CallHeaderDelegate) {
        self.call = call
        self.delegate = delegate
        super.init(frame: .zero)

        call.addObserverAndSyncState(observer: self)

        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor.ows_blackAlpha60.cgColor,
            UIColor.black.withAlphaComponent(0).cgColor
        ]
        let gradientView = OWSLayerView(frame: .zero) { view in
            gradientLayer.frame = view.bounds
        }
        gradientView.layer.addSublayer(gradientLayer)

        addSubview(gradientView)
        gradientView.autoPinEdgesToSuperviewEdges()

        let hStack = UIStackView()
        hStack.axis = .horizontal
        hStack.spacing = 13
        hStack.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        hStack.isLayoutMarginsRelativeArrangement = true
        addSubview(hStack)
        hStack.autoPinWidthToSuperview()
        hStack.autoPinEdge(toSuperviewMargin: .top)
        hStack.autoPinEdge(toSuperviewEdge: .bottom, withInset: 46)

        // Back button

        let backButton = UIButton()
        let backButtonImage = CurrentAppContext().isRTL ? #imageLiteral(resourceName: "NavBarBackRTL") : #imageLiteral(resourceName: "NavBarBack")
        backButton.setTemplateImage(backButtonImage, tintColor: .ows_white)
        backButton.autoSetDimensions(to: CGSize(square: 40))
        backButton.addTarget(delegate, action: #selector(CallHeaderDelegate.didTapBackButton), for: .touchUpInside)
        addShadow(to: backButton)

        hStack.addArrangedSubview(backButton)

        // vStack

        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.spacing = 4

        hStack.addArrangedSubview(vStack)

        // Name Label

        callTitleLabel.type = .continuous
        // This feels pretty slow when you're initially waiting for it, but when you're overlaying video calls, anything faster is distracting.
        callTitleLabel.speed = .duration(30.0)
        callTitleLabel.animationCurve = .linear
        callTitleLabel.fadeLength = 10.0
        callTitleLabel.animationDelay = 5
        // Add trailing space after the name scrolls before it wraps around and scrolls back in.
        callTitleLabel.trailingBuffer = ScaleFromIPhone5(80.0)

        callTitleLabel.font = UIFont.ows_dynamicTypeHeadlineClamped.ows_semibold
        callTitleLabel.textAlignment = .center
        callTitleLabel.textColor = UIColor.white
        addShadow(to: callTitleLabel)

        vStack.addArrangedSubview(callTitleLabel)
        callTitleLabel.setContentHuggingVerticalHigh()
        callTitleLabel.setCompressionResistanceHigh()

        // Status label

        callStatusLabel.font = UIFont.ows_dynamicTypeFootnoteClamped
        callStatusLabel.textAlignment = .center
        callStatusLabel.textColor = UIColor.white
        addShadow(to: callStatusLabel)

        vStack.addArrangedSubview(callStatusLabel)
        callStatusLabel.setContentHuggingVerticalHigh()
        callStatusLabel.setCompressionResistanceHigh()

        // Group members button

        groupMembersButton.titleLabel?.font = UIFont.ows_dynamicTypeFootnoteClamped.ows_monospaced
        groupMembersButton.setTitleColor(.ows_white, for: .normal)
        groupMembersButton.setTemplateImage(#imageLiteral(resourceName: "group-solid-16"), tintColor: .ows_white)
        groupMembersButton.autoSetDimensions(to: CGSize(square: 50))
        groupMembersButton.addTarget(delegate, action: #selector(CallHeaderDelegate.didTapMembersButton), for: .touchUpInside)
        addShadow(to: groupMembersButton)

        hStack.addArrangedSubview(groupMembersButton)
        hStack.addArrangedSubview(groupMembersButtonPlaceholder)

        updateCallTitleLabel()
        updateCallStatusLabel()
        updateGroupMembersButton()
    }

    deinit { call.removeObserver(self) }

    private func addShadow(to view: UIView) {
        view.layer.shadowOffset = .zero
        view.layer.shadowOpacity = 0.25
        view.layer.shadowRadius = 4
    }

    private func updateCallStatusLabel() {
        let callStatusText: String
        switch call.groupCall.localDeviceState.joinState {
        case .notJoined, .joining:
            callStatusText = ""
        case .joined:
            let callDuration = call.connectionDuration()
            let callDurationDate = Date(timeIntervalSinceReferenceDate: callDuration)
            var formattedDate = dateFormatter.string(from: callDurationDate)
            if formattedDate.hasPrefix("00:") {
                // Don't show the "hours" portion of the date format unless the
                // call duration is at least 1 hour.
                formattedDate = String(formattedDate[formattedDate.index(formattedDate.startIndex, offsetBy: 3)...])
            } else {
                // If showing the "hours" portion of the date format, strip any leading
                // zeroes.
                if formattedDate.hasPrefix("0") {
                    formattedDate = String(formattedDate[formattedDate.index(formattedDate.startIndex, offsetBy: 1)...])
                }
            }
            callStatusText = String(format: CallStrings.callStatusFormat, formattedDate)
        }

        callStatusLabel.text = callStatusText
        callStatusLabel.isHidden = call.groupCall.localDeviceState.joinState != .joined || call.groupCall.sortedRemoteDeviceStates.count > 1

        // Handle reconnecting blinking
        if call.groupCall.localDeviceState.connectionState == .reconnecting {
            if !isBlinkingReconnectLabel {
                isBlinkingReconnectLabel = true
                UIView.animate(withDuration: 0.7, delay: 0, options: [.autoreverse, .repeat],
                               animations: {
                                self.callStatusLabel.alpha = 0.2
                }, completion: nil)
            } else {
                // already blinking
            }
        } else {
            // We're no longer in a reconnecting state, either the call failed or we reconnected.
            // Stop the blinking animation
            if isBlinkingReconnectLabel {
                callStatusLabel.layer.removeAllAnimations()
                callStatusLabel.alpha = 1
                isBlinkingReconnectLabel = false
            }
        }
    }

    func updateCallTitleLabel() {
        let callTitleText: String

        let memberNames: [String] = databaseStorage.uiRead { transaction in
            if self.call.groupCall.localDeviceState.joinState == .joined {
                return self.call.groupCall.sortedRemoteDeviceStates
                    .map { self.contactsManager.displayName(for: $0.address, transaction: transaction) }
            } else {
                // TODO: For now, we can only use `joinedGroupMembers` before you join.
                // We might be able to just always use it here.
                return self.call.groupCall.joinedGroupMembers
                    .filter { !SignalServiceAddress(uuid: $0).isLocalAddress }
                    .map { self.contactsManager.displayName(for: SignalServiceAddress(uuid: $0), transaction: transaction) }
            }
        }

        switch call.groupCall.localDeviceState.joinState {
        case .joined:
            switch memberNames.count {
            case 0:
                callTitleText = NSLocalizedString(
                    "GROUP_CALL_NO_ONE_HERE",
                    comment: "Text explaining that you are the only person currently in the group call"
                )
            case 1:
                callTitleText = memberNames[0]
            default:
                callTitleText = ""
            }
        default:
            switch memberNames.count {
            case 0:
                callTitleText = ""
            case 1:
                let formatString = NSLocalizedString(
                    "GROUP_CALL_ONE_PERSON_HERE_FORMAT",
                    comment: "Text explaining that there is one person in the group call. Embeds {member name}"
                )
                callTitleText = String(format: formatString, memberNames[0])
            case 2:
                let formatString = NSLocalizedString(
                    "GROUP_CALL_TWO_PEOPLE_HERE_FORMAT",
                    comment: "Text explaining that there are two people in the group call. Embeds {member name}"
                )
                callTitleText = String(format: formatString, memberNames[0], memberNames[1])
            default:
                let formatString = NSLocalizedString(
                    "GROUP_CALL_MANY_PEOPLE_HERE_FORMAT",
                    comment: "Text explaining that there are three or more people in the group call. Embeds {member name}"
                )
                callTitleText = String(format: formatString, memberNames[0], memberNames[1], call.groupCall.joinedGroupMembers.count - 2)
            }
        }

        callTitleLabel.text = callTitleText
        callTitleLabel.isHidden = callTitleText.isEmpty
    }

    func updateGroupMembersButton() {
        groupMembersButton.setTitle(" \(call.groupCall.joinedGroupMembers.count)", for: .normal)
        groupMembersButton.isHidden = call.groupCall.localDeviceState.joinState == .joined
            ? call.groupCall.remoteDeviceStates.count < 2
            : call.groupCall.joinedGroupMembers.count < 2
        groupMembersButtonPlaceholder.isHidden = !groupMembersButton.isHidden
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension CallHeader: CallObserver {
    func individualCallStateDidChange(_ call: SignalCall, state: CallState) {}
    func individualCallLocalVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {}
    func individualCallLocalAudioMuteDidChange(_ call: SignalCall, isAudioMuted: Bool) {}
    func individualCallRemoteVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {}
    func individualCallHoldDidChange(_ call: SignalCall, isOnHold: Bool) {}

    func groupCallLocalDeviceStateChanged(_ call: SignalCall) {
        owsAssertDebug(call.isGroupCall)

        if call.groupCall.localDeviceState.joinState == .joined {
            if callDurationTimer == nil {
                let kDurationUpdateFrequencySeconds = 1 / 20.0
                callDurationTimer = WeakTimer.scheduledTimer(
                    timeInterval: TimeInterval(kDurationUpdateFrequencySeconds),
                    target: self,
                    userInfo: nil,
                    repeats: true
                ) {[weak self] _ in
                    self?.updateCallStatusLabel()
                }
            }
        } else {
            callDurationTimer?.invalidate()
            callDurationTimer = nil
        }

        updateCallTitleLabel()
        updateCallStatusLabel()
    }

    func groupCallJoinedMembersChanged(_ call: SignalCall) {
        updateCallTitleLabel()
        updateGroupMembersButton()
    }

    func groupCallRemoteDeviceStatesChanged(_ call: SignalCall) {}
    func groupCallRequestMembershipProof(_ call: SignalCall) {}
    func groupCallRequestGroupMembers(_ call: SignalCall) {}
    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason) {}
}
