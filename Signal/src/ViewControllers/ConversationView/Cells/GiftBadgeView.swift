//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalUI

class GiftBadgeView: ManualStackView {

    struct State {
        let badgeLoader: BadgeLoader
        let timeRemainingText: String
        let isIncoming: Bool
        let conversationStyle: ConversationStyle
    }

    final class BadgeLoader: Dependencies, Equatable {
        let level: OneTimeBadgeLevel

        init(level: OneTimeBadgeLevel) {
            self.level = level
        }

        static func == (lhs: BadgeLoader, rhs: BadgeLoader) -> Bool {
            return lhs.level == rhs.level
        }

        lazy var profileBadge: Guarantee<ProfileBadge?> = self.buildProfileBadgeGuarantee()
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
            // TODO: (GB) Load this from the ProfileBadge.
            text: "Gift Badge",
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
            return NSLocalizedString(
                "BADGE_GIFTING_REDEEM",
                comment: "A button shown on a gift message you receive to redeem the badge and add it to your profile."
            )
        } else {
            return NSLocalizedString(
                "BADGE_GIFTING_VIEW",
                comment: "A button shown on a gift message you send to view additional details about the badge."
            )
        }
    }

    private let badgeView = CVImageView()
    private static let badgeSize: CGFloat = 64

    private var badgeLoadCounter = 0

    override func reset() {
        super.reset()

        self.innerStack.reset()
        self.labelStack.reset()
        self.buttonStack.reset()

        self.titleLabel.text = nil
        self.timeRemainingLabel.text = nil
        self.redeemButtonLabel.text = nil

        self.badgeLoadCounter += 1  // cancel any outstanding load request
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

    func configureForRendering(state: State, cellMeasurement: CVCellMeasurement) {
        Self.titleLabelConfig(for: state).applyForRendering(label: self.titleLabel)
        Self.timeRemainingLabelConfig(for: state).applyForRendering(label: self.timeRemainingLabel)
        Self.redeemButtonLabelConfig(for: state).applyForRendering(label: self.redeemButtonLabel)

        self.badgeLoadCounter += 1
        let badgeLoadRequest = self.badgeLoadCounter

        self.badgeView.image = nil
        state.badgeLoader.profileBadge.done { [weak self] profileBadge in
            guard let self = self else { return }
            // If the `badgeLoadCounter` changes, it means the request was canceled,
            // perhaps due to view reuse.
            guard badgeLoadRequest == self.badgeLoadCounter else { return }

            self.badgeView.image = profileBadge?.assets?.universal64
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
}

private extension GiftBadgeView.BadgeLoader {
    func buildProfileBadgeGuarantee() -> Guarantee<ProfileBadge?> {
        // TODO: (GB) Cache the payload to avoid fetching it every time it's rendered.
        firstly {
            SubscriptionManager.getBadge(level: self.level)
        }.then { [weak self] profileBadge -> Promise<ProfileBadge?> in
            guard let self = self else { return Promise.value(nil) }

            return firstly {
                self.profileManager.badgeStore.populateAssetsOnBadge(profileBadge)
            }.map { () -> ProfileBadge? in
                return profileBadge
            }
        }.recover { (error) -> Guarantee<ProfileBadge?> in
            Logger.warn("Couldn't fetch gift badge image: \(error)")
            return Guarantee.value(nil)
        }
    }

}
