//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import Foundation
import Lottie
import QuartzCore
import SignalMessaging
import SignalUI

class GiftBadgeView: ManualStackView {

    struct State {
        enum Badge {
            // The badge isn't loaded. Calling the block will load it.
            case notLoaded(() -> Promise<Void>)
            // The badge is loaded. The associated value is the badge.
            case loaded(ProfileBadge)
            // No badge was found for the level in the gift.
            case notFound
        }
        let badge: Badge
        let messageUniqueId: String
        let timeRemainingText: String
        let otherUserShortName: String
        let redemptionState: OWSGiftBadgeRedemptionState
        let isIncoming: Bool
        let conversationStyle: ConversationStyle
    }

    // The outerStack contains the details (innerStack) & redeem button.
    private static let measurementKey_outerStack = "GiftBadgeView.measurementKey_outerStack"
    private static var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .fill,
            spacing: 15,
            layoutMargins: .init(hMargin: 0, vMargin: 8)
        )
    }

    // The innerStack contains the badge icon & labels (labelStack).
    private let innerStack = ManualStackView(name: "GiftBadgeView.innerStack")
    private static let measurementKey_innerStack = "GiftBadgeView.measurementKey_innerStack"
    private static var innerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .horizontal,
            alignment: .center,
            spacing: 12,
            layoutMargins: .init(hMargin: 4, vMargin: 0)
        )
    }

    // The labelStack contains "Gift Badge" & "N days remaining".
    private let labelStack = ManualStackView(name: "GiftBadgeView.labelStack")
    private static let measurementKey_labelStack = "GiftBadgeView.measurementKey_labelStack"
    private static var labelStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical, alignment: .leading, spacing: 4, layoutMargins: .zero)
    }

    private let titleLabel = CVLabel()
    private static func titleLabelConfig(for state: State) -> CVLabelConfig {
        let textFormat: String
        if state.isIncoming {
            textFormat = NSLocalizedString(
                "DONATION_ON_BEHALF_OF_A_FRIEND_RECEIVED_TITLE_FORMAT",
                comment: "You received a donation from a friend. This is the title of that message in the chat. Embeds {{short contact name}}."
            )
        } else {
            textFormat = NSLocalizedString(
                "DONATION_ON_BEHALF_OF_A_FRIEND_SENT_TITLE_FORMAT",
                comment: "You sent a donation to a friend. This is the title of that message in the chat. Embeds {{short contact name}}."
            )
        }
        let text = String(format: textFormat, state.otherUserShortName)

        let textColor = state.conversationStyle.bubbleTextColor(isIncoming: state.isIncoming)

        return CVLabelConfig(
            text: text,
            font: .ows_dynamicTypeBody,
            textColor: textColor,
            numberOfLines: 0
        )
    }

    static func timeRemainingText(for expirationDate: Date) -> String {
        let timeRemaining = expirationDate.timeIntervalSinceNow
        guard timeRemaining > 0 else {
            return NSLocalizedString(
                "DONATE_ON_BEHALF_OF_A_FRIEND_CHAT_EXPIRED",
                comment: "If a donation badge has been sent, indicates that it's expired and can no longer be redeemed. This is shown in the chat."
            )
        }
        return self.localizedDurationText(for: timeRemaining)
    }

    private static func localizedDurationText(for timeRemaining: TimeInterval) -> String {
        // If there's less than a minute remaining, report "1 minute remaining".
        // Otherwise, we'll say "0 minutes remaining", which implies the badge has
        // expired, even though it hasn't.
        let normalizedTimeRemaining = max(timeRemaining, 60)

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .hour, .day]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .full
        formatter.includesTimeRemainingPhrase = true
        guard let result = formatter.string(from: normalizedTimeRemaining) else {
            owsFailDebug("Couldn't format time until badge expiration")
            return ""
        }
        return result
    }

    private let timeRemainingLabel = CVLabel()
    private static func timeRemainingLabelConfig(for state: State) -> CVLabelConfig {
        let textColor = state.conversationStyle.bubbleSecondaryTextColor(isIncoming: state.isIncoming)
        return CVLabelConfig(
            text: state.timeRemainingText,
            font: .ows_dynamicTypeSubheadline,
            textColor: textColor,
            numberOfLines: 0
        )
    }

    // Use a stack with one item to get layout & padding for free.
    public let buttonStack = ManualStackViewWithLayer(name: "GiftBadgeView.buttonStack")
    private static let measurementKey_buttonStack = "GiftBadgeView.measurementKey_buttonStack"
    private static var buttonStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .horizontal,
            alignment: .center,
            spacing: 0,
            layoutMargins: UIEdgeInsets(margin: 10)
        )
    }

    private func redeemButtonBackgroundColor(for state: State) -> UIColor {
        if state.isIncoming {
            return state.conversationStyle.isDarkThemeEnabled ? .ows_gray60 : .ows_whiteAlpha80
        } else {
            return .ows_whiteAlpha70
        }
    }

    // This is a label, not a button, to remain compatible with the hit testing code.
    private let redeemButtonLabel = CVLabel()
    private static func redeemButtonLabelConfig(for state: State) -> CVLabelConfig {
        let font: UIFont = .ows_dynamicTypeBody.ows_semibold
        return CVLabelConfig(
            attributedText: Self.redeemButtonText(for: state, font: font),
            font: font,
            textColor: Self.redeemButtonTextColor(for: state),
            lineBreakMode: .byTruncatingTail,
            textAlignment: .center
        )
    }

    private static func redeemButtonTextColor(for state: State) -> UIColor {
        if state.isIncoming {
            return state.conversationStyle.bubbleTextColorIncoming
        } else {
            return .ows_gray90
        }
    }

    private static func redeemButtonText(for state: State, font: UIFont) -> NSAttributedString {
        let nonAttributedString: String
        if state.isIncoming {
            // TODO: (GB) Alter this value based on whether or not the badge has been redeemed.
            switch state.redemptionState {
            case .opened:
                owsFailDebug("Only outgoing gifts can be permanently opened")
                fallthrough
            case .pending:
                nonAttributedString = CommonStrings.redeemGiftButton
            case .redeemed:
                let attrString = NSMutableAttributedString()
                attrString.appendTemplatedImage(named: "check-circle-outline-24", font: font)
                attrString.append("\u{2004}\u{2009}")
                attrString.append(NSLocalizedString(
                    "DONATION_ON_BEHALF_OF_A_FRIEND_BADGE_REDEEMED",
                    comment: "Label for a button to see details about a badge you've already redeemed, received as a result of a donation from a friend. This text is shown next to a check mark."
                ))
                return attrString
            }
        } else {
            nonAttributedString = NSLocalizedString(
                "DONATION_ON_BEHALF_OF_A_FRIEND_VIEW",
                comment: "A button shown on a donation message you send, to view additional details about the badge that was sent."
            )
        }
        return NSAttributedString(string: nonAttributedString)
    }

    private let badgeView = CVImageView()
    private static let badgeSize: CGFloat = 64

    struct ActivityIndicator {
        var name: String
        var view: AnimationView
    }

    private var _activityIndicator: ActivityIndicator?
    private func activityIndicator(for state: State) -> AnimationView {
        let animationName: String
        if state.isIncoming && !state.conversationStyle.isDarkThemeEnabled {
            animationName = "indeterminate_spinner_blue"
        } else {
            animationName = "indeterminate_spinner_white"
        }
        if let activityIndicator = self._activityIndicator, activityIndicator.name == animationName {
            return activityIndicator.view
        }
        let view = AnimationView(name: animationName)
        view.backgroundBehavior = .pauseAndRestore
        view.loopMode = .loop
        view.contentMode = .center
        self._activityIndicator = ActivityIndicator(name: animationName, view: view)
        return view
    }

    private(set) var giftWrap: GiftWrap?

    override func reset() {
        super.reset()

        self.innerStack.reset()
        self.labelStack.reset()
        self.buttonStack.reset()

        self.titleLabel.text = nil
        self.timeRemainingLabel.text = nil
        self.redeemButtonLabel.text = nil

        self.badgeView.image = nil

        self._activityIndicator?.view.stop()

        let allSubviews: [UIView?] = [
            self.innerStack,
            self.labelStack,
            self.buttonStack,
            self.titleLabel,
            self.timeRemainingLabel,
            self.redeemButtonLabel,
            self.badgeView,
            self._activityIndicator?.view
        ]
        for subview in allSubviews {
            subview?.removeFromSuperview()
        }
    }

    func configureForRendering(state: State, cellMeasurement: CVCellMeasurement, componentDelegate: CVComponentDelegate) {
        Self.redeemButtonLabelConfig(for: state).applyForRendering(label: self.redeemButtonLabel)
        self.buttonStack.backgroundColor = self.redeemButtonBackgroundColor(for: state)
        self.buttonStack.addLayoutBlock { v in
            v.layer.cornerRadius = 8
            v.layer.masksToBounds = true
        }
        self.buttonStack.configure(
            config: Self.buttonStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_buttonStack,
            subviews: [self.redeemButtonLabel]
        )

        let innerStackSubviews: [UIView]
        switch state.badge {
        case .notLoaded(let loadPromise):
            loadPromise().done { [weak componentDelegate] in
                componentDelegate?.enqueueReload()
            }.cauterize()
            // TODO: (GB) If an error occurs, we'll be stuck with a spinner.

            let activityIndicator = self.activityIndicator(for: state)
            activityIndicator.play()
            innerStackSubviews = [activityIndicator]
            self.buttonStack.alpha = 0.5

        case .notFound:
            // Show the same UI as we do when loading.
            let activityIndicator = self.activityIndicator(for: state)
            activityIndicator.play()
            innerStackSubviews = [activityIndicator]
            self.buttonStack.alpha = 0.5

        case .loaded(let profileBadge):
            self.badgeView.image = profileBadge.assets?.universal64
            Self.titleLabelConfig(for: state).applyForRendering(label: self.titleLabel)
            Self.timeRemainingLabelConfig(for: state).applyForRendering(label: self.timeRemainingLabel)
            self.labelStack.configure(
                config: Self.labelStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_labelStack,
                subviews: [self.titleLabel, self.timeRemainingLabel]
            )
            innerStackSubviews = [self.badgeView, self.labelStack]
            self.buttonStack.alpha = 1.0
        }
        self.innerStack.configure(
            config: Self.innerStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_innerStack,
            subviews: innerStackSubviews
        )

        self.configure(
            config: Self.outerStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_outerStack,
            subviews: [self.innerStack, self.buttonStack]
        )

        if state.wrapState == .unwrapped || !componentDelegate.willWrapGift(state.messageUniqueId) {
            self.giftWrap = nil
        } else if self.giftWrap?.isIncoming != state.isIncoming {
            // If `giftWrap` is nil, we'll also fall into this case.
            self.giftWrap = GiftWrap(isIncoming: state.isIncoming)
        }
    }

    /**
     * Calculates the maxWidth available within nested stack views.
     *
     * If a view is contained within a stack view, then its available width is
     * reduced by the stack view's horizontal margins. If it's placed within
     * multiple stack views, its available width is reduced by each of the
     * stack view's margins.
     *
     * The `subtracting` parameter allows the caller to account for space
     * consumed by siblings.
     */
    private static func maxWidthForView(
        placedWithin stackConfigs: [CVStackViewConfig],
        startingAt maxWidth: CGFloat,
        subtracting value: CGFloat
    ) -> CGFloat {
        return maxWidth - value - stackConfigs.reduce(0) { $0 + $1.layoutMargins.totalWidth }
    }

    static func measurement(for state: State, maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        // NOTE: We don't alter the measurement when showing the loading animation.
        // This ensures that the size of the bubble doesn't shift once the badge
        // has finished loading.

        let badgeViewSize = CGSize(square: self.badgeSize)

        let outerStackConfig = self.outerStackConfig
        let innerStackConfig = self.innerStackConfig
        let labelStackConfig = self.labelStackConfig
        let buttonStackConfig = self.buttonStackConfig

        // The space for labels is reduced by all stacks & the badgeView.
        let labelMaxWidth = self.maxWidthForView(
            placedWithin: [labelStackConfig, innerStackConfig, outerStackConfig],
            startingAt: maxWidth,
            subtracting: badgeViewSize.width + innerStackConfig.spacing
        )
        let titleLabelSize = self.titleLabelConfig(for: state).measure(maxWidth: labelMaxWidth)
        let timeRemainingLabelSize = self.timeRemainingMeasurement(for: state, maxWidth: labelMaxWidth)

        let labelStackMeasurement = ManualStackView.measure(
            config: labelStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_labelStack,
            subviewInfos: [titleLabelSize.asManualSubviewInfo, timeRemainingLabelSize.asManualSubviewInfo]
        )

        let innerStackMeasurement = ManualStackView.measure(
            config: innerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_innerStack,
            subviewInfos: [
                badgeViewSize.asManualSubviewInfo,
                labelStackMeasurement.measuredSize.asManualSubviewInfo
            ]
        )

        let buttonMaxWidth = self.maxWidthForView(
            placedWithin: [buttonStackConfig, outerStackConfig],
            startingAt: maxWidth,
            subtracting: 0
        )
        let redeemButtonLabelSize = self.redeemButtonLabelConfig(for: state).measure(maxWidth: buttonMaxWidth)

        let buttonStackMeasurement = ManualStackView.measure(
            config: buttonStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_buttonStack,
            subviewInfos: [redeemButtonLabelSize.asManualSubviewInfo]
        )

        let outerStackMeasurement = ManualStackView.measure(
            config: outerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_outerStack,
            subviewInfos: [
                innerStackMeasurement.measuredSize.asManualSubviewInfo,
                buttonStackMeasurement.measuredSize.asManualSubviewInfo
            ]
        )

        return outerStackMeasurement.measuredSize
    }

    private static func timeRemainingMeasurement(for state: State, maxWidth: CGFloat) -> CGSize {
        let labelConfig = self.timeRemainingLabelConfig(for: state)
        var labelSize = labelConfig.measure(maxWidth: maxWidth)

        // The time remaining label often defines the overall width/aspect ratio of
        // the gift message. The "Expired" label is typically the shortest, which
        // leads to weird aspect ratios. Use the maximum of a few sizes to try and
        // give the badge a bit more consistency, even though this may not be
        // perfect across all languages.

        let timeRemainingCandidates: [TimeInterval] = [59*kMinuteInterval, 23*kHourInterval, 59*kDayInterval]
        for timeRemaining in timeRemainingCandidates {
            let candidateConfig = CVLabelConfig(
                text: self.localizedDurationText(for: timeRemaining),
                font: labelConfig.font,
                textColor: labelConfig.textColor,
                // Only consider the first line for these alternative values. This (a)
                // ensures that we don't reserve space for the second line unless the value
                // we're going to show needs two lines and (b) still maintains a roughly
                // constant overall bubble width.
                lineBreakMode: .byTruncatingTail
            )
            let candidateSize = candidateConfig.measure(maxWidth: maxWidth)
            labelSize.width = max(labelSize.width, candidateSize.width)
        }

        return labelSize
    }

    func animateUnwrap() {
        self.giftWrap?.animateUnwrap()
        self.giftWrap = nil
    }
}

