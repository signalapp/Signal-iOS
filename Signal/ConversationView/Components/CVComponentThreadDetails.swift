//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
public import SignalUI

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
    private var groupDescriptionText: String? { threadDetails.groupDescriptionText }

    private var canTapTitle: Bool {
        thread is TSContactThread && !thread.isNoteToSelf
    }

    init(itemModel: CVItemModel, threadDetails: CVComponentState.ThreadDetails) {
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

            let unblurAvatarLabelConfig = CVLabelConfig.unstyledText(
                OWSLocalizedString(
                    "THREAD_DETAILS_TAP_TO_UNBLUR_AVATAR",
                    comment: "Indicator that a blurred avatar can be revealed by tapping."
                ),
                font: UIFont.dynamicTypeSubheadlineClamped,
                textColor: .ows_white
            )
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
            configureWallpaperBlurView(
                wallpaperBlurView: wallpaperBlurView,
                maskCornerRadius: 24,
                componentDelegate: componentDelegate
            )
            innerStackView.addSubviewToFillSuperviewEdges(wallpaperBlurView)
        }

        let titleButton = componentView.titleButton
        titleLabelConfig.applyForRendering(button: titleButton)
        self.configureTitleAction(button: titleButton, delegate: componentDelegate)
        innerViews.append(titleButton)

        if let bioText = self.bioText {
            let bioLabel = componentView.bioLabel
            bioLabelConfig(text: bioText).applyForRendering(label: bioLabel)
            innerViews.append(UIView.spacer(withHeight: vSpacingSubtitle))
            innerViews.append(bioLabel)
        }

        if let groupDescriptionText = self.groupDescriptionText {
            let groupDescriptionPreviewView = componentView.groupDescriptionPreviewView
            let config = groupDescriptionTextLabelConfig(text: groupDescriptionText)
            groupDescriptionPreviewView.apply(config: config)
            groupDescriptionPreviewView.groupName = titleText
            innerViews.append(UIView.spacer(withHeight: vSpacingMutualGroups))
            innerViews.append(groupDescriptionPreviewView)
        }

        let safetySection = threadDetails.safetySection
        let detailsButton = componentView.detailsButton
        let mutualGroupsLabel = componentView.mutualGroupsLabel
        let showTipsButton = componentView.showTipsButton

        let groupInfoWrapper = ManualLayoutViewWithLayer(name: "groupWrapper")
        var groupInfoSubviewInfos = [ManualStackSubviewInfo]()
        var groupInfoSubviews: [UIView] = []

        if safetySection.shouldShowLowTrustWarning {
            let reviewCarefullyLabel = componentView.reviewCarefullyLabel
            groupInfoSubviews.append(reviewCarefullyLabel)
            let config = self.reviewCarefullyConfig()
            config.applyForRendering(label: reviewCarefullyLabel)
            groupInfoSubviewInfos.append(reviewCarefullyLabel.sizeThatFitsMaxSize.asManualSubviewInfo)
        }

        innerViews.append(UIView.spacer(withHeight: vSpacingMutualGroups))

        if conversationStyle.hasWallpaper {
            // Add divider before mutual groups
            let divider = UIView()
            divider.autoSetDimension(.width, toSize: cellMeasurement.cellSize.width)
            divider.autoSetDimension(.height, toSize: 1)
            divider.backgroundColor = UIColor(
                white: Theme.isDarkThemeEnabled ? 1 : 0,
                alpha: 0.12
            )
            innerViews.append(divider)
        } else {
            groupInfoWrapper.layer.cornerRadius = 18
            groupInfoWrapper.layer.borderWidth = 2
            if Theme.isDarkThemeEnabled {
                groupInfoWrapper.layer.borderColor = nil
                groupInfoWrapper.backgroundColor = UIColor(white: 1, alpha: 0.08)
            } else {
                groupInfoWrapper.layer.borderColor = UIColor(white: 0, alpha: 0.06).cgColor
                groupInfoWrapper.backgroundColor = Theme.backgroundColor
                groupInfoWrapper.setShadow(radius: 4, opacity: 0.04, offset: .init(width: 0, height: 2))
                groupInfoWrapper.setShadow(radius: 4, opacity: 0.04, offset: .init(width: 0, height: 2))
            }
        }
        innerViews.append(groupInfoWrapper)

        let maxWidth = cellMeasurement.cellSize.width
        - outerStackConfig.layoutMargins.totalWidth
        - innerStackConfig.layoutMargins.totalWidth
        - (mutualGroupsPadding * 2)

        if let detailsText = safetySection.detailsText {
            groupInfoSubviews.append(detailsButton)
            let config = mutualGroupsLabelConfig(attributedText: detailsText)
            config.applyForRendering(button: detailsButton)
            // Tap to see member count
            if safetySection.threadType == .group {
                detailsButton.block = { [weak componentDelegate] in
                    componentDelegate?.didTapShowConversationSettings()
                }
            }
            groupInfoSubviewInfos.append(detailsButton.sizeThatFitsMaxSize.asManualSubviewInfo)
        }

        if let mutualGroupsText = safetySection.mutualGroupsText {
            let mutualGroupsLabelConfig = mutualGroupsLabelConfig(attributedText: mutualGroupsText)
            mutualGroupsLabelConfig.applyForRendering(label: mutualGroupsLabel)
            let mutualGroupsLabelSize = CVText.measureLabel(config: mutualGroupsLabelConfig, maxWidth: maxWidth)
            groupInfoSubviewInfos.append(mutualGroupsLabelSize.asManualSubviewInfo)
            groupInfoSubviews.append(mutualGroupsLabel)
        }

        if safetySection.shouldShowSafetyTipsButton {
            groupInfoSubviews.append(showTipsButton)
            let safetyButtonLabelConfig = safetyTipsConfig()
            safetyButtonLabelConfig.applyForRendering(button: showTipsButton)
            showTipsButton.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray60 : .ows_gray05
            showTipsButton.ows_contentEdgeInsets = .init(hMargin: 12.0, vMargin: 8.0)
            showTipsButton.dimsWhenHighlighted = true
            showTipsButton.block = { [weak self] in
                self?.didShowTips(type: safetySection.threadType)
            }
            groupInfoSubviewInfos.append(showTipsButton.sizeThatFitsMaxSize.asManualSubviewInfo)
        }

        let groupInfoStackMeasurement = ManualStackView.measure(
            config: groupStackConfig,
            subviewInfos: groupInfoSubviewInfos
        )

        let groupInfoStack = ManualStackView(name: "groupInfoStack")
        groupInfoStack.configure(
            config: groupStackConfig,
            measurement: groupInfoStackMeasurement,
            subviews: groupInfoSubviews
        )
        groupInfoWrapper.addSubviewToCenterOnSuperview(
            groupInfoStack,
            size: groupInfoStackMeasurement.measuredSize
        )

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
    private let vSpacingMutualGroups: CGFloat = 16
    private let mutualGroupsPadding: CGFloat = 24

    private var titleLabelConfig: CVLabelConfig {
        let font = UIFont.dynamicTypeTitle1.semibold()
        let textColor = Theme.primaryTextColor
        let attributedString = NSMutableAttributedString(string: titleText, attributes: [
            .font: font,
            .foregroundColor: textColor,
        ])

        if threadDetails.shouldShowVerifiedBadge {
            attributedString.append(" ")
            let verifiedBadgeImage = Theme.iconImage(.official)
            let verifiedBadgeAttachment = NSAttributedString.with(
                image: verifiedBadgeImage,
                font: .dynamicTypeTitle3,
                centerVerticallyRelativeTo: font,
                heightReference: .pointSize
            )
            attributedString.append(verifiedBadgeAttachment)
        }

        if
            canTapTitle,
            let chevron = UIImage(named: "chevron-right-20")
        {
            attributedString.append(.with(
                image: chevron,
                font: .systemFont(ofSize: 24),
                attributes: [
                    .foregroundColor: Theme.primaryIconColor
                ],
                centerVerticallyRelativeTo: font,
                heightReference: .pointSize
            ))
        }

        return CVLabelConfig.init(
            text: .attributedText(attributedString),
            displayConfig: .forUnstyledText(font: font, textColor: textColor),
            font: font,
            textColor: textColor,
            numberOfLines: 0,
            lineBreakMode: .byWordWrapping,
            textAlignment: .center
        )
    }

    private func configureTitleAction(
        button: OWSButton,
        delegate: CVComponentDelegate?
    ) {
        guard
            canTapTitle,
            let contactThread = thread as? TSContactThread
        else {
            button.isEnabled = false
            button.dimsWhenHighlighted = false
            button.block = {}
            return
        }

        button.dimsWhenHighlighted = true
        button.block = { [weak delegate] in
            delegate?.didTapContactName(thread: contactThread)
        }
        button.isEnabled = true
    }

    private func bioLabelConfig(text: String) -> CVLabelConfig {
        CVLabelConfig.unstyledText(
            text,
            font: .dynamicTypeSubheadline,
            textColor: Theme.primaryTextColor,
            numberOfLines: 0,
            lineBreakMode: .byWordWrapping,
            textAlignment: .center
        )
    }

    private static var mutualGroupsFont: UIFont { .dynamicTypeSubheadline }
    private static var mutualGroupsTextColor: UIColor { Theme.primaryTextColor }

    private static var reviewCarefullyFont: UIFont { .dynamicTypeSubheadline.semibold() }
    private static var reviewCarefullyTextColor: UIColor { UIColor(rgbHex: 0xA88746) }

    private func reviewCarefullyConfig() -> CVLabelConfig {
        CVLabelConfig.init(
            text: .attributedText(
                .composed(of: [
                    NSAttributedString.with(
                        image: UIImage(named: "error-triangle-fill-compact")!,
                        font: .dynamicTypeCallout,
                        centerVerticallyRelativeTo: Self.reviewCarefullyFont,
                        heightReference: .pointSize
                    ),
                    SignalSymbol.LeadingCharacter.nonBreakingSpace.rawValue,
                    OWSLocalizedString(
                        "SYSTEM_MESSAGE_UNKNOWN_THREAD_REVIEW_CAREFULLY_WARNING",
                        comment: "Indicator warning about an unknown contact thread"
                    ),
                ])
            ),
            displayConfig: .forUnstyledText(
                font: Self.reviewCarefullyFont,
                textColor: Self.reviewCarefullyTextColor
            ),
            font: Self.reviewCarefullyFont,
            textColor: Self.reviewCarefullyTextColor
        )
    }

    private func mutualGroupsLabelConfig(attributedText: NSAttributedString) -> CVLabelConfig {
        CVLabelConfig(
            text: .attributedText(attributedText),
            displayConfig: .forUnstyledText(
                font: Self.mutualGroupsFont,
                textColor: Self.mutualGroupsTextColor
            ),
            font: Self.mutualGroupsFont,
            textColor: Self.mutualGroupsTextColor,
            numberOfLines: 0,
            lineBreakMode: .byWordWrapping,
            textAlignment: .center
        )
    }
    private func safetyTipsConfig() -> CVLabelConfig {
        CVLabelConfig.unstyledText(
            OWSLocalizedString(
                "SAFETY_TIPS_BUTTON_ACTION_TITLE",
                comment: "Title for Safety Tips button in thread details."
            ),
            font: UIFont.dynamicTypeCaption1.medium(),
            textColor: Theme.isDarkThemeEnabled ? .ows_white : .ows_black
        )
    }

    private func groupDescriptionTextLabelConfig(text: String) -> CVLabelConfig {
        CVLabelConfig.unstyledText(
            text,
            font: .dynamicTypeSubheadline,
            textColor: Theme.primaryTextColor,
            numberOfLines: 2,
            lineBreakMode: .byTruncatingTail,
            textAlignment: .center
        )
    }

    private static let avatarSizeClass = ConversationAvatarView.Configuration.SizeClass.eightyEight
    private var avatarSizeClass: ConversationAvatarView.Configuration.SizeClass { Self.avatarSizeClass }

    static func buildComponentState(
        thread: TSThread,
        transaction: SDSAnyReadTransaction,
        avatarBuilder: CVAvatarBuilder
    ) -> CVComponentState.ThreadDetails {
        if let contactThread = thread as? TSContactThread {
            return buildComponentState(
                contactThread: contactThread,
                transaction: transaction,
                avatarBuilder: avatarBuilder
            )
        } else if let groupThread = thread as? TSGroupThread {
            return buildComponentState(
                groupThread: groupThread,
                transaction: transaction,
                avatarBuilder: avatarBuilder
            )
        } else {
            owsFailDebug("Invalid thread.")
            return CVComponentState.ThreadDetails(
                avatarDataSource: nil,
                isAvatarBlurred: false,
                titleText: TSGroupThread.defaultGroupName,
                shouldShowVerifiedBadge: false,
                bioText: nil,
                safetySection: .init(
                    shouldShowLowTrustWarning: false,
                    detailsText: nil,
                    mutualGroupsText: nil,
                    threadType: .contact,
                    shouldShowSafetyTipsButton: false
                ),
                groupDescriptionText: nil
            )
        }
    }

    private static func buildComponentState(
        contactThread: TSContactThread,
        transaction: SDSAnyReadTransaction,
        avatarBuilder: CVAvatarBuilder
    ) -> CVComponentState.ThreadDetails {

        let avatarDataSource = avatarBuilder.buildAvatarDataSource(
            forAddress: contactThread.contactAddress,
            includingBadge: true,
            localUserDisplayMode: .noteToSelf,
            diameterPoints: avatarSizeClass.diameter
        )

        let isAvatarBlurred = SSKEnvironment.shared.contactManagerImplRef.shouldBlurContactAvatar(
            contactThread: contactThread,
            transaction: transaction
        )

        let displayName = SSKEnvironment.shared.contactManagerRef.displayName(
            for: contactThread.contactAddress,
            tx: transaction
        )

        let titleText = { () -> String in
            if contactThread.isNoteToSelf {
                return MessageStrings.noteToSelf
            } else {
                return displayName.resolvedValue()
            }
        }()

        let shouldShowVerifiedBadge = contactThread.isNoteToSelf

        let bioText = { () -> String? in
            if contactThread.isNoteToSelf {
                return nil
            }
            let profileManager = SSKEnvironment.shared.profileManagerRef
            let userProfile = profileManager.userProfile(for: contactThread.contactAddress, tx: transaction)
            return userProfile?.bioForDisplay
        }()

        let safetySection = Self.buildContactSafetySection(
            for: displayName,
            in: contactThread,
            tx: transaction
        )

        return CVComponentState.ThreadDetails(
            avatarDataSource: avatarDataSource,
            isAvatarBlurred: isAvatarBlurred,
            titleText: titleText,
            shouldShowVerifiedBadge: shouldShowVerifiedBadge,
            bioText: bioText,
            safetySection: safetySection,
            groupDescriptionText: nil
        )
    }

    private static func buildComponentState(
        groupThread: TSGroupThread,
        transaction: SDSAnyReadTransaction,
        avatarBuilder: CVAvatarBuilder
    ) -> CVComponentState.ThreadDetails {
        // If we need to reload this cell to reflect changes to any of the
        // state captured here, we need update the didThreadDetailsChange().        

        let avatarDataSource = avatarBuilder.buildAvatarDataSource(
            forGroupThread: groupThread,
            diameterPoints: avatarSizeClass.diameter)

        let isAvatarBlurred = SSKEnvironment.shared.contactManagerImplRef.shouldBlurGroupAvatar(
            groupThread: groupThread,
            transaction: transaction
        )

        let titleText = groupThread.groupNameOrDefault

        let safetySection = Self.buildGroupsSafetySection(
            from: groupThread,
            tx: transaction
        )
        let descriptionText: String? = {
            guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else { return nil }
            return groupModelV2.descriptionText
        }()

        return CVComponentState.ThreadDetails(
            avatarDataSource: avatarDataSource,
            isAvatarBlurred: isAvatarBlurred,
            titleText: titleText,
            shouldShowVerifiedBadge: false,
            bioText: nil,
            safetySection: safetySection,
            groupDescriptionText: descriptionText
        )
    }

    private var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .fill,
            spacing: 0,
            layoutMargins: UIEdgeInsets(top: 8, left: 32, bottom: 16, right: 32)
        )
    }

    private var innerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .center,
            spacing: 3,
            layoutMargins: UIEdgeInsets(top: 20, leading: 16, bottom: 24, trailing: 16)
        )
    }

    private var groupStackConfig: CVStackViewConfig {
        ManualStackView.Config(
            axis: .vertical,
            alignment: .center,
            spacing: 12,
            layoutMargins: .init(hMargin: mutualGroupsPadding, vMargin: 24.0)
        )
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

        if let groupDescriptionText = self.groupDescriptionText {
            var groupDescriptionSize = CVText.measureLabel(
                config: groupDescriptionTextLabelConfig(text: groupDescriptionText),
                maxWidth: maxContentWidth
            )
            groupDescriptionSize.width = maxContentWidth
            innerSubviewInfos.append(CGSize(square: vSpacingMutualGroups).asManualSubviewInfo)
            innerSubviewInfos.append(groupDescriptionSize.asManualSubviewInfo(hasFixedWidth: true))
        }

        let safetySection = threadDetails.safetySection
        let maxGroupWidth = maxContentWidth - mutualGroupsPadding * 2
        var groupInfoSubviewInfos = [ManualStackSubviewInfo]()

        innerSubviewInfos.append(CGSize(square: vSpacingMutualGroups).asManualSubviewInfo)

        if safetySection.shouldShowLowTrustWarning {
            let reviewCarefullySize = CVText.measureLabel(
                config: self.reviewCarefullyConfig(),
                maxWidth: maxGroupWidth
            )
            groupInfoSubviewInfos.append(reviewCarefullySize.asManualSubviewInfo)
        }

        let mutualGroupsSize: CGSize
        if conversationStyle.hasWallpaper {
            innerSubviewInfos.append(CGSize(width: maxContentWidth - 16, height: 1).asManualSubviewInfo)
        }

        if let detailsText = safetySection.detailsText {
            let size = CVText.measureLabel(
                config: mutualGroupsLabelConfig(attributedText: detailsText),
                maxWidth: maxGroupWidth
            )
            groupInfoSubviewInfos.append(size.asManualSubviewInfo)
        }

        if let mutualGroupsText = safetySection.mutualGroupsText {
            let groupLabelSize = CVText.measureLabel(
                config: mutualGroupsLabelConfig(attributedText: mutualGroupsText),
                maxWidth: maxGroupWidth
            )
            groupInfoSubviewInfos.append(groupLabelSize.asManualSubviewInfo)
        }

        if safetySection.shouldShowSafetyTipsButton {
            let safetyTipSize = CVText.measureLabel(
                config: safetyTipsConfig(),
                maxWidth: maxGroupWidth
            )
            groupInfoSubviewInfos.append(safetyTipSize.asManualSubviewInfo)
        }

        mutualGroupsSize = ManualStackView.measure(
            config: groupStackConfig,
            subviewInfos: groupInfoSubviewInfos
        ).measuredSize
        innerSubviewInfos.append(mutualGroupsSize.asManualSubviewInfo)

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

    public override func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem
    ) -> Bool {
        guard let componentView = componentView as? CVComponentViewThreadDetails else {
            owsFailDebug("Unexpected componentView.")
            return false
        }

        if
            canTapTitle,
            let contactThread = thread as? TSContactThread,
            componentView.titleButton.bounds.contains(sender.location(in: componentView.titleButton))
        {
            componentDelegate.didTapContactName(thread: contactThread)
            return true
        }

        if
            threadDetails.safetySection.shouldShowSafetyTipsButton,
            componentView.showTipsButton.bounds.contains(sender.location(in: componentView.showTipsButton))
        {
            didShowTips(type: threadDetails.safetySection.threadType)
            return true
        }

        if
            threadDetails.safetySection.threadType == .group,
            threadDetails.safetySection.detailsText != nil,
            componentView.detailsButton.bounds.contains(sender.location(in: componentView.detailsButton))
        {
            componentDelegate.didTapShowConversationSettings()
            return true
        }

        if threadDetails.isAvatarBlurred {
            guard let avatarView = componentView.avatarView else {
                owsFailDebug("Missing avatarView.")
                return false
            }

            let location = sender.location(in: avatarView)
            if avatarView.bounds.contains(location) {
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    if let contactThread = self.thread as? TSContactThread {
                        SSKEnvironment.shared.contactManagerImplRef.doNotBlurContactAvatar(address: contactThread.contactAddress,
                                                                        transaction: transaction)
                    } else if let groupThread = self.thread as? TSGroupThread {
                        SSKEnvironment.shared.contactManagerImplRef.doNotBlurGroupAvatar(groupThread: groupThread,
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
        fileprivate let titleButton = CVButton()
        fileprivate let bioLabel = CVLabel()

        fileprivate let reviewCarefullyLabel = CVLabel()
        fileprivate let detailsButton = CVButton()
        fileprivate let mutualGroupsLabel = CVLabel()
        fileprivate let showTipsButton = OWSRoundedButton()
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
            titleButton.reset()
            bioLabel.text = nil
            detailsButton.reset()
            mutualGroupsLabel.text = nil
            groupDescriptionPreviewView.descriptionText = nil
            avatarView = nil

            wallpaperBlurView?.removeFromSuperview()
            wallpaperBlurView?.resetContentAndConfiguration()
        }

    }
}

extension CVComponentThreadDetails {

    private func didShowTips(type: SafetyTipsType) {
        let viewController = SafetyTipsViewController(type: type)
        UIApplication.shared.frontmostViewController?.present(viewController, animated: true)
    }

    private static func buildGroupsSafetySection(
        from groupThread: TSGroupThread,
        tx: SDSAnyReadTransaction
    ) -> CVComponentState.ThreadDetails.SafetySection {
        let memberCount = groupThread.groupModel.groupMembership.fullMembers.count
        let memberCountString = GroupViewUtils.formatGroupMembersLabel(memberCount: memberCount)

        let memberCountAttributedText = NSAttributedString.composed(of: [
            NSAttributedString.with(
                image: UIImage(named: "group-resizable")!,
                font: Self.mutualGroupsFont
            ),
            "  ",
            memberCountString.styled(
                with: .underline(.single, Self.mutualGroupsTextColor)
            ),
        ]).styled(
            with: .font(Self.mutualGroupsFont),
            .color(Self.mutualGroupsTextColor)
        )

        if SSKEnvironment.shared.contactManagerImplRef.shouldShowUnknownThreadWarning(
            thread: groupThread,
            transaction: tx
        ) {
            let text = NSAttributedString.composed(of: [
                NSAttributedString.with(
                    image: UIImage(named: "error-circle-20")!,
                    font: Self.mutualGroupsFont
                ),
                "  ",
                OWSLocalizedString(
                    "SYSTEM_MESSAGE_UNKNOWN_THREAD_WARNING_GROUP",
                    comment: "Indicator warning about an unknown group thread."
                ),
            ]).styled(
                with: .font(Self.mutualGroupsFont),
                .color(Self.mutualGroupsTextColor),
                .alignment(.center)
            )

            return .init(
                shouldShowLowTrustWarning: true,
                detailsText: memberCountAttributedText,
                mutualGroupsText: text,
                threadType: .group,
                shouldShowSafetyTipsButton: true
            )
        } else {
            return .init(
                shouldShowLowTrustWarning: false,
                detailsText: memberCountAttributedText,
                mutualGroupsText: nil,
                threadType: .group,
                shouldShowSafetyTipsButton: groupThread.hasPendingMessageRequest(transaction: tx)
            )
        }
    }

    private static func buildContactSafetySection(
        for displayName: DisplayName,
        in contactThread: TSContactThread,
        tx: SDSAnyReadTransaction
    ) -> CVComponentState.ThreadDetails.SafetySection {
        guard !contactThread.isNoteToSelf else {
            return .init(
                shouldShowLowTrustWarning: false,
                detailsText: nil,
                mutualGroupsText: OWSLocalizedString(
                    "THREAD_DETAILS_NOTE_TO_SELF_EXPLANATION",
                    comment: "Subtitle appearing at the top of the users 'note to self' conversation"
                ).styled(
                    with: .font(.dynamicTypeSubheadline),
                    .color(UIColor.Signal.label)
                ),
                threadType: .contact,
                shouldShowSafetyTipsButton: false
            )
        }

        let groupThreads = TSGroupThread.groupThreads(with: contactThread.contactAddress, transaction: tx)
        let mutualGroupNames = groupThreads.filter { $0.isLocalUserFullMember && $0.shouldThreadBeVisible }.map { $0.groupNameOrDefault }

        let formatString: String
        var formatArgs: [AttributedFormatArg] = mutualGroupNames.map { name in
            return .string(name, attributes: [.font: Self.mutualGroupsFont.semibold()])
        }

        let isMessageRequest = contactThread.hasPendingMessageRequest(transaction: tx)

        lazy var shouldShowUnknownThreadWarning = SSKEnvironment.shared.contactManagerImplRef.shouldShowUnknownThreadWarning(
            thread: contactThread,
            transaction: tx
        )

        var shouldShowLowTrustWarning = false
        switch mutualGroupNames.count {
        case 0 where shouldShowUnknownThreadWarning:
            formatString = OWSLocalizedString(
                "SYSTEM_MESSAGE_UNKNOWN_THREAD_WARNING_CONTACT",
                comment: "Indicator warning about an unknown contact thread."
            )
            shouldShowLowTrustWarning = true
        case 0 where !shouldShowUnknownThreadWarning:
            formatString = OWSLocalizedString(
                "THREAD_DETAILS_ZERO_MUTUAL_GROUPS",
                comment: "A string indicating there are no mutual groups the user shares with this contact"
            )
        case 1:
            formatString = OWSLocalizedString(
                "THREAD_DETAILS_ONE_MUTUAL_GROUP",
                comment: "A string indicating a mutual group the user shares with this contact. Embeds {{mutual group name}}"
            )
            if shouldShowUnknownThreadWarning {
                shouldShowLowTrustWarning = true
            }
        case 2:
            formatString = OWSLocalizedString(
                "THREAD_DETAILS_TWO_MUTUAL_GROUP",
                comment: "A string indicating two mutual groups the user shares with this contact. Embeds {{mutual group name}}"
            )
        case 3:
            formatString = OWSLocalizedString(
                "THREAD_DETAILS_THREE_MUTUAL_GROUP",
                comment: "A string indicating three mutual groups the user shares with this contact. Embeds {{mutual group name}}"
            )
        default:
            formatString = OWSLocalizedString(
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

        let icon: String
        if mutualGroupNames.isEmpty && shouldShowUnknownThreadWarning {
            icon = "error-circle-20"
        } else {
            icon = "group-resizable"
        }

        // In order for the phone number to appear in the same box as the
        // mutual groups, it needs to be part of the same label.
        let phoneNumberString: NSAttributedString? = {
            if case .phoneNumber = displayName {
                return nil
            }
            let phoneNumber = contactThread.contactAddress.phoneNumber
            let formattedPhoneNumber = phoneNumber.map(PhoneNumber.bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(_:))
            guard let formattedPhoneNumber else {
                return nil
            }
            return NSAttributedString.composed(of: [
                NSAttributedString.with(image: Theme.iconImage(.contactInfoPhone), font: Self.mutualGroupsFont),
                "  ",
                formattedPhoneNumber,
            ])
        }()

        return .init(
            shouldShowLowTrustWarning: shouldShowLowTrustWarning,
            detailsText: phoneNumberString,
            mutualGroupsText: NSAttributedString.composed(of: [
                NSAttributedString.with(
                    image: UIImage(named: icon)!,
                    font: Self.mutualGroupsFont
                ),
                "  ",
                NSAttributedString.make(
                    fromFormat: formatString,
                    attributedFormatArgs: formatArgs
                )
            ]),
            threadType: .contact,
            shouldShowSafetyTipsButton: isMessageRequest
        )
    }
}
