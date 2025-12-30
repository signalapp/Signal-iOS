//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class CVComponentUndownloadableAttachment: CVComponentBase, CVComponent {
    var componentKey: CVComponentKey { .undownloadableAttachment }

    private var icon: UIImage {
        switch attachmentType {
        case .audio:
            UIImage(named: "audio-square-slash")!
        case .sticker:
            UIImage(named: "sticker-slash")!
        }
    }

    private var message: String {
        switch attachmentType {
        case .audio:
            OWSLocalizedString(
                "AUDIO_UNAVAILABLE_MESSAGE_LABEL",
                value: "Voice message not available",
                comment: "Message when trying to show a voice message that has expired and is unavailable for download",
            )
        case .sticker:
            OWSLocalizedString(
                "STICKER_UNAVAILABLE_MESSAGE_LABEL",
                value: "Sticker not available",
                comment: "Message when trying to show a sticker that has expired and is unavailable for download",
            )
        }
    }

    private let attachmentType: CVComponentState.UndownloadableAttachment
    private let footerOverlay: CVComponent?

    init(
        itemModel: CVItemModel,
        attachmentType: CVComponentState.UndownloadableAttachment,
        footerOverlay: CVComponent?,
    ) {
        self.attachmentType = attachmentType
        self.footerOverlay = footerOverlay
        super.init(itemModel: itemModel)
    }

    private static let measurementKey_stackView = "CVComponentUndownloadableAttachment.measurementKey_stackView"
    private static let measurementKey_footerSize = "CVComponentUndownloadableAttachment.measurementKey_footerSize"

    func buildComponentView(componentDelegate: any CVComponentDelegate) -> any CVComponentView {
        CVComponentViewUndownloadableAttachment()
    }

    func configureForRendering(
        componentView: any CVComponentView,
        cellMeasurement: SignalUI.CVCellMeasurement,
        componentDelegate: any CVComponentDelegate,
    ) {
        guard let componentView = componentView as? CVComponentViewUndownloadableAttachment else {
            owsFailDebug("Unexpected componentView.")
            componentView.reset()
            return
        }

        let stackView = componentView.stackView
        let conversationStyle = self.conversationStyle

        if let footerOverlay = self.footerOverlay {
            let footerView: CVComponentView
            if let footerOverlayView = componentView.footerOverlayView {
                footerView = footerOverlayView
            } else {
                let footerOverlayView = CVComponentFooter.CVComponentViewFooter()
                componentView.footerOverlayView = footerOverlayView
                footerView = footerOverlayView
            }
            footerOverlay.configureForRendering(
                componentView: footerView,
                cellMeasurement: cellMeasurement,
                componentDelegate: componentDelegate,
            )
            let footerRootView = footerView.rootView

            let footerSize = cellMeasurement.size(key: Self.measurementKey_footerSize) ?? .zero
            stackView.addSubview(footerRootView) { view in
                var footerFrame = view.bounds
                footerFrame.height = min(view.bounds.height, footerSize.height)
                footerFrame.y = view.bounds.height - footerSize.height
                footerRootView.frame = footerFrame
            }
        }

        let label = CVTextLabel()
        label.configureForRendering(
            config: self.labelConfig(
                conversationStyle: conversationStyle,
                isIncoming: itemModel.interaction is TSIncomingMessage,
            ),
            spoilerAnimationManager: .init(),
        )

        stackView.configure(
            config: self.stackViewConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_stackView,
            subviews: [label.view],
        )
    }

    func measure(maxWidth: CGFloat, measurementBuilder: SignalUI.CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let config = self.labelConfig(
            conversationStyle: conversationStyle,
            isIncoming: false, // Used for color. Doesn't matter for measurement
        )

        let footerSize: CGSize
        if let footerOverlay {
            let maxFooterWidth = max(0, maxWidth - conversationStyle.textInsets.totalWidth)
            footerSize = footerOverlay.measure(
                maxWidth: maxFooterWidth,
                measurementBuilder: measurementBuilder,
            )
            measurementBuilder.setSize(key: Self.measurementKey_footerSize, size: footerSize)
        } else {
            footerSize = .zero
        }

        let info = CVText.measureBodyTextLabelInManualStackView(
            config: config,
            footerSize: footerSize,
            maxWidth: maxWidth,
            measurementBuilder: measurementBuilder,
        )

        let stackMeasurement = ManualStackView.measure(
            config: stackViewConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_stackView,
            subviewInfos: info,
            maxWidth: maxWidth,
        )

        return stackMeasurement.measuredSize
    }

    var stackViewConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .leading,
            spacing: 0,
            layoutMargins: .zero,
        )
    }

    private func labelConfig(
        conversationStyle: ConversationStyle,
        isIncoming: Bool,
    ) -> CVTextLabel.Config {
        let font = UIFont.dynamicTypeBodyClamped
        let textColor = conversationStyle.bubbleTextColor(isIncoming: isIncoming)

        return CVTextLabel.Config(
            text: .attributedText(
                .composed(of: [
                    NSAttributedString.with(
                        image: self.icon,
                        font: .dynamicTypeSubheadlineClamped,
                        centerVerticallyRelativeTo: font,
                    ),
                    " ",
                    self.message,
                    SignalSymbol.LeadingCharacter.nonBreakingSpace.rawValue,
                    SignalSymbol.chevronTrailing.attributedString(
                        dynamicTypeBaseSize: 16,
                        clamped: true,
                        weight: .bold,
                        leadingCharacter: .nonBreakingSpace,
                        attributes: [.foregroundColor: UIColor.Signal.secondaryLabel],
                    ),
                ]).styled(with: .font(font), .color(textColor)),
            ),
            displayConfig: .forUnstyledText(font: font, textColor: textColor),
            font: font,
            textColor: textColor,
            selectionStyling: [:],
            textAlignment: .natural,
            lineBreakMode: .byWordWrapping,
            items: [],
            linkifyStyle: .linkAttribute,
        )
    }

    override func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: any CVComponentDelegate,
        componentView: any CVComponentView,
        renderItem: CVRenderItem,
    ) -> Bool {
        switch self.attachmentType {
        case .audio:
            componentDelegate.didTapUndownloadableAudio()
        case .sticker:
            componentDelegate.didTapUndownloadableSticker()
        }
        return true
    }

    class CVComponentViewUndownloadableAttachment: NSObject, CVComponentView {
        fileprivate let stackView = ManualStackView(name: "CVComponentViewAudioAttachment.stackView")
        fileprivate var footerOverlayView: CVComponentView?

        var isDedicatedCellView: Bool = false

        var rootView: UIView {
            stackView
        }

        func setIsCellVisible(_ isCellVisible: Bool) {}

        func reset() {
            stackView.reset()
            footerOverlayView?.reset()
            footerOverlayView = nil
        }
    }
}