// MARK: - Wrapping View

private enum WrapState {
    case wrapped
    case unwrapped
}

private extension GiftBadgeView.State {
    var wrapState: WrapState {
        switch self.redemptionState {
        case .redeemed, .opened:
            return .unwrapped
        case .pending:
            return .wrapped
        }
    }
}

class GiftWrap {

    /// The rootView for use in the conversation view.
    let rootView: ManualLayoutView

    /// The view whose edge should match that of the related bubble.
    var bubbleViewPartner: OWSBubbleViewPartner { self.giftWrapView.wrappingView }

    /// The actual view containing the gift wrapping. This view is transferred
    /// from the conversation view to the window for the "unwrap" animation.
    private let giftWrapView: GiftWrapView

    fileprivate let isIncoming: Bool

    static let shakeAnimationDuration: CGFloat = 0.8

    fileprivate init(isIncoming: Bool) {
        let giftWrapView = GiftWrapView()

        // Don't let the subview wrapper touch `GiftWrapView` -- we want this view
        // to be pristine for when we reuse it during the unwrap animation.
        let view = UIView()
        view.addSubview(giftWrapView)
        giftWrapView.autoPinEdgesToSuperviewEdges()

        self.giftWrapView = giftWrapView
        self.rootView = .wrapSubviewUsingIOSAutoLayout(view, wrapperName: "giftWrapWrapper")
        self.isIncoming = isIncoming
    }

