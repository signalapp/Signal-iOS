//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import SignalServiceKit

open class TextAttachmentView: UIView {

    private var linkPreviewUrlString: String? {
        return linkPreview?.urlString()
    }

    public let contentLayoutGuide = UILayoutGuide()

    convenience public init(attachment: TextAttachment) {
        self.init(
            text: attachment.text,
            textStyle: attachment.textStyle,
            textForegroundColor: attachment.textForegroundColor,
            textBackgroundColor: attachment.textBackgroundColor,
            background: attachment.background,
            linkPreview: attachment.preview
        )
    }

    convenience public init(attachment: UnsentTextAttachment) {
        self.init(
            text: attachment.text,
            textStyle: attachment.textStyle,
            textForegroundColor: attachment.textForegroundColor,
            textBackgroundColor: attachment.textBackgroundColor,
            background: attachment.background,
            linkPreview: nil,
            linkPreviewDraft: attachment.linkPreviewDraft
        )
    }

    public init(
        text: String?,
        textStyle: TextAttachment.TextStyle,
        textForegroundColor: UIColor?,
        textBackgroundColor: UIColor?,
        background: TextAttachment.Background,
        linkPreview: OWSLinkPreview?,
        linkPreviewDraft: OWSLinkPreviewDraft? = nil
    ) {
        self.text = text
        self.textStyle = textStyle
        self.textForegroundColor = textForegroundColor ?? Theme.darkThemePrimaryColor
        self.textBackgroundColor = textBackgroundColor
        self.background = background

        super.init(frame: .zero)

        clipsToBounds = true

        addLayoutGuide(contentLayoutGuide)
        let constraints = [
            contentLayoutGuide.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            contentLayoutGuide.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            contentLayoutGuide.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            contentLayoutGuide.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)
        ]
        constraints.forEach { $0.priority = .defaultHigh }
        addConstraints(constraints)

        if let linkPreview = linkPreview {
            var attachment: TSAttachment?
            if let imageAttachmentId = linkPreview.imageAttachmentId {
                attachment = databaseStorage.read(block: { TSAttachment.anyFetch(uniqueId: imageAttachmentId, transaction: $0) })
            }
            self.linkPreview = LinkPreviewSent(
                linkPreview: linkPreview,
                imageAttachment: attachment,
                conversationStyle: nil
            )
        } else if let linkPreviewDraft = linkPreviewDraft {
            self.linkPreview = LinkPreviewDraft(linkPreviewDraft: linkPreviewDraft)
        }

