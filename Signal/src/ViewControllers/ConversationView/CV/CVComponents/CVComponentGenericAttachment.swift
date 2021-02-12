//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import QuickLook

@objc
public class CVComponentGenericAttachment: CVComponentBase, CVComponent {

    private let genericAttachment: CVComponentState.GenericAttachment
    private var attachment: TSAttachment { genericAttachment.attachment }
    private var attachmentStream: TSAttachmentStream? { genericAttachment.attachmentStream }
    private var attachmentPointer: TSAttachmentPointer? { genericAttachment.attachmentPointer }

    init(itemModel: CVItemModel, genericAttachment: CVComponentState.GenericAttachment) {
        self.genericAttachment = genericAttachment

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewGenericAttachment()
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewGenericAttachment else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let hStackView = componentView.hStackView
        hStackView.apply(config: hStackConfig)

        if let downloadView = tryToBuildDownloadView() {
            hStackView.addArrangedSubview(downloadView)
        } else {
            let iconImageView = componentView.iconImageView
            if let icon = UIImage(named: "generic-attachment") {
                owsAssertDebug(icon.size == iconSize)
                iconImageView.image = icon
            } else {
                owsFailDebug("Missing icon.")
            }
            iconImageView.autoSetDimensions(to: iconSize)
            iconImageView.setCompressionResistanceHigh()
            iconImageView.setContentHuggingHigh()
            hStackView.addArrangedSubview(iconImageView)

            let fileTypeLabel = componentView.fileTypeLabel
            fileTypeLabelConfig.applyForRendering(label: fileTypeLabel)
            fileTypeLabel.adjustsFontSizeToFitWidth = true
            fileTypeLabel.minimumScaleFactor = 0.25
            fileTypeLabel.textAlignment = .center
            // Center on icon.
            iconImageView.addSubview(fileTypeLabel)
            fileTypeLabel.autoCenterInSuperview()
            fileTypeLabel.autoSetDimension(.width, toSize: iconSize.width - 15)
        }

        let vStackView = componentView.vStackView
        vStackView.apply(config: vStackViewConfig)
        hStackView.addArrangedSubview(vStackView)

        let topLabel = componentView.topLabel
        topLabelConfig.applyForRendering(label: topLabel)
        vStackView.addArrangedSubview(topLabel)

        let bottomLabel = componentView.bottomLabel
        bottomLabelConfig.applyForRendering(label: bottomLabel)
        vStackView.addArrangedSubview(bottomLabel)
    }

    private var hStackLayoutMargins: UIEdgeInsets {
        return UIEdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
    }

