//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalRingRTC
import SignalServiceKit

// MARK: - RaisedHandsToastDelegate

protocol RaisedHandsToastDelegate: AnyObject {
    func didTapViewRaisedHands()
    func raisedHandsToastDidChangeHeight()
}

// MARK: - RaisedHandsToast

class RaisedHandsToast: UIView {

    // MARK: Properties

    private enum Constants {
        static let hMarginCollapsed: CGFloat = 16
        static let hMarginExpanded: CGFloat = 12
        static let vMargin: CGFloat = 12
    }

    struct Dependencies {
        let db: SDSDatabaseStorage
        let contactsManager: any ContactManager
    }

    private let deps = Dependencies(
        db: SSKEnvironment.shared.databaseStorageRef,
        contactsManager: SSKEnvironment.shared.contactManagerRef
    )

    private let outerHStack = UIStackView()
    private let iconLabelContainer = UIView()
    private let labelContainer = UIView()
    private let label = UILabel()
    private lazy var viewButton = OWSButton(
        title: CommonStrings.viewButton,
        tintColor: .ows_white,
        dimsWhenHighlighted: true
    ) { [weak self] in
        self?.delegate?.didTapViewRaisedHands()
    }
    private lazy var lowerHandButton = OWSButton(
        title: CallStrings.lowerHandButton,
        tintColor: .ows_white,
        dimsWhenHighlighted: true
    ) { [weak self] in
        self?.call.ringRtcCall.raiseHand(raise: false)
    }

    private var isCollapsed = false

    private var collapsedText: String = ""
    private var expandedText: String = ""

    private var call: GroupCall
    weak var delegate: RaisedHandsToastDelegate?
    var horizontalPinConstraint: NSLayoutConstraint?

    var raisedHands: [DemuxId] = [] {
        didSet {
            self.updateRaisedHands(raisedHands, oldValue: oldValue)
        }
    }

    private var yourHandIsRaised: Bool {
        self.call.ringRtcCall.localDeviceState.demuxId.map(raisedHands.contains) ?? false
    }

    // MARK: Init

    init(call: GroupCall) {
        self.call = call
        super.init(frame: .zero)

        self.addSubview(outerHStack)
        outerHStack.axis = .horizontal
        outerHStack.alignment = .center
        outerHStack.autoPinEdgesToSuperviewEdges()
        outerHStack.addBackgroundBlurView(blur: .systemMaterialDark, accessibilityFallbackColor: .ows_gray75)
        outerHStack.clipsToBounds = true

        let raisedHandIcon = UILabel()
        raisedHandIcon.attributedText = .with(
            image: UIImage(named: "raise_hand")!,
            font: .dynamicTypeTitle3,
            attributes: [.foregroundColor: UIColor.white]
        )
        raisedHandIcon.setContentCompressionResistancePriority(.required, for: .horizontal)
        raisedHandIcon.contentMode = .scaleAspectFit
        raisedHandIcon.tintColor = .white
        raisedHandIcon.setContentHuggingHorizontalHigh()
        raisedHandIcon.setCompressionResistanceVerticalHigh()

        labelContainer.addSubview(label)
        labelContainer.heightAnchor.constraint(greaterThanOrEqualTo: label.heightAnchor, multiplier: 1).isActive = true
        label.autoPinEdges(toSuperviewEdgesExcludingEdge: .bottom)
        label.font = .dynamicTypeBody2
        label.numberOfLines = 0
        label.contentMode = CurrentAppContext().isRTL ? .topRight : .topLeft
        label.textColor = .white
        label.setContentHuggingHorizontalLow()
        label.setCompressionResistanceVerticalHigh()

        outerHStack.addArrangedSubview(iconLabelContainer)
        iconLabelContainer.addSubview(raisedHandIcon)
        iconLabelContainer.addSubview(labelContainer)

        let lineHeight = label.font.lineHeight
        raisedHandIcon.centerYAnchor.constraint(equalTo: labelContainer.topAnchor, constant: lineHeight / 2).isActive = true
        raisedHandIcon.autoPinEdge(toSuperviewMargin: .top)
        raisedHandIcon.autoPinEdge(toSuperviewMargin: .leading)

        labelContainer.autoPinEdge(toSuperviewMargin: .trailing)
        labelContainer.autoVCenterInSuperview()
        labelContainer.autoPinEdge(.leading, to: .trailing, of: raisedHandIcon, withOffset: 12)

        for button in [self.viewButton, self.lowerHandButton] {
            outerHStack.addArrangedSubview(button)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.setContentHuggingHorizontalHigh()
            // The button slides to the trailing edge when hiding, but it only goes as
            // far as the superview's margins, so if we had
            // isLayoutMarginsRelativeArrangement on outerHStack, the button wouldn't
            // slide all the way off, so instead set margins on the button itself.
            button.ows_contentEdgeInsets = .init(
                top: 8,
                leading: 8,
                bottom: 8,
                trailing: Constants.hMarginExpanded
            )
            button.titleLabel?.font = .dynamicTypeBody2.bold()
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(toggleExpanded))
        outerHStack.addGestureRecognizer(tapGesture)
        outerHStack.isUserInteractionEnabled = true

        updateExpansionState(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if isCollapsed {
            layer.cornerRadius = height / 2
        }
    }

    // MARK: State

    private var autoCollapseTimer: Timer?

    /// Called by a parent when a hide animation is completed. Sets
    /// `isCollapsed` to `false` so it is expanded for its next presentation.
    func wasHidden() {
        self.isCollapsed = false
        self.updateExpansionState(animated: false)
    }

    @objc
    private func toggleExpanded() {
        self.isCollapsed.toggle()
        self.updateExpansionState(animated: true)

        guard !self.isCollapsed else { return }
        self.queueCollapse()
    }

    private func queueCollapse() {
        self.autoCollapseTimer?.invalidate()
        self.autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.isCollapsed = true
            self.updateExpansionState(animated: true)
            self.autoCollapseTimer = nil
        }
    }