    func animateShake() {
        self.giftWrapView.animateShake()
    }

    fileprivate func animateUnwrap() {
        let giftWrapView = self.giftWrapView

        // If the view isn't attached to a window, we can't show the unwrap
        // animation. Since this happens when the user taps an optional button,
        // crashing is a reasonable course of action.
        guard let window = giftWrapView.window else {
            owsFail("no window for unwrap animation")
        }

        // Clear the bubble view host -- this is necessary as part of detaching
        // this view from the conversation view rendering pipeline. When this link
        // is removed, the shape of the wrapping view is no longer updated by the
        // bubble. This ensures it doesn't change if the bubble is reused.
        giftWrapView.wrappingView.setBubbleViewHost(nil)

        // Figure out where the view is currently positioned in the window. We'll
        // assign this as the initial starting point of the animation.
        let frame = giftWrapView.convert(giftWrapView.bounds, to: window)

        let view = UnwrapAnimationView(giftWrapView)
        view.frame = frame
        window.addSubview(view)
        view.animateUnwrap(isIncoming: self.isIncoming)

        UIImpactFeedbackGenerator().impactOccurred()
    }
}

private class GiftWrapView: UIView {
    let wrappingContainer = UIView()
    let wrappingView = OWSBubbleShapeView(mode: .clip)
    let bowView = UIImageView(image: UIImage(named: "gift-bow"))