    private var hStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .center,
                          spacing: hSpacing,
                          layoutMargins: hStackLayoutMargins)
    }

    private var vStackViewConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .leading,
                          spacing: labelVSpacing,
                          layoutMargins: .zero)
    }

    private var topLabelConfig: CVLabelConfig {
        var text: String = attachment.sourceFilename?.ows_stripped() ?? ""
        if text.isEmpty,
           let fileExtension = MIMETypeUtil.fileExtension(forMIMEType: attachment.contentType) {
            text = (fileExtension as NSString).localizedUppercase
        }
        if text.isEmpty {
            text = NSLocalizedString("GENERIC_ATTACHMENT_LABEL", comment: "A label for generic attachments.")
        }
        return CVLabelConfig(text: text,
                             font: UIFont.ows_dynamicTypeBody,
                             textColor: conversationStyle.bubbleTextColor(isIncoming: isIncoming),
                             lineBreakMode: .byTruncatingMiddle)
    }

    private var bottomLabelConfig: CVLabelConfig {

        // We don't want to show the file size while the attachment is downloading.
        // To avoid layout jitter when the download completes, we reserve space in
        // the layout using a whitespace string.
        var text = " "

        if let attachmentPointer = self.attachmentPointer {
            var textComponents = [String]()

            if attachmentPointer.byteCount > 0 {
                textComponents.append(OWSFormat.formatFileSize(UInt(attachmentPointer.byteCount)))
            }

            switch attachmentPointer.state {
            case .enqueued, .downloading:
                break
            case .failed, .pendingMessageRequest, .pendingManualDownload:
                textComponents.append(NSLocalizedString("ACTION_TAP_TO_DOWNLOAD", comment: "A label for 'tap to download' buttons."))
            @unknown default:
                owsFailDebug("Invalid value.")
                break
            }

            if !textComponents.isEmpty {
                text = textComponents.joined(separator: " • ")
            }
        } else if let attachmentStream = attachmentStream {
            if let originalFilePath = attachmentStream.originalFilePath,
               let nsFileSize = OWSFileSystem.fileSize(ofPath: originalFilePath) {
                let fileSize = nsFileSize.uintValue
                if fileSize > 0 {
                    text = OWSFormat.formatFileSize(fileSize)
                }
            }
        } else {
            owsFailDebug("Invalid attachment")
        }

        return CVLabelConfig(text: text,
                             font: UIFont.ows_dynamicTypeCaption1,
                             textColor: conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming),
                             lineBreakMode: .byTruncatingMiddle)
    }

    private var fileTypeLabelConfig: CVLabelConfig {
        var filename: String = attachment.sourceFilename ?? ""
        if filename.isEmpty,
           let attachmentStream = attachmentStream,
           let originalFilePath = attachmentStream.originalFilePath {
            filename = (originalFilePath as NSString).lastPathComponent
        }
        var fileExtension: String = (filename as NSString).pathExtension
        if fileExtension.isEmpty {
            fileExtension = MIMETypeUtil.fileExtension(forMIMEType: attachment.contentType) ?? ""
        }
        let text = (fileExtension as NSString).localizedUppercase

        return CVLabelConfig(text: text,
                             font: UIFont.ows_dynamicTypeCaption1.ows_semibold,
                             textColor: .ows_gray90,
                             lineBreakMode: .byTruncatingTail)
    }

    private func tryToBuildDownloadView() -> UIView? {

        let direction: CVAttachmentProgressView.Direction
        switch CVAttachmentProgressView.progressType(forAttachment: attachment,
                                                     interaction: interaction) {
        case .none:
            return nil
        case .uploading:
            // We currently only show progress for downloads here.
            return nil
        case .pendingDownload(let attachmentPointer):
            direction = .download(attachmentPointer: attachmentPointer)
        case .downloading(let attachmentPointer):
            direction = .download(attachmentPointer: attachmentPointer)
        case .restoring:
            // TODO: We could easily show progress for restores.
            owsFailDebug("Restoring progress type.")
            return nil
        case .unknown:
            owsFailDebug("Unknown progress type.")
            return nil
        }

        let downloadViewSize = min(iconSize.width, iconSize.height)
        return CVAttachmentProgressView(direction: direction,
                                        style: .withoutCircle(diameter: downloadViewSize),
                                        conversationStyle: conversationStyle)
    }

    private let hSpacing: CGFloat = 8
    private let labelVSpacing: CGFloat = 2
    private let iconSize = CGSize(width: 36, height: CGFloat(kStandardAvatarSize))

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let labelsHeight = (topLabelConfig.font.lineHeight +
                                bottomLabelConfig.font.lineHeight + labelVSpacing)
        let contentHeight = max(iconSize.height, labelsHeight)
        let height = contentHeight + hStackLayoutMargins.totalHeight

        let maxLabelWidth = max(0, maxWidth - (iconSize.width + hSpacing + hStackLayoutMargins.totalWidth))
        let topLabelSize = CVText.measureLabel(config: topLabelConfig, maxWidth: maxLabelWidth)
        let bottomLabelSize = CVText.measureLabel(config: bottomLabelConfig, maxWidth: maxLabelWidth)
        let labelsWidth = max(topLabelSize.width, bottomLabelSize.width)
        let contentWidth = iconSize.width + labelsWidth + hSpacing
        let width = min(maxLabelWidth, contentWidth)

        return CGSize(width: width, height: height).ceil
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        if attachmentStream != nil {
            switch componentDelegate.cvc_didTapGenericAttachment(self) {
            case .handledByDelegate:
                break
            case .default:
                showShareUI(from: componentView.rootView)
            }
        } else if let attachmentPointer = attachmentPointer {
            switch attachmentPointer.state {
            case .failed, .pendingMessageRequest, .pendingManualDownload:
                guard let message = renderItem.interaction as? TSMessage else {
                    owsFailDebug("Invalid interaction.")
                    return true
                }
                componentDelegate.cvc_didTapFailedOrPendingDownloads(message)
            case .enqueued, .downloading:
                break
            default:
                break
            }
        } else {
            owsFailDebug("Invalid attachment.")
        }

        return true
    }

    @objc
    public var canQuickLook: Bool {
        guard #available(iOS 13, *) else { return false }
        guard let url = attachmentStream?.originalMediaURL else {
            return false
        }
        return QLPreviewController.canPreview(url as NSURL)
    }

    @objc(showShareUIFromView:)
    public func showShareUI(from view: UIView) {
        guard let attachmentStream = attachmentStream else {
            owsFailDebug("should not show the share UI unless there's a downloaded attachment")
            return
        }
        // TODO: Ensure share UI is shown from correct location.
        AttachmentSharing.showShareUI(forAttachment: attachmentStream, sender: view)
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewGenericAttachment: NSObject, CVComponentView {

        fileprivate let hStackView = OWSStackView(name: "GenericAttachment.hStackView")
        fileprivate let vStackView = OWSStackView(name: "GenericAttachment.vStackView")
        fileprivate let topLabel = UILabel()
        fileprivate let bottomLabel = UILabel()
        fileprivate let fileTypeLabel = UILabel()
        fileprivate let iconImageView = UIImageView()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            hStackView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            hStackView.reset()
            vStackView.reset()
            topLabel.text = nil
            bottomLabel.text = nil
            fileTypeLabel.text = nil
            iconImageView.image = nil
        }
    }
}

extension CVComponentGenericAttachment: QLPreviewControllerDataSource {
    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }

    public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        owsAssertDebug(index == 0)
        return (attachmentStream?.originalMediaURL as QLPreviewItem?) ?? UnavailableItem()
    }

    private class UnavailableItem: NSObject, QLPreviewItem {
        var previewItemURL: URL? { nil }
    }
}

// MARK: -

extension CVComponentGenericAttachment: CVAccessibilityComponent {
    public var accessibilityDescription: String {
        // TODO: We could include information about the attachment format,
        //       and/or filename, and download state.
        NSLocalizedString("ACCESSIBILITY_LABEL_ATTACHMENT",
                          comment: "Accessibility label for attachment.")
    }
}
