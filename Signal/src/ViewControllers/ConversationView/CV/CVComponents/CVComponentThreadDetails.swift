//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit
import SignalUI

public class CVComponentThreadDetails: CVComponentBase, CVRootComponent {

    public var componentKey: CVComponentKey { .threadDetails }

    public var cellReuseIdentifier: CVCellReuseIdentifier {
        CVCellReuseIdentifier.threadDetails
    }

    public let isDedicatedCell = false

    private let threadDetails: CVComponentState.ThreadDetails

    private var avatarDataSource: ConversationAvatarDataSource? { threadDetails.avatarDataSource }
    private var titleText: String { threadDetails.titleText }
    private var bioText: String? { threadDetails.bioText }
    private var detailsText: String? { threadDetails.detailsText }
    private var mutualGroupsText: NSAttributedString? { threadDetails.mutualGroupsText }
    private var groupDescriptionText: String? { threadDetails.groupDescriptionText }

    required init(itemModel: CVItemModel, threadDetails: CVComponentState.ThreadDetails) {
        self.threadDetails = threadDetails

        super.init(itemModel: itemModel)
    }

    public func configureCellRootComponent(cellView: UIView,
                                           cellMeasurement: CVCellMeasurement,
                                           componentDelegate: CVComponentDelegate,
                                           messageSwipeActionState: CVMessageSwipeActionState,
                                           componentView: CVComponentView) {
        Self.configureCellRootComponent(rootComponent: self,
                                        cellView: cellView,
                                        cellMeasurement: cellMeasurement,
                                        componentDelegate: componentDelegate,
                                        componentView: componentView)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewThreadDetails()
    }

    public override func wallpaperBlurView(componentView: CVComponentView) -> CVWallpaperBlurView? {
        guard let componentView = componentView as? CVComponentViewThreadDetails else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }
        return componentView.wallpaperBlurView
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewThreadDetails else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let outerStackView = componentView.outerStackView
        let innerStackView = componentView.innerStackView

        innerStackView.reset()
        outerStackView.reset()

        outerStackView.insetsLayoutMarginsFromSafeArea = false
        innerStackView.insetsLayoutMarginsFromSafeArea = false

        var innerViews = [UIView]()

        let avatarView = ConversationAvatarView(sizeClass: avatarSizeClass, localUserDisplayMode: .asUser, useAutolayout: false)
        avatarView.updateWithSneakyTransactionIfNecessary { configuration in
            configuration.dataSource = avatarDataSource
        }
        componentView.avatarView = avatarView
        if threadDetails.isAvatarBlurred {
            let avatarWrapper = ManualLayoutView(name: "avatarWrapper")
            avatarWrapper.addSubviewToFillSuperviewEdges(avatarView)
            innerViews.append(avatarWrapper)

            var unblurAvatarSubviewInfos = [ManualStackSubviewInfo]()
            let unblurAvatarIconView = CVImageView()
            unblurAvatarIconView.setTemplateImageName("tap-outline-24", tintColor: .ows_white)
            unblurAvatarSubviewInfos.append(CGSize.square(24).asManualSubviewInfo(hasFixedSize: true))

            let unblurAvatarLabelConfig = CVLabelConfig(text: NSLocalizedString("THREAD_DETAILS_TAP_TO_UNBLUR_AVATAR",
                                                                                comment: "Indicator that a blurred avatar can be revealed by tapping."),
                                                        font: UIFont.dynamicTypeSubheadlineClamped,
                                                        textColor: .ows_white)
            let maxWidth = CGFloat(avatarSizeClass.diameter) - 12
            let unblurAvatarLabelSize = CVText.measureLabel(config: unblurAvatarLabelConfig, maxWidth: maxWidth)
            unblurAvatarSubviewInfos.append(unblurAvatarLabelSize.asManualSubviewInfo)
            let unblurAvatarLabel = CVLabel()
            unblurAvatarLabelConfig.applyForRendering(label: unblurAvatarLabel)
            let unblurAvatarStackConfig = ManualStackView.Config(axis: .vertical,
                                                                 alignment: .center,
                                                                 spacing: 8,
                                                                 layoutMargins: .zero)
            let unblurAvatarStackMeasurement = ManualStackView.measure(config: unblurAvatarStackConfig,
                                                                       subviewInfos: unblurAvatarSubviewInfos)
            let unblurAvatarStack = ManualStackView(name: "unblurAvatarStack")
            unblurAvatarStack.configure(config: unblurAvatarStackConfig,
                                        measurement: unblurAvatarStackMeasurement,
                                        subviews: [
                                            unblurAvatarIconView,
                                            unblurAvatarLabel
                                        ])
            avatarWrapper.addSubviewToCenterOnSuperview(unblurAvatarStack,
                                                        size: unblurAvatarStackMeasurement.measuredSize)
        } else {
            innerViews.append(avatarView)
        }
        innerViews.append(UIView.spacer(withHeight: 1))