    init() {
        super.init(frame: .zero)

        let wrapWidth: CGFloat = 16

        let wrappingContainer = self.wrappingContainer
        self.addSubview(wrappingContainer)
        wrappingContainer.autoPinEdgesToSuperviewEdges()

        let wrappingView = self.wrappingView
        wrappingView.backgroundColor = .ows_accentBlue
        wrappingContainer.addSubview(wrappingView)

        let horizontalWrap = UIView()
        horizontalWrap.backgroundColor = .ows_white
        wrappingContainer.addSubview(horizontalWrap)
        horizontalWrap.autoSetDimension(.height, toSize: wrapWidth)
        horizontalWrap.autoPinWidthToSuperview()
        horizontalWrap.autoCenterInSuperview()

        let verticalWrap = UIView()
        verticalWrap.backgroundColor = .ows_white
        wrappingContainer.addSubview(verticalWrap)
        verticalWrap.autoSetDimension(.width, toSize: wrapWidth)
        verticalWrap.autoPinHeightToSuperview()
        verticalWrap.autoCenterInSuperview()

        // The bowView is not a subview of wrappingContainer. This allows it to
        // animate separately.
        let bowView = self.bowView
        self.addSubview(bowView)
        bowView.autoCenterInSuperview()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // This view doesn't support Auto Layout.
        self.wrappingView.frame = self.wrappingContainer.bounds
    }