        updateTextAttributes()
        reloadLinkPreviewAppearance()
        updateBackground()
    }

    public func asThumbnailView() -> TextAttachmentThumbnailView { TextAttachmentThumbnailView(self) }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public enum LayoutConstants {
        public static let textBackgroundHMargin: CGFloat = 16
        public static let textBackgroundVMargin: CGFloat = 16
        public static let textBackgroundCornerRadius: CGFloat = 18
        public static let linkPreviewAreaTopMargin: CGFloat = 8
        public static let linkPreviewHMargin: CGFloat = 12
        public static let linkPreviewVMargin: CGFloat = 20
    }

    private var expandedLinkPreviewAreaHeight: CGFloat?

    open var isEditing: Bool { false }

    public private(set) var textContentSize: CGSize = .zero

    open override func layoutSubviews() {
        super.layoutSubviews()

        // Resize link preview view to its desired size.
        if let linkPreviewView = linkPreviewView {
            let linkPreviewMaxSize = contentLayoutGuide.layoutFrame.inset(by: linkPreviewWrapperView.layoutMargins).size
            let linkPreviewSize = linkPreviewView.systemLayoutSizeFitting(
                linkPreviewMaxSize,
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )

            linkPreviewWrapperView.bounds.size = CGSize(
                width: linkPreviewSize.width + 2 * LayoutConstants.linkPreviewHMargin,
                height: linkPreviewSize.height + 2 * LayoutConstants.linkPreviewVMargin
            )
            linkPreviewView.frame = linkPreviewWrapperView.bounds.insetBy(
                dx: LayoutConstants.linkPreviewHMargin,
                dy: LayoutConstants.linkPreviewVMargin
            )

            // Save height of link preview with "regular" layout so that we can calculate
            // if there's enough room to go back from "compact" to "regular".
            if linkPreviewView.layout == .regular {
                expandedLinkPreviewAreaHeight = linkPreviewWrapperView.frame.height
            }
        }

        textContentSize = calculateTextContentSize()

        // If link preview view has "regular" (tall) layout and there's no enough vertical space for both link and text,
        // we force "compact" layout for the link preview and trigger a new layout pass.
        if let linkPreviewView = linkPreviewView, linkPreviewView.layout == .regular, textContentSize.height > 0 {
            let contentHeight = textContentSize.height + LayoutConstants.linkPreviewAreaTopMargin + linkPreviewWrapperView.frame.height
            if contentHeight > contentLayoutGuide.layoutFrame.height {
                forceCompactLayoutForLinkPreview = true
                reloadLinkPreviewAppearance()
                return
            }
        }

        // If link preview view has "compact" layout and there's enough vertical space for both text
        // and link in "regular" size, we disable forcing link preview to be compact.
        if let linkPreviewView = linkPreviewView, linkPreviewView.layout == .compact,
           let expandedLinkPreviewAreaHeight = expandedLinkPreviewAreaHeight {
            if forceCompactLayoutForLinkPreview {
                var contentHeight = expandedLinkPreviewAreaHeight
                if textContentSize.height > 0 {
                    contentHeight += (LayoutConstants.linkPreviewAreaTopMargin + textContentSize.height)
                }
                if contentHeight < contentLayoutGuide.layoutFrame.height {
                    forceCompactLayoutForLinkPreview = false
                }
            }
            if !shouldUseCompactLayoutForLinkPreview() {
                reloadLinkPreviewAppearance()
                return
            }
        }

        layoutTextContentAndLinkPreview()
    }

    open func layoutTextContentAndLinkPreview() {
        var maxTextAreaHeight = contentLayoutGuide.layoutFrame.height
        var linkPreviewAreaHeight: CGFloat = 0
        if linkPreviewView != nil {
            linkPreviewAreaHeight = linkPreviewWrapperView.frame.height
            maxTextAreaHeight -= (linkPreviewAreaHeight + LayoutConstants.linkPreviewAreaTopMargin)
        }

        var textAreaHeight: CGFloat = 0

        // Position text and/or link preview.
        if let textLabel = textLabel, textContentSize.height > 0 {
            textLabel.bounds.size = textContentSize

            let cappedTextContentHeight = min(textContentSize.height, maxTextAreaHeight - 2 * LayoutConstants.textBackgroundVMargin)
            let scaleFactor = min(1, cappedTextContentHeight / textContentSize.height)
            textLabel.transform = CGAffineTransform.scale(scaleFactor)

            let verticalOffset = linkPreviewAreaHeight > 0 ? 0.5 * (linkPreviewAreaHeight + LayoutConstants.linkPreviewAreaTopMargin) : 0
            textLabel.center = CGPoint(
                x: contentLayoutGuide.layoutFrame.center.x,
                y: contentLayoutGuide.layoutFrame.center.y - verticalOffset
            )
            if let textBackgroundView = textBackgroundView {
                textBackgroundView.frame = convert(textLabel.bounds, from: textLabel).insetBy(
                    dx: -LayoutConstants.textBackgroundHMargin,
                    dy: -LayoutConstants.textBackgroundVMargin
                )
            }

            textAreaHeight = cappedTextContentHeight + 2 * LayoutConstants.textBackgroundVMargin
        }
        if linkPreviewView != nil {
            let verticalOffset = textAreaHeight > 0 ? 0.5 * (textAreaHeight + LayoutConstants.linkPreviewAreaTopMargin) : 0
            linkPreviewWrapperView.center = CGPoint(
                x: contentLayoutGuide.layoutFrame.center.x,
                y: contentLayoutGuide.layoutFrame.center.y + verticalOffset
            )
        }
    }

    open func calculateTextContentSize() -> CGSize {
        guard let textLabel = textLabel else {
            return .zero
        }

        let maxTextLabelSize = contentLayoutGuide.layoutFrame.insetBy(
            dx: LayoutConstants.textBackgroundHMargin,
            dy: LayoutConstants.textBackgroundVMargin
        ).size
        return textLabel.systemLayoutSizeFitting(
            maxTextLabelSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
    }

    // MARK: - Attributes

    public var text: String? {
        didSet { updateTextAttributes() }
    }

    public var textStyle: TextAttachment.TextStyle = .regular {
        didSet { updateTextAttributes() }
    }

    public private(set) var textForegroundColor: UIColor = Theme.darkThemePrimaryColor

    public private(set) var textBackgroundColor: UIColor?

    public func setTextForegroundColor(_ textForegroundColor: UIColor, backgroundColor: UIColor?) {
        self.textForegroundColor = textForegroundColor
        self.textBackgroundColor = backgroundColor
        updateTextAttributes()
    }

    // MARK: - Text

    public func sizeAndAlignment(forText text: String) -> (fontPointSize: CGFloat, textAlignment: NSTextAlignment) {
        switch text.count {
        case ..<50: return (34, .center)
        case 50...199: return (24, .center)
        default: return (18, .natural)
        }
    }

    public func updateTextAttributes() {
        defer { updateVisibilityOfComponents(animated: false) }

        guard let text = text else { return }

        var textLabel: UILabel
        if let existingLabel = self.textLabel {
            textLabel = existingLabel
        } else {
            textLabel = UILabel()
            textLabel.adjustsFontSizeToFitWidth = true
            textLabel.allowsDefaultTighteningForTruncation = true
            textLabel.lineBreakMode = .byWordWrapping
            textLabel.minimumScaleFactor = 0.2
            textLabel.numberOfLines = 0
            addSubview(textLabel)
            self.textLabel = textLabel
        }

        let (fontPointSize, textAlignment) = sizeAndAlignment(forText: text)
        textLabel.text = transformedText(text, for: textStyle)
        textLabel.textAlignment = textAlignment
        textLabel.font = .font(for: textStyle, withPointSize: fontPointSize)
        textLabel.textColor = textForegroundColor

        if let textBackgroundColor = textBackgroundColor {
            var textBackgroundView: UIView
            if let existingBackgroundView = self.textBackgroundView {
                textBackgroundView = existingBackgroundView
            } else {
                textBackgroundView = UIView()
                textBackgroundView.layer.cornerRadius = LayoutConstants.textBackgroundCornerRadius
                insertSubview(textBackgroundView, belowSubview: textLabel)
                self.textBackgroundView = textBackgroundView
            }
            textBackgroundView.backgroundColor = textBackgroundColor
        }

        setNeedsLayout()
    }

    public func transformedText(_ text: String, for textStyle: TextAttachment.TextStyle) -> String {
        guard case .condensed = textStyle else { return text }
        return text.uppercased()
    }

    open func updateVisibilityOfComponents(animated: Bool) {
        let isEditing = isEditing
        if text != nil {
            textLabel?.setIsHidden(isEditing, animated: animated)
            textBackgroundView?.setIsHidden(isEditing || textBackgroundColor == nil, animated: animated)
        } else {
            textLabel?.setIsHidden(true, animated: animated)
            textBackgroundView?.setIsHidden(true, animated: animated)
        }
    }

    public private(set) var textLabel: UILabel?

    public private(set) var textBackgroundView: UIView?

    // MARK: - Background

    public var background: TextAttachment.Background {
        didSet { updateBackground() }
    }

    private var gradientView: GradientView?

    private func updateBackground() {
        switch background {
        case .color(let color):
            if let gradientView = gradientView {
                gradientView.isHidden = true
            }
            backgroundColor = color

        case .gradient(let gradient):
            var gradientView: GradientView
            if let existingGradientView = self.gradientView {
                gradientView = existingGradientView
            } else {
                gradientView = GradientView(colors: [])
                insertSubview(gradientView, at: 0)
                gradientView.autoPinEdgesToSuperviewEdges()
                self.gradientView = gradientView
            }
            gradientView.isHidden = false
            gradientView.colors = gradient.colors
            gradientView.locations = gradient.locations
            gradientView.setAngle(gradient.angle)
        }
    }

    // MARK: - Link Preview

    public var linkPreview: LinkPreviewState? {
        didSet {
            expandedLinkPreviewAreaHeight = nil
            reloadLinkPreviewAppearance()
        }
    }

    public private(set) var linkPreviewView: LinkPreviewView?

    public private(set) lazy var linkPreviewWrapperView = UIView()

    private var forceCompactLayoutForLinkPreview = false

    private func shouldUseCompactLayoutForLinkPreview() -> Bool {
        if let text = text, text.count >= 50 { return true }
        return forceCompactLayoutForLinkPreview
    }

    open func reloadLinkPreviewAppearance() {
        if let linkPreviewView = linkPreviewView {
            linkPreviewView.removeFromSuperview()
            self.linkPreviewView = nil
        }

        defer {
            setNeedsLayout()
        }

        guard let linkPreview = linkPreview else {
            linkPreviewWrapperView.isHidden = true
            return
        }

        if linkPreviewWrapperView.superview == nil {
            addSubview(linkPreviewWrapperView)
        }
        linkPreviewWrapperView.isHidden = false

        let linkPreviewView = TextAttachmentView.LinkPreviewView(
            linkPreview: linkPreview,
            forceCompactSize: shouldUseCompactLayoutForLinkPreview()
        )
        linkPreviewWrapperView.addSubview(linkPreviewView)
        self.linkPreviewView = linkPreviewView
    }

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
                  let urlString = linkPreviewUrlString,
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

    // MARK: - LinkPreviewView

    public class LinkPreviewView: UIStackView {

        public enum Layout {
            case regular
            case compact
            case draft
            case domainOnly
        }
        public private(set) var layout: Layout = .regular

        public init(linkPreview: LinkPreviewState, isDraft: Bool = false, forceCompactSize: Bool = false) {
            super.init(frame: .zero)

            let backgroundColor: UIColor = isDraft ? Theme.darkThemeTableView2PresentedBackgroundColor : .ows_gray02
            let backgroundView = addBackgroundView(withBackgroundColor: backgroundColor)

            let title = linkPreview.title()
            let description = linkPreview.previewDescription()
            let hasTitleOrDescription = title != nil || description != nil
            if isDraft {
                layout = .draft
            } else if hasTitleOrDescription {
                layout = forceCompactSize ? .compact : .regular
            } else {
                layout = .domainOnly
            }

            let thumbnailImageView = UIImageView()
            thumbnailImageView.clipsToBounds = true
            if layout != .domainOnly && linkPreview.imageState() == .loaded {
                thumbnailImageView.contentMode = .scaleAspectFill

                // Downgrade "regular" to "compact" if thumbnail is too small.
                let imageSize = linkPreview.imagePixelSize
                if layout == .regular && (imageSize.width < 300 || imageSize.height < 300) {
                    layout = .compact
                }
                let thumbnailQuality: AttachmentThumbnailQuality = layout == .regular ? .mediumLarge : .small
                if let cacheKey = linkPreview.imageCacheKey(thumbnailQuality: thumbnailQuality),
                   let image = Self.mediaCache.get(key: cacheKey) as? UIImage {
                    thumbnailImageView.image = image
                } else {
                    linkPreview.imageAsync(thumbnailQuality: thumbnailQuality) { image in
                        thumbnailImageView.image = image
                    }
                }
            } else {
                // Dark placeholder icon on light background if there's no thumbnail associated with the link preview.
                layout = .compact
                thumbnailImageView.backgroundColor = .ows_gray02
                thumbnailImageView.contentMode = .center
                thumbnailImageView.image = UIImage(imageLiteralResourceName: "link-diagonal")
                thumbnailImageView.tintColor = Theme.lightThemePrimaryColor
            }

            alignment = .fill
            axis = layout == .regular ? .vertical : .horizontal

            switch layout {
            case .regular:
                backgroundView.layer.cornerRadius = 18
                thumbnailImageView.autoSetDimension(.height, toSize: 152)
                thumbnailImageView.layer.maskedCorners = [ .layerMinXMinYCorner, .layerMaxXMinYCorner ]

            case .compact:
                backgroundView.layer.cornerRadius = 18
                thumbnailImageView.autoSetDimension(.width, toSize: 88)
                // Allow thumbnail to grow vertically with the text.
                thumbnailImageView.autoSetDimension(.height, toSize: 88, relation: .greaterThanOrEqual)
                thumbnailImageView.layer.maskedCorners = [ .layerMinXMinYCorner, .layerMinXMaxYCorner ]

            case .draft:
                backgroundView.layer.cornerRadius = 8
                thumbnailImageView.autoSetDimension(.width, toSize: 76)
                // Allow thumbnail to grow vertically with the text.
                thumbnailImageView.autoSetDimension(.height, toSize: 76, relation: .greaterThanOrEqual)
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

        fileprivate static let mediaCache = LRUCache<String, NSObject>(maxSize: 32, shouldEvacuateInBackground: true)
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
