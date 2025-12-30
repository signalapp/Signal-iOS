//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
public import SignalUI
import Lottie

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

    public func configureCellRootComponent(
        cellView: UIView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
        messageSwipeActionState: CVMessageSwipeActionState,
        componentView: CVComponentView,
    ) {
        Self.configureCellRootComponent(
            rootComponent: self,
            cellView: cellView,
            cellMeasurement: cellMeasurement,
            componentDelegate: componentDelegate,
            componentView: componentView,
        )
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewThreadDetails()
    }

    override public func wallpaperBlurView(componentView: CVComponentView) -> CVWallpaperBlurView? {
        guard let componentView = componentView as? CVComponentViewThreadDetails else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }
        return componentView.wallpaperBlurView
    }

    public func configureForRendering(
        componentView componentViewParam: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
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
            let subviews: [UIView]

            if threadDetails.isAvatarBeingDownloaded {
                let lottieView = LottieAnimationView(name: "indeterminate_spinner_44")
                lottieView.loopMode = .loop
                lottieView.play()
                unblurAvatarSubviewInfos.append(CGSize.square(44).asManualSubviewInfo(hasFixedSize: true))

                subviews = [lottieView]
            } else {
                let unblurAvatarIconView = CVImageView()
                unblurAvatarIconView.setTemplateImageName("tap-outline-24", tintColor: .ows_white)
                unblurAvatarSubviewInfos.append(CGSize.square(24).asManualSubviewInfo(hasFixedSize: true))

                let unblurAvatarLabelConfig = CVLabelConfig.unstyledText(
                    OWSLocalizedString(
                        "THREAD_DETAILS_TAP_TO_UNBLUR_AVATAR",
                        comment: "Indicator that a blurred avatar can be revealed by tapping.",
                    ),
                    font: UIFont.dynamicTypeSubheadlineClamped,
                    textColor: .ows_white,
                )
                let maxWidth = CGFloat(avatarSizeClass.diameter) - 12
                let unblurAvatarLabelSize = CVText.measureLabel(
                    config: unblurAvatarLabelConfig,
                    maxWidth: maxWidth,
                )
                unblurAvatarSubviewInfos.append(unblurAvatarLabelSize.asManualSubviewInfo)
                let unblurAvatarLabel = CVLabel()
                unblurAvatarLabelConfig.applyForRendering(label: unblurAvatarLabel)
                subviews = [unblurAvatarIconView, unblurAvatarLabel]
            }

            let unblurAvatarStackConfig = ManualStackView.Config(
                axis: .vertical,
                alignment: .center,
                spacing: 8,
                layoutMargins: .zero,
            )
            let unblurAvatarStackMeasurement = ManualStackView.measure(
                config: unblurAvatarStackConfig,
                subviewInfos: unblurAvatarSubviewInfos,
            )

            let unblurAvatarStack = ManualStackView(name: "unblurAvatarStack")
            unblurAvatarStack.configure(
                config: unblurAvatarStackConfig,
                measurement: unblurAvatarStackMeasurement,
                subviews: subviews,
            )
            avatarWrapper.addSubviewToCenterOnSuperview(
                unblurAvatarStack,
                size: unblurAvatarStackMeasurement.measuredSize,
            )
        } else {
            innerViews.append(avatarView)
        }
        innerViews.append(UIView.spacer(withHeight: vSpacingTitle))

        if conversationStyle.hasWallpaper {
            let wallpaperBlurView = componentView.ensureWallpaperBlurView()
            configureWallpaperBlurView(
                wallpaperBlurView: wallpaperBlurView,
                maskCornerRadius: 24,
                componentDelegate: componentDelegate,
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
            innerViews.append(groupDescriptionPreviewView)
        }

        let namesEducationLabel = componentView.profileNamesEducationLabel
        let detailsButton = componentView.detailsButton
        let mutualGroupsLabel = componentView.mutualGroupsLabel
        let showTipsButton = componentView.showTipsButton

        let groupInfoWrapper = ManualLayoutViewWithLayer(name: "groupWrapper")
        var groupInfoSubviewInfos = [ManualStackSubviewInfo]()
        var groupInfoSubviews: [UIView] = []

        if let safetySection = threadDetails.safetySection {
            if safetySection.shouldShowLowTrustWarning {
                let reviewCarefullyLabel = componentView.reviewCarefullyLabel
                groupInfoSubviews.append(reviewCarefullyLabel)
                let config = self.reviewCarefullyConfig()
                config.applyForRendering(label: reviewCarefullyLabel)
                groupInfoSubviewInfos.append(reviewCarefullyLabel.sizeThatFitsMaxSize.asManualSubviewInfo)
            }

            innerViews.append(UIView.spacer(withHeight: vSpacingSafetySection(hasWallpaper: conversationStyle.hasWallpaper)))

            if conversationStyle.hasWallpaper {
                // Add divider before mutual groups
                let divider = UIView()
                divider.autoSetDimension(.width, toSize: cellMeasurement.cellSize.width)
                divider.autoSetDimension(.height, toSize: 1)
                divider.backgroundColor = UIColor(
                    white: Theme.isDarkThemeEnabled ? 1 : 0,
                    alpha: 0.12,
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
                - (hPaddingSafetySection * 2)

            if safetySection.shouldShowProfileNamesEducation {
                groupInfoSubviews.append(namesEducationLabel)
                let config = namesEducationConfig(type: safetySection.threadType)
                config.applyForRendering(button: namesEducationLabel)
                namesEducationLabel.block = { [weak componentDelegate] in
                    componentDelegate?.didTapNameEducation(type: safetySection.threadType)
                }

                let size = CVText.measureLabel(config: config, maxWidth: maxWidth)
                groupInfoSubviewInfos.append(size.asManualSubviewInfo)
            }

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

                let size = CVText.measureLabel(config: config, maxWidth: maxWidth)
                groupInfoSubviewInfos.append(size.asManualSubviewInfo)
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
                subviewInfos: groupInfoSubviewInfos,
            )

            let groupInfoStack = ManualStackView(name: "groupInfoStack")
            groupInfoStack.configure(
                config: groupStackConfig,
                measurement: groupInfoStackMeasurement,
                subviews: groupInfoSubviews,
            )
            groupInfoWrapper.addSubviewToCenterOnSuperview(
                groupInfoStack,
                size: groupInfoStackMeasurement.measuredSize,
            )
        } else {
            innerViews.append(UIView.spacer(withHeight: minBottomPadding))
        }

        innerStackView.configure(
            config: innerStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_innerStack,
            subviews: innerViews,
        )
        let outerViews = [innerStackView]
        outerStackView.configure(
            config: outerStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_outerStack,
            subviews: outerViews,
        )
    }

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
                heightReference: .pointSize,
            )
            attributedString.append(verifiedBadgeAttachment)
        }

        if canTapTitle {
            attributedString.append(
                SignalSymbol.chevronTrailing(for: titleText).attributedString(
                    dynamicTypeBaseSize: 24,
                    leadingCharacter: .nonBreakingSpace,
                    attributes: [.foregroundColor: UIColor.Signal.secondaryLabel],
                ),
            )
        }

        return CVLabelConfig(
            text: .attributedText(attributedString),
            displayConfig: .forUnstyledText(font: font, textColor: textColor),
            font: font,
            textColor: textColor,
            numberOfLines: 0,
            lineBreakMode: .byWordWrapping,
            textAlignment: .center,
        )
    }

    private func configureTitleAction(
        button: OWSButton,
        delegate: CVComponentDelegate?,
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
            textAlignment: .center,
        )
    }

    private static var mutualGroupsFont: UIFont { .dynamicTypeSubheadline }
    private static var mutualGroupsTextColor: UIColor { Theme.primaryTextColor }

    private static var underlineColor: UIColor { UIColor.Signal.transparentSeparator }

    private static var reviewCarefullyFont: UIFont { .dynamicTypeSubheadline.semibold() }
    private static var reviewCarefullyTextColor: UIColor { UIColor(rgbHex: 0xA88746) }

    private func reviewCarefullyConfig() -> CVLabelConfig {
        CVLabelConfig(
            text: .attributedText(
                .composed(of: [
                    NSAttributedString.with(
                        image: UIImage(named: "error-triangle-fill-compact")!,
                        font: .dynamicTypeCallout,
                        centerVerticallyRelativeTo: Self.reviewCarefullyFont,
                        heightReference: .pointSize,
                    ),
                    SignalSymbol.LeadingCharacter.nonBreakingSpace.rawValue,
                    OWSLocalizedString(
                        "SYSTEM_MESSAGE_UNKNOWN_THREAD_REVIEW_CAREFULLY_WARNING",
                        comment: "Indicator warning about an unknown contact thread",
                    ),
                ]).styled(with: .alignment(.center)),
            ),
            displayConfig: .forUnstyledText(
                font: Self.reviewCarefullyFont,
                textColor: Self.reviewCarefullyTextColor,
            ),
            font: Self.reviewCarefullyFont,
            textColor: Self.reviewCarefullyTextColor,
            numberOfLines: 0,
        )
    }

    private func namesEducationIcon(type: SafetyTipsType) -> UIImage {
        switch type {
        case .contact:
            return UIImage(named: "person-questionmark-compact")!
        case .group:
            return UIImage(named: "group-questionmark-compact")!
        }
    }

    private func underlinedNamesEducationString(type: SafetyTipsType) -> NSAttributedString {
        let (subject, predicate): (String, String) = switch type {
        case .contact:
            (
                OWSLocalizedString(
                    "THREAD_DETAILS_PROFILE_NAMES_ARE_NOT_VERIFIED_SUBJECT",
                    comment: "Label displayed below profiles. This is the subject part of the sentence 'Profile names are not verified'. It is embedded into THREAD_DETAILS_PROFILE_NAMES_ARE_NOT_VERIFIED_PREDICATE.",
                ),
                OWSLocalizedString(
                    "THREAD_DETAILS_PROFILE_NAMES_ARE_NOT_VERIFIED_PREDICATE",
                    comment: "Label displayed below profiles. This is the predicate part of the sentence 'Profile names are not verified'. Embeds {{ THREAD_DETAILS_PROFILE_NAMES_ARE_NOT_VERIFIED_SUBJECT }}",
                ),
            )
        case .group:
            (
                OWSLocalizedString(
                    "THREAD_DETAILS_GROUP_NAMES_ARE_NOT_VERIFIED_SUBJECT",
                    comment: "Label displayed below group info. This is the subject part of the sentence 'Group names are not verified'. It is embedded into THREAD_DETAILS_GROUP_NAMES_ARE_NOT_VERIFIED_PREDICATE.",
                ),
                OWSLocalizedString(
                    "THREAD_DETAILS_GROUP_NAMES_ARE_NOT_VERIFIED_PREDICATE",
                    comment: "Label displayed below group info. This is the predicate part of the sentence 'Group names are not verified'. Embeds {{ THREAD_DETAILS_GROUP_NAMES_ARE_NOT_VERIFIED_SUBJECT }}",
                ),
            )
        }

        let formattedString = String(format: predicate, subject)
        let subjectRange = NSString(string: formattedString).range(of: subject)
        let attributedString = NSMutableAttributedString(string: formattedString)
        attributedString.addAttributes(
            [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: Self.underlineColor,
            ],
            range: subjectRange,
        )
        return attributedString
    }

    private func namesEducationConfig(type: SafetyTipsType) -> CVLabelConfig {
        CVLabelConfig(
            text: .attributedText(
                .composed(of: [
                    NSAttributedString.with(
                        image: self.namesEducationIcon(type: type),
                        font: .dynamicTypeCallout,
                        centerVerticallyRelativeTo: Self.mutualGroupsFont,
                        heightReference: .pointSize,
                    ),
                    SignalSymbol.LeadingCharacter.nonBreakingSpace.rawValue,
                    self.underlinedNamesEducationString(type: type),
                ]).styled(with: .alignment(.center)),
            ),
            displayConfig: .forUnstyledText(
                font: Self.mutualGroupsFont,
                textColor: Self.mutualGroupsTextColor,
            ),
            font: Self.mutualGroupsFont,
            textColor: Self.mutualGroupsTextColor,
            numberOfLines: 0,
        )
    }

    private func mutualGroupsLabelConfig(attributedText: NSAttributedString) -> CVLabelConfig {
        CVLabelConfig(
            text: .attributedText(attributedText),
            displayConfig: .forUnstyledText(
                font: Self.mutualGroupsFont,
                textColor: Self.mutualGroupsTextColor,
            ),
            font: Self.mutualGroupsFont,
            textColor: Self.mutualGroupsTextColor,
            numberOfLines: 0,
            lineBreakMode: .byWordWrapping,
            textAlignment: .center,
        )
    }

    private func safetyTipsConfig() -> CVLabelConfig {
        CVLabelConfig.unstyledText(
            OWSLocalizedString(
                "SAFETY_TIPS_BUTTON_ACTION_TITLE",
                comment: "Title for Safety Tips button in thread details.",
            ),
            font: UIFont.dynamicTypeCaption1.medium(),
            textColor: Theme.isDarkThemeEnabled ? .ows_white : .ows_black,
        )
    }

    private func groupDescriptionTextLabelConfig(text: String) -> CVLabelConfig {
        CVLabelConfig.unstyledText(
            text,
            font: .dynamicTypeSubheadline,
            textColor: Theme.primaryTextColor,
            numberOfLines: 2,
            lineBreakMode: .byTruncatingTail,
            textAlignment: .center,
        )
    }

    private static let avatarSizeClass = ConversationAvatarView.Configuration.SizeClass.eightyEight
    private var avatarSizeClass: ConversationAvatarView.Configuration.SizeClass { Self.avatarSizeClass }

    static func buildComponentState(
        thread: TSThread,
        transaction: DBReadTransaction,
        avatarBuilder: CVAvatarBuilder,
    ) -> CVComponentState.ThreadDetails {
        if let contactThread = thread as? TSContactThread {
            return buildComponentState(
                contactThread: contactThread,
                transaction: transaction,
                avatarBuilder: avatarBuilder,
            )
        } else if let groupThread = thread as? TSGroupThread {
            return buildComponentState(
                groupThread: groupThread,
                transaction: transaction,
                avatarBuilder: avatarBuilder,
            )
        } else {
            owsFailDebug("Invalid thread.")
            return CVComponentState.ThreadDetails(
                avatarDataSource: nil,
                isAvatarBlurred: false,
                isAvatarBeingDownloaded: false,
                titleText: TSGroupThread.defaultGroupName,
                shouldShowVerifiedBadge: false,
                bioText: nil,
                safetySection: nil,
                groupDescriptionText: nil,
            )
        }
    }

    private static func buildComponentState(
        contactThread: TSContactThread,
        transaction: DBReadTransaction,
        avatarBuilder: CVAvatarBuilder,
    ) -> CVComponentState.ThreadDetails {

        let avatarDataSource = avatarBuilder.buildAvatarDataSource(
            forAddress: contactThread.contactAddress,
            includingBadge: true,
            localUserDisplayMode: .noteToSelf,
            diameterPoints: avatarSizeClass.diameter,
        )

        let contactManager = SSKEnvironment.shared.contactManagerImplRef
        let isAvatarBlurred = contactManager.shouldBlurContactAvatar(
            address: contactThread.contactAddress,
            tx: transaction,
        )
        let isAvatarBeingDownloaded = contactManager.avatarAddressesToShowDownloadingSpinner.contains(contactThread.contactAddress)

        let displayName = SSKEnvironment.shared.contactManagerRef.displayName(
            for: contactThread.contactAddress,
            tx: transaction,
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
            tx: transaction,
        )

        return CVComponentState.ThreadDetails(
            avatarDataSource: avatarDataSource,
            isAvatarBlurred: isAvatarBlurred,
            isAvatarBeingDownloaded: isAvatarBeingDownloaded,
            titleText: titleText,
            shouldShowVerifiedBadge: shouldShowVerifiedBadge,
            bioText: bioText,
            safetySection: safetySection,
            groupDescriptionText: nil,
        )
    }

    private static func buildComponentState(
        groupThread: TSGroupThread,
        transaction: DBReadTransaction,
        avatarBuilder: CVAvatarBuilder,
    ) -> CVComponentState.ThreadDetails {
        // If we need to reload this cell to reflect changes to any of the
        // state captured here, we need update the didThreadDetailsChange().

        let avatarDataSource = avatarBuilder.buildAvatarDataSource(
            forGroupThread: groupThread,
            diameterPoints: avatarSizeClass.diameter,
        )

        let contactManager = SSKEnvironment.shared.contactManagerImplRef
        let isAvatarBlurred = contactManager.shouldBlurGroupAvatar(
            groupId: groupThread.groupId,
            tx: transaction,
        )
        let isAvatarBeingDownloaded = contactManager.avatarGroupIdsToShowDownloadingSpinner.contains(groupThread.groupId)

        let titleText = groupThread.groupNameOrDefault

        let safetySection = Self.buildGroupsSafetySection(
            from: groupThread,
            tx: transaction,
        )
        let descriptionText: String? = {
            guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else { return nil }
            return groupModelV2.descriptionText
        }()

        return CVComponentState.ThreadDetails(
            avatarDataSource: avatarDataSource,
            isAvatarBlurred: isAvatarBlurred,
            isAvatarBeingDownloaded: isAvatarBeingDownloaded,
            titleText: titleText,
            shouldShowVerifiedBadge: false,
            bioText: nil,
            safetySection: safetySection,
            groupDescriptionText: descriptionText,
        )
    }

    private let vSpacingTitle: CGFloat = 12
    private let vSpacingSubtitle: CGFloat = 2
    private let hPaddingSafetySection: CGFloat = 24
    private func vSpacingSafetySection(hasWallpaper: Bool) -> CGFloat {
        hasWallpaper ? 12 : 16
    }

    private let minBottomPadding: CGFloat = 4

    private var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .fill,
            spacing: 0,
            layoutMargins: UIEdgeInsets(top: 8, left: 32, bottom: 16, right: 32),
        )
    }

    private var innerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .center,
            spacing: 0,
            layoutMargins: UIEdgeInsets(top: 20, leading: 16, bottom: 8, trailing: 16),
        )
    }

    private var groupStackConfig: CVStackViewConfig {
        ManualStackView.Config(
            axis: .vertical,
            alignment: .center,
            spacing: 12,
            layoutMargins: .init(hMargin: hPaddingSafetySection, vMargin: 16),
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
        innerSubviewInfos.append(CGSize(square: vSpacingTitle).asManualSubviewInfo)

        let titleSize = CVText.measureLabel(config: titleLabelConfig, maxWidth: maxContentWidth)
        innerSubviewInfos.append(titleSize.asManualSubviewInfo)

        if let bioText = self.bioText {
            let bioSize = CVText.measureLabel(
                config: bioLabelConfig(text: bioText),
                maxWidth: maxContentWidth,
            )
            innerSubviewInfos.append(CGSize(square: vSpacingSubtitle).asManualSubviewInfo)
            innerSubviewInfos.append(bioSize.asManualSubviewInfo)
        }

        if let groupDescriptionText = self.groupDescriptionText {
            var groupDescriptionSize = CVText.measureLabel(
                config: groupDescriptionTextLabelConfig(text: groupDescriptionText),
                maxWidth: maxContentWidth,
            )
            groupDescriptionSize.width = maxContentWidth
            innerSubviewInfos.append(groupDescriptionSize.asManualSubviewInfo(hasFixedWidth: true))
        }

        let maxGroupWidth = maxContentWidth - hPaddingSafetySection * 2
        var groupInfoSubviewInfos = [ManualStackSubviewInfo]()

        if let safetySection = threadDetails.safetySection {
            if safetySection.shouldShowLowTrustWarning {
                let reviewCarefullySize = CVText.measureLabel(
                    config: self.reviewCarefullyConfig(),
                    maxWidth: maxGroupWidth,
                )
                groupInfoSubviewInfos.append(reviewCarefullySize.asManualSubviewInfo)
            }

            innerSubviewInfos.append(CGSize(square: vSpacingSafetySection(hasWallpaper: conversationStyle.hasWallpaper)).asManualSubviewInfo)

            let mutualGroupsSize: CGSize
            if conversationStyle.hasWallpaper {
                innerSubviewInfos.append(CGSize(width: maxContentWidth - 16, height: 1).asManualSubviewInfo)
            }

            if safetySection.shouldShowProfileNamesEducation {
                let size = CVText.measureLabel(
                    config: self.namesEducationConfig(type: safetySection.threadType),
                    maxWidth: maxGroupWidth,
                )
                groupInfoSubviewInfos.append(size.asManualSubviewInfo)
            }

            if let detailsText = safetySection.detailsText {
                let size = CVText.measureLabel(
                    config: mutualGroupsLabelConfig(attributedText: detailsText),
                    maxWidth: maxGroupWidth,
                )
                groupInfoSubviewInfos.append(size.asManualSubviewInfo)
            }

            if let mutualGroupsText = safetySection.mutualGroupsText {
                let groupLabelSize = CVText.measureLabel(
                    config: mutualGroupsLabelConfig(attributedText: mutualGroupsText),
                    maxWidth: maxGroupWidth,
                )
                groupInfoSubviewInfos.append(groupLabelSize.asManualSubviewInfo)
            }

            if safetySection.shouldShowSafetyTipsButton {
                let safetyTipSize = CVText.measureLabel(
                    config: safetyTipsConfig(),
                    maxWidth: maxGroupWidth,
                )
                groupInfoSubviewInfos.append(safetyTipSize.asManualSubviewInfo)
            }

            mutualGroupsSize = ManualStackView.measure(
                config: groupStackConfig,
                subviewInfos: groupInfoSubviewInfos,
            ).measuredSize
            innerSubviewInfos.append(mutualGroupsSize.asManualSubviewInfo)
        } else {
            innerSubviewInfos.append(CGSize(square: minBottomPadding).asManualSubviewInfo)
        }

        let innerStackMeasurement = ManualStackView.measure(
            config: innerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_innerStack,
            subviewInfos: innerSubviewInfos,
        )
        let outerSubviewInfos = [innerStackMeasurement.measuredSize.asManualSubviewInfo]
        let outerStackMeasurement = ManualStackView.measure(
            config: outerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_outerStack,
            subviewInfos: outerSubviewInfos,
            maxWidth: maxWidth,
        )
        return outerStackMeasurement.measuredSize
    }

    // MARK: - Events

    override public func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
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

        if let safetySection = threadDetails.safetySection {
            if
                safetySection.shouldShowSafetyTipsButton,
                componentView.showTipsButton.bounds.contains(sender.location(in: componentView.showTipsButton))
            {
                didShowTips(type: safetySection.threadType)
                return true
            }

            if
                safetySection.threadType == .group,
                safetySection.detailsText != nil,
                componentView.detailsButton.bounds.contains(sender.location(in: componentView.detailsButton))
            {
                componentDelegate.didTapShowConversationSettings()
                return true
            }

            if
                safetySection.shouldShowProfileNamesEducation,
                componentView.profileNamesEducationLabel.bounds.contains(sender.location(in: componentView.profileNamesEducationLabel))
            {
                componentDelegate.didTapNameEducation(type: safetySection.threadType)
                return true
            }
        }

        if threadDetails.isAvatarBlurred {
            guard let avatarView = componentView.avatarView else {
                owsFailDebug("Missing avatarView.")
                return false
            }

            let location = sender.location(in: avatarView)
            if avatarView.bounds.contains(location) {
                let contactManager = SSKEnvironment.shared.contactManagerImplRef
                contactManager.didTapToUnblurAvatar(for: thread)
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
        fileprivate let profileNamesEducationLabel = CVButton()
        fileprivate let detailsButton = CVButton()
        fileprivate let mutualGroupsLabel = CVLabel()
        fileprivate let showTipsButton = OWSRoundedButton()
        fileprivate let groupDescriptionPreviewView = GroupDescriptionPreviewView(
            shouldDeactivateConstraints: true,
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
            reviewCarefullyLabel.text = nil
            profileNamesEducationLabel.reset()
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
        tx: DBReadTransaction,
    ) -> CVComponentState.ThreadDetails.SafetySection {
        let accountManager = DependenciesBridge.shared.tsAccountManager

        let groupMembership = groupThread.groupModel.groupMembership
        var members = groupMembership.fullMembers

        let localUserIsAMember: Bool
        if let localIdentifiers = accountManager.localIdentifiers(tx: tx) {
            // Remove yourself because we don't want to show your display name
            let removedMember = members.remove(localIdentifiers.aciAddress)
            localUserIsAMember = removedMember != nil
        } else {
            localUserIsAMember = false
        }

        let sortedMemberNames = SSKEnvironment.shared.contactManagerImplRef
            .sortedComparableNames(for: members, tx: tx)
            .map { $0.displayName.resolvedValue() }

        let formatString: String
        var underlinedPortion: String?
        var arguments: [CVarArg] = sortedMemberNames
        switch (sortedMemberNames.count, localUserIsAMember) {
        case (0, _):
            formatString = OWSLocalizedString(
                "THREAD_DETAILS_NO_MEMBERS",
                comment: "Label for a group with no members or no members but yourself",
            )
        case (1, false):
            formatString = OWSLocalizedString(
                "THREAD_DETAILS_ONE_MEMBER",
                comment: "Label for a group with one member (not counting yourself), displaying their name",
            )
        case (1, true):
            formatString = OWSLocalizedString(
                "THREAD_DETAILS_ONE_MEMBER_AND_YOURSELF",
                comment: "Label for a group you are in with one other member, listing their name and yourself",
            )
        case (2, false):
            formatString = OWSLocalizedString(
                "THREAD_DETAILS_TWO_MEMBERS",
                comment: "Label for a group you are not in which has two members, listing their names",
            )
        case (2, true):
            formatString = OWSLocalizedString(
                "THREAD_DETAILS_TWO_MEMBERS_AND_YOURSELF",
                comment: "Label for a group you are in which has two other members, listing their names and yourself",
            )
        case (3, false):
            formatString = OWSLocalizedString(
                "THREAD_DETAILS_THREE_MEMBERS",
                comment: "Label for a group you are not in which has three members, listing their names",
            )
        case (3, true):
            formatString = OWSLocalizedString(
                "THREAD_DETAILS_THREE_MEMBERS_AND_YOURSELF",
                comment: "Label for a group you are in which has three other members, listing their names and yourself",
            )
        case (4, false):
            formatString = OWSLocalizedString(
                "THREAD_DETAILS_FOUR_MEMBERS",
                comment: "Label for a group you are not in which has four members, listing their names",
            )
        default:
            formatString = OWSLocalizedString(
                "THREAD_DETAILS_MANY_MEMBERS",
                comment: "Label for a group with more than four members, listing the first three members' names and embedding THREAD_DETAILS_OTHER_MEMBERS_COUNT_%ld as a count of other members",
            )

            let otherMembersFormat = OWSLocalizedString(
                "THREAD_DETAILS_OTHER_MEMBERS_COUNT_%ld",
                tableName: "PluralAware",
                comment: "The number of other members in a group. Embedded into the last parameter of THREAD_DETAILS_MANY_MEMBERS",
            )

            let firstThreeMembers = Array(arguments.prefix(3))
            let remainingMembersCount = sortedMemberNames.count + (localUserIsAMember ? 1 : 0) - firstThreeMembers.count

            let otherMembersString = String.localizedStringWithFormat(otherMembersFormat, remainingMembersCount)

            underlinedPortion = otherMembersString
            arguments = firstThreeMembers + [otherMembersString]
        }

        let membersString = String(
            format: formatString,
            arguments: arguments,
        )
        let membersAttributedString: NSAttributedString
        if let underlinedPortion {
            let underlinedRange = NSString(string: membersString).range(of: underlinedPortion)
            let attributedString = NSMutableAttributedString(string: membersString)
            attributedString.addAttributes(
                [
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: Self.underlineColor,
                ],
                range: underlinedRange,
            )
            membersAttributedString = attributedString
        } else {
            membersAttributedString = NSAttributedString(string: membersString)
        }

        let membersAttributedText = NSAttributedString.composed(of: [
            NSAttributedString.with(
                image: UIImage(named: "group-resizable")!,
                font: Self.mutualGroupsFont,
            ),
            "  ",
            membersAttributedString,
        ]).styled(
            with: .font(Self.mutualGroupsFont),
            .color(Self.mutualGroupsTextColor),
        )

        let shouldShowUnknownThreadWarning = SSKEnvironment.shared.contactManagerImplRef.isLowTrustGroup(groupThread: groupThread, tx: tx)

        return .init(
            shouldShowLowTrustWarning: shouldShowUnknownThreadWarning,
            shouldShowProfileNamesEducation: shouldShowUnknownThreadWarning,
            detailsText: membersAttributedText,
            mutualGroupsText: nil,
            threadType: .group,
            shouldShowSafetyTipsButton: shouldShowUnknownThreadWarning && groupThread.hasPendingMessageRequest(transaction: tx),
        )
    }

    private static func buildContactSafetySection(
        for displayName: DisplayName,
        in contactThread: TSContactThread,
        tx: DBReadTransaction,
    ) -> CVComponentState.ThreadDetails.SafetySection? {
        switch displayName {
        case .nickname, .systemContactName, .profileName:
            break
        case .phoneNumber, .username, .deletedAccount, .unknown:
            // If the display name is a phone number or username, you started a
            // conversation with them and don't yet have a profile name, so we
            // don't need to show name-related info.
            return nil
        }

        guard !contactThread.isNoteToSelf else {
            return .init(
                shouldShowLowTrustWarning: false,
                shouldShowProfileNamesEducation: false,
                detailsText: nil,
                mutualGroupsText: OWSLocalizedString(
                    "THREAD_DETAILS_NOTE_TO_SELF_EXPLANATION",
                    comment: "Subtitle appearing at the top of the users 'note to self' conversation",
                ).styled(
                    with: .font(.dynamicTypeSubheadline),
                    .color(UIColor.Signal.label),
                ),
                threadType: .contact,
                shouldShowSafetyTipsButton: false,
            )
        }

        let groupThreads = TSGroupThread.groupThreads(with: contactThread.contactAddress, transaction: tx)
        let mutualGroupNames = groupThreads.filter { $0.groupModel.groupMembership.isLocalUserFullMember && $0.shouldThreadBeVisible }.map { $0.groupNameOrDefault }

        let isMessageRequest = contactThread.hasPendingMessageRequest(transaction: tx)

        let shouldShowUnknownThreadWarning = SSKEnvironment.shared.contactManagerImplRef.isLowTrustContact(
            contactThread: contactThread,
            tx: tx,
        )

        // We need these to be CVarArgs for them to format appropriately.
        let groupNamesFormatArg: [CVarArg] = mutualGroupNames
        let formattedString: String
        switch mutualGroupNames.count {
        case 0:
            formattedString = String(
                format: OWSLocalizedString(
                    "THREAD_DETAILS_ZERO_MUTUAL_GROUPS",
                    comment: "A string indicating there are no mutual groups the user shares with this contact",
                ),
                groupNamesFormatArg,
            )
        case 1:
            formattedString = String(
                format: OWSLocalizedString(
                    "THREAD_DETAILS_ONE_MUTUAL_GROUP",
                    comment: "A string indicating a mutual group the user shares with this contact. Embeds {{mutual group name}}",
                ),
                groupNamesFormatArg,
            )
        case 2:
            formattedString = String(
                format: OWSLocalizedString(
                    "THREAD_DETAILS_TWO_MUTUAL_GROUP",
                    comment: "A string indicating two mutual groups the user shares with this contact. Embeds {{mutual group name}}",
                ),
                groupNamesFormatArg,
            )
        case 3:
            formattedString = String(
                format: OWSLocalizedString(
                    "THREAD_DETAILS_THREE_MUTUAL_GROUP",
                    comment: "A string indicating three mutual groups the user shares with this contact. Embeds {{mutual group name}}",
                ),
                groupNamesFormatArg,
            )
        default:
            // For this string, we want to use the first two groups' names
            // and add a final format arg for the number of remaining
            // groups.
            let firstTwoGroups = Array(mutualGroupNames[0..<2])
            let remainingGroupsCount = mutualGroupNames.count - firstTwoGroups.count
            let formatArgs: [CVarArg] = firstTwoGroups + [remainingGroupsCount]
            formattedString = String.localizedStringWithFormat(
                OWSLocalizedString(
                    "THREAD_DETAILS_MORE_MUTUAL_GROUP_%3$ld",
                    tableName: "PluralAware",
                    comment: "A string indicating two mutual groups the user shares with this contact and that there are more unlisted. Embeds {{group name, group name, number of other groups}}",
                ),
                formatArgs,
            )
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

        let isPhoneContact = phoneNumberString != nil
        let shouldShowProfileNamesEducation = if isPhoneContact {
            false
        } else if case .nickname = displayName {
            false
        } else {
            true
        }

        return .init(
            shouldShowLowTrustWarning: shouldShowUnknownThreadWarning,
            shouldShowProfileNamesEducation: shouldShowProfileNamesEducation,
            detailsText: phoneNumberString,
            mutualGroupsText: NSAttributedString.composed(of: [
                NSAttributedString.with(
                    image: UIImage(named: "group-resizable")!,
                    font: Self.mutualGroupsFont,
                ),
                "  ",
                formattedString,
            ]),
            threadType: .contact,
            shouldShowSafetyTipsButton: isMessageRequest,
        )
    }
}
