//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalUI
import QuartzCore

class GiftBadgeView: ManualStackView {

    struct State {
        enum Badge {
            // The badge isn't loaded. Calling the block will load it.
            case notLoaded(() -> Promise<Void>)
            // The badge is loaded. The associated value is the badge.
            case loaded(ProfileBadge)
        }
        let badge: Badge
        let messageUniqueId: String
        let timeRemainingText: String
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
        let textColor = state.conversationStyle.bubbleTextColor(isIncoming: state.isIncoming)
        return CVLabelConfig(
            text: NSLocalizedString(
                "BADGE_GIFTING_CHAT_TITLE",
                comment: "Shown on a gift badge message to indicate that the message contains a gift."
            ),
            font: .ows_dynamicTypeBody,
            textColor: textColor,
            lineBreakMode: .byTruncatingTail
        )
    }

    static func timeRemainingText(for expirationDate: Date) -> String {
        let timeRemaining = expirationDate.timeIntervalSinceNow
        guard timeRemaining > 0 else {
            return NSLocalizedString(
                "BADGE_GIFTING_CHAT_EXPIRED",
                comment: "Shown on a gift badge message to indicate that it's already expired and can no longer be redeemed."
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
            lineBreakMode: .byTruncatingTail
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
            return Theme.isDarkThemeEnabled ? .ows_gray60 : .ows_whiteAlpha80
        } else {
            return .ows_whiteAlpha70
        }
    }

    // This is a label, not a button, to remain compatible with the hit testing code.
    private let redeemButtonLabel = CVLabel()
    private static func redeemButtonLabelConfig(for state: State) -> CVLabelConfig {
        return CVLabelConfig(
            text: Self.redeemButtonText(for: state),
            font: .ows_dynamicTypeBody.ows_semibold,
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

    private static func redeemButtonText(for state: State) -> String {
        if state.isIncoming {
            // TODO: (GB) Alter this value based on whether or not the badge has been redeemed.
            switch state.redemptionState {
            case .opened:
                owsFailDebug("Only outgoing gifts can be permanently opened")
                fallthrough
            case .pending:
                return CommonStrings.redeemGiftButton
            case .redeemed:
                return NSLocalizedString(
                    "BADGE_GIFTING_REDEEMED",
                    comment: "Label for a button to see details about a gift you've already redeemed. The text is shown next to a checkmark."
                )
            }
        } else {
            return NSLocalizedString(
                "BADGE_GIFTING_VIEW",
                comment: "A button shown on a gift message you send to view additional details about the badge."
            )
        }
    }

    private let badgeView = CVImageView()
    private static let badgeSize: CGFloat = 64

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

        let allSubviews: [UIView] = [
            self.innerStack,
            self.labelStack,
            self.buttonStack,
            self.titleLabel,
            self.timeRemainingLabel,
            self.redeemButtonLabel,
            self.badgeView
        ]
        for subview in allSubviews {
            subview.removeFromSuperview()
        }
    }

    func configureForRendering(state: State, cellMeasurement: CVCellMeasurement, componentDelegate: CVComponentDelegate) {
        Self.titleLabelConfig(for: state).applyForRendering(label: self.titleLabel)
        Self.timeRemainingLabelConfig(for: state).applyForRendering(label: self.timeRemainingLabel)
        Self.redeemButtonLabelConfig(for: state).applyForRendering(label: self.redeemButtonLabel)

        switch state.badge {
        case .notLoaded(let loadPromise):
            loadPromise().done { [weak componentDelegate] in
                componentDelegate?.cvc_enqueueReload()
            }.cauterize()
            // TODO: (GB) If an error occurs, we'll be stuck with a spinner.
        case .loaded(let profileBadge):
            self.badgeView.image = profileBadge.assets?.universal64
        }

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

        self.labelStack.configure(
            config: Self.labelStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_labelStack,
            subviews: [self.titleLabel, self.timeRemainingLabel]
        )

        self.innerStack.configure(
            config: Self.innerStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_innerStack,
            subviews: [self.badgeView, self.labelStack]
        )

        self.configure(
            config: Self.outerStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_outerStack,
            subviews: [self.innerStack, self.buttonStack]
        )

        if state.wrapState == .unwrapped || !componentDelegate.cvc_willWrapGift(state.messageUniqueId) {
            self.giftWrap = nil
        } else if self.giftWrap == nil {
            self.giftWrap = GiftWrap()
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
                lineBreakMode: labelConfig.lineBreakMode
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

    static let shakeAnimationDuration: CGFloat = 0.8

    fileprivate init() {
        let giftWrapView = GiftWrapView()

        // Don't let the subview wrapper touch `GiftWrapView` -- we want this view
        // to be pristine for when we reuse it during the unwrap animation.
        let view = UIView()
        view.addSubview(giftWrapView)
        giftWrapView.autoPinEdgesToSuperviewEdges()

        self.giftWrapView = giftWrapView
        self.rootView = .wrapSubviewUsingIOSAutoLayout(view, wrapperName: "giftWrapWrapper")
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
        view.animateUnwrap(minimumVerticalDelta: window.height - frame.y)
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

    init(_ containerView: UIView) {
        super.init(frame: .zero)

        // When animating, don't capture any touches.
        self.isUserInteractionEnabled = false

        self.addSubview(containerView)
        containerView.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private struct CurvePoint {
        var point: CGPoint
        var controlPoint1: CGPoint
        var controlPoint2: CGPoint

        func scaled(by scale: CGFloat) -> Self {
            var result = self
            result.point *= scale
            result.controlPoint1 *= scale
            result.controlPoint2 *= scale
            return result
        }
    }

    /// Builds an animation for unwrapping a gift.
    ///
    /// - Parameters:
    ///   - minimumVerticalDelta: The minimum distance the view will travel
    ///     downward by the end of its animation. Used to ensure the view moves
    ///     all the way off the screen. Note that the view may move further than
    ///     requested by this parameter.
    ///
    func animateUnwrap(minimumVerticalDelta: CGFloat) {
        let defaultScale: CGFloat = 221

        // This is the default animation curve. We'll adjust it as necessary for
        // the device.
        var curvePoints: [CurvePoint] = [
            CurvePoint(
                point: CGPoint(x: 0.521, y: -1.242),
                controlPoint1: CGPoint(x: 0.114, y: -0.640),
                controlPoint2: CGPoint(x: 0.194, y: -1.232)
            ),
            CurvePoint(
                point: CGPoint(x: 1.000, y: 1.588),
                controlPoint1: CGPoint(x: 0.834, y: -1.251),
                controlPoint2: CGPoint(x: 1.019, y: -0.431)
            )
        ]

        // Start by scaling all the points by the scale factor. This factor is
        // determined based on the width of the device, it's an aspect
        // ratio-preserving adjustment.
        curvePoints = curvePoints.map { $0.scaled(by: defaultScale) }

        // Next, ensure that the ending position will be off the screen. Note that
        // we don't touch any of the control points when moving the point -- this
        // keeps the shape of the curve roughly correct. (In a perfect world, we'd
        // probably move `controlPoint2` up slightly as we move `point` downwards.)
        curvePoints[1].point.y = max(curvePoints[1].point.y, minimumVerticalDelta)

        let path = UIBezierPath()
        path.move(to: .zero)
        for curvePoint in curvePoints {
            path.addCurve(
                to: curvePoint.point,
                controlPoint1: curvePoint.controlPoint1,
                controlPoint2: curvePoint.controlPoint2
            )
        }

        let animation = CAKeyframeAnimation(keyPath: "transform.translation")
        animation.path = path.cgPath
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.duration = 0.7
        animation.delegate = self

        let finalPoint = path.currentPoint
        self.layer.setAffineTransform(CGAffineTransform(translationX: finalPoint.x, y: finalPoint.y))

        self.layer.add(animation, forKey: "unwrap")
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        self.removeFromSuperview()
    }
}
