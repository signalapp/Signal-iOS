//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

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
    private let callTitleLabel = UILabel()
    private let callStatusLabel = UILabel()
    private let groupMembersButton = UIButton()
    private let groupMembersButtonPlaceholder = UIView.spacer(withWidth: 40)
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
        hStack.layoutMargins = UIEdgeInsets(top: 0, left: 17, bottom: 0, right: 17)
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

        hStack.addArrangedSubview(backButton)

        // vStack

        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.spacing = 4

        hStack.addArrangedSubview(vStack)

        // Name Label

        callTitleLabel.font = UIFont.ows_dynamicTypeHeadlineClamped.ows_semibold
        callTitleLabel.textAlignment = .center
        callTitleLabel.textColor = UIColor.white
        callTitleLabel.layer.shadowOffset = .zero
        callTitleLabel.layer.shadowOpacity = 0.25
        callTitleLabel.layer.shadowRadius = 4
        callTitleLabel.numberOfLines = 0
        callTitleLabel.lineBreakMode = .byWordWrapping

        vStack.addArrangedSubview(callTitleLabel)
        callTitleLabel.setContentHuggingVerticalHigh()
        callTitleLabel.setCompressionResistanceHigh()

        // Status label

        callStatusLabel.font = UIFont.ows_dynamicTypeFootnoteClamped
        callStatusLabel.textAlignment = .center
        callStatusLabel.textColor = UIColor.white
        callStatusLabel.layer.shadowOffset = .zero
        callStatusLabel.layer.shadowOpacity = 0.25
        callStatusLabel.layer.shadowRadius = 4

        vStack.addArrangedSubview(callStatusLabel)
        callStatusLabel.setContentHuggingVerticalHigh()
        callStatusLabel.setCompressionResistanceHigh()

        // Group members button

        groupMembersButton.setTemplateImage(#imageLiteral(resourceName: "group-solid-24"), tintColor: .ows_white)
        groupMembersButton.autoSetDimensions(to: CGSize(square: 40))
        groupMembersButton.addTarget(delegate, action: #selector(CallHeaderDelegate.didTapMembersButton), for: .touchUpInside)

        hStack.addArrangedSubview(groupMembersButton)
        hStack.addArrangedSubview(groupMembersButtonPlaceholder)

        updateCallTitleLabel()
        updateCallStatusLabel()
        updateGroupMembersButton()
    }

    private func updateCallStatusLabel() {
        let callStatusText: String
        switch call.groupCall.localDevice.joinState {
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
        callStatusLabel.isHidden = callStatusText.isEmpty

        // Handle reconnecting blinking
        if call.groupCall.localDevice.connectionState == .reconnecting {
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

        let members = databaseStorage.uiRead { transaction in
            return self.call.groupCall.joinedGroupMembers
                .map { SignalServiceAddress(uuid: $0) }
                .filter { !$0.isLocalAddress }
                .map {
                    (
                        address: $0,
                        displayName: self.contactsManager.displayName(for: $0, transaction: transaction),
                        comparableName: self.contactsManager.comparableName(for: $0, transaction: transaction)
                    )
                }
                .sorted { $0.comparableName > $1.comparableName }
        }

        // TODO: Localization
        switch members.count {
        case 0:
            callTitleText = "No one else is here"
        case 1:
            callTitleText = "\(members[0].displayName) is in this call"
        case 2:
            callTitleText = "\(members[0].displayName) and \(members[1].displayName) are in this call"
        default:
            callTitleText = "\(members[0].displayName), \(members[1].displayName), and \(call.groupCall.joinedGroupMembers.count - 2) others are in this call"
        }

        callTitleLabel.text = callTitleText
        callTitleLabel.isHidden = callTitleText.isEmpty
    }

    func updateGroupMembersButton() {
        groupMembersButton.isHidden = call.groupCall.joinedGroupMembers.isEmpty
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

        if call.groupCall.localDevice.joinState == .joined {
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

    func groupCallJoinedGroupMembersChanged(_ call: SignalCall) {
        updateCallTitleLabel()
        updateGroupMembersButton()
    }

    func groupCallRemoteDeviceStatesChanged(_ call: SignalCall) {}
    func groupCallUpdateSfuInfo(_ call: SignalCall) {}
    func groupCallUpdateGroupMembershipProof(_ call: SignalCall) {}
    func groupCallUpdateGroupMembers(_ call: SignalCall) {}
    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason) {}
}
