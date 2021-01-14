//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentThreadDetails: CVComponentBase, CVRootComponent {

    public var cellReuseIdentifier: CVCellReuseIdentifier {
        CVCellReuseIdentifier.threadDetails
    }

    public let isDedicatedCell = false

    private let threadDetails: CVComponentState.ThreadDetails

    private var avatarImage: UIImage? { threadDetails.avatar }
    private var titleText: String { threadDetails.titleText }
    private var detailsText: String? { threadDetails.detailsText }
    private var mutualGroupsText: NSAttributedString? { threadDetails.mutualGroupsText }

    required init(itemModel: CVItemModel, threadDetails: CVComponentState.ThreadDetails) {
        self.threadDetails = threadDetails

        super.init(itemModel: itemModel)
    }

    public func configure(cellView: UIView,
                          cellMeasurement: CVCellMeasurement,
                          componentDelegate: CVComponentDelegate,
                          cellSelection: CVCellSelection,
                          swipeToReplyState: CVSwipeToReplyState,
                          componentView: CVComponentView) {
        owsAssertDebug(cellView.layoutMargins == .zero)
        owsAssertDebug(cellView.subviews.isEmpty)

        configureForRendering(componentView: componentView,
                              cellMeasurement: cellMeasurement,
                              componentDelegate: componentDelegate)
        let rootView = componentView.rootView
        cellView.addSubview(rootView)

        rootView.autoPinEdgesToSuperviewMargins()
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewThreadDetails()
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewThreadDetails else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let stackView = componentView.stackView
        stackView.apply(config: stackViewConfig)

        let avatarView = AvatarImageView(image: self.avatarImage)
        componentView.avatarView = avatarView
        avatarView.autoSetDimensions(to: CGSize(square: avatarDiameter))
        avatarView.setContentHuggingHigh()
        avatarView.setCompressionResistanceHigh()
        stackView.addArrangedSubview(avatarView)
        stackView.addArrangedSubview(UIView.spacer(withHeight: 1))

        let titleLabel = componentView.titleLabel
        titleLabelConfig.applyForRendering(label: titleLabel)
        stackView.addArrangedSubview(titleLabel)

        if let detailsText = self.detailsText {
            let detailsLabel = componentView.detailsLabel
            detailsLabelConfig(text: detailsText).applyForRendering(label: detailsLabel)
            stackView.addArrangedSubview(detailsLabel)
        }

        if let mutualGroupsText = self.mutualGroupsText {
            let mutualGroupsLabel = componentView.mutualGroupsLabel
            mutualGroupsLabelConfig(attributedText: mutualGroupsText).applyForRendering(label: mutualGroupsLabel)
            stackView.addArrangedSubview(UIView.spacer(withHeight: 5))
            stackView.addArrangedSubview(mutualGroupsLabel)
        }
    }

    private var titleLabelConfig: CVLabelConfig {
        CVLabelConfig(text: titleText,
                      font: UIFont.ows_dynamicTypeTitle1.ows_semibold,
                      textColor: Theme.secondaryTextAndIconColor,
                      numberOfLines: 0,
                      lineBreakMode: .byWordWrapping,
                      textAlignment: .center)
    }

    private func detailsLabelConfig(text: String) -> CVLabelConfig {
        CVLabelConfig(text: text,
                      font: .ows_dynamicTypeSubheadline,
                      textColor: Theme.secondaryTextAndIconColor,
                      numberOfLines: 0,
                      lineBreakMode: .byWordWrapping,
                      textAlignment: .center)
    }

    private func mutualGroupsLabelConfig(attributedText: NSAttributedString) -> CVLabelConfig {
        CVLabelConfig(attributedText: attributedText,
                      font: .ows_dynamicTypeSubheadline,
                      textColor: Theme.secondaryTextAndIconColor,
                      numberOfLines: 0,
                      lineBreakMode: .byWordWrapping,
                      textAlignment: .center)
    }

    private static let avatarDiameter: UInt = 112
    private var avatarDiameter: CGFloat { CGFloat(Self.avatarDiameter) }

    static func buildComponentState(thread: TSThread,
                                    transaction: SDSAnyReadTransaction,
                                    avatarBuilder: CVAvatarBuilder) -> CVComponentState.ThreadDetails {

        if let contactThread = thread as? TSContactThread {
            return buildComponentState(contactThread: contactThread,
                                       transaction: transaction,
                                       avatarBuilder: avatarBuilder)
        } else if let groupThread = thread as? TSGroupThread {
            return buildComponentState(groupThread: groupThread,
                                       transaction: transaction,
                                       avatarBuilder: avatarBuilder)
        } else {
            owsFailDebug("Invalid thread.")
            return CVComponentState.ThreadDetails(avatar: nil,
                                                  titleText: TSGroupThread.defaultGroupName,
                                                  detailsText: nil,
                                                  mutualGroupsText: nil)
        }
    }

    private static func buildComponentState(contactThread: TSContactThread,
                                            transaction: SDSAnyReadTransaction,
                                            avatarBuilder: CVAvatarBuilder) -> CVComponentState.ThreadDetails {

        let avatar = avatarBuilder.buildAvatar(forAddress: contactThread.contactAddress, diameter: avatarDiameter)

        let contactName = Self.contactsManager.displayName(for: contactThread.contactAddress,
                                                           transaction: transaction)

        let titleText = { () -> String in
            if contactThread.isNoteToSelf {
                return MessageStrings.noteToSelf
            } else {
                return contactName
            }
        }()

        let detailsText = { () -> String? in
            if contactThread.isNoteToSelf {
                return NSLocalizedString("THREAD_DETAILS_NOTE_TO_SELF_EXPLANATION",
                                         comment: "Subtitle appearing at the top of the users 'note to self' conversation")
            }
            var details: String?
            let threadName = contactName
            if let phoneNumber = contactThread.contactAddress.phoneNumber, phoneNumber != threadName {
                let formattedNumber = PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber)
                if threadName != formattedNumber {
                    details = formattedNumber
                }
            }

            if let username = Self.profileManager.username(for: contactThread.contactAddress,
                                                           transaction: transaction) {
                if let formattedUsername = CommonFormats.formatUsername(username), threadName != formattedUsername {
                    if let existingDetails = details {
                        details = existingDetails + "\n" + formattedUsername
                    } else {
                        details = formattedUsername
                    }
                }
            }
            return details
        }()

        let mutualGroupsText = { () -> NSAttributedString? in

            guard !contactThread.contactAddress.isLocalAddress else {
                // Don't show mutual groups for "Note to Self".
                return nil
            }

            let groupThreads = TSGroupThread.groupThreads(with: contactThread.contactAddress, transaction: transaction)
            let mutualGroupNames = groupThreads.filter { $0.isLocalUserFullMember && $0.shouldThreadBeVisible }.map { $0.groupNameOrDefault }

            let formatString: String
            var groupsToInsert = mutualGroupNames
            switch mutualGroupNames.count {
            case 0:
                return nil
            case 1:
                formatString = NSLocalizedString(
                    "THREAD_DETAILS_ONE_MUTUAL_GROUP",
                    comment: "A string indicating a mutual group the user shares with this contact. Embeds {{mutual group name}}"
                )
            case 2:
                formatString = NSLocalizedString(
                    "THREAD_DETAILS_TWO_MUTUAL_GROUP",
                    comment: "A string indicating two mutual groups the user shares with this contact. Embeds {{mutual group name}}"
                )
            case 3:
                formatString = NSLocalizedString(
                    "THREAD_DETAILS_THREE_MUTUAL_GROUP",
                    comment: "A string indicating three mutual groups the user shares with this contact. Embeds {{mutual group name}}"
                )
            default:
                formatString = NSLocalizedString(
                    "THREAD_DETAILS_MORE_MUTUAL_GROUP",
                    comment: "A string indicating two mutual groups the user shares with this contact and that there are more unlisted. Embeds {{mutual group name}}"
                )
                groupsToInsert = Array(groupsToInsert[0...1])
            }

            var formatStringCount = formatString.components(separatedBy: "%@").count
            if formatString.count > 1 { formatStringCount -= 1 }

            guard formatStringCount == groupsToInsert.count else {
                owsFailDebug("Incorrect number of format characters in string")
                return nil
            }

            let mutableAttributedString = NSMutableAttributedString(string: formatString)

            // We don't use `String(format:)` so that we can make sure each group name is bold.
            for groupName in groupsToInsert {
                let nextInsertionPoint = (mutableAttributedString.string as NSString).range(of: "%@")
                guard nextInsertionPoint.location != NSNotFound else {
                    owsFailDebug("Unexpectedly tried to insert too many group names")
                    return nil
                }

                let boldGroupName = NSAttributedString(string: groupName, attributes: [.font: UIFont.ows_dynamicTypeSubheadline.ows_semibold])
                mutableAttributedString.replaceCharacters(in: nextInsertionPoint, with: boldGroupName)
            }

            // We also need to insert the count if we're more than 3
            if mutualGroupNames.count > 3 {
                let nextInsertionPoint = (mutableAttributedString.string as NSString).range(of: "%lu")
                guard nextInsertionPoint.location != NSNotFound else {
                    owsFailDebug("Unexpectedly failed to insert more count")
                    return nil
                }

                mutableAttributedString.replaceCharacters(in: nextInsertionPoint, with: "\(mutualGroupNames.count - 2)")
            } else if mutableAttributedString.string.range(of: "%lu") != nil {
                owsFailDebug("unexpected format string remaining in string")
                return nil
            }

            return mutableAttributedString
        }()

        return CVComponentState.ThreadDetails(avatar: avatar,
                                              titleText: titleText,
                                              detailsText: detailsText,
                                              mutualGroupsText: mutualGroupsText)
    }

    private static func buildComponentState(groupThread: TSGroupThread,
                                            transaction: SDSAnyReadTransaction,
                                            avatarBuilder: CVAvatarBuilder) -> CVComponentState.ThreadDetails {

        // If we need to reload this cell to reflect changes to any of the
        // state captured here, we need update the didThreadDetailsChange().        

        let avatar = avatarBuilder.buildAvatar(forGroupThread: groupThread, diameter: avatarDiameter)

        let titleText = groupThread.groupNameOrDefault

        let detailsText = { () -> String? in
            if let groupModelV2 = groupThread.groupModel as? TSGroupModelV2,
               groupModelV2.isPlaceholderModel {
                // Don't show details for a placeholder.
                return nil
            }

            let memberCount = groupThread.groupModel.groupMembership.fullMembers.count
            return GroupViewUtils.formatGroupMembersLabel(memberCount: memberCount)
        }()

        return CVComponentState.ThreadDetails(avatar: avatar,
                                              titleText: titleText,
                                              detailsText: detailsText,
                                              mutualGroupsText: nil)
    }

    private var stackViewConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .center,
                          spacing: 3,
                          layoutMargins: UIEdgeInsets(top: 8, leading: 16, bottom: 28, trailing: 16))
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let maxContentWidth = maxWidth - (stackViewConfig.layoutMargins.left + stackViewConfig.layoutMargins.right)

        var subviewSizes = [CGSize]()
        subviewSizes.append(CGSize(square: avatarDiameter))
        subviewSizes.append(CGSize(square: 1))

        let titleSize = CVText.measureLabel(config: titleLabelConfig, maxWidth: maxContentWidth)
        subviewSizes.append(titleSize)

        if let detailsText = self.detailsText {
            let detailsSize = CVText.measureLabel(config: detailsLabelConfig(text: detailsText),
                                                  maxWidth: maxContentWidth)
            subviewSizes.append(detailsSize)
        }

        if let mutualGroupsText = self.mutualGroupsText {
            let mutualGroupsSize = CVText.measureLabel(config: mutualGroupsLabelConfig(attributedText: mutualGroupsText),
                                                       maxWidth: maxContentWidth)
            subviewSizes.append(CGSize(square: 5))
            subviewSizes.append(mutualGroupsSize)
        }

        return CVStackView.measure(config: stackViewConfig, subviewSizes: subviewSizes).ceil
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewThreadDetails: NSObject, CVComponentView {

        fileprivate var avatarView: AvatarImageView?

        fileprivate let titleLabel = UILabel()
        fileprivate let detailsLabel = UILabel()

        fileprivate let mutualGroupsLabel = UILabel()

        fileprivate let stackView = OWSStackView(name: "threadDetails")

        public var isDedicatedCellView = false

        public var rootView: UIView {
            stackView
        }

        // MARK: -

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            stackView.reset()
            titleLabel.text = nil
            detailsLabel.text = nil
            mutualGroupsLabel.text = nil
            avatarView = nil
        }
    }
}