        if conversationStyle.hasWallpaper {
            let wallpaperBlurView = componentView.ensureWallpaperBlurView()
            configureWallpaperBlurView(wallpaperBlurView: wallpaperBlurView,
                                       maskCornerRadius: 12,
                                       componentDelegate: componentDelegate)
            innerStackView.addSubviewToFillSuperviewEdges(wallpaperBlurView)
        }

        let titleLabel = componentView.titleLabel
        titleLabelConfig.applyForRendering(label: titleLabel)
        innerViews.append(titleLabel)

        if let bioText = self.bioText {
            let bioLabel = componentView.bioLabel
            bioLabelConfig(text: bioText).applyForRendering(label: bioLabel)
            innerViews.append(UIView.spacer(withHeight: vSpacingSubtitle))
            innerViews.append(bioLabel)
        }

        if let detailsText = self.detailsText {
            let detailsLabel = componentView.detailsLabel
            detailsLabelConfig(text: detailsText).applyForRendering(label: detailsLabel)
            innerViews.append(UIView.spacer(withHeight: vSpacingSubtitle))
            innerViews.append(detailsLabel)
        }

        if let mutualGroupsText = self.mutualGroupsText {
            let mutualGroupsLabel = componentView.mutualGroupsLabel
            mutualGroupsLabelConfig(attributedText: mutualGroupsText).applyForRendering(label: mutualGroupsLabel)
            innerViews.append(UIView.spacer(withHeight: vSpacingMutualGroups))
            innerViews.append(mutualGroupsLabel)
        }

        if let groupDescriptionText = self.groupDescriptionText {
            let groupDescriptionPreviewView = componentView.groupDescriptionPreviewView
            let config = groupDescriptionTextLabelConfig(text: groupDescriptionText)
            groupDescriptionPreviewView.apply(config: config)
            groupDescriptionPreviewView.groupName = titleLabelConfig.stringValue
            innerViews.append(UIView.spacer(withHeight: vSpacingMutualGroups))
            innerViews.append(groupDescriptionPreviewView)
        }

