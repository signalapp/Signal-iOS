//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Lottie
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

        let titleButton = componentView.titleButton
        titleLabelConfig.applyForRendering(button: titleButton)
        self.configureTitleAction(button: titleButton, delegate: componentDelegate)
        innerViews.append(titleButton)

        let groupInfoWrapper = ManualLayoutViewWithLayer(name: "groupWrapper")

        // Unique background for release notes channel,
        // blurred background for when there's wallpaper,
        // frame with rounded corners otherwise.
        let cornerRadius: CGFloat = 40
        if thread.isReleaseNotesThread {
            if Theme.isDarkThemeEnabled {
                groupInfoWrapper.backgroundColor = UIColor(rgbHex: 0x2F3240, alpha: 1)
            } else {
                groupInfoWrapper.backgroundColor = UIColor(rgbHex: 0xF6F7FF, alpha: 1)
            }
            groupInfoWrapper.layer.cornerRadius = cornerRadius
            groupInfoWrapper.layer.borderWidth = 2
            groupInfoWrapper.layer.borderColor = UIColor.Signal.tertiaryFill.cgColor
        } else if conversationStyle.hasWallpaper {
            let wallpaperBlurView = componentView.ensureWallpaperBlurView()
            configureWallpaperBlurView(
                wallpaperBlurView: wallpaperBlurView,
                componentDelegate: componentDelegate,
                bubbleConfig: BubbleConfiguration(
                    corners: .uniform(cornerRadius),
                    stroke: ConversationStyle.bubbleStroke(isDarkThemeEnabled: isDarkThemeEnabled),
                ),
            )
            groupInfoWrapper.addSubviewToFillSuperviewEdges(wallpaperBlurView)
        } else {
            groupInfoWrapper.layer.cornerRadius = cornerRadius
            groupInfoWrapper.layer.borderWidth = 2
            groupInfoWrapper.layer.borderColor = UIColor.Signal.tertiaryFill.cgColor
        }

        if let safetySection = threadDetails.safetySection {
            if safetySection.shouldShowProfileNamesEducation {
                innerViews.append(UIView.spacer(withHeight: vSpacingNotVerifiedLabel))

                var buttonConfiguration = headerButtonConfigurationBase()
                buttonConfiguration.baseBackgroundColor = .Signal.warningLabel.withAlphaComponent(0.2)
                buttonConfiguration.contentInsets = notVerifierButtonContentInsets

                let nameNotVerifiedButtonLabelConfig = nameNotVerifiedConfig()
                nameNotVerifiedButtonLabelConfig.applyForRendering(buttonConfiguration: &buttonConfiguration)

                let nameNotVerifiedButton = UIButton(
                    configuration: buttonConfiguration,
                    primaryAction: UIAction { _ in
                        componentDelegate.didTapNameEducation(type: safetySection.threadType)
                    },
                )
                innerViews.append(nameNotVerifiedButton)

                componentView.profileNamesEducationButton = nameNotVerifiedButton
            } else if safetySection.isOfficialChat {
                innerViews.append(UIView.spacer(withHeight: vSpacingNotVerifiedLabel))

                let officialLabel = componentView.officialLabel
                let officialLabelConfig = officialLabelConfig()
                officialLabelConfig.applyForRendering(label: officialLabel)
                officialLabel.backgroundColor = UIColor.Signal.officialLabelBackground
                officialLabel.layer.cornerRadius = 14
                officialLabel.layer.masksToBounds = true
                innerViews.append(officialLabel)
            }
        }

        if let groupDescriptionText {
            innerViews.append(UIView.spacer(withHeight: vSpacingSafetySectionDefault))
            let groupDescriptionPreviewView = componentView.groupDescriptionPreviewView
            let config = groupDescriptionTextLabelConfig(text: groupDescriptionText)
            groupDescriptionPreviewView.apply(config: config)
            groupDescriptionPreviewView.groupName = titleText
            innerViews.append(groupDescriptionPreviewView)
        }

        if let safetySection = threadDetails.safetySection {
            if let detailsText = safetySection.detailsText {
                let detailsButton = componentView.detailsButton

                innerViews.append(UIView.spacer(withHeight: vSpacingSafetySectionDefault))
                innerViews.append(detailsButton)
                let config = mutualGroupsLabelConfig(attributedText: detailsText)
                config.applyForRendering(button: detailsButton)
                // Tap to see member count
                if safetySection.threadType == .group {
                    detailsButton.block = { [weak componentDelegate] in
                        componentDelegate?.didTapShowConversationSettings()
                    }
                }
            }

            if let mutualGroupsText = safetySection.mutualGroupsText {
                let mutualGroupsLabel = componentView.mutualGroupsLabel

                innerViews.append(UIView.spacer(withHeight: vSpacingSafetySectionDefault))
                let mutualGroupsLabelConfig = mutualGroupsLabelConfig(attributedText: mutualGroupsText)
                mutualGroupsLabelConfig.applyForRendering(label: mutualGroupsLabel)
                mutualGroupsLabel.accessibilityLabel = safetySection.mutualGroupsAccessibilityText
                innerViews.append(mutualGroupsLabel)
            }

            if safetySection.shouldShowSafetyTipsButton {
                var buttonConfiguration = headerButtonConfigurationBase()
                buttonConfiguration.contentInsets = safetyButtonContentInsets
                buttonConfiguration.baseBackgroundColor =
                    conversationStyle.hasWallpaper ? .Signal.MaterialBase.button : .Signal.secondaryFill

                let safetyTipsButtonLabelConfig = safetyTipsButtonLabelConfig()
                safetyTipsButtonLabelConfig.applyForRendering(buttonConfiguration: &buttonConfiguration)

                let showTipsButton = UIButton(
                    configuration: buttonConfiguration,
                    primaryAction: UIAction { _ in
                        componentDelegate.didTapSafetyTips()
                    },
                )

                innerViews.append(UIView.spacer(withHeight: vSpacingSafetyButton))
                innerViews.append(showTipsButton)

                componentView.showTipsButton = showTipsButton
            }
        }

        innerStackView.configure(
            config: innerStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_innerStack,
            subviews: innerViews,
        )

        let groupInfoView = ManualLayoutView(name: "groupInfoView")
        groupInfoView.addSubview(groupInfoWrapper)

        groupInfoView.addSubviewToCenterOnSuperviewWithDesiredSize(innerStackView)
        groupInfoView.addLayoutBlock({ [weak self] _ in
            guard let self, let superview = groupInfoWrapper.superview else {
                return
            }

            let outlineViewWidth = innerStackView.frame.width + hPaddingGroupDetails * 2

            let adjustedContainerSize = CGSize(
                width: outlineViewWidth,
                height: superview.bounds.height - vOffsetThreadDetailsOutline,
            )

            let originShift = (superview.width - outlineViewWidth) / 2

            let subviewFrame = CGRect(
                origin: CGPoint(x: originShift, y: superview.bounds.origin.y + vOffsetThreadDetailsOutline),
                size: adjustedContainerSize,
            )

            ManualLayoutView.setSubviewFrame(subview: groupInfoWrapper, frame: subviewFrame)
        })

        let outerViews = [groupInfoView]
        outerStackView.configure(
            config: outerStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_outerStack,
            subviews: outerViews,
        )
    }

    private var titleLabelConfig: CVLabelConfig {
        let font = UIFont.dynamicTypeTitle3.semibold()
        let textColor = Theme.primaryTextColor
        let attributedString = NSMutableAttributedString(string: titleText, attributes: [
            .font: font,
            .foregroundColor: textColor,
        ])

        if threadDetails.shouldShowContactIcon {
            let contactIcon = SignalSymbol.personCircle.attributedString(
                dynamicTypeBaseSize: 20,
                weight: .bold,
                leadingCharacter: .space,
            )
            attributedString.append(contactIcon)
        } else if threadDetails.shouldShowVerifiedBadge {
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
                    dynamicTypeBaseSize: 20,
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

    private static var mutualGroupsFont: UIFont { .dynamicTypeSubheadline }
    private static var mutualGroupsTextColor: UIColor { Theme.primaryTextColor }

    private static var underlineColor: UIColor { UIColor.Signal.transparentSeparator }

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

    private func nameNotVerifiedConfig() -> CVLabelConfig {
        let symbol = SignalSymbol.personQuestion.attributedString(dynamicTypeBaseSize: UIFont.dynamicTypeCalloutClamped.pointSize)
        let notVerifiedString = NSAttributedString.composed(
            of: [
                symbol,
                SignalSymbol.LeadingCharacter.space.rawValue,
                OWSLocalizedString(
                    "THREAD_DETAILS_PROFILE_NAMES_ARE_NOT_VERIFIED_SUBJECT",
                    comment: "Label displayed below profiles",
                ),
            ],
        )
        return CVLabelConfig(
            text: .attributedText(notVerifiedString),
            displayConfig: .forUnstyledText(
                font: .dynamicTypeCallout.medium(),
                textColor: UIColor.Signal.warningLabel,
            ),
            font: .dynamicTypeCallout.medium(),
            textColor: UIColor.Signal.warningLabel,
            numberOfLines: 0,
            lineBreakMode: .byWordWrapping,
        )
    }

    private func officialLabelConfig() -> CVLabelConfig {
        let symbol = SignalSymbol.officialBadge.attributedString(dynamicTypeBaseSize: UIFont.dynamicTypeCalloutClamped.pointSize)
        let notVerifiedString = NSAttributedString.composed(
            of: [
                symbol,
                SignalSymbol.LeadingCharacter.space.rawValue,
                OWSLocalizedString("RELEASE_NOTES_CHANNEL_OFFICIAL_LABEL", comment: "Label displayed in thread details of the release notes chat"),
            ],
        )
        return CVLabelConfig(
            text: .attributedText(notVerifiedString),
            displayConfig: .forUnstyledText(
                font: .dynamicTypeCallout.medium(),
                textColor: UIColor.Signal.officialLabel,
            ),
            font: .dynamicTypeCallout.medium(),
            textColor: UIColor.Signal.officialLabel,
            numberOfLines: 0,
            lineBreakMode: .byWordWrapping,
            textAlignment: .center,
        )
    }

    private func safetyTipsButtonLabelConfig() -> CVLabelConfig {
        CVLabelConfig.unstyledText(
            OWSLocalizedString(
                "SAFETY_TIPS_BUTTON_ACTION_TITLE",
                comment: "Title for Safety Tips button in thread details.",
            ),
            font: UIFont.dynamicTypeSubheadline.semibold(),
            textColor: Theme.primaryTextColor,
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

    private static let avatarSizeClass = ConversationAvatarView.Configuration.SizeClass.seventyFour
    private var avatarSizeClass: ConversationAvatarView.Configuration.SizeClass { Self.avatarSizeClass }

    static func buildComponentState(
        thread: TSThread,
        threadAssociatedData: ThreadAssociatedData,
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
                threadAssociatedData: threadAssociatedData,
                transaction: transaction,
                avatarBuilder: avatarBuilder,
            )
        } else if let releaseNotesThread = thread as? TSReleaseNotesThread {
            return buildComponentState(
                releaseNotesThread: releaseNotesThread,
                transaction: transaction,
            )
        } else {
            owsFailDebug("Invalid thread.")
            return CVComponentState.ThreadDetails(
                avatarDataSource: nil,
                isAvatarBlurred: false,
                isAvatarBeingDownloaded: false,
                titleText: TSGroupThread.defaultGroupName,
                shouldShowVerifiedBadge: false,
                shouldShowContactIcon: false,
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

        let safetySection = Self.buildContactSafetySection(
            for: displayName,
            in: contactThread,
            tx: transaction,
        )

        let isSystemContact = SSKEnvironment.shared.contactManagerRef.fetchSignalAccount(for: contactThread.contactAddress, transaction: transaction) != nil

        return CVComponentState.ThreadDetails(
            avatarDataSource: avatarDataSource,
            isAvatarBlurred: isAvatarBlurred,
            isAvatarBeingDownloaded: isAvatarBeingDownloaded,
            titleText: titleText,
            shouldShowVerifiedBadge: shouldShowVerifiedBadge,
            shouldShowContactIcon: isSystemContact,
            safetySection: safetySection,
            groupDescriptionText: nil,
        )
    }

    private static func buildComponentState(
        groupThread: TSGroupThread,
        threadAssociatedData: ThreadAssociatedData,
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
            threadAssociatedData: threadAssociatedData,
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
            shouldShowContactIcon: false,
            safetySection: safetySection,
            groupDescriptionText: descriptionText,
        )
    }

    private static func buildComponentState(
        releaseNotesThread: TSReleaseNotesThread,
        transaction: DBReadTransaction,
    ) -> CVComponentState.ThreadDetails {

        let titleText = OWSLocalizedString(
            "RELEASE_NOTES_CHANNEL_NAME",
            comment: "Display name for the release notes channel",
        )

        let safetySection = Self.buildReleaseNotesSafetySection(from: releaseNotesThread, tx: transaction)

        return CVComponentState.ThreadDetails(
            avatarDataSource: .asset(avatar: AvatarBuilder.releaseNotesIcon(), badge: nil),
            isAvatarBlurred: false,
            isAvatarBeingDownloaded: false,
            titleText: titleText,
            shouldShowVerifiedBadge: true,
            shouldShowContactIcon: false,
            safetySection: safetySection,
            groupDescriptionText: nil,
        )
    }

    private let vSpacingTitle: CGFloat = 8
    private let vSpacingNotVerifiedLabel: CGFloat = 6
    private let vSpacingSafetyButton: CGFloat = 16
    private let vSpacingSafetySectionDefault: CGFloat = 8

    private let safetyButtonContentInsets = NSDirectionalEdgeInsets(hMargin: 12, vMargin: 5)
    private let notVerifierButtonContentInsets = NSDirectionalEdgeInsets(hMargin: 12, vMargin: 2)
    private func headerButtonConfigurationBase() -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        return configuration
    }

    private let hPaddingGroupDetails: CGFloat = 25

    private let vOffsetThreadDetailsOutline: CGFloat = 16

    private let minBottomPadding: CGFloat = 4

    private var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .fill,
            spacing: 0,
            layoutMargins: UIEdgeInsets(top: 8, left: 0, bottom: 16, right: 0),
        )
    }

    private var innerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .center,
            spacing: 0,
            layoutMargins: UIEdgeInsets(top: 0, left: 0, bottom: 24, right: 0),
        )
    }

    private static let measurementKey_outerStack = "CVComponentThreadDetails.measurementKey_outerStack"
    private static let measurementKey_innerStack = "CVComponentThreadDetails.measurementKey_innerStack"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        var innerSubviewInfos = [ManualStackSubviewInfo]()

        let maxContentWidth = min(maxWidth, 276) - (hPaddingGroupDetails * 2)

        innerSubviewInfos.append(avatarSizeClass.size.asManualSubviewInfo)
        innerSubviewInfos.append(CGSize(square: vSpacingTitle).asManualSubviewInfo)

        let titleSize = CVText.measureLabel(config: titleLabelConfig, maxWidth: maxContentWidth)
        innerSubviewInfos.append(titleSize.asManualSubviewInfo)

        if let safetySection = threadDetails.safetySection {
            if safetySection.shouldShowProfileNamesEducation {
                innerSubviewInfos.append(CGSize(square: vSpacingNotVerifiedLabel).asManualSubviewInfo)
                let buttonSize = CVText.measureLabel(
                    config: nameNotVerifiedConfig(),
                    maxWidth: maxContentWidth,
                ) + notVerifierButtonContentInsets.asSize
                innerSubviewInfos.append(buttonSize.asManualSubviewInfo)
            } else if safetySection.isOfficialChat {
                innerSubviewInfos.append(CGSize(square: vSpacingNotVerifiedLabel).asManualSubviewInfo)
                let buttonSize = CVText.measureLabel(
                    config: officialLabelConfig(),
                    maxWidth: maxContentWidth,
                ) + notVerifierButtonContentInsets.asSize
                innerSubviewInfos.append(buttonSize.asManualSubviewInfo)
            }
        }

        if let groupDescriptionText {
            innerSubviewInfos.append(CGSize(square: vSpacingSafetySectionDefault).asManualSubviewInfo)
            var groupDescriptionSize = CVText.measureLabel(
                config: groupDescriptionTextLabelConfig(text: groupDescriptionText),
                maxWidth: maxContentWidth,
            )
            groupDescriptionSize.width = maxContentWidth
            innerSubviewInfos.append(groupDescriptionSize.asManualSubviewInfo(hasFixedWidth: true))
        }

        if let safetySection = threadDetails.safetySection {
            if let detailsText = safetySection.detailsText {
                innerSubviewInfos.append(CGSize(square: vSpacingSafetySectionDefault).asManualSubviewInfo)
                let size = CVText.measureLabel(
                    config: mutualGroupsLabelConfig(attributedText: detailsText),
                    maxWidth: maxContentWidth,
                )
                innerSubviewInfos.append(size.asManualSubviewInfo)
            }

            if let mutualGroupsText = safetySection.mutualGroupsText {
                innerSubviewInfos.append(CGSize(square: vSpacingSafetySectionDefault).asManualSubviewInfo)
                let groupLabelSize = CVText.measureLabel(
                    config: mutualGroupsLabelConfig(attributedText: mutualGroupsText),
                    maxWidth: maxContentWidth,
                )
                innerSubviewInfos.append(groupLabelSize.asManualSubviewInfo)
            }

            if safetySection.shouldShowSafetyTipsButton {
                innerSubviewInfos.append(CGSize(square: vSpacingSafetyButton).asManualSubviewInfo)
                let buttonSize = CVText.measureLabel(
                    config: safetyTipsButtonLabelConfig(),
                    maxWidth: maxContentWidth,
                ) + safetyButtonContentInsets.asSize
                innerSubviewInfos.append(buttonSize.asManualSubviewInfo)
            }
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
                let showTipsButton = componentView.showTipsButton,
                showTipsButton.bounds.contains(sender.location(in: componentView.showTipsButton))
            {
                componentDelegate.didTapSafetyTips()
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
                let profileNamesEducationButton = componentView.profileNamesEducationButton,
                profileNamesEducationButton.bounds.contains(sender.location(in: componentView.profileNamesEducationButton))
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

        fileprivate var profileNamesEducationButton: UIButton?
        fileprivate let officialLabel = CVLabel()

        fileprivate let reviewCarefullyLabel = CVLabel()
        fileprivate let detailsButton = CVButton()
        fileprivate let mutualGroupsLabel = CVLabel()
        fileprivate var showTipsButton: UIButton?

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
            innerStackView.removeFromSuperview()

            titleLabel.text = nil
            titleButton.reset()
            bioLabel.text = nil
            reviewCarefullyLabel.text = nil
            detailsButton.reset()
            mutualGroupsLabel.text = nil
            groupDescriptionPreviewView.descriptionText = nil
            avatarView = nil

            wallpaperBlurView?.removeFromSuperview()
        }

    }
}