    func animateShake() {
        let shakeCount = 3
        let shakeMagnitude: CGFloat = 10
        let bowDelay: CGFloat = 0.04
        let duration: CGFloat = GiftWrap.shakeAnimationDuration - bowDelay

        self.animateShake(
            for: self.wrappingContainer,
            shakeCount: shakeCount,
            shakeMagnitude: shakeMagnitude,
            startDelay: 0,
            duration: duration
        )
        // The bow animates with a 40ms delay compared to the wrapping.
        self.animateShake(
            for: self.bowView,
            shakeCount: shakeCount,
            shakeMagnitude: shakeMagnitude * 0.5,
            startDelay: bowDelay,
            duration: duration
        )
    }

    /// Build a CAAnimation that shakes the view back and forth.
    ///
    /// - Parameters:
    ///   - shakeCount: The number of times the view should be shaken. One shake
    ///     starts at the middle, moves left, moves right, and then moves back to
    ///     the middle.
    ///
    ///   - shakeMagnitude: How far from its original position the view should
    ///     deviate. In circle terms, this is the radius, not the diameter.
    ///
    ///   - startDelay: How long to delay the animation before starting.
    ///
    ///   - duration: How long the animation should last. The total duration is
    ///     `startDelay + duration`.
    ///
    private func animateShake(
        for view: UIView,
        shakeCount: Int,
        shakeMagnitude: CGFloat,
        startDelay: CGFloat,
        duration: CGFloat
    ) {
        // Build the equally-spaced positions for the animation.
        var values = [CGFloat]()
        for _ in 0..<shakeCount {
            values.append(contentsOf: [0, -shakeMagnitude, 0, shakeMagnitude])
        }
        values.append(0)

        // Build equally-spaced keyTimes on the [0, 1] scale.
        let totalDuration = startDelay + duration
        let firstKeyTime = startDelay / totalDuration
        let deltaKeyTime = (1 - firstKeyTime) / CGFloat(values.count - 1)

        var keyTimes = [NSNumber]()
        for idx in 0..<values.count {
            keyTimes.append(NSNumber(value: firstKeyTime + deltaKeyTime * CGFloat(idx)))
        }

        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = values
        animation.keyTimes = keyTimes
        animation.duration = totalDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        view.layer.add(animation, forKey: "shake")
    }
}

