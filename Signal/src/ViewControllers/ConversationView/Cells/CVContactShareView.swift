//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

public class CVContactShareView: ManualStackView {

    struct State: Equatable {
        let contactShare: ContactShareViewModel
        let isIncoming: Bool
        let conversationStyle: ConversationStyle
        let firstPhoneNumber: String?
        let avatar: UIImage?
    }

    private let labelStack = ManualStackView(name: "CVContactShareView.labelStack")
    private let avatarView: AvatarImageView = AvatarImageView(shouldDeactivateConstraints: true)

    private let topLabel = CVLabel()
    private let bottomLabel = CVLabel()
    private let disclosureImageView = CVImageView()

    static func buildState(contactShare: ContactShareViewModel,
                           isIncoming: Bool,
                           conversationStyle: ConversationStyle,
                           transaction: SDSAnyReadTransaction) -> State {
        let firstPhoneNumber = contactShare.systemContactsWithSignalAccountPhoneNumbers(transaction: transaction).first
        let avatar = contactShare.getAvatarImage(diameter: Self.avatarSize,
                                                 transaction: transaction)
        owsAssertDebug(avatar != nil)
        return State(contactShare: contactShare,
                     isIncoming: isIncoming,
                     conversationStyle: conversationStyle,
                     firstPhoneNumber: firstPhoneNumber,
                     avatar: avatar)
    }

    private static var avatarSize: CGFloat { CGFloat(AvatarBuilder.standardAvatarSizePoints) }
    private static let disclosureIconSize = CGSize.square(20)

    func configureForRendering(state: State,
                               cellMeasurement: CVCellMeasurement) {

        var labelStackSubviews = [UIView]()

        let topLabelConfig = Self.topLabelConfig(state: state)
        topLabelConfig.applyForRendering(label: topLabel)
        labelStackSubviews.append(topLabel)

        if let bottomLabelConfig = Self.bottomLabelConfig(state: state) {
            bottomLabelConfig.applyForRendering(label: bottomLabel)
            labelStackSubviews.append(bottomLabel)
        }

        labelStack.configure(config: Self.labelStackConfig,
                             cellMeasurement: cellMeasurement,
                             measurementKey: Self.measurementKey_labelStack,
                             subviews: labelStackSubviews)

        avatarView.image = state.avatar

        let disclosureColor = state.conversationStyle.bubbleTextColor(isIncoming: state.isIncoming)
        disclosureImageView.setTemplateImage(UIImage(imageLiteralResourceName: "chevron-right-20"),
                                             tintColor: disclosureColor)

        self.configure(config: Self.outerStackConfig,
                             cellMeasurement: cellMeasurement,
                             measurementKey: Self.measurementKey_outerStack,
                             subviews: [
                                avatarView,
                                labelStack,
                                disclosureImageView
                             ])
    }

    private static var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .center,
                          spacing: 8,
                          layoutMargins: UIEdgeInsets(hMargin: 0, vMargin: 4))
    }

    private static var labelStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .leading,
                          spacing: 2,
                          layoutMargins: .zero)
    }

    private static func topLabelConfig(state: State) -> CVLabelConfig {
        let textColor = state.conversationStyle.bubbleTextColor(isIncoming: state.isIncoming)
        return CVLabelConfig(text: state.contactShare.displayName,
                             font: .dynamicTypeBody2.semibold(),
                             textColor: textColor,
                             lineBreakMode: .byTruncatingTail)
    }

    private static func bottomLabelConfig(state: State) -> CVLabelConfig? {
        guard let firstPhoneNumber = state.firstPhoneNumber?.nilIfEmpty else {
            return nil
        }
        let text = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: firstPhoneNumber)
        let textColor = state.conversationStyle.bubbleSecondaryTextColor(isIncoming: state.isIncoming)
        return CVLabelConfig(text: text,
                             font: .dynamicTypeCaption1,
                             textColor: textColor,
                             lineBreakMode: .byTruncatingTail)
    }

    private static let measurementKey_outerStack = "CVContactShareView.measurementKey_outerStack"
    private static let measurementKey_labelStack = "CVContactShareView.measurementKey_labelStack"

    static func measure(maxWidth: CGFloat,
                        measurementBuilder: CVCellMeasurement.Builder,
                        state: State) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        var maxContentWidth = (maxWidth -
                                (Self.avatarSize +
                                    disclosureIconSize.width +
                                    outerStackConfig.spacing * 2))
        maxContentWidth = max(0, maxContentWidth)

        var labelStackSubviewInfos = [ManualStackSubviewInfo]()

        let topLabelConfig = self.topLabelConfig(state: state)
        let topLabelSize = CVText.measureLabel(config: topLabelConfig,
                                               maxWidth: maxContentWidth)
        labelStackSubviewInfos.append(topLabelSize.asManualSubviewInfo)

        if let bottomLabelConfig = self.bottomLabelConfig(state: state) {
            let bottomLabelSize = CVText.measureLabel(config: bottomLabelConfig,
                                                   maxWidth: maxContentWidth)
            labelStackSubviewInfos.append(bottomLabelSize.asManualSubviewInfo)
        }

        let labelStackMeasurement = ManualStackView.measure(config: labelStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_labelStack,
                                                            subviewInfos: labelStackSubviewInfos)

        var outerSubviewInfos = [ManualStackSubviewInfo]()

        let avatarSize = CGSize(square: Self.avatarSize)
        outerSubviewInfos.append(avatarSize.asManualSubviewInfo(hasFixedSize: true))

        outerSubviewInfos.append(labelStackMeasurement.measuredSize.asManualSubviewInfo)

        outerSubviewInfos.append(disclosureIconSize.asManualSubviewInfo(hasFixedSize: true))

        let outerStackMeasurement = ManualStackView.measure(config: outerStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_outerStack,
                                                            subviewInfos: outerSubviewInfos,
                                                            maxWidth: maxWidth)
        return outerStackMeasurement.measuredSize
    }

    public override func reset() {
        super.reset()

        labelStack.reset()
        avatarView.image = nil
        topLabel.text = nil
        bottomLabel.text = nil
        disclosureImageView.image = nil
    }
}
