//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalServiceKit
import SignalRingRTC

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
            self.updateRaisedHands(raisedHands)
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
        // TODO: Localize
        label.contentMode = .topLeft
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

    @objc
    private func toggleExpanded() {
        // TODO: Automatically collapse after a timer
        self.isCollapsed.toggle()
        updateExpansionState(animated: true)
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

    private func updateRaisedHands(_ raisedHands: [DemuxId]) {
        guard let firstRaisedHandDemuxID = raisedHands.first else {
            // Parent handles hiding. Don't update.
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
                // TODO: Localize
                "You + \(raisedHands.count - 1)"
            } else if yourHandIsRaised {
                // TODO: Unique localization to make sure it matches the above?
                CommonStrings.you
            } else {
                "\(raisedHands.count)"
            }

            let youAreFirstInQueue = firstRaisedHandRemoteDeviceState.aci == tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci

            let expandedText: String
            if youAreFirstInQueue, raisedHands.count == 1 {
                // TODO: Localize
                expandedText = "You raised your hand"
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
                    // TODO: Localize
                    expandedText = "\(firstRaisedHandMemberName) and \(otherMembersCount) more have raised a hand"
                } else {
                    // TODO: Localize
                    expandedText = "\(firstRaisedHandMemberName) has raised a hand"
                }
            }

            return (collapsedText, expandedText)
        }

        self.updateExpansionState(animated: true)
    }
}
