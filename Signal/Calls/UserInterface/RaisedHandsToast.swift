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
}

// MARK: - RaisedHandsToast

class RaisedHandsToast: UIView {

    // MARK: Properties

    private let outerHStack = UIStackView()
    private let iconLabelHStack = UIStackView()
    private let labelContainer = UIView()
    private let label = UILabel()
    private lazy var button = OWSButton(
        title: CommonStrings.viewButton,
        tintColor: .ows_white,
        dimsWhenHighlighted: true
    ) { [weak self] in
        self?.delegate?.didTapViewRaisedHands()
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

    // MARK: Init

    init(call: GroupCall) {
        self.call = call
        super.init(frame: .zero)

        self.addSubview(outerHStack)
        outerHStack.axis = .horizontal
        outerHStack.alignment = .center
        outerHStack.autoPinEdgesToSuperviewEdges()

        outerHStack.addArrangedSubview(iconLabelHStack)
        iconLabelHStack.axis = .horizontal
        iconLabelHStack.alignment = .top
        iconLabelHStack.spacing = 12
        iconLabelHStack.layoutMargins = .init(margin: 12)
        iconLabelHStack.isLayoutMarginsRelativeArrangement = true

        outerHStack.addBackgroundBlurView(blur: .dark, accessibilityFallbackColor: .ows_gray80)
        outerHStack.layer.cornerRadius = 10
        outerHStack.clipsToBounds = true

        let raisedHandIcon = UIImageView(image: UIImage(named: "raise_hand"))
        raisedHandIcon.setContentCompressionResistancePriority(.required, for: .horizontal)
        raisedHandIcon.contentMode = .scaleAspectFit
        raisedHandIcon.tintColor = .white
        raisedHandIcon.setContentHuggingHorizontalHigh()
        raisedHandIcon.setCompressionResistanceVerticalHigh()
        iconLabelHStack.addArrangedSubview(raisedHandIcon)

        labelContainer.addSubview(label)
        labelContainer.heightAnchor.constraint(greaterThanOrEqualTo: label.heightAnchor, multiplier: 1).isActive = true
        label.autoPinEdges(toSuperviewEdgesExcludingEdge: .bottom)
        // TODO: Set font
        label.numberOfLines = 0
        label.contentMode = CurrentAppContext().isRTL ? .topRight : .topLeft
        label.textColor = .white
        label.setContentHuggingHorizontalLow()
        label.setCompressionResistanceVerticalHigh()
        iconLabelHStack.addArrangedSubview(labelContainer)

        outerHStack.addArrangedSubview(button)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentHuggingHorizontalHigh()
        // The button slides to the trailing edge when hiding, but it only goes as
        // far as the superview's margins, so if we had
        // isLayoutMarginsRelativeArrangement on outerHStack, the button wouldn't
        // slide all the way off, so instead set margins on the button itself.
        button.contentEdgeInsets = .init(top: 8, leading: 8, bottom: 8, trailing: 12)

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

    private func updateExpansionState(animated: Bool) {
        if isCollapsed {
            label.text = self.collapsedText
        } else {
            label.text = self.expandedText
        }

        let action: () -> Void = {
            self.button.isHidden = self.isCollapsed
            self.horizontalPinConstraint?.isActive = !self.isCollapsed
            self.layoutIfNeeded()
            self.outerHStack.layer.cornerRadius = self.isCollapsed ? self.outerHStack.height / 2 : 10
        }

        if animated {
            let animator = UIViewPropertyAnimator(duration: 0.3, springDamping: 1, springResponse: 0.3)
            animator.addAnimations(action)
            animator.startAnimation()
        } else {
            action()
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

        guard let firstRaisedHandRemoteDeviceState = self.call.ringRtcCall.remoteDeviceStates[firstRaisedHandDemuxID] else {
            // TODO: Local user raise hand
            owsFailDebug("Could not find remote device state for demux ID")
            return
        }

        // TODO: Inject account manager and database storage
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        (self.collapsedText, self.expandedText) = databaseStorage.read { tx -> (String, String) in
            let yourHandIsRaised = self.call.ringRtcCall.localDeviceState.demuxId.map(raisedHands.contains) ?? false
            let collapsedText: String = if yourHandIsRaised, raisedHands.count > 1 {
                "\(CommonStrings.you) + \(raisedHands.count - 1)"
            } else if yourHandIsRaised {
                CommonStrings.you
            } else {
                "\(raisedHands.count)"
            }

            let youAreFirstInQueue = firstRaisedHandRemoteDeviceState.aci == tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci

            let expandedText: String
            if youAreFirstInQueue, raisedHands.count == 1 {
                expandedText = OWSLocalizedString(
                    "RAISED_HANDS_TOAST_YOUR_HAND_MESSAGE",
                    comment: "A message appearing on the call view's raised hands toast indicating that you raised your own hand."
                )
            } else {
                let firstRaisedHandMemberName = if youAreFirstInQueue {
                    CommonStrings.you
                } else {
                    self.contactsManager.displayName(
                        for: firstRaisedHandRemoteDeviceState.address,
                        tx: tx
                    ).resolvedValue(useShortNameIfAvailable: true)
                }

                if raisedHands.count > 1 {
                    let otherMembersCount = raisedHands.count - 1
                    expandedText = String(
                        format: OWSLocalizedString(
                            "RAISED_HANDS_TOAST_MULTIPLE_HANDS_MESSAGE_%d",
                            tableName: "PluralAware",
                            comment: "A message appearing on the call view's raised hands toast indicating that multiple members have raised their hands."
                        ),
                        firstRaisedHandMemberName, otherMembersCount
                    )
                } else {
                    expandedText = String(
                        format: OWSLocalizedString(
                            "RAISED_HANDS_TOAST_SINGLE_HAND_MESSAGE",
                            comment: "A message appearing on the call view's raised hands toast indicating that another named member has raised their hand."
                        ),
                        firstRaisedHandMemberName
                    )
                }
            }

            return (collapsedText, expandedText)
        }

        if oldValue.isEmpty {
            self.isCollapsed = false
        }

        self.updateExpansionState(animated: true)
        self.queueCollapse()
    }
}
