//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalServiceKit

public class TextAttachmentView: UIView {
    private(set) weak var linkPreviewView: UIView?
    private let textAttachment: TextAttachment

    public init(attachment: TextAttachment) {
        self.textAttachment = attachment

        super.init(frame: .zero)

        switch attachment.background {
        case .color(let color):
            backgroundColor = color
        case .gradient(let gradient):
            addGradientBackground(gradient)
        }

        let contentStackView = UIStackView()
        contentStackView.axis = .vertical
        contentStackView.alignment = .center
        contentStackView.spacing = 16
        addSubview(contentStackView)
        contentStackView.autoPinEdgesToSuperviewEdges()

        if let text = attachment.text {
            let label = UILabel()
            label.numberOfLines = 0
            label.textColor = attachment.textForegroundColor ?? Theme.darkThemePrimaryColor
            label.text = transformedText(text, for: attachment.textStyle)
            label.textAlignment = .center
            label.font = font(for: attachment.textStyle)
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.2

            if let textBackgroundColor = attachment.textBackgroundColor {
                let labelBackgroundView = UIView()
                labelBackgroundView.layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 16)
                labelBackgroundView.backgroundColor = textBackgroundColor
                labelBackgroundView.layer.cornerRadius = 18

                labelBackgroundView.addSubview(label)
                label.autoPinEdgesToSuperviewMargins()

                let labelWrapper = UIView()
                labelWrapper.addSubview(labelBackgroundView)
                labelBackgroundView.autoPinWidthToSuperview(withMargin: 24)
                labelBackgroundView.autoPinHeightToSuperview()
                contentStackView.addArrangedSubview(labelWrapper)
            } else {
                let labelWrapper = UIView()
                labelWrapper.addSubview(label)
                label.autoPinWidthToSuperview(withMargin: 40)
                label.autoPinHeightToSuperview()
                contentStackView.addArrangedSubview(labelWrapper)
            }
        }

        if let linkPreview = attachment.preview {
            var attachment: TSAttachment?
            if let imageAttachmentId = linkPreview.imageAttachmentId {
                attachment = databaseStorage.read(block: { TSAttachment.anyFetch(uniqueId: imageAttachmentId, transaction: $0) })
            }
            let linkPreviewView = LinkPreviewView(linkPreview: LinkPreviewSent(linkPreview: linkPreview,
                                                                               imageAttachment: attachment,
                                                                               conversationStyle: nil))
            let previewWrapper = UIView()
            previewWrapper.addSubview(linkPreviewView)
            linkPreviewView.autoPinWidthToSuperview(withMargin: 36)
            linkPreviewView.autoPinHeightToSuperview()
            contentStackView.addArrangedSubview(previewWrapper)
            self.linkPreviewView = linkPreviewView
        }