extension CVComponentThreadDetails {
    private static func buildReleaseNotesSafetySection(
        from releaseNotesThread: TSReleaseNotesThread,
        tx: DBReadTransaction,
    ) -> CVComponentState.ThreadDetails.SafetySection {
        return .init(
            shouldShowProfileNamesEducation: false,
            detailsText: NSAttributedString(string: OWSLocalizedString("RELEASE_NOTES_DETAILS", comment: "Details text for the thread details view of the release notes channel")),
            mutualGroupsText: nil,
            mutualGroupsAccessibilityText: nil,
            threadType: .contact,
            shouldShowSafetyTipsButton: false,
            isOfficialChat: true,
        )
    }

    private static func buildGroupsSafetySection(
        from groupThread: TSGroupThread,
        threadAssociatedData: ThreadAssociatedData,
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
        var arguments: [String] = sortedMemberNames
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

        let membersString = String.nonPluralLocalizedStringWithFormat(
            formatString,
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

        let shouldShowUnknownThreadWarning = !threadAssociatedData.isGroupNameVerified(groupName: groupThread.groupNameOrDefault)

        return .init(
            shouldShowProfileNamesEducation: shouldShowUnknownThreadWarning,
            detailsText: membersAttributedText,
            mutualGroupsText: nil,
            mutualGroupsAccessibilityText: nil,
            threadType: .group,
            shouldShowSafetyTipsButton: shouldShowUnknownThreadWarning && groupThread.hasPendingMessageRequest(transaction: tx),
            isOfficialChat: false,
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
                shouldShowProfileNamesEducation: false,
                detailsText: nil,
                mutualGroupsText: OWSLocalizedString(
                    "THREAD_DETAILS_NOTE_TO_SELF_EXPLANATION",
                    comment: "Subtitle appearing at the top of the users 'note to self' conversation",
                ).styled(
                    with: .font(.dynamicTypeSubheadline),
                    .color(UIColor.Signal.label),
                ),
                mutualGroupsAccessibilityText: nil,
                threadType: .contact,
                shouldShowSafetyTipsButton: false,
                isOfficialChat: false,
            )
        }

        let groupThreads = TSGroupThread.groupThreads(with: contactThread.contactAddress, transaction: tx)
        let mutualGroupNames = groupThreads.filter { $0.groupModel.groupMembership.isLocalUserFullMember && $0.shouldThreadBeVisible && !$0.isTerminatedGroup }.map { $0.groupNameOrDefault }

        let isMessageRequest = contactThread.hasPendingMessageRequest(transaction: tx)

        let groupNamesFormatArg: [String] = mutualGroupNames
        let formattedString: String
        switch mutualGroupNames.count {
        case 0:
            formattedString = String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "THREAD_DETAILS_ZERO_MUTUAL_GROUPS",
                    comment: "A string indicating there are no mutual groups the user shares with this contact",
                ),
                arguments: groupNamesFormatArg,
            )
        case 1:
            formattedString = String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "THREAD_DETAILS_ONE_MUTUAL_GROUP",
                    comment: "A string indicating a mutual group the user shares with this contact. Embeds {{mutual group name}}",
                ),
                arguments: groupNamesFormatArg,
            )
        case 2:
            formattedString = String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "THREAD_DETAILS_TWO_MUTUAL_GROUP",
                    comment: "A string indicating two mutual groups the user shares with this contact. Embeds {{mutual group name}}",
                ),
                arguments: groupNamesFormatArg,
            )
        case 3:
            formattedString = String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "THREAD_DETAILS_THREE_MUTUAL_GROUP",
                    comment: "A string indicating three mutual groups the user shares with this contact. Embeds {{mutual group name}}",
                ),
                arguments: groupNamesFormatArg,
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

        let isSystemContact = SSKEnvironment.shared.contactManagerRef.fetchSignalAccount(for: contactThread.contactAddress, transaction: tx) != nil
        let shouldShowProfileNamesEducation: Bool
        if isMessageRequest {
            shouldShowProfileNamesEducation = true
        } else if case .nickname = displayName {
            shouldShowProfileNamesEducation = false
        } else if isSystemContact {
            shouldShowProfileNamesEducation = false
        } else {
            shouldShowProfileNamesEducation = true
        }

        return .init(
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
            mutualGroupsAccessibilityText: formattedString,
            threadType: .contact,
            shouldShowSafetyTipsButton: isMessageRequest,
            isOfficialChat: false,
        )
    }
}
