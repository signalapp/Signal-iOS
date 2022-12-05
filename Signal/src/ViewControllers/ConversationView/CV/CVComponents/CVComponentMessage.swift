//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI
import UIKit

public class CVComponentMessage: CVComponentBase, CVRootComponent {

    public var componentKey: CVComponentKey { .messageRoot }

    public static let selectionAnimationDuration: TimeInterval = 0.2

    public var cellReuseIdentifier: CVCellReuseIdentifier {
        .`default`
    }

    public var isDedicatedCell: Bool { false }

    private var bodyText: CVComponent?

    private var bodyMedia: CVComponent?

    private var senderName: CVComponent?

    private var senderAvatar: CVComponentState.SenderAvatar?
    private var hasSenderAvatarLayout: Bool {
        // Return true if space for a sender avatar appears in the layout.
        // Avatar itself might not appear due to de-duplication.
        isIncoming && isGroupThread && senderAvatar != nil && conversationStyle.type != .messageDetails
    }
    private var hasSenderAvatar: Bool {
        // Return true if a sender avatar appears.
        hasSenderAvatarLayout && itemViewState.shouldShowSenderAvatar
    }

    // This is the "standalone" footer, as opposed to
    // a footer overlaid over body media.
    private var standaloneFooter: CVComponentFooter?

    private var sticker: CVComponent?

    private var viewOnce: CVComponent?

    private var quotedReply: CVComponent?

    private var linkPreview: CVComponent?

    private var giftBadge: CVComponent?

    private var reactions: CVComponent?

    private var audioAttachment: CVComponent?

    private var genericAttachment: CVComponent?

    private var contactShare: CVComponent?

    private var bottomButtons: CVComponent?

    private var swipeActionProgress: CVMessageSwipeActionState.Progress?

    private var hasSendFailureBadge = false

    override init(itemModel: CVItemModel) {
        super.init(itemModel: itemModel)

        buildComponentStates()
    }

    private var sharpCorners: OWSDirectionalRectCorner {
        var result: OWSDirectionalRectCorner = []

        if !itemViewState.isFirstInCluster {
            result.insert(isIncoming ? .topLeading : .topTrailing)
        }

        if !itemViewState.isLastInCluster {
            result.insert(isIncoming ? .bottomLeading : .bottomTrailing)
        }

        return result
    }

    private var sharpCornersForQuotedMessage: OWSDirectionalRectCorner {
        var sharpCorners = sharpCorners

        if itemViewState.senderNameState != nil || componentState.quotedReply?.quotedReplyModel.reactionEmoji != nil {
            sharpCorners.insert(.topLeading)
            sharpCorners.insert(.topTrailing)
        }

        if componentState.bodyText != nil || !itemViewState.shouldHideFooter {
            sharpCorners.insert(.bottomLeading)
            sharpCorners.insert(.bottomTrailing)
        }

        return sharpCorners
    }

    private func subcomponent(forKey key: CVComponentKey) -> CVComponent? {
        switch key {
        case .senderName:
            return self.senderName
        case .bodyText:
            return self.bodyText
        case .bodyMedia:
            return self.bodyMedia
        case .footer:
            return self.standaloneFooter
        case .sticker:
            return self.sticker
        case .viewOnce:
            return self.viewOnce
        case .audioAttachment:
            return self.audioAttachment
        case .genericAttachment:
            return self.genericAttachment
        case .quotedReply:
            return self.quotedReply
        case .linkPreview:
            return self.linkPreview
        case .giftBadge:
            return self.giftBadge
        case .reactions:
            return self.reactions
        case .contactShare:
            return self.contactShare
        case .bottomButtons:
            return self.bottomButtons

        // We don't render sender avatars with a subcomponent.
        case .senderAvatar:
            return nil
        case .systemMessage, .dateHeader, .unreadIndicator, .typingIndicator, .threadDetails, .failedOrPendingDownloads, .sendFailureBadge, .unknownThreadWarning, .defaultDisappearingMessageTimer, .messageRoot:
            return nil
        }
    }

    private var hasBodyMedia: Bool {
        bodyMedia != nil
    }

    // TODO: We might want to render the "remotely deleted" indicator using a dedicated component.
    private var hasBodyText: Bool {
        if wasRemotelyDeleted {
            return true
        }

        return componentState.bodyText != nil
    }

    private var hasSecondaryContentForSelection: Bool {
        componentState.hasPrimaryAndSecondaryContentForSelection
    }

    private var isBubbleTransparent: Bool {
        if wasRemotelyDeleted {
            return false
        } else if componentState.isSticker {
            return true
        } else if isBorderlessViewOnceMessage {
            return false
        } else {
            return isBorderless
        }
    }

    private var isBorderlessViewOnceMessage: Bool {
        guard let viewOnce = componentState.viewOnce else {
            return false
        }
        switch viewOnce.viewOnceState {
        case .unknown:
            owsFailDebug("Invalid value.")
            return true
        case .incomingExpired, .incomingInvalidContent:
            return true
        default:
            return false
        }
    }

    private var hasTapForMore: Bool {
        standaloneFooter?.hasTapForMore ?? false
    }

    private func buildComponentStates() {

        hasSendFailureBadge = componentState.sendFailureBadge != nil

        if let senderNameState = itemViewState.senderNameState {
            self.senderName = CVComponentSenderName(itemModel: itemModel, senderNameState: senderNameState)
        }
        if let senderAvatar = componentState.senderAvatar {
            self.senderAvatar = senderAvatar
        }
        if let stickerState = componentState.sticker {
            self.sticker = CVComponentSticker(itemModel: itemModel, sticker: stickerState)
        }
        if let viewOnceState = componentState.viewOnce {
            self.viewOnce = CVComponentViewOnce(itemModel: itemModel, viewOnce: viewOnceState)
        }
        if let genericAttachmentState = componentState.genericAttachment {
            self.genericAttachment = CVComponentGenericAttachment(itemModel: itemModel,
                                                                  genericAttachment: genericAttachmentState)
        }
        if let bodyTextState = itemViewState.bodyTextState {
            bodyText = CVComponentBodyText(itemModel: itemModel, bodyTextState: bodyTextState)
        }
        if let contactShareState = componentState.contactShare {
            contactShare = CVComponentContactShare(itemModel: itemModel,
                                                   contactShareState: contactShareState)
        }
        if let bottomButtonsState = componentState.bottomButtons {
            bottomButtons = CVComponentBottomButtons(itemModel: itemModel,
                                                     bottomButtonsState: bottomButtonsState)
        }

        var footerOverlay: CVComponentFooter?

        if let audioAttachmentState = componentState.audioAttachment {
            let shouldFooterOverlayAudio = (bodyText == nil && !itemViewState.shouldHideFooter && !hasTapForMore)
            if shouldFooterOverlayAudio {
                if let footerState = itemViewState.footerState {
                    footerOverlay = CVComponentFooter(itemModel: itemModel,
                                                      footerState: footerState,
                                                      isOverlayingMedia: false,
                                                      isOutsideBubble: false)
                } else {
                    owsFailDebug("Missing footerState.")
                }
            }

            self.audioAttachment = CVComponentAudioAttachment(
                itemModel: itemModel,
                audioAttachment: audioAttachmentState,
                nextAudioAttachment: itemViewState.nextAudioAttachment,
                footerOverlay: footerOverlay
            )
        }

        if let bodyMediaState = componentState.bodyMedia {
            let shouldFooterOverlayMedia = (bodyText == nil && !isBorderless && !itemViewState.shouldHideFooter && !hasTapForMore)
            if shouldFooterOverlayMedia {
                owsAssertDebug(footerOverlay == nil)
                if let footerState = itemViewState.footerState {
                    footerOverlay = CVComponentFooter(itemModel: itemModel,
                                                      footerState: footerState,
                                                      isOverlayingMedia: true,
                                                      isOutsideBubble: false)
                } else {
                    owsFailDebug("Missing footerState.")
                }
            }

            bodyMedia = CVComponentBodyMedia(itemModel: itemModel, bodyMedia: bodyMediaState, footerOverlay: footerOverlay)
        }

        let hasStandaloneFooter = (footerOverlay == nil && !itemViewState.shouldHideFooter)
        if hasStandaloneFooter {
            if let footerState = itemViewState.footerState {
                self.standaloneFooter = CVComponentFooter(itemModel: itemModel,
                                                          footerState: footerState,
                                                          isOverlayingMedia: false,
                                                          isOutsideBubble: isBubbleTransparent)
            } else {
                owsFailDebug("Missing footerState.")
            }
        }

        if let quotedReplyState = componentState.quotedReply {
            self.quotedReply = CVComponentQuotedReply(itemModel: itemModel,
                                                      quotedReply: quotedReplyState,
                                                      sharpCornersForQuotedMessage: sharpCornersForQuotedMessage)
        }

        if let linkPreviewState = componentState.linkPreview {
            self.linkPreview = CVComponentLinkPreview(itemModel: itemModel,
                                                      linkPreviewState: linkPreviewState)
        }

        if let giftBadge = componentState.giftBadge, let viewState = itemViewState.giftBadgeState {
            self.giftBadge = CVComponentGiftBadge(itemModel: itemModel, giftBadge: giftBadge, viewState: viewState)
        }

        if let reactionsState = componentState.reactions {
            self.reactions = CVComponentReactions(itemModel: itemModel, reactions: reactionsState)
        }
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

        self.swipeActionProgress = messageSwipeActionState.getProgress(interactionId: interaction.uniqueId)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewMessage()
    }

    public override func updateScrollingContent(componentView: CVComponentView) {
        super.updateScrollingContent(componentView: componentView)

        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return
        }
        componentView.chatColorView.updateAppearance()