/// Provides a fixed-size container for the unwrap animation.
///
/// The contents of this view are transferred from the view used in the
/// conversation when the animation starts.
///
/// When the animation is done, this view removes itself from its superview.
private class UnwrapAnimationView: UIView, CAAnimationDelegate {

    private let bowView: UIView

    init(_ containerView: GiftWrapView) {
        self.bowView = containerView.bowView

        super.init(frame: .zero)

        // When animating, don't capture any touches.
        self.isUserInteractionEnabled = false

        self.addSubview(containerView)
        containerView.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Builds an animation for unwrapping a gift.
    ///
    func animateUnwrap(isIncoming: Bool) {
        let animationKey = "unwrap"

        // Flip the horizontal and rotation elements for outgoing gifts.
        let directionMultipler: CGFloat = isIncoming ? 1.0 : -1.0

        // The bow rotates back and forth.
        self.bowView.layer.animateRotation(animationKey: animationKey, duration: 1.8, keyFrames: [
            (0.000, 0 * directionMultipler),
            (0.050, 3 * directionMultipler),
            (0.220, -3 * directionMultipler),
            (0.400, 3 * directionMultipler),
            (1.030, -8 * directionMultipler),
            (1.400, 5 * directionMultipler),
            (1.800, 5 * directionMultipler)
        ])
        // The bubble rotates back and forth, opposite from the bow.
        self.layer.animateRotation(animationKey: animationKey, duration: 1.8, keyFrames: [
            (0.000, 0 * directionMultipler),
            (0.400, 0 * directionMultipler),
            (1.030, 8 * directionMultipler),
            (1.400, -5 * directionMultipler),
            (1.800, -5 * directionMultipler)
        ])
        // The vertical movement is "approximately gravity". As a result, the path
        // is closer to a parabola than a standard easeInEaseOut curve (that curve
        // would have the fastest movement at the top of the arc). This gravity
        // motion is roughly approximated by an easeOutEaseIn curve (note the
        // flipped order of out/in), but the magnitude of the easing has been
        // tweaked to mimic the spec.
        self.layer.animateTranslation(animationKey: animationKey, coordinateKey: "y", duration: 1.8, keyFrames: [
            (0.400, 0, .init(name: .linear)),
            (0.730, -74, .init(controlPoints: 0.00, 0.00, 0.25, 1.00)),
            (1.800, 1366, .init(controlPoints: 0.90, 0.00, 1.00, 1.00))
        ]).delegate = self

        // The horizontal movement uses easeInEaseOut, split across the two phases.
        self.layer.animateTranslation(animationKey: animationKey, coordinateKey: "x", duration: 1.8, keyFrames: [
            (0.400, 0 * directionMultipler, .init(name: .linear)),
            (0.730, 11 * directionMultipler, .init(name: .easeIn)),
            (1.400, 18 * directionMultipler, .init(name: .easeOut)),
            (1.800, 18 * directionMultipler, .init(name: .linear))
        ])

        // The vertical motion uses a constant of 1366, which is (currently) the
        // tallest iPad. As a result, all devices use the same shape and *velocity*
        // for the animation. Most of the time, however, the wrapping view will be
        // offscreen before the total duration has elapsed, so you'll only see part
        // of the animation. This is more natural than animating faster or slower
        // depending on how far the gift wrap needs to move.
        assert(self.window!.bounds.size.height <= 1366)

        // Set the final position off the screen so that the view doesn't "jump
        // back" before it gets removed.
        self.layer.setAffineTransform(
            CGAffineTransform(translationX: 18 * directionMultipler, y: 1366)
        )
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        self.removeFromSuperview()
    }
}

private extension CALayer {