        // Keep content vertically centered, but limit to screen size.
        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()
        contentStackView.insertArrangedSubview(topSpacer, at: 0)
        contentStackView.addArrangedSubview(bottomSpacer)
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)
    }

    public func asThumbnailView() -> TextAttachmentThumbnailView { TextAttachmentThumbnailView(self) }

    public var isPresentingLinkTooltip: Bool { linkPreviewTooltipView != nil }

    private var linkPreviewTooltipView: LinkPreviewTooltipView?
    public func willHandleTapGesture(_ gesture: UITapGestureRecognizer) -> Bool {
        if let linkPreviewTooltipView = linkPreviewTooltipView {
            if let container = linkPreviewTooltipView.superview,
               linkPreviewTooltipView.frame.contains(gesture.location(in: container)) {
                CurrentAppContext().open(linkPreviewTooltipView.url)
            } else {
                linkPreviewTooltipView.removeFromSuperview()
                self.linkPreviewTooltipView = nil
            }

            return true
        } else if let linkPreviewView = linkPreviewView,
                  let urlString = textAttachment.preview?.urlString,
                  let container = linkPreviewView.superview,
                  linkPreviewView.frame.contains(gesture.location(in: container)) {
            let tooltipView = LinkPreviewTooltipView(
                fromView: self,
                tailReferenceView: linkPreviewView,
                url: URL(string: urlString)!
            )
            self.linkPreviewTooltipView = tooltipView

            return true
        }

        return false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func transformedText(_ text: String, for textStyle: TextAttachment.TextStyle) -> String {
        guard case .condensed = textStyle else { return text }
        return text.uppercased()
    }

    private func font(for textStyle: TextAttachment.TextStyle) -> UIFont {
        let attributes: [UIFontDescriptor.AttributeName: Any]

        switch textStyle {
        case .regular:
            attributes = [.name: "Inter-Regular_Bold"]
        case .bold:
            attributes = [.name: "Inter-Regular_Black"]
        case .serif:
            attributes = [.name: "EBGaramond-Regular"]
        case .script:
            attributes = [.name: "Parisienne-Regular"]
        case .condensed:
            // TODO: Ideally we could set an attribute to make this font
            // all caps, but iOS deprecated that ability and didn't add
            // a new equivalent function.
            attributes = [.name: "BarlowCondensed-Medium"]
        }

        // TODO: Eventually we'll want to provide a cascadeList here to fallback
        // to different fonts for different scripts rather than just relying on
        // the built in OS fallbacks that don't tend to match the desired style.
        let descriptor = UIFontDescriptor(fontAttributes: attributes)

        return UIFont(descriptor: descriptor, size: 28)
    }

    private func addGradientBackground(_ gradient: TextAttachment.Background.Gradient) {
        let gradientView = GradientView(colors: gradient.colors, locations: gradient.locations)
        gradientView.setAngle(gradient.angle)

        addSubview(gradientView)
        gradientView.autoPinEdgesToSuperviewEdges()
    }

    public class LinkPreviewView: UIStackView {

        public init(linkPreview: LinkPreviewState) {
            super.init(frame: .zero)

            axis = .horizontal
            alignment = .center
            spacing = 8
            isLayoutMarginsRelativeArrangement = true
            layoutMargins = UIEdgeInsets(hMargin: 12, vMargin: 12)
            addBackgroundView(withBackgroundColor: .ows_blackAlpha40, cornerRadius: 12)

            if linkPreview.imageState() == .loaded {
                let thumbnailImageView = UIImageView()
                thumbnailImageView.layer.cornerRadius = 8
                thumbnailImageView.clipsToBounds = true
                thumbnailImageView.contentMode = .scaleAspectFill
                thumbnailImageView.autoSetDimensions(to: CGSize(square: 76))
                addArrangedSubview(thumbnailImageView)

                linkPreview.imageAsync(thumbnailQuality: .small) { image in
                    thumbnailImageView.image = image
                }
            }

            let previewVStack = UIStackView()
            previewVStack.axis = .vertical
            previewVStack.alignment = .leading
            addArrangedSubview(previewVStack)

            if let title = linkPreview.title() {
                let titleLabel = UILabel()
                titleLabel.text = title
                titleLabel.font = .boldSystemFont(ofSize: 16)
                titleLabel.textColor = Theme.darkThemePrimaryColor
                titleLabel.numberOfLines = 2
                titleLabel.setCompressionResistanceVerticalHigh()
                titleLabel.setContentHuggingVerticalHigh()
                previewVStack.addArrangedSubview(titleLabel)
            }

            if let description = linkPreview.previewDescription() {
                let descriptionLabel = UILabel()
                descriptionLabel.text = description
                descriptionLabel.font = .systemFont(ofSize: 12)
                descriptionLabel.textColor = Theme.darkThemePrimaryColor
                descriptionLabel.numberOfLines = 3
                descriptionLabel.setCompressionResistanceVerticalHigh()
                descriptionLabel.setContentHuggingVerticalHigh()
                previewVStack.addArrangedSubview(descriptionLabel)
            }

            let footerLabel = UILabel()
            footerLabel.font = .systemFont(ofSize: 12)
            footerLabel.numberOfLines = 2
            footerLabel.textColor = Theme.darkThemeSecondaryTextAndIconColor
            footerLabel.setCompressionResistanceVerticalHigh()
            footerLabel.setContentHuggingVerticalHigh()
            previewVStack.addArrangedSubview(footerLabel)

            var footerText: String
            if let displayDomain = OWSLinkPreviewManager.displayDomain(forUrl: linkPreview.urlString()) {
                footerText = displayDomain.lowercased()
            } else {
                footerText = NSLocalizedString(
                    "LINK_PREVIEW_UNKNOWN_DOMAIN",
                    comment: "Label for link previews with an unknown host."
                ).uppercased()
            }
            if let date = linkPreview.date() {
                footerText.append(" ⋅ \(Self.dateFormatter.string(from: date))")
            }
            footerLabel.text = footerText
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter
        }()
    }
}

private class LinkPreviewTooltipView: TooltipView {
    let url: URL
    init(fromView: UIView, tailReferenceView: UIView, url: URL) {
        self.url = url
        super.init(
            fromView: fromView,
            widthReferenceView: fromView,
            tailReferenceView: tailReferenceView,
            wasTappedBlock: nil
        )
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func bubbleContentView() -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString(
            "STORY_LINK_PREVIEW_VISIT_LINK_TOOLTIP",
            comment: "Tooltip prompting the user to visit a story link."
        )
        titleLabel.font = UIFont.ows_dynamicTypeBody2Clamped.ows_semibold
        titleLabel.textColor = .ows_white

        let urlLabel = UILabel()
        urlLabel.text = url.absoluteString
        urlLabel.font = .ows_dynamicTypeCaption1Clamped
        urlLabel.textColor = .ows_white

        let stackView = UIStackView(arrangedSubviews: [titleLabel, urlLabel])
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 1
        stackView.layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 14)
        stackView.isLayoutMarginsRelativeArrangement = true

        return stackView
    }

    public override var bubbleColor: UIColor { .ows_black }
    public override var bubbleHSpacing: CGFloat { 16 }

    public override var tailDirection: TooltipView.TailDirection { .down }
    public override var dismissOnTap: Bool { false }
}

public class TextAttachmentThumbnailView: UIView {
    // By default, we render the textView at a large 3:2 size (matching the aspect
    //  of the thumbnail container), so the fonts and gradients all render properly
    // for the preview. We then scale it down to render a "thumbnail" view.
    public static let defaultRenderSize = CGSize(width: 375, height: 563)

    public lazy var renderSize = Self.defaultRenderSize {
        didSet {
            textAttachmentView.transform = .scale(width / renderSize.width)
        }
    }

    private let textAttachmentView: TextAttachmentView
    public init(_ textAttachmentView: TextAttachmentView) {
        self.textAttachmentView = textAttachmentView
        super.init(frame: .zero)
        addSubview(textAttachmentView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        textAttachmentView.transform = .scale(width / renderSize.width)
        textAttachmentView.frame = bounds
    }
}