        innerStackView.configure(config: innerStackConfig,
                                 cellMeasurement: cellMeasurement,
                                 measurementKey: Self.measurementKey_innerStack,
                                 subviews: innerViews)
        let outerViews = [ innerStackView ]
        outerStackView.configure(config: outerStackConfig,
                                 cellMeasurement: cellMeasurement,
                                 measurementKey: Self.measurementKey_outerStack,
                                 subviews: outerViews)
    }

    private let vSpacingSubtitle: CGFloat = 2
    private let vSpacingMutualGroups: CGFloat = 4

    private var titleLabelConfig: CVLabelConfig {
        CVLabelConfig(text: titleText,
                      font: UIFont.dynamicTypeTitle1.semibold(),
                      textColor: Theme.secondaryTextAndIconColor,
                      numberOfLines: 0,
                      lineBreakMode: .byWordWrapping,
                      textAlignment: .center)
    }

    private func bioLabelConfig(text: String) -> CVLabelConfig {
        CVLabelConfig(text: text,
                      font: .dynamicTypeSubheadline,
                      textColor: Theme.secondaryTextAndIconColor,
                      numberOfLines: 0,
                      lineBreakMode: .byWordWrapping,
                      textAlignment: .center)
    }

    private func detailsLabelConfig(text: String) -> CVLabelConfig {
        CVLabelConfig(text: text,
                      font: .dynamicTypeSubheadline,
                      textColor: Theme.secondaryTextAndIconColor,
                      numberOfLines: 0,
                      lineBreakMode: .byWordWrapping,
                      textAlignment: .center)
    }

    private func mutualGroupsLabelConfig(attributedText: NSAttributedString) -> CVLabelConfig {
        CVLabelConfig(attributedText: attributedText,
                      font: .dynamicTypeSubheadline,
                      textColor: Theme.secondaryTextAndIconColor,
                      numberOfLines: 0,
                      lineBreakMode: .byWordWrapping,
                      textAlignment: .center)
    }

    private func groupDescriptionTextLabelConfig(text: String) -> CVLabelConfig {
        CVLabelConfig(text: text,
                      font: .dynamicTypeSubheadline,
                      textColor: Theme.secondaryTextAndIconColor,
                      numberOfLines: 2,
                      lineBreakMode: .byTruncatingTail,
                      textAlignment: .center)
    }

    private static let avatarSizeClass = ConversationAvatarView.Configuration.SizeClass.oneHundredTwelve
    private var avatarSizeClass: ConversationAvatarView.Configuration.SizeClass { Self.avatarSizeClass }

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
            return CVComponentState.ThreadDetails(avatarDataSource: nil,
                                                  isAvatarBlurred: false,
                                                  titleText: TSGroupThread.defaultGroupName,
                                                  bioText: nil,
                                                  detailsText: nil,
                                                  mutualGroupsText: nil,
                                                  groupDescriptionText: nil)
        }
    }

    private static func buildComponentState(contactThread: TSContactThread,
                                            transaction: SDSAnyReadTransaction,
                                            avatarBuilder: CVAvatarBuilder) -> CVComponentState.ThreadDetails {

        let avatarDataSource = avatarBuilder.buildAvatarDataSource(forAddress: contactThread.contactAddress,
                                                                   includingBadge: true,
                                                                   localUserDisplayMode: .noteToSelf,
                                                                   diameterPoints: avatarSizeClass.diameter)

        let isAvatarBlurred = contactsManagerImpl.shouldBlurContactAvatar(contactThread: contactThread,
                                                                          transaction: transaction)

        let contactName = Self.contactsManager.displayName(for: contactThread.contactAddress,
                                                           transaction: transaction)

        let titleText = { () -> String in
            if contactThread.isNoteToSelf {
                return MessageStrings.noteToSelf
            } else {
                return contactName
            }
        }()

        let bioText = { () -> String? in
            if contactThread.isNoteToSelf {
                return nil
            }
            return Self.profileManagerImpl.profileBioForDisplay(for: contactThread.contactAddress,
                                                                transaction: transaction)
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
            var formatArgs: [AttributedFormatArg] = mutualGroupNames.map { name in
                return .string(name, attributes: [.font: UIFont.dynamicTypeSubheadline.semibold()])
            }

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

                // For this string, we want to use the first two groups' names
                // and add a final format arg for the number of remaining
                // groups.
                let firstTwoGroups = Array(formatArgs[0..<2])
                let remainingGroupsCount = mutualGroupNames.count - firstTwoGroups.count
                formatArgs = firstTwoGroups + [.raw(remainingGroupsCount)]
            }

            return NSAttributedString.make(
                fromFormat: formatString,
                attributedFormatArgs: formatArgs
            )
        }()

        return CVComponentState.ThreadDetails(avatarDataSource: avatarDataSource,
                                              isAvatarBlurred: isAvatarBlurred,
                                              titleText: titleText,
                                              bioText: bioText,
                                              detailsText: detailsText,
                                              mutualGroupsText: mutualGroupsText,
                                              groupDescriptionText: nil)
    }

    private static func buildComponentState(groupThread: TSGroupThread,
                                            transaction: SDSAnyReadTransaction,
                                            avatarBuilder: CVAvatarBuilder) -> CVComponentState.ThreadDetails {

        // If we need to reload this cell to reflect changes to any of the
        // state captured here, we need update the didThreadDetailsChange().        

        let avatarDataSource = avatarBuilder.buildAvatarDataSource(
            forGroupThread: groupThread,
            diameterPoints: avatarSizeClass.diameter)

        let isAvatarBlurred = contactsManagerImpl.shouldBlurGroupAvatar(groupThread: groupThread,
                                                                        transaction: transaction)

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

        let descriptionText: String? = {
            guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else { return nil }
            return groupModelV2.descriptionText
        }()

        return CVComponentState.ThreadDetails(avatarDataSource: avatarDataSource,
                                              isAvatarBlurred: isAvatarBlurred,
                                              titleText: titleText,
                                              bioText: nil,
                                              detailsText: detailsText,
                                              mutualGroupsText: nil,
                                              groupDescriptionText: descriptionText)
    }

    private var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .fill,
                          spacing: 0,
                          layoutMargins: UIEdgeInsets(top: 32, left: 32, bottom: 16, right: 32))
    }

    private var innerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .center,
                          spacing: 3,
                          layoutMargins: UIEdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
    }

    private static let measurementKey_outerStack = "CVComponentThreadDetails.measurementKey_outerStack"
    private static let measurementKey_innerStack = "CVComponentThreadDetails.measurementKey_innerStack"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        var innerSubviewInfos = [ManualStackSubviewInfo]()

        let maxContentWidth = maxWidth - (outerStackConfig.layoutMargins.totalWidth +
                                            innerStackConfig.layoutMargins.totalWidth)

        innerSubviewInfos.append(avatarSizeClass.size.asManualSubviewInfo)
        innerSubviewInfos.append(CGSize(square: 1).asManualSubviewInfo)

        let titleSize = CVText.measureLabel(config: titleLabelConfig, maxWidth: maxContentWidth)
        innerSubviewInfos.append(titleSize.asManualSubviewInfo)

        if let bioText = self.bioText {
            let bioSize = CVText.measureLabel(config: bioLabelConfig(text: bioText),
                                              maxWidth: maxContentWidth)
            innerSubviewInfos.append(CGSize(square: vSpacingSubtitle).asManualSubviewInfo)
            innerSubviewInfos.append(bioSize.asManualSubviewInfo)
        }

        if let detailsText = self.detailsText {
            let detailsSize = CVText.measureLabel(config: detailsLabelConfig(text: detailsText),
                                                  maxWidth: maxContentWidth)
            innerSubviewInfos.append(CGSize(square: vSpacingSubtitle).asManualSubviewInfo)
            innerSubviewInfos.append(detailsSize.asManualSubviewInfo)
        }

        if let mutualGroupsText = self.mutualGroupsText {
            let mutualGroupsSize = CVText.measureLabel(config: mutualGroupsLabelConfig(attributedText: mutualGroupsText),
                                                       maxWidth: maxContentWidth)
            innerSubviewInfos.append(CGSize(square: vSpacingMutualGroups).asManualSubviewInfo)
            innerSubviewInfos.append(mutualGroupsSize.asManualSubviewInfo)
        }

        if let groupDescriptionText = self.groupDescriptionText {
            var groupDescriptionSize = CVText.measureLabel(
                config: groupDescriptionTextLabelConfig(text: groupDescriptionText),
                maxWidth: maxContentWidth
            )
            groupDescriptionSize.width = maxContentWidth
            innerSubviewInfos.append(CGSize(square: vSpacingMutualGroups).asManualSubviewInfo)
            innerSubviewInfos.append(groupDescriptionSize.asManualSubviewInfo(hasFixedWidth: true))
        }

        let innerStackMeasurement = ManualStackView.measure(config: innerStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_innerStack,
                                                            subviewInfos: innerSubviewInfos)
        let outerSubviewInfos = [ innerStackMeasurement.measuredSize.asManualSubviewInfo ]
        let outerStackMeasurement = ManualStackView.measure(config: outerStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_outerStack,
                                                            subviewInfos: outerSubviewInfos,
                                                            maxWidth: maxWidth)
        return outerStackMeasurement.measuredSize
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        guard let componentView = componentView as? CVComponentViewThreadDetails else {
            owsFailDebug("Unexpected componentView.")
            return false
        }
        guard let avatarView = componentView.avatarView else {
            owsFailDebug("Missing avatarView.")
            return false
        }
        if threadDetails.isAvatarBlurred {
            let location = sender.location(in: avatarView)
            if avatarView.bounds.contains(location) {
                Self.databaseStorage.write { transaction in
                    if let contactThread = self.thread as? TSContactThread {
                        Self.contactsManagerImpl.doNotBlurContactAvatar(address: contactThread.contactAddress,
                                                                        transaction: transaction)
                    } else if let groupThread = self.thread as? TSGroupThread {
                        Self.contactsManagerImpl.doNotBlurGroupAvatar(groupThread: groupThread,
                                                                      transaction: transaction)
                    } else {
                        owsFailDebug("Invalid thread.")
                    }
                }
                return true
            }
        }
        return false
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewThreadDetails: NSObject, CVComponentView {

        fileprivate var avatarView: ConversationAvatarView?

        fileprivate let titleLabel = CVLabel()
        fileprivate let bioLabel = CVLabel()
        fileprivate let detailsLabel = CVLabel()

        fileprivate let mutualGroupsLabel = CVLabel()
        fileprivate let groupDescriptionPreviewView = GroupDescriptionPreviewView(
            shouldDeactivateConstraints: true
        )

        fileprivate let outerStackView = ManualStackView(name: "Thread details outer")
        fileprivate let innerStackView = ManualStackView(name: "Thread details inner")

        fileprivate var wallpaperBlurView: CVWallpaperBlurView?
        fileprivate func ensureWallpaperBlurView() -> CVWallpaperBlurView {
            if let wallpaperBlurView = self.wallpaperBlurView {
                return wallpaperBlurView
            }
            let wallpaperBlurView = CVWallpaperBlurView()
            self.wallpaperBlurView = wallpaperBlurView
            return wallpaperBlurView
        }

        public var isDedicatedCellView = false

        public var rootView: UIView {
            outerStackView
        }

        // MARK: -

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            outerStackView.reset()
            innerStackView.reset()

            titleLabel.text = nil
            bioLabel.text = nil
            detailsLabel.text = nil
            mutualGroupsLabel.text = nil
            groupDescriptionPreviewView.descriptionText = nil
            avatarView = nil

            wallpaperBlurView?.removeFromSuperview()
            wallpaperBlurView?.resetContentAndConfiguration()
        }

    }
}
