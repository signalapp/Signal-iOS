//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public class CVContactShareView: UIView {

    struct State: Equatable {
        let contactShare: ContactShareViewModel
        let isIncoming: Bool
        let conversationStyle: ConversationStyle
        let firstPhoneNumber: String?
        let avatar: UIImage?
    }

    private let state: State
    private var contactShare: ContactShareViewModel { state.contactShare }
    private var isIncoming: Bool { state.isIncoming }
    private var conversationStyle: ConversationStyle { state.conversationStyle }
    private var firstPhoneNumber: String? { state.firstPhoneNumber }

    static func buildState(contactShare: ContactShareViewModel,
                           isIncoming: Bool,
                           conversationStyle: ConversationStyle,
                           transaction: SDSAnyReadTransaction) -> State {
        let firstPhoneNumber = contactShare.systemContactsWithSignalAccountPhoneNumbers(transaction: transaction).first
        let avatar = contactShare.getAvatarImage(diameter: Self.iconSize, transaction: transaction)
        return State(contactShare: contactShare,
                     isIncoming: isIncoming,
                     conversationStyle: conversationStyle,
                     firstPhoneNumber: firstPhoneNumber,
                     avatar: avatar)
    }

    required init(state: State) {
        self.state = state

        super.init(frame: .zero)

        createContents()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static let hMargin: CGFloat = 0
    private static let vMargin: CGFloat = 4
    private static let iconHSpacing: CGFloat = 8
    private static var iconSize: CGFloat { CGFloat(kStandardAvatarSize) }
    private static var nameFont: UIFont { UIFont.ows_dynamicTypeBody }
    private static var subtitleFont: UIFont { UIFont.ows_dynamicTypeCaption1 }
    private static let labelsVSpacing: CGFloat = 2

    private func createContents() {
        layoutMargins = .zero

        let textColor = conversationStyle.bubbleTextColor(isIncoming: isIncoming)

        let avatarView = AvatarImageView()
        avatarView.image = state.avatar
        avatarView.autoSetDimensions(to: CGSize(square: Self.iconSize))
        avatarView.setCompressionResistanceHigh()
        avatarView.setContentHuggingHigh()

        let topLabel = UILabel()
        topLabel.text = contactShare.displayName
        topLabel.textColor = textColor
        topLabel.lineBreakMode = .byTruncatingTail
        topLabel.font = Self.nameFont

        let labelsView = UIStackView()
        labelsView.axis = .vertical
        labelsView.spacing = Self.labelsVSpacing
        labelsView.addArrangedSubview(topLabel)

        if let firstPhoneNumber = self.firstPhoneNumber,
           !firstPhoneNumber.isEmpty {
            let bottomLabel = UILabel()
            bottomLabel.text = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: firstPhoneNumber)
            bottomLabel.textColor = conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming)
            bottomLabel.lineBreakMode = .byTruncatingTail
            bottomLabel.font = Self.subtitleFont
            labelsView.addArrangedSubview(bottomLabel)
        }

        let disclosureImage = UIImage(named: CurrentAppContext().isRTL ? "small_chevron_left" : "small_chevron_right")
        owsAssertDebug(disclosureImage != nil)
        let disclosureImageView = UIImageView()
        disclosureImageView.image = disclosureImage?.withRenderingMode(.alwaysTemplate)
        disclosureImageView.tintColor = textColor
        disclosureImageView.setCompressionResistanceHigh()
        disclosureImageView.setContentHuggingHigh()

        let hStackView = UIStackView()
        hStackView.axis = .horizontal
        hStackView.spacing = Self.iconHSpacing
        hStackView.alignment = .center
        hStackView.isLayoutMarginsRelativeArrangement = true
        hStackView.layoutMargins = UIEdgeInsets(hMargin: Self.hMargin, vMargin: Self.vMargin)
        hStackView.addArrangedSubview(avatarView)
        hStackView.addArrangedSubview(labelsView)
        hStackView.addArrangedSubview(disclosureImageView)
        self.addSubview(hStackView)
        hStackView.autoPinEdgesToSuperviewEdges()
    }

    static func measureHeight(state: State) -> CGFloat {
        let labelsHeight = nameFont.lineHeight + labelsVSpacing + subtitleFont.lineHeight
        var contentHeight = max(iconSize, labelsHeight)
        contentHeight += vMargin * 2
        return contentHeight
    }
}
