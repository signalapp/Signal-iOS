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

        private enum Layout {
            case regular
            case compact
            case draft
            case domainOnly
        }

        public init(linkPreview: LinkPreviewState, isDraft: Bool = false) {
            super.init(frame: .zero)

            let backgroundColor: UIColor = isDraft ? Theme.darkThemeTableView2PresentedBackgroundColor : .ows_gray02
            let backgroundView = addBackgroundView(withBackgroundColor: backgroundColor)

            let title = linkPreview.title()
            let description = linkPreview.previewDescription()
            let hasTitleOrDescription = title != nil || description != nil
            var layout: Layout = isDraft ? .draft : (hasTitleOrDescription ? .regular : .domainOnly)

            let thumbnailImageView = UIImageView()
            thumbnailImageView.clipsToBounds = true
            if layout != .domainOnly && linkPreview.imageState() == .loaded {
                thumbnailImageView.contentMode = .scaleAspectFill

                // Downgrade "regular" to "compact" if thumbnail is too small.
                let imageSize = linkPreview.imagePixelSize
                if layout == .regular && (imageSize.width < 300 || imageSize.height < 300) {
                    layout = .compact
                }
                linkPreview.imageAsync(thumbnailQuality: layout == .regular ? .mediumLarge : .small) { image in
                    thumbnailImageView.image = image
                }
            } else {
                // Dark placeholder icon on light background if there's no thumbnail associated with the link preview.
                thumbnailImageView.backgroundColor = .ows_gray02
                thumbnailImageView.contentMode = .center
                thumbnailImageView.image = UIImage(imageLiteralResourceName: "link-diagonal")
                thumbnailImageView.tintColor = Theme.lightThemePrimaryColor
            }

            switch layout {
            case .regular:
                // Display image above the text with the fixed height and all available width.
                axis = .vertical
                alignment = .fill

            default:
                // Display image and text side by side.
                axis = .horizontal
                alignment = .center
            }

            switch layout {
            case .regular:
                backgroundView.layer.cornerRadius = 18
                thumbnailImageView.autoSetDimension(.height, toSize: 152)
                thumbnailImageView.layer.maskedCorners = [ .layerMinXMinYCorner, .layerMaxXMinYCorner ]

            case .compact:
                backgroundView.layer.cornerRadius = 18
                thumbnailImageView.autoSetDimensions(to: CGSize(square: 88))
                thumbnailImageView.layer.maskedCorners = [ .layerMinXMinYCorner, .layerMinXMaxYCorner ]

            case .draft:
                backgroundView.layer.cornerRadius = 8
                thumbnailImageView.autoSetDimensions(to: CGSize(square: 76))
                thumbnailImageView.layer.maskedCorners = .all

            case .domainOnly:
                backgroundView.layer.cornerRadius = 12
                thumbnailImageView.autoSetDimensions(to: CGSize(width: 50, height: 50))
            }
            thumbnailImageView.layer.cornerRadius = backgroundView.layer.cornerRadius
            addArrangedSubview(thumbnailImageView)

            let previewVStack = UIStackView()
            previewVStack.axis = .vertical
            previewVStack.spacing = 2
            previewVStack.alignment = .leading
            previewVStack.isLayoutMarginsRelativeArrangement = true
            previewVStack.layoutMargins = UIEdgeInsets(hMargin: 12, vMargin: 8)
            // Make placeholder icon look centered between leading edge of the panel and text.
            if layout == .domainOnly {
                previewVStack.layoutMargins.leading = 0
            }
           addArrangedSubview(previewVStack)

            if let title = title {
                let titleLabel = UILabel()
                titleLabel.text = title
                titleLabel.font = .ows_dynamicTypeSubheadlineClamped.ows_semibold
                titleLabel.textColor = isDraft ? Theme.darkThemePrimaryColor : Theme.lightThemePrimaryColor
                titleLabel.numberOfLines = 2
                titleLabel.setCompressionResistanceVerticalHigh()
                titleLabel.setContentHuggingVerticalHigh()
                previewVStack.addArrangedSubview(titleLabel)
            }

            if let description = description {
                let descriptionLabel = UILabel()
                descriptionLabel.text = description
                descriptionLabel.font = .ows_dynamicTypeFootnoteClamped
                descriptionLabel.textColor = isDraft ? Theme.darkThemePrimaryColor : Theme.lightThemePrimaryColor
                descriptionLabel.numberOfLines = 2
                descriptionLabel.setCompressionResistanceVerticalHigh()
                descriptionLabel.setContentHuggingVerticalHigh()
                previewVStack.addArrangedSubview(descriptionLabel)
            }

            let footerLabel = UILabel()
            footerLabel.numberOfLines = 1
            if hasTitleOrDescription {
                footerLabel.font = .ows_dynamicTypeCaption1Clamped
                footerLabel.textColor = isDraft ? Theme.darkThemeSecondaryTextAndIconColor : .ows_gray60
            } else {
                footerLabel.font = .ows_dynamicTypeSubheadlineClamped.ows_semibold
                footerLabel.textColor = isDraft ? Theme.darkThemePrimaryColor : Theme.lightThemePrimaryColor
            }
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