        // We propagate this event to all subcomponents that use the CVColorOrGradientView.
        let keys: [CVComponentKey] = [.quotedReply, .footer]
        for key in keys {
            if let subcomponentAndView = findActiveComponentAndView(key: key,
                                                                    messageView: componentView,
                                                                    ignoreMissing: true) {
                let subcomponent = subcomponentAndView.component
                let subcomponentView = subcomponentAndView.componentView
                subcomponent.updateScrollingContent(componentView: subcomponentView)
            }
        }
    }

    public static let textViewVSpacing: CGFloat = 3
    public static let bodyMediaQuotedReplyVSpacing: CGFloat = 6
    public static let quotedReplyTopMargin: CGFloat = 6

    private var sendFailureBadgeSize: CGFloat { conversationStyle.hasWallpaper ? 40 : 24 }

    public static let bubbleSharpCornerRadius: CGFloat = 4
    public static let bubbleWideCornerRadius: CGFloat = 18

    public func configureForRendering(componentView: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        var outerBubbleView: CVColorOrGradientView?
        func configureBubbleView() {
            let chatColorView = componentView.chatColorView
            var strokeConfig: CVColorOrGradientView.StrokeConfig?
            if let bubbleStrokeColor = self.bubbleStrokeColor {
                strokeConfig = CVColorOrGradientView.StrokeConfig(color: bubbleStrokeColor, width: 1)
            }
            let bubbleConfig = CVColorOrGradientView.BubbleConfig(sharpCorners: self.sharpCorners,
                                                                  sharpCornerRadius: Self.bubbleSharpCornerRadius,
                                                                  wideCornerRadius: Self.bubbleWideCornerRadius,
                                                                  strokeConfig: strokeConfig)
            chatColorView.configure(value: self.bubbleChatColor,
                                    referenceView: componentDelegate.view,
                                    bubbleConfig: bubbleConfig)
            outerBubbleView = chatColorView
        }

        let outerContentView = configureContentStack(componentView: componentView,
                                                     cellMeasurement: cellMeasurement,
                                                     componentDelegate: componentDelegate)

        let stickerOverlaySubcomponent = subcomponent(forKey: .sticker)
        if nil == stickerOverlaySubcomponent {
            // TODO: We don't always use the bubble view for media.
            configureBubbleView()
        }

        // hInnerStack

        let hInnerStack = componentView.hInnerStack
        hInnerStack.reset()
        var hInnerStackSubviews = [UIView]()

        if hasSenderAvatarLayout, let senderAvatar = self.senderAvatar {
            if hasSenderAvatar {
                componentView.avatarView.updateWithSneakyTransactionIfNecessary { config in
                    config.dataSource = senderAvatar.avatarDataSource
                }
            }
            // Add the view wrapper, not the view.
            hInnerStackSubviews.append(componentView.avatarViewSwipeToReplyWrapper)
        }

        let contentViewSwipeToReplyWrapper = componentView.contentViewSwipeToReplyWrapper
        if let bubbleView = outerBubbleView {
            bubbleView.addSubview(outerContentView)

            if let (giftWrapView, bubbleViewPartner) = self.configureGiftWrapIfNeeded(messageView: componentView) {
                let wrapper = ManualLayoutView(name: "containerForOverlay")
                wrapper.addSubviewToFillSuperviewEdges(bubbleView)
                wrapper.addSubviewToFillSuperviewEdges(giftWrapView)
                contentViewSwipeToReplyWrapper.subview = wrapper

                bubbleViewPartner.setBubbleViewHost(bubbleView)
            } else {
                contentViewSwipeToReplyWrapper.subview = bubbleView
            }

            if let componentAndView = findActiveComponentAndView(key: .bodyMedia,
                                                                 messageView: componentView) {
                if let bodyMediaComponent = componentAndView.component as? CVComponentBodyMedia {
                    if let bubbleViewPartner = bodyMediaComponent.bubbleViewPartner(componentView: componentAndView.componentView) {
                        bubbleViewPartner.setBubbleViewHost(bubbleView)
                        contentViewSwipeToReplyWrapper.addLayoutBlock { _ in
                            // The "bubble view partner" must update it's layers
                            // to reflect the bubble view state.
                            bubbleViewPartner.updateLayers()
                        }
                        hInnerStack.addLayoutBlock { _ in
                            // The "bubble view partner" must update it's layers
                            // to reflect the bubble view state.
                            bubbleViewPartner.updateLayers()
                        }
                    }
                } else {
                    owsFailDebug("Invalid component.")
                }
            }
        } else {
            contentViewSwipeToReplyWrapper.subview = outerContentView
        }
        // Use the view wrapper, not the view.
        let contentRootView = contentViewSwipeToReplyWrapper
        hInnerStackSubviews.append(contentRootView)

        hInnerStack.configure(config: hInnerStackConfig,
                              cellMeasurement: cellMeasurement,
                              measurementKey: Self.measurementKey_hInnerStack,
                              subviews: hInnerStackSubviews)

        // hOuterStack

        var hOuterStackSubviews = [UIView]()
        if isShowingSelectionUI || wasShowingSelectionUI {
            let primarySelectionView = componentView.primarySelectionView
            primarySelectionView.isSelected = componentDelegate.selectionState.isSelected(interaction.uniqueId,
                                                                                          selectionType: .primaryContent)
            primarySelectionView.updateStyle(conversationStyle: conversationStyle)

            let selectionWrapper = componentView.selectionWrapper
            if hasSecondaryContentForSelection,
               let bodyTextRootView = CVComponentBodyText.findBodyTextRootView(outerContentView) {

                struct SelectionLayoutHelper {
                    let outerContentView: UIView
                    let bodyTextRootView: UIView

                    func applyLayout(bottomSelectionView: UIView, topSelectionView: UIView?) {
                        let size = MessageSelectionView.totalSize
                        guard let superview = bottomSelectionView.superview else {
                            owsFailDebug("Missing superview.")
                            return
                        }

                        // Determine the frame of the body text view in the local
                        // coordinate system.
                        let bodyTextFrame = superview.convert(bodyTextRootView.bounds, from: bodyTextRootView)
                        let outerContentFrame = superview.convert(outerContentView.bounds, from: outerContentView)

                        if let topSelectionView = topSelectionView {
                            // "Top" should center-align with the area above the body text.
                            let topY = bodyTextFrame.y * 0.5 - size.height * 0.5
                            topSelectionView.frame = CGRect(origin: CGPoint(x: 0, y: topY), size: size)
                        }

                        // "Bottom" should center-align with the body text and the content below it.
                        //
                        // This bakes in the assumption that the group sender avatar will
                        // be bottom-aligned with the bottom of the message bubble.
                        let bottomMidY = bodyTextFrame.minY.average(outerContentFrame.maxY)
                        let bottomY = bottomMidY - size.height * 0.5
                        bottomSelectionView.frame = CGRect(origin: CGPoint(x: 0, y: bottomY), size: size)
                    }
                }
                let selectionLayoutHelper = SelectionLayoutHelper(outerContentView: outerContentView,
                                                                  bodyTextRootView: bodyTextRootView)

                let secondarySelectionView = componentView.secondarySelectionView
                secondarySelectionView.isSelected = componentDelegate.selectionState.isSelected(interaction.uniqueId,
                                                                                                selectionType: .secondaryContent)
                secondarySelectionView.updateStyle(conversationStyle: conversationStyle)

                let selectionLayoutBlock = { (_: UIView) -> Void in
                    selectionLayoutHelper.applyLayout(bottomSelectionView: secondarySelectionView,
                                                      topSelectionView: primarySelectionView)
                }

                // When doing "partial" selection, the selection UI needs to
                // align with the corresponding content views.
                //
                // Coordinating layout of "distant cousin" views in a view hierarchy
                // is trivial with iOS Auto Layout, but hard with manual layout, since
                // changes to any "intermediary" relative can affect the coordination,
                // and for a rich view hierarchy it's not practical to observe all of
                // the "intermediaries".  It's also impractical to calculate their
                // relative positions using the "measurement/layout" state.
                //
                // Therefore, we coordinate their layouts by:
                //
                // * Using layout blocks that use the actual final layouts.
                // * Adding the layout block (selectionLayoutBlock) to both
                //   the immediate parent (as usual) and to the "oldest common
                //   ancestor" (unusual).  The latter ensures that we re-layout
                //   whenever the cell changes size, for example.
                selectionWrapper.addSubview(primarySelectionView, withLayoutBlock: { _ in })
                selectionWrapper.addSubview(secondarySelectionView, withLayoutBlock: { _ in })
                selectionWrapper.addLayoutBlock(selectionLayoutBlock)
                outerContentView.addLayoutBlock(selectionLayoutBlock)
                outerContentView.setNeedsLayout()
            } else {
                selectionWrapper.addSubviewToCenterOnSuperview(primarySelectionView,
                                                               size: MessageSelectionView.totalSize)
            }
            hOuterStackSubviews.append(selectionWrapper)
        }

        if isOutgoing {
            hOuterStackSubviews.append(componentView.cellSpacer)
        }
        hOuterStackSubviews.append(hInnerStack)
        if isIncoming {
            hOuterStackSubviews.append(componentView.cellSpacer)
        }
        if let badgeConfig = componentState.sendFailureBadge {
            // Send failures are rare, so it's cheaper to only build these views when we need them.
            let sendFailureBadge = CVImageView()
            sendFailureBadge.contentMode = .center
            sendFailureBadge.setTemplateImageName("error-outline-24", tintColor: badgeConfig.color)
            if conversationStyle.hasWallpaper {
                sendFailureBadge.backgroundColor = conversationStyle.bubbleColorIncoming
                sendFailureBadge.layer.cornerRadius = sendFailureBadgeSize / 2
                sendFailureBadge.clipsToBounds = true
            }

            let sendFailureWrapper = ManualLayoutView(name: "sendFailureWrapper")
            hOuterStackSubviews.append(sendFailureWrapper)
            sendFailureWrapper.addSubview(sendFailureBadge)
            let sendFailureBadgeSize = self.sendFailureBadgeSize
            let conversationStyle = self.conversationStyle
            sendFailureWrapper.addLayoutBlock { view in
                var sendFailureFrame = CGRect(origin: .zero,
                                              size: CGSize(square: sendFailureBadgeSize))
                // Bottom align.
                sendFailureFrame.y = view.bounds.height - sendFailureFrame.height
                if !conversationStyle.hasWallpaper {
                    let sendFailureBadgeBottomMargin = round(conversationStyle.lastTextLineAxis - sendFailureBadgeSize * 0.5)
                    sendFailureFrame.y -= sendFailureBadgeBottomMargin
                }
                sendFailureBadge.frame = sendFailureFrame
            }
        }

        let hOuterStack = componentView.hOuterStack
        hOuterStack.reset()
        hOuterStack.configure(config: hOuterStackConfig,
                              cellMeasurement: cellMeasurement,
                              measurementKey: Self.measurementKey_hOuterStack,
                              subviews: hOuterStackSubviews)

        let swipeToReplyIconView = componentView.swipeToReplyIconView
        swipeToReplyIconView.contentMode = .center
        swipeToReplyIconView.alpha = 0
        let swipeToReplyIconSwipeToReplyWrapper = componentView.swipeToReplyIconSwipeToReplyWrapper
        // Add the view wrapper, not the view.
        let swipeToReplyView = swipeToReplyIconSwipeToReplyWrapper
        hInnerStack.addSubview(swipeToReplyView)
        hInnerStack.sendSubviewToBack(swipeToReplyView)

        let swipeToReplySize: CGFloat
        if conversationStyle.hasWallpaper {
            swipeToReplyIconView.backgroundColor = conversationStyle.bubbleColorIncoming
            swipeToReplyIconView.clipsToBounds = true
            swipeToReplySize = 34
            swipeToReplyIconView.setTemplateImageName("reply-outline-20",
                                                      tintColor: .ows_gray45)
        } else {
            swipeToReplyIconView.backgroundColor = .clear
            swipeToReplyIconView.clipsToBounds = false
            swipeToReplySize = 24
            swipeToReplyIconView.setTemplateImageName("reply-outline-24",
                                                      tintColor: .ows_gray45)
        }
        hInnerStack.addLayoutBlock { _ in
            guard let superview = swipeToReplyView.superview else {
                return
            }
            let contentFrame = superview.convert(contentRootView.bounds, from: contentRootView)
            var swipeToReplyFrame = CGRect(origin: .zero, size: .square(swipeToReplySize))
            // swipeToReplyIconView.autoPinEdge(.leading, to: .leading, of: swipeActionContentView, withOffset: 8)
            if CurrentAppContext().isRTL {
                swipeToReplyFrame.x = contentFrame.maxX - (swipeToReplySize + 8)
            } else {
                swipeToReplyFrame.x = contentFrame.x + 8
            }
            // swipeToReplyIconView.autoAlignAxis(.horizontal, toSameAxisOf: swipeActionContentView)
            swipeToReplyFrame.y = contentFrame.y + (contentFrame.height - swipeToReplyFrame.height) * 0.5
            swipeToReplyView.frame = swipeToReplyFrame
        }

        if let reactions = self.reactions,
           let reactionsSize = cellMeasurement.size(key: Self.measurementKey_reactions) {
            let reactionsView = configureSubcomponentView(messageView: componentView,
                                                          subcomponent: reactions,
                                                          cellMeasurement: cellMeasurement,
                                                          componentDelegate: componentDelegate,
                                                          key: .reactions)

            // Use the view wrapper, not the view.
            let reactionsSwipeToReplyWrapper = componentView.reactionsSwipeToReplyWrapper
            reactionsSwipeToReplyWrapper.subview = reactionsView.rootView
            let reactionsRootView = reactionsSwipeToReplyWrapper

            hInnerStack.addSubview(reactionsRootView)
            let reactionsVOverlap = self.reactionsVOverlap
            let reactionsHInset = self.reactionsHInset
            let isIncoming = self.isIncoming
            // We want the reaction bubbles to stick to the middle of the screen inset from
            // the edge of the bubble with a small amount of padding unless the bubble is smaller
            // than the reactions view in which case it will break these constraints and extend
            // further into the middle of the screen than the message itself.
            hInnerStack.addLayoutBlock { _ in
                guard let superview = reactionsRootView.superview else {
                    return
                }
                let contentFrame = superview.convert(outerContentView.bounds, from: outerContentView)
                var reactionsFrame = CGRect(origin: .zero, size: reactionsSize)
                reactionsFrame.y = contentFrame.maxY - reactionsVOverlap
                let leftAlignX = contentFrame.minX + reactionsHInset
                let rightAlignX = contentFrame.maxX - (reactionsSize.width + reactionsHInset)
                if isIncoming ^ CurrentAppContext().isRTL {
                    reactionsFrame.x = max(leftAlignX, rightAlignX)
                } else {
                    reactionsFrame.x = min(leftAlignX, rightAlignX)
                }
                reactionsRootView.frame = reactionsFrame
            }
        }

        componentView.hInnerStack.accessibilityLabel = buildAccessibilityLabel(componentView: componentView)
        componentView.hInnerStack.isAccessibilityElement = true

        var selectionViews: [ManualLayoutView] = [ componentView.primarySelectionView ]
        if hasSecondaryContentForSelection {
            selectionViews.append(componentView.secondarySelectionView)
        }

        // Configure hOuterStack/hInnerStack animations animations
        if isShowingSelectionUI || wasShowingSelectionUI {
            // Configure selection animations
            let selectionViewWidth = ConversationStyle.selectionViewWidth
            let layoutMargins = CurrentAppContext().isRTL ? hOuterStackConfig.layoutMargins.right : hOuterStackConfig.layoutMargins.left
            let selectionOffset = -(layoutMargins + selectionViewWidth)
            let hInnerStackOffset = -(hOuterStackConfig.spacing + selectionViewWidth)
            if isShowingSelectionUI && !wasShowingSelectionUI { // Animate in
                for selectionView in selectionViews {
                    selectionView.addTransformBlock { view in
                        let animation = CABasicAnimation(keyPath: "transform.translation.x")
                        animation.fromValue = selectionOffset
                        animation.toValue = 0
                        animation.duration = CVComponentMessage.selectionAnimationDuration
                        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
                        view.layer.add(animation, forKey: "insert")
                    }
                }

                if isIncoming {
                    hInnerStack.addTransformBlock { view in
                        let animation = CABasicAnimation(keyPath: "transform.translation.x")
                        animation.fromValue = hInnerStackOffset
                        animation.toValue = 0
                        animation.duration = CVComponentMessage.selectionAnimationDuration
                        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
                        view.layer.add(animation, forKey: "insert")
                    }
                }
            } else if !isShowingSelectionUI && wasShowingSelectionUI { // Animate out
                for selectionView in selectionViews {
                    selectionView.addTransformBlock { view in
                        let animation = CABasicAnimation(keyPath: "transform.translation.x")
                        animation.fromValue = 0
                        animation.toValue = selectionOffset
                        animation.duration = CVComponentMessage.selectionAnimationDuration
                        animation.isRemovedOnCompletion = false
                        animation.repeatCount = 0
                        animation.fillMode = CAMediaTimingFillMode.forwards
                        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
                        view.layer.add(animation, forKey: "remove")
                    }
                }

                if isIncoming {
                    hInnerStack.addTransformBlock { view in
                        let animation = CABasicAnimation(keyPath: "transform.translation.x")
                        animation.fromValue = 0
                        animation.toValue = hInnerStackOffset
                        animation.duration = CVComponentMessage.selectionAnimationDuration
                        animation.isRemovedOnCompletion = false
                        animation.repeatCount = 0
                        animation.fillMode = CAMediaTimingFillMode.forwards
                        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
                        view.layer.add(animation, forKey: "remove")
                    }
                }
            }
        } else {
            // Remove outstanding animations if needed
            for selectionView in selectionViews {
                selectionView.invalidateTransformBlocks()
            }
            hInnerStack.invalidateTransformBlocks()
        }

        hOuterStack.applyTransformBlocks()
    }

    // The behavior of this method has to align exactly with that of measureContentStack().
    private func configureContentStack(componentView: CVComponentViewMessage,
                                       cellMeasurement: CVCellMeasurement,
                                       componentDelegate: CVComponentDelegate) -> ManualLayoutView {

        let stickerOverlaySubcomponent = subcomponent(forKey: .sticker)

        func configureStackView(_ stackView: ManualStackView,
                                stackConfig: CVStackViewConfig,
                                measurementKey: String,
                                componentKeys keys: [CVComponentKey]) -> ManualStackView {
            self.configureSubcomponentStack(messageView: componentView,
                                            stackView: stackView,
                                            stackConfig: stackConfig,
                                            cellMeasurement: cellMeasurement,
                                            measurementKey: measurementKey,
                                            componentDelegate: componentDelegate,
                                            keys: keys)
            return stackView
        }

        if nil != stickerOverlaySubcomponent {
            // Sticker message.
            //
            // Stack is borderless.
            //
            // Optional senderName and footer.
            return configureStackView(componentView.contentStack,
                                      stackConfig: buildBorderlessStackConfig(),
                                      measurementKey: Self.measurementKey_contentStack,
                                      componentKeys: [.senderName, .sticker, .footer])
        } else {
            // The non-sticker case.
            // Use multiple stacks.

            let contentSections = buildContentSections()

            var contentSubviews = [UIView]()
            enumerate(contentSections: contentSections) { (contentSection: ContentSection, stackConfig: CVStackViewConfig) in
                guard let stackView = contentSection.stackView(componentView: componentView),
                      let stackMeasurementKey = contentSection.stackMeasurementKey else {
                    owsFailDebug("Missing stackView or stackMeasurementKey.")
                    return
                }
                let componentKeys = contentSection.components.map { $0.componentKey }

                var stackConfig = stackConfig
                if contentSection.sectionType == .bottomNestedText,
                   let bottomNestedTextSpacing = cellMeasurement.value(key: Self.measurementKey_bottomNestedTextSpacing) {
                    stackConfig = stackConfig.withSpacing(bottomNestedTextSpacing)
                }

                _ = configureStackView(stackView,
                                       stackConfig: stackConfig,
                                       measurementKey: stackMeasurementKey,
                                       componentKeys: componentKeys)
                contentSubviews.append(stackView)
            }
            // Append the bottom buttons if necessary.
            if nil != bottomButtons {
                if let componentAndView = configureSubcomponent(messageView: componentView,
                                                                cellMeasurement: cellMeasurement,
                                                                componentDelegate: componentDelegate,
                                                                key: .bottomButtons) {
                    let subview = componentAndView.componentView.rootView
                    contentSubviews.append(subview)
                } else {
                    owsFailDebug("Couldn't configure bottomButtons.")
                }
            }

            let contentStack = componentView.contentStack
            contentStack.reset()
            contentStack.configure(config: buildContentStackConfig(),
                                   cellMeasurement: cellMeasurement,
                                   measurementKey: Self.measurementKey_contentStack,
                                   subviews: contentSubviews)
            return contentStack
        }
    }

    private func configureGiftWrapIfNeeded(
        messageView componentView: CVComponentViewMessage
    ) -> (ManualLayoutView, OWSBubbleViewPartner)? {
        guard
            let componentAndView = self.findActiveComponentAndView(key: .giftBadge, messageView: componentView),
            let giftBadgeComponent = componentAndView.component as? CVComponentGiftBadge
        else {
            return nil
        }
        return giftBadgeComponent.configureGiftWrapIfNeeded(componentView: componentAndView.componentView)
    }

    // The "message" contents of this component are vertically
    // stacked in four sections.  Ordering of the keys in each
    // section determines the ordering of the subcomponents.
    private static var topFullWidthCVComponentKeys: [CVComponentKey] { [.linkPreview] }
    private static var topNestedCVComponentKeys: [CVComponentKey] { [.senderName] }
    private static var bottomFullWidthCVComponentKeys: [CVComponentKey] { [.quotedReply, .bodyMedia] }
    private static var bottomNestedShareCVComponentKeys: [CVComponentKey] { [.viewOnce, .audioAttachment, .genericAttachment, .contactShare, .giftBadge] }
    private static var bottomNestedTextCVComponentKeys: [CVComponentKey] { [.bodyText, .footer] }

    // The "message" contents of this component for most messages are vertically
    // stacked in four sections.
    fileprivate enum SectionType: CaseIterable {
        case topFullWidth
        case topNested
        case bottomFullWidth
        case bottomNestedShare
        case bottomNestedText
        case bottomButtons

        // Ordering of the keys in each section determines the ordering of the subcomponents.
        var hasStack: Bool {
            switch self {
            case .topFullWidth, .topNested, .bottomFullWidth, .bottomNestedShare, .bottomNestedText:
                return true
            case .bottomButtons:
                return false
            }
        }

        var isNestedSection: Bool {
            switch self {
            case .topNested, .bottomNestedShare, .bottomNestedText:
                return true
            case .topFullWidth, .bottomFullWidth, .bottomButtons:
                return false
            }
        }

        // Ordering of the keys in each section determines the ordering of the subcomponents.
        var possibleComponentKeys: [CVComponentKey] {
            switch self {
            case .topFullWidth:
                return CVComponentMessage.topFullWidthCVComponentKeys
            case .topNested:
                return CVComponentMessage.topNestedCVComponentKeys
            case .bottomFullWidth:
                return CVComponentMessage.bottomFullWidthCVComponentKeys
            case .bottomNestedShare:
                return CVComponentMessage.bottomNestedShareCVComponentKeys
            case .bottomNestedText:
                return CVComponentMessage.bottomNestedTextCVComponentKeys
            case .bottomButtons:
                return [.bottomButtons]
            }
        }

        var stackMeasurementKey: String? {
            switch self {
            case .topFullWidth:
                return CVComponentMessage.measurementKey_topFullWidthStackView
            case .topNested:
                return CVComponentMessage.measurementKey_topNestedStackView
            case .bottomFullWidth:
                return CVComponentMessage.measurementKey_bottomFullWidthStackView
            case .bottomNestedShare:
                return CVComponentMessage.measurementKey_bottomNestedShareStackView
            case .bottomNestedText:
                return CVComponentMessage.measurementKey_bottomNestedTextStackView
            case .bottomButtons:
                owsFailDebug("Invalid section")
                return nil
            }
        }

        func stackView(componentView: CVComponentViewMessage) -> ManualStackView? {
            switch self {
            case .topFullWidth:
                return componentView.topFullWidthStackView
            case .topNested:
                return componentView.topNestedStackView
            case .bottomFullWidth:
                return componentView.bottomFullWidthStackView
            case .bottomNestedShare:
                return componentView.bottomNestedShareStackView
            case .bottomNestedText:
                return componentView.bottomNestedTextStackView
            case .bottomButtons:
                return nil
            }
        }
    }

    fileprivate struct ContentSection {
        let sectionType: SectionType
        let components: [CVComponent]

        var stackMeasurementKey: String? { sectionType.stackMeasurementKey }

        func stackView(componentView: CVComponentViewMessage) -> ManualStackView? {
            sectionType.stackView(componentView: componentView)
        }
    }

    fileprivate func buildContentSections() -> [ContentSection] {
        var contentSections = [ContentSection]()
        for sectionType in SectionType.allCases {
            let subcomponents = subcomponents(forKeys: sectionType.possibleComponentKeys)
            if !subcomponents.isEmpty {
                contentSections.append(ContentSection(
                    sectionType: sectionType,
                    components: subcomponents
                ))
            }
        }
        return contentSections
    }

    fileprivate func enumerate(contentSections: [ContentSection],
                               block: (ContentSection, CVStackViewConfig) -> Void) {
        for (currentSectionIndex, contentSection) in contentSections.enumerated() {
            guard !contentSection.components.isEmpty,
                  let firstComponent = contentSection.components.first,
                  let lastComponent = contentSection.components.last else {
                owsFailDebug("Empty content section.")
                continue
            }

            let sectionType = contentSection.sectionType
            // Only enumate the sections that use stacks.
            guard sectionType.hasStack else {
                continue
            }

            let previousSections = contentSections.enumerated().compactMap { sectionIndex, section in
                sectionIndex < currentSectionIndex ? section : nil
            }
            let previousSectionItems = Array(previousSections.map { section in
                section.components.map { component in
                    SectionItem(sectionType: section.sectionType, component: component)
                }
            }.joined())

            let nextSections = contentSections.enumerated().compactMap { sectionIndex, section in
                sectionIndex > currentSectionIndex ? section : nil
            }
            let nextSectionItems = Array(nextSections.map { section in
                section.components.map { component in
                    SectionItem(sectionType: section.sectionType, component: component)
                }
            }.joined())

            let firstSectionItem = SectionItem(sectionType: sectionType, component: firstComponent)
            let lastSectionItem = SectionItem(sectionType: sectionType, component: lastComponent)
            let stackConfig = contentSectionStackConfig(sectionType: sectionType,
                                                        firstSectionItem: firstSectionItem,
                                                        lastSectionItem: lastSectionItem,
                                                        previousSectionItems: previousSectionItems,
                                                        nextSectionItems: nextSectionItems)
            block(contentSection, stackConfig)
        }
    }

    fileprivate func contentSectionStackConfig(sectionType: SectionType,
                                               firstSectionItem: SectionItem,
                                               lastSectionItem: SectionItem,
                                               previousSectionItems: [SectionItem],
                                               nextSectionItems: [SectionItem]) -> CVStackViewConfig {

        switch sectionType {
        case .topFullWidth:
            return buildFullWidthStackConfig(includeTopMargin: false, includeBottomMargin: false)
        case .bottomFullWidth:
            var applyTopMargin = false
            var applyBottomMargin = false
            if previousSectionItems.isEmpty,
               quotedReply != nil {
                applyTopMargin = true
                applyBottomMargin = bodyText == nil && standaloneFooter == nil
            } else if let previousSectionItem = previousSectionItems.last,
                      previousSectionItem.componentKey == .linkPreview,
                      quotedReply != nil {
                applyTopMargin = true
            }
            return buildFullWidthStackConfig(includeTopMargin: applyTopMargin, includeBottomMargin: applyBottomMargin)
        case .topNested, .bottomNestedShare, .bottomNestedText:
            let topMargin: ContentStackMargin
            if let previousSectionItem = previousSectionItems.last {
                // The top margin of a section's stack reflects the first item
                // in the section and the previous item (if any) before the stack.
                topMargin = contentStackMarginBetweenComponents(marginType: .top,
                                                                topSectionItem: previousSectionItem,
                                                                bottomSectionItem: firstSectionItem)
            } else {
                // If this is the first section stack, it should use the outer margin.
                topMargin = .topMargin
            }

            var bottomMargin: ContentStackMargin = .none
            if let nextSectionItem = nextSectionItems.first {
                // The bottom margin of a section's stack reflects the last item
                // in the section and the next item (if any) after the stack.
                bottomMargin = contentStackMarginBetweenComponents(marginType: .bottom,
                                                                   topSectionItem: lastSectionItem,
                                                                   bottomSectionItem: nextSectionItem)
            } else {
                // If this is the last section stack, it should use the outer margin.
                bottomMargin = .bottomMargin
            }

            return buildNestedStackConfig(topMargin: topMargin,
                                          bottomMargin: bottomMargin)
        case .bottomButtons:
            owsFailDebug("Section does not use a stack.")
            return CVStackViewConfig(axis: .vertical, alignment: .center, spacing: 0, layoutMargins: .zero)
        }
    }

    fileprivate enum ContentStackMarginType {
        case top
        case bottom
    }

    fileprivate struct SectionItem {
        let sectionType: SectionType
        let component: CVComponent

        var componentKey: CVComponentKey { component.componentKey }
    }

    private func contentStackMarginBetweenComponents(marginType: ContentStackMarginType,
                                                     topSectionItem: SectionItem,
                                                     bottomSectionItem: SectionItem) -> ContentStackMargin {

        let topComponentKey = topSectionItem.componentKey
        let bottomComponentKey = bottomSectionItem.componentKey

        // Special case: Bottom buttons are not in a stack.
        if bottomComponentKey == .bottomButtons {
            return .bottomMargin
        }

        // We use stack margins to create spacing between content sections.
        //
        // We only place the spacing on "nested" stacks.
        // So one of the two sections should be nested.
        owsAssertDebug(topSectionItem.sectionType.isNestedSection ||
                        bottomSectionItem.sectionType.isNestedSection)
        // If two "nested" sections are adjacent, we don't want to create the
        // margin on both stacks, that would double the spacing.
        if topSectionItem.sectionType.isNestedSection,
           bottomSectionItem.sectionType.isNestedSection {
            // If both sections are "nested", arbitrarily chose one.
            if marginType == .bottom {
                return .none
            }
        }

        func isLargeComponent(_ componentKey: CVComponentKey) -> Bool {
            switch componentKey {
            case .bodyText:
                return false
            case .bodyMedia, .sticker, .quotedReply, .linkPreview, .viewOnce, .audioAttachment, .genericAttachment, .contactShare:
                return true
            case .giftBadge:
                // TODO: (GB) Confirm that Gift Badges should use large component spacing.
                return true
            case .senderName:
                return false
            case .senderAvatar, .reactions, .systemMessage, .dateHeader, .unreadIndicator, .typingIndicator, .threadDetails, .unknownThreadWarning, .failedOrPendingDownloads, .sendFailureBadge, .defaultDisappearingMessageTimer, .messageRoot:
                owsFailDebug("Unexpected component.")
                return false
            case .footer:
                return false
            case .bottomButtons:
                return true
            }
        }

        // Special case: Sender name and body text.
        if topComponentKey == .senderName,
           bottomComponentKey == .bodyText {
            return .spacingCustom(spacing: 1)
        }

        // Special case: Sender name and quoted reply.
        if topComponentKey == .senderName,
           bottomComponentKey == .quotedReply {
            return .spacingCustom(spacing: 5)
        }

        // Special case: Quoted reply and "large" components.
        if topComponentKey == .quotedReply,
           isLargeComponent(bottomComponentKey) {
            return .spacingCustom(spacing: 8)
        }

        // Special case: Contact share and footer.
        if topComponentKey == .contactShare,
           bottomComponentKey == .footer {
            return .spacingCustom(spacing: 5)
        }

        // Use extra-large spacing after "large" components.
        if isLargeComponent(topComponentKey) {
            if bottomComponentKey == .footer {
                return .spacingCustom(spacing: 5)
            } else {
                return .spacingCustom(spacing: 7)
            }
        }
        // Use large spacing before "large" components.
        if isLargeComponent(bottomComponentKey) {
            return .spacingCustom(spacing: 5)
        }

        return .spacingDefault
    }

    // Builds an accessibility label for the entire message.
    // This label uses basic punctuation which might be used by
    // VoiceOver for pauses/timing.
    //
    // Example: Lilia sent: a picture, check out my selfie.
    // Example: You sent: great shot!
    private func buildAccessibilityLabel(componentView: CVComponentViewMessage) -> String {
        var elements = [String]()

        if isIncoming {
            if let accessibilityAuthorName = itemViewState.accessibilityAuthorName {
                let format = NSLocalizedString("CONVERSATION_VIEW_CELL_ACCESSIBILITY_SENDER_FORMAT",
                                               comment: "Format for sender info for accessibility label for message. Embeds {{ the sender name }}.")
                elements.append(String(format: format, accessibilityAuthorName))
            } else {
                owsFailDebug("Missing accessibilityAuthorName.")
            }
        } else if isOutgoing {
            elements.append(NSLocalizedString("CONVERSATION_VIEW_CELL_ACCESSIBILITY_SENDER_LOCAL_USER",
                                              comment: "Format for sender info for outgoing messages."))
        }

        // Order matters. For example, body media should be before body text.
        let accessibilityComponentKeys: [CVComponentKey] = [
            .bodyMedia,
            .bodyText,
            .sticker,
            .viewOnce,
            .audioAttachment,
            .genericAttachment,
            .contactShare
        ]
        var contents = [String]()
        for key in accessibilityComponentKeys {
            if let subcomponent = self.subcomponent(forKey: key) {
                if let accessibilityComponent = subcomponent as? CVAccessibilityComponent {
                    contents.append(accessibilityComponent.accessibilityDescription)
                } else {
                    owsFailDebug("Invalid accessibilityComponent.")
                }
            }
        }

        let timestampText = CVComponentFooter.timestampText(forInteraction: interaction,
                                                            shouldUseLongFormat: true)
        contents.append(timestampText)

        elements.append(contents.joined(separator: ", "))

        // NOTE: In the interest of keeping the accessibility label short,
        // we do not include information that is usually presented in the
        // following components:
        //
        // * footer (message send status, disappearing message status).
        //   We _do_ include time but not date. Dates are in the date headers.
        // * senderName
        // * senderAvatar
        // * quotedReply
        // * linkPreview
        // * reactions
        // * bottomButtons
        // * sendFailureBadge

        let result = elements.joined(separator: " ")
        return result
    }

    private var hOuterStackConfig: CVStackViewConfig {
        let bottomInset = reactions != nil ? reactionsVProtrusion : 0
        let cellLayoutMargins = UIEdgeInsets(top: 0,
                                             leading: conversationStyle.fullWidthGutterLeading,
                                             bottom: bottomInset,
                                             trailing: conversationStyle.fullWidthGutterTrailing)
        return CVStackViewConfig(axis: .horizontal,
                                 alignment: .fill,
                                 spacing: ConversationStyle.messageStackSpacing,
                                 layoutMargins: cellLayoutMargins)
    }

    private var hInnerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .bottom,
                          spacing: ConversationStyle.messageStackSpacing,
                          layoutMargins: .zero)
    }

    private let reactionsHInset: CGFloat = 6
    // The overlap between the message content and the reactions bubble.
    private var reactionsVOverlap: CGFloat {
        CVReactionCountsView.inset
    }
    // How far the reactions bubble protrudes below the message content.
    private var reactionsVProtrusion: CGFloat {
        let reactionsHeight = CVReactionCountsView.height
        return max(0, reactionsHeight - reactionsVOverlap)
    }

    private var bubbleChatColor: ColorOrGradientValue {
        if !conversationStyle.hasWallpaper && (wasRemotelyDeleted || isBorderlessViewOnceMessage) {
            return .solidColor(color: Theme.backgroundColor)
        }
        if isBubbleTransparent {
            return .transparent
        }
        return itemModel.conversationStyle.bubbleChatColor(isIncoming: isIncoming)
    }

    private var bubbleStrokeColor: UIColor? {
        if wasRemotelyDeleted || isBorderlessViewOnceMessage {
            return conversationStyle.hasWallpaper ? nil : Theme.outlineColor
        } else {
            return nil
        }
    }

    private static let measurementKey_hOuterStack = "CVComponentMessage.measurementKey_hOuterStack"
    private static let measurementKey_hInnerStack = "CVComponentMessage.measurementKey_hInnerStack"
    private static let measurementKey_contentStack = "CVComponentMessage.measurementKey_contentStack"
    private static let measurementKey_topFullWidthStackView = "CVComponentMessage.measurementKey_topFullWidthStackView"
    private static let measurementKey_topNestedStackView = "CVComponentMessage.measurementKey_topNestedStackView"
    private static let measurementKey_bottomFullWidthStackView = "CVComponentMessage.measurementKey_bottomFullWidthStackView"
    private static let measurementKey_bottomNestedShareStackView = "CVComponentMessage.measurementKey_bottomNestedShareStackView"
    private static let measurementKey_bottomNestedTextStackView = "CVComponentMessage.measurementKey_bottomNestedTextStackView"
    private static let measurementKey_reactions = "CVComponentMessage.measurementKey_reactions"
    private static let measurementKey_bottomNestedTextSpacing = "CVComponentMessage.measurementKey_bottomNestedTextSpacing"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let selectionViewWidth = ConversationStyle.selectionViewWidth

        let hOuterStackConfig = self.hOuterStackConfig
        var contentMaxWidth = maxWidth - hOuterStackConfig.layoutMargins.totalWidth
        contentMaxWidth -= ConversationStyle.messageDirectionSpacing
        if isShowingSelectionUI {
            contentMaxWidth -= selectionViewWidth + hOuterStackConfig.spacing
        }
        if !isIncoming, hasSendFailureBadge {
            contentMaxWidth -= sendFailureBadgeSize + hOuterStackConfig.spacing
        }
        if hasSenderAvatarLayout {
            // Sender avatar in groups.
            contentMaxWidth -= CGFloat(ConversationStyle.groupMessageAvatarSizeClass.diameter) + ConversationStyle.messageStackSpacing
        }

        owsAssertDebug(conversationStyle.maxMediaMessageWidth <= conversationStyle.maxMessageWidth)
        let shouldUseNarrowMaxWidth = (bodyMedia != nil ||
                                        linkPreview != nil)
        if shouldUseNarrowMaxWidth {
            contentMaxWidth = max(0, min(conversationStyle.maxMediaMessageWidth, contentMaxWidth))
        } else {
            contentMaxWidth = max(0, min(conversationStyle.maxMessageWidth, contentMaxWidth))
        }

        let contentStackSize = measureContentStack(maxWidth: contentMaxWidth,
                                                   measurementBuilder: measurementBuilder)
        if contentStackSize.width > contentMaxWidth {
            owsFailDebug("contentStackSize: \(contentStackSize) > contentMaxWidth: \(contentMaxWidth)")
        }

        var hInnerStackSubviewInfos = [ManualStackSubviewInfo]()
        if hasSenderAvatarLayout,
           nil != self.senderAvatar {
            // Sender avatar in groups.
            let avatarSize = CGSize.square(CGFloat(ConversationStyle.groupMessageAvatarSizeClass.diameter))
            hInnerStackSubviewInfos.append(avatarSize.asManualSubviewInfo(hasFixedSize: true))
        }
        // NOTE: The contentStackSize does not have fixed width and may grow
        //       to reflect the minBubbleWidth below.
        hInnerStackSubviewInfos.append(contentStackSize.asManualSubviewInfo)
        let hInnerStackMeasurement = ManualStackView.measure(config: hInnerStackConfig,
                                                             measurementBuilder: measurementBuilder,
                                                             measurementKey: Self.measurementKey_hInnerStack,
                                                             subviewInfos: hInnerStackSubviewInfos)
        var hInnerStackSize = hInnerStackMeasurement.measuredSize
        let minBubbleWidth = Self.bubbleWideCornerRadius * 2
        hInnerStackSize.width = max(hInnerStackSize.width, minBubbleWidth)

        var hOuterStackSubviewInfos = [ManualStackSubviewInfo]()
        if isShowingSelectionUI || wasShowingSelectionUI {
            let selectionViewSize = CGSize(width: selectionViewWidth, height: 0)
            hOuterStackSubviewInfos.append(selectionViewSize.asManualSubviewInfo(hasFixedWidth: true))
        }
        if isOutgoing {
            // cellSpacer
            hOuterStackSubviewInfos.append(CGSize.zero.asManualSubviewInfo)
        }
        hOuterStackSubviewInfos.append(hInnerStackSize.asManualSubviewInfo(hasFixedWidth: true))
        if isIncoming {
            // cellSpacer
            hOuterStackSubviewInfos.append(CGSize.zero.asManualSubviewInfo)
        }
        if !isIncoming, hasSendFailureBadge {
            let sendFailureBadgeSize = CGSize(square: self.sendFailureBadgeSize)
            hOuterStackSubviewInfos.append(sendFailureBadgeSize.asManualSubviewInfo(hasFixedWidth: true))
        }
        let hOuterStackMeasurement = ManualStackView.measure(config: hOuterStackConfig,
                                                             measurementBuilder: measurementBuilder,
                                                             measurementKey: Self.measurementKey_hOuterStack,
                                                             subviewInfos: hOuterStackSubviewInfos,
                                                             maxWidth: maxWidth)

        if let reactionsSubcomponent = subcomponent(forKey: .reactions) {
            let reactionsSize = reactionsSubcomponent.measure(maxWidth: maxWidth,
                                                              measurementBuilder: measurementBuilder)
            measurementBuilder.setSize(key: Self.measurementKey_reactions, size: reactionsSize)
        }

        return hOuterStackMeasurement.measuredSize
    }

    // The behavior of this method has to align exactly with that of configureContentStack().
    private func measureContentStack(maxWidth contentMaxWidth: CGFloat,
                                     measurementBuilder: CVCellMeasurement.Builder) -> CGSize {

        func measure(stackConfig: CVStackViewConfig,
                     measurementKey: String,
                     componentKeys keys: [CVComponentKey]) -> CGSize {
            let maxWidth = contentMaxWidth - stackConfig.layoutMargins.totalWidth
            var subviewSizes = [CGSize]()
            for key in keys {
                guard let subcomponent = self.subcomponent(forKey: key) else {
                    // Not all subcomponents may be present.
                    continue
                }
                let subviewSize = subcomponent.measure(maxWidth: maxWidth,
                                                       measurementBuilder: measurementBuilder)
                if subviewSize.width > maxWidth {
                    owsFailDebug("key: \(key), subviewSize: \(subviewSize) > maxWidth: \(maxWidth)")
                }
                subviewSizes.append(subviewSize)
            }

            var stackConfig = stackConfig
            func tryToOverlapBodyTextAndFooter() {
                guard keys == [ .bodyText, .footer ],
                      let bodyText = self.bodyText as? CVComponentBodyText,
                      let standaloneFooter = self.standaloneFooter,
                      !standaloneFooter.hasTapForMore else {
                    return
                }
                guard let footerMeasurement = CVComponentFooter.footerMeasurement(measurementBuilder: measurementBuilder),
                      let bodyTextMaxWidth = CVComponentBodyText.bodyTextMaxWidth(measurementBuilder: measurementBuilder),
                      let bodyTextMeasurement = CVComponentBodyText.bodyTextMeasurement(measurementBuilder: measurementBuilder),
                      let lastLineRect = bodyTextMeasurement.lastLineRect,
                      lastLineRect.width > 0,
                      lastLineRect.height > 0 else {
                    owsFailDebug("Missing measurement state.")
                    return
                }
                guard let bodyTextSubviewSize = subviewSizes.first,
                      bodyTextSubviewSize == bodyTextMeasurement.size else {
                    owsFailDebug("Invalid bodyTextSubviewSize.")
                    return
                }

                let textMessageFont = bodyText.textMessageFont
                let lineHeight = max(0, textMessageFont.lineHeight)
                let capHeight = max(0, textMessageFont.capHeight)
                // NOTE: descender is expressed as a negative value.
                let descender = max(0, -textMessageFont.descender)

                // TODO: Design is finalizing how this value should scale with dynamic type.
                let spacingScaling = max(1, lineHeight / 20)
                let kMinimumOverlapSpacingDefault: CGFloat = 6
                let minOverlapSpacing = kMinimumOverlapSpacingDefault * spacingScaling

                let isRTL = CurrentAppContext().isRTL
                let bodyTextSize = bodyTextSubviewSize.width
                let footerSize = footerMeasurement.measuredSize
                let overlappedLastLineWidth = ceil(lastLineRect.width) + minOverlapSpacing + footerSize.width
                let overlappedContentWidth = max(bodyTextSize, overlappedLastLineWidth)
                let hasSpaceForOverlap = overlappedContentWidth <= bodyTextMaxWidth
                guard hasSpaceForOverlap else {
                    return
                }

                // Do collision detection to determine if footer and last line would
                // collide if overlapped.
                let isFooterAlignedLeft = isRTL

                var isBodyTextAlignedLeft = false
                let bodyTextLabelConfig = bodyText.buildBodyTextLabelConfig()
                // For body text messages, textAlignment should reflect the natural
                // alignment of the content.
                switch bodyTextLabelConfig.textAlignment {
                case .left:
                    isBodyTextAlignedLeft = true
                case .right:
                    isBodyTextAlignedLeft = false
                default:
                    // This is expected for edge cases: oversize text messages, remotely deleted, etc.
                    Logger.verbose("Unknown text alignment: \(bodyTextLabelConfig.textAlignment).")
                    return
                }

                var detectionLastLineFrame = CGRect(origin: .zero, size: lastLineRect.size)
                if !isBodyTextAlignedLeft {
                    detectionLastLineFrame.x = overlappedContentWidth - lastLineRect.width
                }
                // Simplify y-axis for purposes of collision detection.
                detectionLastLineFrame.y = 0
                detectionLastLineFrame.height = 1

                var detectionFooterFrame = CGRect(origin: .zero, size: footerSize)
                if !isFooterAlignedLeft {
                    detectionFooterFrame.x = overlappedContentWidth - footerSize.width
                }
                // Inset one of the frames to account for the "min overlap spacing".
                detectionFooterFrame = detectionFooterFrame.insetBy(dx: -minOverlapSpacing, dy: 0)
                detectionFooterFrame.y = 0
                detectionFooterFrame.height = 1

                let doComponentsIntersect = detectionLastLineFrame.intersects(detectionFooterFrame)

                guard !doComponentsIntersect else {
                    return
                }

                let fontOuterSpacing = max(0, lineHeight - (capHeight + descender)) * 0.5
                let baselineSpacing = max(0, fontOuterSpacing + descender)
                // We want to v-align the center of the footer with the baseline of the
                // last line of body text.
                let overlapHeight = footerMeasurement.measuredSize.height * 0.5 + baselineSpacing
                let bottomNestedTextSpacing = -overlapHeight

                // 1. Rewrite the stack spacing for overlap.
                stackConfig = stackConfig.withSpacing(bottomNestedTextSpacing)

                // 2. Store the spacing for usage when rendering.
                measurementBuilder.setValue(key: Self.measurementKey_bottomNestedTextSpacing,
                                            value: bottomNestedTextSpacing)

                // 3. Rewrite the body text component size for overlap.
                subviewSizes[0] = CGSize(width: overlappedContentWidth,
                                         height: bodyTextSubviewSize.height)
            }
            tryToOverlapBodyTextAndFooter()

            let subviewInfos: [ManualStackSubviewInfo] = subviewSizes.map { subviewSize in
                subviewSize.asManualSubviewInfo
            }

            let stackMeasurement = ManualStackView.measure(config: stackConfig,
                                                           measurementBuilder: measurementBuilder,
                                                           measurementKey: measurementKey,
                                                           subviewInfos: subviewInfos)
            return stackMeasurement.measuredSize
        }

        let stickerOverlaySubcomponent = subcomponent(forKey: .sticker)

        if nil != stickerOverlaySubcomponent {
            // Sticker message.
            //
            // Stack is borderless.
            // Optional footer.
            return measure(stackConfig: buildBorderlessStackConfig(),
                           measurementKey: Self.measurementKey_contentStack,
                           componentKeys: [.senderName, .sticker, .footer])
        } else {
            // The non-sticker case.
            // Use multiple stacks.

            let contentSections = buildContentSections()

            var subviewSizes = [CGSize]()
            enumerate(contentSections: contentSections) { (contentSection: ContentSection, stackConfig: CVStackViewConfig) in
                guard let stackMeasurementKey = contentSection.stackMeasurementKey else {
                    owsFailDebug("Missing stackMeasurementKey.")
                    return
                }
                let componentKeys = contentSection.components.map { $0.componentKey }
                let stackSize = measure(stackConfig: stackConfig,
                                        measurementKey: stackMeasurementKey,
                                        componentKeys: componentKeys)
                subviewSizes.append(stackSize)
            }
            // Append the bottom buttons if necessary.
            if let bottomButtons = bottomButtons {
                let subviewSize = bottomButtons.measure(maxWidth: contentMaxWidth,
                                                        measurementBuilder: measurementBuilder)
                subviewSizes.append(subviewSize)
            }

            let subviewInfos: [ManualStackSubviewInfo] = subviewSizes.map { subviewSize in
                subviewSize.asManualSubviewInfo
            }
            return ManualStackView.measure(config: buildContentStackConfig(),
                                           measurementBuilder: measurementBuilder,
                                           measurementKey: Self.measurementKey_contentStack,
                                           subviewInfos: subviewInfos).measuredSize
        }
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return false
        }

        if isShowingSelectionUI {
            // By default, use primarySelectionView to handle .allContent...
            let primarySelectionView = componentView.primarySelectionView
            var selectionView = primarySelectionView
            var selectionType: CVSelectionType = .allContent

            // ...but we might have separate "primary" and "secondary" selections.
            // "Primary" is "everything but body text" and "secondary" is "just body text".
            if hasSecondaryContentForSelection {
                let secondarySelectionView = componentView.secondarySelectionView
                func distanceToViewCenter(_ view: UIView) -> CGFloat {
                    let tapLocation = sender.location(in: view)
                    let viewCenter = view.bounds.center
                    return tapLocation.distance(viewCenter)
                }
                let primaryDistance = distanceToViewCenter(primarySelectionView)
                let secondaryDistance = distanceToViewCenter(secondarySelectionView)
                if primaryDistance < secondaryDistance {
                    selectionView = primarySelectionView
                    selectionType = .primaryContent
                } else {
                    selectionView = secondarySelectionView
                    selectionType = .secondaryContent
                }
            }

            let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
            let selectionState = componentDelegate.selectionState
            if selectionState.isSelected(interaction.uniqueId, selectionType: selectionType) {
                selectionView.isSelected = false
                componentDelegate.selectionState.remove(itemViewModel: itemViewModel,
                                                        selectionType: selectionType)
            } else {
                selectionView.isSelected = true
                componentDelegate.selectionState.add(itemViewModel: itemViewModel,
                                                     selectionType: selectionType)
            }

            // Suppress other tap handling during selection mode.
            return true
        }

        if let outgoingMessage = interaction as? TSOutgoingMessage {
            switch outgoingMessage.messageState {
            case .failed:
                // Tap to retry.
                componentDelegate.didTapFailedOutgoingMessage(outgoingMessage)
                return true
            case .pending:
                componentDelegate.didTapPendingOutgoingMessage(outgoingMessage)
            default:
                break
            }
        }

        if hasSenderAvatar,
           componentView.avatarView.containsGestureLocation(sender) {
            componentDelegate.didTapSenderAvatar(interaction)
            return true
        }

        if let subcomponentAndView = findComponentAndView(sender: sender,
                                                          componentView: componentView) {
            let subcomponent = subcomponentAndView.component
            let subcomponentView = subcomponentAndView.componentView
            Logger.verbose("key: \(subcomponentAndView.key)")
            if subcomponent.handleTap(sender: sender,
                                      componentDelegate: componentDelegate,
                                      componentView: subcomponentView,
                                      renderItem: renderItem) {
                return true
            }
        }

        if let message = interaction as? TSMessage,
           nil != componentState.failedOrPendingDownloads {
            Logger.verbose("Retrying failed downloads.")
            componentDelegate.didTapFailedOrPendingDownloads(message)
            return true
        }

        return false
    }

    public override func findLongPressHandler(sender: UIGestureRecognizer,
                                              componentDelegate: CVComponentDelegate,
                                              componentView: CVComponentView,
                                              renderItem: CVRenderItem) -> CVLongPressHandler? {

        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }

        if let componentAndView = findActiveComponentAndView(key: .bodyText,
                                                             messageView: componentView,
                                                             ignoreMissing: true),
           let handler = componentAndView.component.findLongPressHandler(sender: sender,
                                                                         componentDelegate: componentDelegate,
                                                                         componentView: componentAndView.componentView,
                                                                         renderItem: renderItem) {
            return handler
        }

        let longPressKeys: [CVComponentKey: CVLongPressHandler.GestureLocation] = [
            .sticker: .sticker,
            .bodyMedia: .media,
            .audioAttachment: .media,
            .genericAttachment: .media,
            .quotedReply: .quotedReply
            // TODO: linkPreview?
        ]
        for (key, gestureLocation) in longPressKeys {
            if let subcomponentView = componentView.subcomponentView(key: key),
               subcomponentView.rootView.containsGestureLocation(sender) {
                return CVLongPressHandler(delegate: componentDelegate,
                                          renderItem: renderItem,
                                          gestureLocation: gestureLocation)
            }
        }

        return CVLongPressHandler(delegate: componentDelegate,
                                  renderItem: renderItem,
                                  gestureLocation: .`default`)
    }

    // For a configured & active cell, this will return the list of
    // currently active subcomponents & their corresponding subcomponent
    // views. This can be used for gesture dispatch, etc.
    private func findComponentAndView(sender: UIGestureRecognizer,
                                      componentView: CVComponentViewMessage) -> CVComponentAndView? {
        for subcomponentAndView in activeComponentAndViews(messageView: componentView) {
            let subcomponentView = subcomponentAndView.componentView
            let rootView = subcomponentView.rootView
            if rootView.containsGestureLocation(sender) {
                return subcomponentAndView
            }
        }
        return nil
    }

    // For a configured & active cell, this will return the list of
    // currently active subcomponents & their corresponding subcomponent
    // views. This can be used for gesture dispatch, etc.
    private func activeComponentAndViews(messageView: CVComponentViewMessage) -> [CVComponentAndView] {
        var result = [CVComponentAndView]()
        for key in CVComponentKey.allCases {
            guard let componentAndView = findActiveComponentAndView(key: key,
                                                                    messageView: messageView,
                                                                    ignoreMissing: true) else {
                continue
            }
            result.append(componentAndView)
        }
        return result
    }

    // For a configured & active cell, this will return a (component,
    // component view) tuple IFF that component is active.
    private func findActiveComponentAndView(key: CVComponentKey,
                                            messageView: CVComponentViewMessage,
                                            ignoreMissing: Bool = false) -> CVComponentAndView? {
        guard let subcomponent = self.subcomponent(forKey: key) else {
            // Not all subcomponents will be active.
            return nil
        }
        guard let subcomponentView = messageView.subcomponentView(key: key) else {
            if ignoreMissing {
                Logger.verbose("Missing subcomponentView: \(key).")
            } else {
                owsFailDebug("Missing subcomponentView.")
            }
            return nil
        }
        return CVComponentAndView(key: key, component: subcomponent, componentView: subcomponentView)
    }

    public func albumItemView(forAttachment attachment: TSAttachmentStream,
                              componentView: CVComponentView) -> UIView? {
        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }
        guard let componentAndView = findActiveComponentAndView(key: .bodyMedia,
                                                                messageView: componentView) else {
            owsFailDebug("Missing bodyMedia subcomponent.")
            return nil
        }
        guard let bodyMediaComponent = componentAndView.component as? CVComponentBodyMedia else {
            owsFailDebug("Unexpected subcomponent.")
            return nil
        }
        let bodyMediaComponentView = componentAndView.componentView
        return bodyMediaComponent.albumItemView(forAttachment: attachment,
                                                componentView: bodyMediaComponentView)
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewMessage: NSObject, CVComponentView {

        // Contains the cell contents which are arranged horizontally:
        //
        // * Gutters
        // * Message Selection UI
        // * hInnerStack
        // * "Send failure" badge
        fileprivate let hOuterStack = ManualStackView(name: "message.hOuterStack")

        // Contains the cell contents which are arranged horizontally:
        //
        // * Group sender avatar
        // * Content view wrapped in message bubble _or_ unwrapped content view.
        //
        // Additionally, it contains:
        //
        // * Reactions view, which uses a custom layout block.
        fileprivate let hInnerStack = ManualStackView(name: "message.hInnerStack")

        fileprivate let avatarView = ConversationAvatarView(
            sizeClass: ConversationStyle.groupMessageAvatarSizeClass,
            localUserDisplayMode: .asUser,
            useAutolayout: false)

        fileprivate let chatColorView = CVColorOrGradientView()

        // Contains the actual renderable message content, arranged vertically.
        fileprivate let contentStack = ManualStackView(name: "message.contentStack")

        // We use these stack views when there is a mixture of subcomponents,
        // some of which are full-width and some of which are not.
        fileprivate let topFullWidthStackView = ManualStackView(name: "message.topFullWidthStackView")
        fileprivate let topNestedStackView = ManualStackView(name: "message.topNestedStackView")
        fileprivate let bottomFullWidthStackView = ManualStackView(name: "message.bottomFullWidthStackView")
        fileprivate let bottomNestedShareStackView = ManualStackView(name: "message.bottomNestedShareStackView")
        fileprivate let bottomNestedTextStackView = ManualStackView(name: "message.bottomNestedTextStackView")

        // If hasSecondaryContentForSelection is false, this is used to select
        // all content.
        //
        // If hasSecondaryContentForSelection is true, this is used to select
        // everything except the body text, e.g. the body media or generic attachment.
        fileprivate lazy var primarySelectionView = MessageSelectionView()
        // If hasSecondaryContentForSelection is true, this is used to select
        // just the body text.
        fileprivate lazy var secondarySelectionView = MessageSelectionView()
        fileprivate let selectionWrapper = ManualLayoutView(name: "message.selectionWrapper")

        fileprivate let swipeToReplyIconView = CVImageView.circleView()

        fileprivate let cellSpacer = UIView()

        fileprivate let avatarViewSwipeToReplyWrapper = SwipeToReplyWrapper(name: "avatarViewSwipeToReplyWrapper",
                                                                            useSlowOffset: true,
                                                                            shouldReset: false)
        fileprivate let swipeToReplyIconSwipeToReplyWrapper = SwipeToReplyWrapper(name: "swipeToReplyIconSwipeToReplyWrapper",
                                                                                  useSlowOffset: true,
                                                                                  shouldReset: false)
        fileprivate var contentViewSwipeToReplyWrapper = SwipeToReplyWrapper(name: "contentViewSwipeToReplyWrapper",
                                                                             useSlowOffset: false,
                                                                             shouldReset: true)
        fileprivate var reactionsSwipeToReplyWrapper = SwipeToReplyWrapper(name: "reactionsSwipeToReplyWrapper",
                                                                           useSlowOffset: false,
                                                                           shouldReset: true)
        fileprivate var swipeToReplyWrappers: [SwipeToReplyWrapper] {
            [
                avatarViewSwipeToReplyWrapper,
                swipeToReplyIconSwipeToReplyWrapper,
                contentViewSwipeToReplyWrapper,
                reactionsSwipeToReplyWrapper
            ]
        }

        public var isDedicatedCellView = false

        public var rootView: UIView {
            hOuterStack
        }

        // MARK: - Subcomponents

        var senderNameView: CVComponentView?
        var bodyTextView: CVComponentView?
        var bodyMediaView: CVComponentView?
        var footerView: CVComponentView?
        var stickerView: CVComponentView?
        var viewOnceView: CVComponentView?
        var quotedReplyView: CVComponentView?
        var linkPreviewView: CVComponentView?
        var giftBadgeView: CVComponentView?
        var reactionsView: CVComponentView?
        var audioAttachmentView: CVComponentView?
        var genericAttachmentView: CVComponentView?
        var contactShareView: CVComponentView?
        var bottomButtonsView: CVComponentView?

        private var allSubcomponentViews: [CVComponentView] {
            [
                senderNameView,
                bodyTextView,
                bodyMediaView,
                footerView,
                stickerView,
                viewOnceView,
                quotedReplyView,
                linkPreviewView,
                giftBadgeView,
                reactionsView,
                audioAttachmentView,
                genericAttachmentView,
                contactShareView,
                bottomButtonsView
            ].compactMap { $0 }
        }

        fileprivate func subcomponentView(key: CVComponentKey) -> CVComponentView? {
            switch key {
            case .senderName:
                return senderNameView
            case .bodyText:
                return bodyTextView
            case .bodyMedia:
                return bodyMediaView
            case .footer:
                return footerView
            case .sticker:
                return stickerView
            case .viewOnce:
                return viewOnceView
            case .quotedReply:
                return quotedReplyView
            case .linkPreview:
                return linkPreviewView
            case .giftBadge:
                return giftBadgeView
            case .reactions:
                return reactionsView
            case .audioAttachment:
                return audioAttachmentView
            case .genericAttachment:
                return genericAttachmentView
            case .contactShare:
                return contactShareView
            case .bottomButtons:
                return bottomButtonsView

            // We don't render sender avatars with a subcomponent.
            case .senderAvatar:
                owsFailDebug("Invalid component key: \(key)")
                return nil
            case .systemMessage, .dateHeader, .unreadIndicator, .typingIndicator, .threadDetails, .failedOrPendingDownloads, .sendFailureBadge, .unknownThreadWarning, .defaultDisappearingMessageTimer, .messageRoot:
                owsFailDebug("Invalid component key: \(key)")
                return nil
            }
        }

        fileprivate func setSubcomponentView(key: CVComponentKey, subcomponentView: CVComponentView?) {
            switch key {
            case .senderName:
                senderNameView = subcomponentView
            case .bodyText:
                bodyTextView = subcomponentView
            case .bodyMedia:
                bodyMediaView = subcomponentView
            case .footer:
                footerView = subcomponentView
            case .sticker:
                stickerView = subcomponentView
            case .viewOnce:
                viewOnceView = subcomponentView
            case .quotedReply:
                quotedReplyView = subcomponentView
            case .linkPreview:
                linkPreviewView = subcomponentView
            case .giftBadge:
                giftBadgeView = subcomponentView
            case .reactions:
                reactionsView = subcomponentView
            case .audioAttachment:
                audioAttachmentView = subcomponentView
            case .genericAttachment:
                genericAttachmentView = subcomponentView
            case .contactShare:
                contactShareView = subcomponentView
            case .bottomButtons:
                bottomButtonsView = subcomponentView

            // We don't render sender avatars with a subcomponent.
            case .senderAvatar:
                owsAssertDebug(subcomponentView == nil)
            case .systemMessage, .dateHeader, .unreadIndicator, .typingIndicator, .threadDetails, .failedOrPendingDownloads, .sendFailureBadge, .unknownThreadWarning, .defaultDisappearingMessageTimer, .messageRoot:
                owsAssertDebug(subcomponentView == nil)
            }
        }

        // MARK: -

        override required init() {
            chatColorView.layoutMargins = .zero
            chatColorView.ensureSubviewsFillBounds = true

            avatarViewSwipeToReplyWrapper.subview = avatarView
            swipeToReplyIconSwipeToReplyWrapper.subview = swipeToReplyIconView
            // Configure contentViewSwipeToReplyWrapper and
            // reactionsSwipeToReplyWrapper later.
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {
            for subcomponentView in allSubcomponentViews {
                subcomponentView.setIsCellVisible(isCellVisible)
            }
            if isCellVisible {
                chatColorView.updateAppearance()
            }
        }

        public func setSwipeToReplyOffset(fastOffset: CGPoint,
                                          slowOffset: CGPoint) {
            for swipeToReplyWrapper in swipeToReplyWrappers {
                let offset = (swipeToReplyWrapper.useSlowOffset
                                ? slowOffset
                                : fastOffset)
                swipeToReplyWrapper.offset = offset
            }
        }

        public func reset() {
            removeSwipeActionAnimations()

            if !isDedicatedCellView {
                hOuterStack.reset()
                hInnerStack.reset()
                contentStack.reset()
                topFullWidthStackView.reset()
                topNestedStackView.reset()
                bottomFullWidthStackView.reset()
                bottomNestedShareStackView.reset()
                bottomNestedTextStackView.reset()

                for swipeToReplyWrapper in swipeToReplyWrappers {
                    if swipeToReplyWrapper.shouldReset {
                        swipeToReplyWrapper.reset()
                    } else {
                        swipeToReplyWrapper.offset = .zero
                    }
                }
            }

            selectionWrapper.reset()

            chatColorView.removeFromSuperview()
            chatColorView.reset()
            avatarView.reset()

            if !isDedicatedCellView {
                swipeToReplyIconView.image = nil
            }
            swipeToReplyIconView.alpha = 0

            // We use hInnerStack.frame to detect whether or not
            // the cell has been laid out yet. Therefore we clear it here.
            hInnerStack.frame = .zero

            if isDedicatedCellView {
                for subcomponentView in allSubcomponentViews {
                    subcomponentView.isDedicatedCellView = true
                }
            }

            for subcomponentView in allSubcomponentViews {
                subcomponentView.reset()
            }

            if !isDedicatedCellView {
                for key in CVComponentKey.allCases {
                    // Don't clear bodyTextView; it is expensive to build.
                    if key != .bodyText {
                        self.setSubcomponentView(key: key, subcomponentView: nil)
                    }
                }
            }
        }

        public func contextMenuContentView() -> UIView? {
            chatColorView.animationsEnabled = true
            return contentViewSwipeToReplyWrapper
        }

        public func contextMenuAuxiliaryContentView() -> UIView? {
            reactionsSwipeToReplyWrapper
        }

        public func contextMenuPresentationWillBegin() {
            avatarView.isHidden = true
        }

        public func contextMenuPresentationDidEnd() {
            avatarView.isHidden = false
            chatColorView.animationsEnabled = false
        }

        fileprivate func removeSwipeActionAnimations() {
            for swipeToReplyWrapper in swipeToReplyWrappers {
                swipeToReplyWrapper.layer.removeAllAnimations()
            }
        }
    }

    // MARK: - Swipe To Reply

    public override func findPanHandler(sender: UIPanGestureRecognizer,
                                        componentDelegate: CVComponentDelegate,
                                        componentView: CVComponentView,
                                        renderItem: CVRenderItem,
                                        messageSwipeActionState: CVMessageSwipeActionState) -> CVPanHandler? {
        AssertIsOnMainThread()

        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }

        if let audioAttachment = self.audioAttachment,
           let subcomponentView = componentView.subcomponentView(key: .audioAttachment),
           subcomponentView.rootView.containsGestureLocation(sender),
           let panHandler = audioAttachment.findPanHandler(sender: sender,
                                                           componentDelegate: componentDelegate,
                                                           componentView: subcomponentView,
                                                           renderItem: renderItem,
                                                           messageSwipeActionState: messageSwipeActionState) {
            return panHandler
        }

        return CVPanHandler(delegate: componentDelegate,
                            panType: .messageSwipeAction,
                            renderItem: renderItem)
    }

    public override func startPanGesture(sender: UIPanGestureRecognizer,
                                         panHandler: CVPanHandler,
                                         componentDelegate: CVComponentDelegate,
                                         componentView: CVComponentView,
                                         renderItem: CVRenderItem,
                                         messageSwipeActionState: CVMessageSwipeActionState) {
        AssertIsOnMainThread()

        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return
        }
        owsAssertDebug(sender.state == .began)

        switch panHandler.panType {
        case .scrubAudio:
            guard let audioAttachment = self.audioAttachment,
                  let subcomponentView = componentView.subcomponentView(key: .audioAttachment) else {
                owsFailDebug("Missing audio attachment component.")
                return
            }
            audioAttachment.startPanGesture(sender: sender,
                                            panHandler: panHandler,
                                            componentDelegate: componentDelegate,
                                            componentView: subcomponentView,
                                            renderItem: renderItem,
                                            messageSwipeActionState: messageSwipeActionState)
        case .messageSwipeAction:
            updateSwipeActionProgress(sender: sender,
                                      panHandler: panHandler,
                                      componentDelegate: componentDelegate,
                                      renderItem: renderItem,
                                      componentView: componentView,
                                      messageSwipeActionState: messageSwipeActionState,
                                      hasFinished: false)
            tryToApplySwipeAction(componentView: componentView, isAnimated: false)
        }
    }

    public override func handlePanGesture(sender: UIPanGestureRecognizer,
                                          panHandler: CVPanHandler,
                                          componentDelegate: CVComponentDelegate,
                                          componentView: CVComponentView,
                                          renderItem: CVRenderItem,
                                          messageSwipeActionState: CVMessageSwipeActionState) {
        AssertIsOnMainThread()

        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        switch panHandler.panType {
        case .scrubAudio:
            guard let audioAttachment = self.audioAttachment,
                  let subcomponentView = componentView.subcomponentView(key: .audioAttachment) else {
                owsFailDebug("Missing audio attachment component.")
                return
            }
            audioAttachment.handlePanGesture(sender: sender,
                                             panHandler: panHandler,
                                             componentDelegate: componentDelegate,
                                             componentView: subcomponentView,
                                             renderItem: renderItem,
                                             messageSwipeActionState: messageSwipeActionState)
        case .messageSwipeAction:
            let hasFinished: Bool
            switch sender.state {
            case .changed:
                hasFinished = false
            case .ended:
                hasFinished = true
            default:
                clearSwipeAction(componentView: componentView,
                                 renderItem: renderItem,
                                 messageSwipeActionState: messageSwipeActionState,
                                 isAnimated: false)
                return
            }
            updateSwipeActionProgress(sender: sender,
                                      panHandler: panHandler,
                                      componentDelegate: componentDelegate,
                                      renderItem: renderItem,
                                      componentView: componentView,
                                      messageSwipeActionState: messageSwipeActionState,
                                      hasFinished: hasFinished)
            let hasFailed = [.failed, .cancelled].contains(sender.state)
            let isAnimated = !hasFailed
            tryToApplySwipeAction(componentView: componentView, isAnimated: isAnimated)
            if sender.state == .ended {
                clearSwipeAction(componentView: componentView,
                                 renderItem: renderItem,
                                 messageSwipeActionState: messageSwipeActionState,
                                 isAnimated: true)
            }
        }
    }

    public override func cellDidLayoutSubviews(componentView: CVComponentView,
                                               renderItem: CVRenderItem,
                                               messageSwipeActionState: CVMessageSwipeActionState) {
        AssertIsOnMainThread()

        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return
        }
        tryToApplySwipeAction(componentView: componentView, isAnimated: false)
    }

    public override func cellDidBecomeVisible(componentView: CVComponentView,
                                              renderItem: CVRenderItem,
                                              messageSwipeActionState: CVMessageSwipeActionState) {
        AssertIsOnMainThread()

        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return
        }
        tryToApplySwipeAction(componentView: componentView, isAnimated: false)
    }

    public override func contextMenuAccessoryViews(componentView: CVComponentView) -> [ContextMenuTargetedPreviewAccessory]? {
        if hasSenderAvatar {
            guard let componentView = componentView as? CVComponentViewMessage else {
                owsFailDebug("Unexpected componentView.")
                return nil
            }

            let avatarView = ConversationAvatarView(sizeClass: componentView.avatarView.configuration.sizeClass, localUserDisplayMode: .asUser)
            avatarView.updateWithSneakyTransactionIfNecessary { newConfig in
                newConfig = componentView.avatarView.configuration
            }
            avatarView.frame = componentView.avatarView.bounds
            let isRTL = CurrentAppContext().isRTL
            let horizontalEdgeAlignment: ContextMenuTargetedPreviewAccessory.AccessoryAlignment.Edge = isRTL ? .trailing : .leading
            let alignment = ContextMenuTargetedPreviewAccessory.AccessoryAlignment(alignments: [(horizontalEdgeAlignment, .exterior), (.bottom, .interior)], alignmentOffset: CGPoint(x: (isRTL ? 8 : -8), y: 0))
            let avatarViewAccessory = ContextMenuTargetedPreviewAccessory(accessoryView: avatarView, accessoryAlignment: alignment)
            avatarViewAccessory.animateAccessoryPresentationAlongsidePreview = true
            return [avatarViewAccessory]
        } else {
            return nil
        }
    }

    private let swipeActionOffsetThreshold: CGFloat = 55

    private func updateSwipeActionProgress(
        sender: UIPanGestureRecognizer,
        panHandler: CVPanHandler,
        componentDelegate: CVComponentDelegate,
        renderItem: CVRenderItem,
        componentView: CVComponentViewMessage,
        messageSwipeActionState: CVMessageSwipeActionState,
        hasFinished: Bool
    ) {
        AssertIsOnMainThread()

        var xOffset = sender.translation(in: componentView.rootView).x
        var xVelocity = sender.velocity(in: componentView.rootView).x

        // Invert positions for RTL logic, since the user is swiping in the opposite direction.
        if CurrentAppContext().isRTL {
            xOffset = -xOffset
            xVelocity = -xVelocity
        }

        let hasFailed = [.failed, .cancelled].contains(sender.state)
        let storedOffset = (hasFailed || hasFinished) ? 0 : xOffset
        let progress = CVMessageSwipeActionState.Progress(xOffset: storedOffset)
        messageSwipeActionState.setProgress(
            interactionId: renderItem.interactionUniqueId,
            progress: progress
        )
        self.swipeActionProgress = progress

        let swipeToReplyIconView = componentView.swipeToReplyIconView
        let swipeToReplyIconWrapper = componentView.swipeToReplyIconSwipeToReplyWrapper

        let previousActiveDirection = panHandler.activeDirection
        let activeDirection: CVPanHandler.ActiveDirection
        switch xOffset {
        case let x where x >= swipeActionOffsetThreshold:
            // We're doing a message swipe action. We should
            // only become active if this message allows
            // swipe-to-reply.
            let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
            if componentDelegate.shouldAllowReplyForItem(itemViewModel) {
                activeDirection = .right
            } else {
                activeDirection = .none
            }
        case let x where x <= -swipeActionOffsetThreshold:
            activeDirection = .left
        default:
            activeDirection = .none
        }

        let didChangeActiveDirection = previousActiveDirection != activeDirection

        panHandler.activeDirection = activeDirection

        // Play a haptic when moving to active.
        if didChangeActiveDirection {
            switch activeDirection {
            case .right:
                ImpactHapticFeedback.impactOccured(style: .light)
                panHandler.percentDrivenTransition?.cancel()
                panHandler.percentDrivenTransition = nil
            case .left:
                ImpactHapticFeedback.impactOccured(style: .light)
                panHandler.percentDrivenTransition = UIPercentDrivenInteractiveTransition()
                componentDelegate.didTapShowMessageDetail(CVItemViewModelImpl(renderItem: renderItem))
            case .none:
                panHandler.percentDrivenTransition?.cancel()
                panHandler.percentDrivenTransition = nil
            }
        }

        // Update the reply image styling to reflect active state
        let isStarting = sender.state == .began
        if isStarting {
            // Prepare the message detail view as soon as we start doing
            // any gesture, we may or may not want to present it.
            componentDelegate.prepareMessageDetailForInteractivePresentation(CVItemViewModelImpl(renderItem: renderItem))
        }

        if isStarting || didChangeActiveDirection {
            let shouldAnimate = didChangeActiveDirection
            let transform: CGAffineTransform
            let tintColor: UIColor
            if activeDirection == .right {
                transform = CGAffineTransform(scaleX: 1.16, y: 1.16)
                tintColor = isDarkThemeEnabled ? .ows_gray25 : .ows_gray75
            } else {
                transform = .identity
                tintColor = .ows_gray45
            }
            swipeToReplyIconWrapper.layer.removeAllAnimations()
            swipeToReplyIconView.tintColor = tintColor
            if shouldAnimate {
                UIView.animate(
                    withDuration: 0.2,
                    delay: 0,
                    usingSpringWithDamping: 0.06,
                    initialSpringVelocity: 0.8,
                    options: [.curveEaseInOut, .beginFromCurrentState],
                    animations: {
                        swipeToReplyIconWrapper.transform = transform
                    },
                    completion: nil
                )
            } else {
                swipeToReplyIconWrapper.transform = transform
            }
        }

        if hasFinished {
            switch activeDirection {
            case .left:
                guard let percentDrivenTransition = panHandler.percentDrivenTransition else {
                    return owsFailDebug("Missing percentDrivenTransition")
                }
                // Only finish the pan if we're actively moving in
                // the correct direction.
                if xVelocity <= 0 {
                    percentDrivenTransition.finish()
                } else {
                    percentDrivenTransition.cancel()
                }
            case .right:
                let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
                componentDelegate.didTapReplyToItem(itemViewModel)
            case .none:
                break
            }
        } else if activeDirection == .left {
            guard let percentDrivenTransition = panHandler.percentDrivenTransition else {
                return owsFailDebug("Missing percentDrivenTransition")
            }
            let viewXOffset = sender.translation(in: componentDelegate.view).x
            let percentDriventTransitionProgress =
                (abs(viewXOffset) - swipeActionOffsetThreshold) / (componentDelegate.view.width - swipeActionOffsetThreshold)
            percentDrivenTransition.update(percentDriventTransitionProgress)
        }
    }

    private func tryToApplySwipeAction(
        componentView: CVComponentViewMessage,
        isAnimated: Bool
    ) {
        AssertIsOnMainThread()

        guard let swipeActionProgress = swipeActionProgress else {
            return
        }
        let swipeToReplyIconView = componentView.swipeToReplyIconView

        // Scale the translation above or below the desired range,
        // to produce an elastic feeling when you overscroll.
        var alpha = swipeActionProgress.xOffset

        let isSwipingLeft = alpha < 0

        if isSwipingLeft, alpha < -swipeActionOffsetThreshold {
            // If we're swiping left, stop moving the message
            // after we reach the threshold.
            alpha = -swipeActionOffsetThreshold
        } else if alpha > swipeActionOffsetThreshold {
            let overflow = alpha - swipeActionOffsetThreshold
            alpha = swipeActionOffsetThreshold + overflow / 4
        }
        let position = CurrentAppContext().isRTL ? -alpha : alpha

        let slowPosition: CGFloat
        if isSwipingLeft {
            slowPosition = position
        } else {
            // When swiping right (swipe-to-reply) the swipe content moves at
            // 1/8th the speed of the message bubble, so that it reveals itself
            // from underneath with an elastic feel.
            slowPosition = position / 8
        }

        var iconAlpha: CGFloat = 1
        let useSwipeFadeTransition = isBorderless
        if useSwipeFadeTransition {
            iconAlpha = CGFloatInverseLerp(alpha, 0, swipeActionOffsetThreshold).clamp01()
        }

        let animations = {
            swipeToReplyIconView.alpha = iconAlpha
            componentView.setSwipeToReplyOffset(fastOffset: CGPoint(x: position, y: 0),
                                                slowOffset: CGPoint(x: slowPosition, y: 0))
        }
        if isAnimated {
            UIView.animate(withDuration: 0.1,
                           delay: 0,
                           options: [.beginFromCurrentState],
                           animations: animations,
                           completion: nil)
        } else {
            componentView.removeSwipeActionAnimations()
            animations()
        }
    }

    private func clearSwipeAction(componentView: CVComponentViewMessage,
                                  renderItem: CVRenderItem,
                                  messageSwipeActionState: CVMessageSwipeActionState,
                                  isAnimated: Bool) {
        AssertIsOnMainThread()

        messageSwipeActionState.resetProgress(interactionId: renderItem.interactionUniqueId)

        let iconView = componentView.swipeToReplyIconView

        let animations = {
            componentView.setSwipeToReplyOffset(fastOffset: .zero, slowOffset: .zero)
            iconView.alpha = 0
        }

        if isAnimated {
            UIView.animate(withDuration: 0.2, animations: animations)
        } else {
            componentView.removeSwipeActionAnimations()
            animations()
        }

        self.swipeActionProgress = nil
    }
}

