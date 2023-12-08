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
        let avatar: UIImage?
    }

    private let labelStack = ManualStackView(name: "CVContactShareView.labelStack")
    private let avatarView: AvatarImageView = AvatarImageView(shouldDeactivateConstraints: true)

    private let contactNameLabel = CVLabel()
    private let disclosureImageView = CVImageView()

    static func buildState(
        contactShare: ContactShareViewModel,
        isIncoming: Bool,
        conversationStyle: ConversationStyle,
        transaction: SDSAnyReadTransaction
    ) -> State {
        let avatar = contactShare.getAvatarImage(diameter: Self.avatarSize,
                                                 transaction: transaction)
        owsAssertDebug(avatar != nil)
        return State(contactShare: contactShare,
                     isIncoming: isIncoming,
                     conversationStyle: conversationStyle,
                     avatar: avatar)
    }

    private static var avatarSize: CGFloat { CGFloat(AvatarBuilder.standardAvatarSizePoints) }
    private static let disclosureIconSize = CGSize.square(20)

    func configureForRendering(state: State, cellMeasurement: CVCellMeasurement) {

        let labelConfig = Self.contactNameLabelConfig(state: state)
        labelConfig.applyForRendering(label: contactNameLabel)

        avatarView.image = state.avatar

        let disclosureColor = state.isIncoming ? UIColor.ows_gray25 : UIColor.ows_whiteAlpha80
        disclosureImageView.setTemplateImage(UIImage(imageLiteralResourceName: "chevron-right-20"),
                                             tintColor: disclosureColor)

        self.configure(config: Self.outerStackConfig,
                             cellMeasurement: cellMeasurement,
                             measurementKey: Self.measurementKey_outerStack,
                             subviews: [
                                avatarView,
                                contactNameLabel,
                                disclosureImageView
                             ])
    }

    private static var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .center,
                          spacing: 12,
                          layoutMargins: UIEdgeInsets(hMargin: 0, vMargin: 4))
    }

    private static func contactNameLabelConfig(state: State) -> CVLabelConfig {
        let textColor = state.conversationStyle.bubbleTextColor(isIncoming: state.isIncoming)
        return CVLabelConfig.unstyledText(
            state.contactShare.displayName,
            font: .dynamicTypeBody,
            textColor: textColor,
            lineBreakMode: .byTruncatingTail
        )
    }

    private static let measurementKey_outerStack = "CVContactShareView.measurementKey_outerStack"

    static func measure(maxWidth: CGFloat,
                        measurementBuilder: CVCellMeasurement.Builder,
                        state: State) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        var maxContentWidth = (maxWidth -
                                (Self.avatarSize +
                                    disclosureIconSize.width +
                                    outerStackConfig.spacing * 2))
        maxContentWidth = max(0, maxContentWidth)

        let labelConfig = self.contactNameLabelConfig(state: state)
        let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxContentWidth)

        var outerSubviewInfos = [ManualStackSubviewInfo]()

        let avatarSize = CGSize(square: Self.avatarSize)
        outerSubviewInfos.append(avatarSize.asManualSubviewInfo(hasFixedSize: true))

        outerSubviewInfos.append(labelSize.asManualSubviewInfo)

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
        contactNameLabel.text = nil
        disclosureImageView.image = nil
    }
}