    /// Animates a rotation through various key frames.
    ///
    /// This animation uses cubic interpolation, which smooths the changes in
    /// direction.
    ///
    /// - Parameters:
    ///   - animationKey: A unique key to associate with the animation. A
    ///     rotation-specific key is appended.
    ///
    ///   - duration: The total duration of the animation, in seconds.
    ///
    ///   - keyFrames: The key frames for the animation. The first key frame
    ///     should have a time of `0`, and the last key frame should have a time
    ///     of `duration`.
    ///
    func animateRotation(
        animationKey: String,
        duration: CFTimeInterval,
        keyFrames: [(keyTime: CFTimeInterval, degrees: CGFloat)]
    ) {
        let keyPath = "transform.rotation"
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        let values = keyFrames.map { $0.degrees * .pi / 180 }
        animation.values = values
        animation.keyTimes = keyFrames.map { NSNumber(value: $0.keyTime / duration) }
        animation.calculationMode = .cubic
        animation.duration = duration
        animation.fillMode = .forwards
        self.add(animation, forKey: "\(animationKey).\(keyPath)")
    }

    /// Animates a translation through various key frames.
    ///
    /// Each key frame specifies its own timing function. The initial position
    /// is assumed to be `0` at 0 seconds, and each timing function argument
    /// applies to the prior point and the current point.
    ///
    /// - Parameters:
    ///   - animationKey: A unique key to associated with the animation. A
    ///     translation-specific key is appended.
    ///
    ///   - coordinateKey: The coordinate whose value should be animated. Should
    ///     be "x" or "y".
    ///
    ///   - duration: The total duration of the animation, in seconds.
    ///
    ///   - keyFrames: The key frames for the animation. The first key frame
    ///     should have a time of `0`, and the last key frame should have a time
    ///     of `duration`.
    ///
    @discardableResult
    func animateTranslation(
        animationKey: String,
        coordinateKey: String,
        duration: CFTimeInterval,
        keyFrames: [(keyTime: CFTimeInterval, value: CGFloat, timingFunction: CAMediaTimingFunction)]
    ) -> CAAnimation {
        let keyPath = "transform.translation.\(coordinateKey)"
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = [0 as CGFloat] + keyFrames.map { $0.value }
        animation.keyTimes = [NSNumber(0)] + keyFrames.map { NSNumber(value: $0.keyTime / duration) }
        animation.timingFunctions = keyFrames.map { $0.timingFunction }
        animation.duration = duration
        self.add(animation, forKey: "\(animationKey).\(keyPath)")
        return animation
    }

}