// MARK: -

fileprivate extension CVComponentMessage {

    func configureSubcomponentView(messageView: CVComponentViewMessage,
                                   subcomponent: CVComponent,
                                   cellMeasurement: CVCellMeasurement,
                                   componentDelegate: CVComponentDelegate,
                                   key: CVComponentKey) -> CVComponentView {
        if let subcomponentView = messageView.subcomponentView(key: key) {
            subcomponent.configureForRendering(componentView: subcomponentView,
                                               cellMeasurement: cellMeasurement,
                                               componentDelegate: componentDelegate)
            return subcomponentView
        } else {
            let subcomponentView = subcomponent.buildComponentView(componentDelegate: componentDelegate)
            messageView.setSubcomponentView(key: key, subcomponentView: subcomponentView)
            subcomponent.configureForRendering(componentView: subcomponentView,
                                               cellMeasurement: cellMeasurement,
                                               componentDelegate: componentDelegate)
            return subcomponentView
        }
    }

    func configureSubcomponent(messageView: CVComponentViewMessage,
                               cellMeasurement: CVCellMeasurement,
                               componentDelegate: CVComponentDelegate,
                               key: CVComponentKey) -> CVComponentAndView? {
        guard let subcomponent = self.subcomponent(forKey: key) else {
            return nil
        }
        let subcomponentView = configureSubcomponentView(messageView: messageView,
                                                         subcomponent: subcomponent,
                                                         cellMeasurement: cellMeasurement,
                                                         componentDelegate: componentDelegate,
                                                         key: key)
        return CVComponentAndView(key: key, component: subcomponent, componentView: subcomponentView)
    }

    private enum ContentStackMargin {
        case none
        case topMargin
        case bottomMargin
        case spacingDefault
        case spacingCustom(spacing: CGFloat)
    }

    private func buildNestedStackConfig(topMargin: ContentStackMargin,
                                        bottomMargin: ContentStackMargin) -> CVStackViewConfig {
        func marginValue(_ margin: ContentStackMargin) -> CGFloat {
            switch margin {
            case .none:
                return 0
            case .topMargin:
                return conversationStyle.textInsetTop
            case .bottomMargin:
                return conversationStyle.textInsetBottom
            case .spacingDefault:
                return Self.textViewVSpacing
            case .spacingCustom(let spacing):
                return spacing
            }
        }
        var layoutMargins = conversationStyle.textInsets
        layoutMargins.top = marginValue(topMargin)
        layoutMargins.bottom = marginValue(bottomMargin)
        return CVStackViewConfig(axis: .vertical,
                                 alignment: .fill,
                                 spacing: Self.textViewVSpacing,
                                 layoutMargins: layoutMargins)
    }

    func buildBorderlessStackConfig() -> CVStackViewConfig {
        buildNoMarginsStackConfig()
    }

    func buildFullWidthStackConfig(includeTopMargin: Bool, includeBottomMargin: Bool) -> CVStackViewConfig {
        var layoutMargins = UIEdgeInsets.zero
        if includeTopMargin {
            layoutMargins.top = conversationStyle.textInsets.top
        }
        if includeBottomMargin {
            layoutMargins.bottom = conversationStyle.textInsets.bottom
        }
        return CVStackViewConfig(axis: .vertical,
                                 alignment: .fill,
                                 spacing: Self.textViewVSpacing,
                                 layoutMargins: layoutMargins)
    }

    func buildNoMarginsStackConfig() -> CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .fill,
                          spacing: Self.textViewVSpacing,
                          layoutMargins: .zero)
    }

    func buildContentStackConfig() -> CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .fill,
                          spacing: 0,
                          layoutMargins: .zero)
    }

    func configureSubcomponentStack(messageView: CVComponentViewMessage,
                                    stackView: ManualStackView,
                                    stackConfig: CVStackViewConfig,
                                    cellMeasurement: CVCellMeasurement,
                                    measurementKey: String,
                                    componentDelegate: CVComponentDelegate,
                                    keys: [CVComponentKey]) {

        let subviews: [UIView] = keys.compactMap { key in
            // TODO: configureSubcomponent should probably just return the componentView.
            guard let componentAndView = configureSubcomponent(messageView: messageView,
                                                               cellMeasurement: cellMeasurement,
                                                               componentDelegate: componentDelegate,
                                                               key: key) else {
                return nil
            }
            return componentAndView.componentView.rootView
        }

        stackView.reset()
        stackView.configure(config: stackConfig,
                            cellMeasurement: cellMeasurement,
                            measurementKey: measurementKey,
                            subviews: subviews)
    }

    func subcomponents(forKeys keys: [CVComponentKey]) -> [CVComponent] {
        keys.compactMap { key in
            guard let subcomponent = self.subcomponent(forKey: key) else {
                // Not all subcomponents may be present.
                return nil
            }
            return subcomponent
        }
    }

    func buildSubcomponentMap(keys: [CVComponentKey]) -> [CVComponentKey: CVComponent] {
        var result = [CVComponentKey: CVComponent]()
        for key in keys {
            guard let subcomponent = self.subcomponent(forKey: key) else {
                // Not all subcomponents may be present.
                continue
            }
            result[key] = subcomponent
        }
        return result
    }
}