    /// Updates the view contents and constraints based on the value of `isCollapsed`.
    /// - Parameter animated: Whether the change should be animated.
    /// Note that changes in view height will result in a
    /// `delegate?.raisedHandsToastDidChangeHeight` call which will animate the
    /// superview, regardless of this value.
    private func updateExpansionState(animated: Bool) {
        let oldHeight = self.height

        if isCollapsed {
            label.text = self.collapsedText
        } else {
            label.text = self.expandedText
        }

        let action: () -> Void = {
            self.viewButton.isHiddenInStackView = self.isCollapsed || self.yourHandIsRaised
            self.lowerHandButton.isHiddenInStackView = self.isCollapsed || !self.yourHandIsRaised

            self.horizontalPinConstraint?.isActive = !self.isCollapsed
            self.layoutIfNeeded()
            self.outerHStack.layer.cornerRadius = self.isCollapsed ? self.outerHStack.height / 2 : 10
            self.iconLabelContainer.layoutMargins = .init(
                hMargin: self.isCollapsed ? Constants.hMarginCollapsed : Constants.hMarginExpanded,
                vMargin: Constants.vMargin
            )
        }

        if animated {
            let animator = UIViewPropertyAnimator(duration: 0.3, springDamping: 1, springResponse: 0.3)
            animator.addAnimations(action)
            animator.startAnimation()
        } else {
            action()
        }

        if self.height != oldHeight {
            self.delegate?.raisedHandsToastDidChangeHeight()
        }
    }

    private func updateRaisedHands(_ raisedHands: [DemuxId], oldValue: [DemuxId]) {
        guard raisedHands != oldValue else { return }

        guard let firstRaisedHandDemuxID = raisedHands.first else {
            // Parent handles hiding. Don't update state.
            // Prevent auto collapse while it's disappearing.
            self.autoCollapseTimer?.invalidate()
            return
        }

        self.collapsedText = if self.yourHandIsRaised, raisedHands.count > 1 {
            String(
                format: OWSLocalizedString(
                    "RAISED_HANDS_TOAST_YOU_PLUS_OTHERS_COUNT",
                    comment: "A compact member count on the call view's raised hands toast indicating that you and a number of other users raised a hand. Embeds {{number of other users}}"
                ),
                raisedHands.count - 1
            )
        } else if self.yourHandIsRaised {
            CommonStrings.you
        } else {
            "\(raisedHands.count)"
        }

        self.expandedText = {
            if self.yourHandIsRaised, raisedHands.count == 1 {
                return OWSLocalizedString(
                    "RAISED_HANDS_TOAST_YOUR_HAND_MESSAGE",
                    comment: "A message appearing on the call view's raised hands toast indicating that you raised your own hand."
                )
            }

            let firstRaisedHandMemberName: String
            if self.yourHandIsRaised {
                firstRaisedHandMemberName = CommonStrings.you
            } else if let firstRaisedHandRemoteDeviceState = self.call.ringRtcCall.remoteDeviceStates[firstRaisedHandDemuxID] {
                firstRaisedHandMemberName = self.deps.db.read { tx -> String in
                    self.deps.contactsManager.displayName(
                        for: firstRaisedHandRemoteDeviceState.address,
                        tx: tx
                    ).resolvedValue(useShortNameIfAvailable: true)
                }
            } else {
                owsFailDebug("Could not find remote device state for demux ID")
                firstRaisedHandMemberName = CommonStrings.unknownUser
            }

            if raisedHands.count > 1 {
                let otherMembersCount = raisedHands.count - 1
                let format = OWSLocalizedString(
                    "RAISED_HANDS_TOAST_MULTIPLE_HANDS_MESSAGE",
                    tableName: "PluralAware",
                    comment: "A message appearing on the call view's raised hands toast indicating that multiple members have raised their hands. Example: 'Alice +4 raised a hand'. Embeds {{number of other users}}, {{name}}"
                )
                return String.localizedStringWithFormat(format, otherMembersCount, firstRaisedHandMemberName)
            }

            return String(
                format: OWSLocalizedString(
                    "RAISED_HANDS_TOAST_SINGLE_HAND_MESSAGE",
                    comment: "A message appearing on the call view's raised hands toast indicating that another named member has raised their hand."
                ),
                firstRaisedHandMemberName
            )
        }()

        var youJustRaisedYourHand: Bool {
            self.call.ringRtcCall.localDeviceState.demuxId.map({ yourDemuxID in
                raisedHands.contains(yourDemuxID) && !oldValue.contains(yourDemuxID)
            }) ?? false
        }

        if oldValue.isEmpty || youJustRaisedYourHand {
            self.isCollapsed = false
        }

        self.updateExpansionState(animated: !oldValue.isEmpty)
        self.queueCollapse()
    }

}
