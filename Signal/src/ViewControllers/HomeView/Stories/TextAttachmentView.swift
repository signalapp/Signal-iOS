//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalServiceKit

class TextAttachmentView: UIView {
    private(set) weak var linkPreviewView: UIView?
    private let textAttachment: TextAttachment

    init(attachment: TextAttachment) {
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

        let label = UILabel()
        label.numberOfLines = 0
        label.textColor = attachment.textForegroundColor ?? Theme.darkThemePrimaryColor
        label.text = transformedText(attachment.text, for: attachment.textStyle)
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

        if let linkPreviewView = buildLinkPreviewView(attachment.preview) {
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

    private var linkPreviewTooltipView: LinkPreviewTooltipView?
    func willHandleTapGesture(_ gesture: UITapGestureRecognizer) -> Bool {
        if let linkPreviewTooltipView = linkPreviewTooltipView {
            if let container = linkPreviewTooltipView.superview,
               linkPreviewTooltipView.frame.contains(gesture.location(in: container)) {
                UIApplication.shared.open(
                    linkPreviewTooltipView.url,
                    options: [:],
                    completionHandler: nil
                )
            }

            linkPreviewTooltipView.removeFromSuperview()
            self.linkPreviewTooltipView = nil

            return true
        } else if let linkPreviewView = linkPreviewView,
                  let urlString = textAttachment.preview?.urlString,
                  let container = linkPreviewView.superview,
                  linkPreviewView.frame.contains(gesture.location(in: container)) {
            let tooltipView = LinkPreviewTooltipView(
                fromView: self,
                referenceView: linkPreviewView,
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
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            gradient.startColor.cgColor,
            gradient.endColor.cgColor
        ]
        gradientLayer.setAngle(gradient.angle)

        let layerView = OWSLayerView(frame: .zero) { view in
            gradientLayer.frame = view.bounds
        }
        layerView.layer.addSublayer(gradientLayer)

        addSubview(layerView)
        layerView.autoPinEdgesToSuperviewEdges()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func buildLinkPreviewView(_ preview: OWSLinkPreview?) -> UIView? {
        guard let preview = preview else { return nil }

        let previewHStack = UIStackView()
        previewHStack.axis = .horizontal
        previewHStack.alignment = .center
        previewHStack.spacing = 8
        previewHStack.isLayoutMarginsRelativeArrangement = true
        previewHStack.layoutMargins = UIEdgeInsets(hMargin: 12, vMargin: 12)
        previewHStack.addBackgroundView(withBackgroundColor: .ows_blackAlpha40, cornerRadius: 12)

        if let imageAttachmentId = preview.imageAttachmentId {
            if let attachment = databaseStorage.read(block: { TSAttachment.anyFetch(uniqueId: imageAttachmentId, transaction: $0) }) {
                if let stream = attachment as? TSAttachmentStream {
                    let thumbnailImageView = UIImageView()
                    thumbnailImageView.layer.cornerRadius = 8
                    thumbnailImageView.clipsToBounds = true
                    thumbnailImageView.contentMode = .scaleAspectFill
                    thumbnailImageView.autoSetDimensions(to: CGSize(square: 76))
                    previewHStack.addArrangedSubview(thumbnailImageView)

                    stream.thumbnailImageSmall { thumbnail in
                        thumbnailImageView.image = thumbnail
                    } failure: {
                        owsFailDebug("Failed to generate thumbnail preview")
                    }
                } else {
                    Logger.warn("Not rendering thumbnail for undownloaded attachment")
                }
            } else {
                owsFailDebug("Missing attachment with id \(imageAttachmentId)")
            }
        }

        let previewVStack = UIStackView()
        previewVStack.axis = .vertical
        previewVStack.alignment = .leading
        previewHStack.addArrangedSubview(previewVStack)

        if let title = preview.title {
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = .boldSystemFont(ofSize: 16)
            titleLabel.textColor = Theme.darkThemePrimaryColor
            titleLabel.numberOfLines = 2
            previewVStack.addArrangedSubview(titleLabel)
        }

        if let description = preview.previewDescription {
            let descriptionLabel = UILabel()
            descriptionLabel.text = description
            descriptionLabel.font = .systemFont(ofSize: 12)
            descriptionLabel.textColor = Theme.darkThemePrimaryColor
            descriptionLabel.numberOfLines = 3
            previewVStack.addArrangedSubview(descriptionLabel)
        }

        let footerLabel = UILabel()
        footerLabel.font = .systemFont(ofSize: 12)
        footerLabel.numberOfLines = 2
        footerLabel.textColor = Theme.darkThemeSecondaryTextAndIconColor
        previewVStack.addArrangedSubview(footerLabel)

        var footerText: String
        if let displayDomain = OWSLinkPreviewManager.displayDomain(forUrl: preview.urlString) {
            footerText = displayDomain.lowercased()
        } else {
            footerText = NSLocalizedString(
                "LINK_PREVIEW_UNKNOWN_DOMAIN",
                comment: "Label for link previews with an unknown host."
            ).uppercased()
        }
        if let date = preview.date {
            footerText.append(" ⋅ \(Self.dateFormatter.string(from: date))")
        }
        footerLabel.text = footerText

        return previewHStack
    }
}

private extension CAGradientLayer {
    /// Sets the `startPoint` and `endPoint` of the layer to reflect an angle in degrees
    /// where 0° starts at 12 o'clock and proceeds in a clockwise direction.
    func setAngle(_ angle: UInt32) {
        // While design provides gradients with 0° at 12 o'clock, core animation's
        // coordinate system works with 0° at 3 o'clock moving in a counter clockwise
        // direction. We need to convert the provided angle accordingly before
        // calculating the gradient's start and end points.

        let caAngle =
            (360 - angle) // Invert to counter clockwise direction
            + 90 // Rotate 90° counter clockwise to shift the start from 3 o'clock to 12 o'clock

        let radians = CGFloat(caAngle) * .pi / 180.0

        // (x,y) in terms of the signed unit circle
        var endPoint = CGPoint(x: cos(radians), y: sin(radians))

        // extrapolate to signed unit square
        if abs(endPoint.x) > abs(endPoint.y) {
            endPoint.x = endPoint.x > 0 ? 1 : -1
            endPoint.y = endPoint.x * tan(radians)
        } else {
            endPoint.y = endPoint.y > 0 ? 1 : -1
            endPoint.x = endPoint.y / tan(radians)
        }

        // The signed unit square is a coordinate space from:
        // (-1,-1) to (1,1), but the gradient coordinate space
        // ranges from (0,0) to (1,1) with 0 being the top
        // left. Convert each point accordingly to calculate
        // the final points.
        func convertPointToGradientSpace(_ point: CGPoint) -> CGPoint {
            return CGPoint(
                x: (point.x + 1) * 0.5,
                y: 1.0 - (point.y + 1) * 0.5
            )
        }

        // The start point will always be at the opposite side of the signed unit square.
        self.startPoint = convertPointToGradientSpace(CGPoint(x: -endPoint.x, y: -endPoint.y))
        self.endPoint = convertPointToGradientSpace(endPoint)
    }
}

private class LinkPreviewTooltipView: TooltipView {
    let url: URL
    init(fromView: UIView, referenceView: UIView, url: URL) {
        self.url = url
        super.init(
            fromView: fromView,
            widthReferenceView: referenceView,
            tailReferenceView: referenceView,
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
}