// MARK: -

class SwipeToReplyWrapper: ManualLayoutView {

    var offset: CGPoint = .zero {
        didSet {
            layoutSubviews()
        }
    }

    var subview: UIView? {
        didSet {
            // This view should only be configured after being reset.
            owsAssertDebug((subview == nil) || (oldValue == nil))

            oldValue?.removeFromSuperview()

            if let subview = subview {
                owsAssertDebug(subview.superview == nil)
                addSubview(subview)

                layoutSubviews()
            }
        }
    }

    let useSlowOffset: Bool
    let shouldReset: Bool

    public required init(name: String,
                         useSlowOffset: Bool,
                         shouldReset: Bool) {
        self.useSlowOffset = useSlowOffset
        self.shouldReset = shouldReset

        super.init(name: name)

        addDefaultLayoutBlock()
    }

    private func addDefaultLayoutBlock() {
        addLayoutBlock { view in
            guard let view = view as? SwipeToReplyWrapper else {
                owsFailDebug("Invalid reference view.")
                return
            }
            guard let subview = view.subview else {
                return
            }
            var subviewFrame = view.bounds
            subviewFrame.origin += view.offset
            ManualLayoutView.setSubviewFrame(subview: subview, frame: subviewFrame)
        }
    }

    @available(*, unavailable, message: "use other constructor instead.")
    public required init(name: String) {
        fatalError("init(name:) has not been implemented")
    }

    override func reset() {
        super.reset()

        subview = nil
        offset = .zero
        addDefaultLayoutBlock()
    }
}
