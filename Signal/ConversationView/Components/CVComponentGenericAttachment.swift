//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import PassKit
public import QuickLook
public import SignalServiceKit
public import SignalUI

public class CVComponentGenericAttachment: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .genericAttachment }

    public var attachmentId: Attachment.IDType { genericAttachment.attachment.attachment.attachment.id }

    private let genericAttachment: CVComponentState.GenericAttachment
    private var attachment: ReferencedAttachment { genericAttachment.attachment.attachment }
    private var attachmentStream: AttachmentStream? { genericAttachment.attachmentStream }
    private var attachmentPointer: AttachmentPointer? { genericAttachment.attachmentPointer }

    init(itemModel: CVItemModel, genericAttachment: CVComponentState.GenericAttachment) {
        self.genericAttachment = genericAttachment

        super.init(itemModel: itemModel)
    }

    deinit {
        // Wipe the value so we delete the file
        self.qlPreviewTmpFileUrl = nil
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewGenericAttachment()
    }

    var isIncomingOverride: Bool?

    var isIncoming: Bool {
        return isIncomingOverride ?? (interaction is TSIncomingMessage)
    }

    public func configureForRendering(
        componentView componentViewParam: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
        guard let componentView = componentViewParam as? CVComponentViewGenericAttachment else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let hStackView = componentView.hStackView
        let vStackView = componentView.vStackView

        var hSubviews = [UIView]()

        if let downloadView = tryToBuildProgressView() {
            hSubviews.append(downloadView)
        } else {
            let iconImageView = componentView.iconImageView
            if let icon = UIImage(named: "generic-attachment") {
                owsAssertDebug(icon.size == Self.iconSize)
                iconImageView.image = icon
            } else {
                owsFailDebug("Missing icon.")
            }
            hSubviews.append(iconImageView)

            let fileTypeLabel = componentView.fileTypeLabel
            fileTypeLabelConfig.applyForRendering(label: fileTypeLabel)
            fileTypeLabel.adjustsFontSizeToFitWidth = true
            fileTypeLabel.minimumScaleFactor = 0.25
            fileTypeLabel.textAlignment = .center
            // Center on icon.
            iconImageView.addSubview(fileTypeLabel)
            vStackView.addLayoutBlock { _ in
                guard let superview = fileTypeLabel.superview else {
                    owsFailDebug("Missing superview.")
                    return
                }
                var labelSize = fileTypeLabel.sizeThatFitsMaxSize
                labelSize.width = min(
                    labelSize.width,
                    superview.bounds.width - 15,
                )

                let labelFrame = CGRect(
                    origin: ((superview.bounds.size - labelSize) * 0.5).asPoint,
                    size: labelSize,
                )
                fileTypeLabel.frame = labelFrame
            }
        }

        let topLabel = componentView.topLabel
        let bottomLabel = componentView.bottomLabel

        Self.topLabelConfig(
            genericAttachment: genericAttachment,
            textColor: conversationStyle.bubbleTextColor(isIncoming: isIncoming),
        ).applyForRendering(label: topLabel)
        Self.bottomLabelConfig(
            genericAttachment: genericAttachment,
            textColor: conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming),
        ).applyForRendering(label: bottomLabel)

        let vSubviews = [
            componentView.topLabel,
            componentView.bottomLabel,
        ]
        vStackView.configure(
            config: Self.vStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_vStack,
            subviews: vSubviews,
        )
        hSubviews.append(vStackView)
        hStackView.configure(
            config: Self.hStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_hStack,
            subviews: hSubviews,
        )
    }

    private static var hStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .horizontal,
            alignment: .center,
            spacing: hSpacing,
            layoutMargins: UIEdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0),
        )
    }

    private static var vStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .leading,
            spacing: labelVSpacing,
            layoutMargins: .zero,
        )
    }

    private static func topLabelConfig(
        genericAttachment: CVComponentState.GenericAttachment,
        textColor: UIColor,
    ) -> CVLabelConfig {
        var text: String = genericAttachment.attachment.attachment.reference.sourceFilename?.ows_stripped() ?? ""
        if
            text.isEmpty,
            let fileExtension = MimeTypeUtil.fileExtensionForMimeType(genericAttachment.attachment.attachment.attachment.mimeType)
        {
            text = (fileExtension as NSString).localizedUppercase
        }
        if text.isEmpty {
            text = OWSLocalizedString("GENERIC_ATTACHMENT_LABEL", comment: "A label for generic attachments.")
        }
        return CVLabelConfig.unstyledText(
            text,
            font: UIFont.dynamicTypeSubheadline.semibold(),
            textColor: textColor,
            lineBreakMode: .byTruncatingMiddle,
        )
    }

    private static func bottomLabelConfig(
        genericAttachment: CVComponentState.GenericAttachment,
        textColor: UIColor,
    ) -> CVLabelConfig {
        let font = UIFont.dynamicTypeCaption1

        // We don't want to show the file size while the attachment is downloading.
        // To avoid layout jitter when the download completes, we reserve space in
        // the layout using a whitespace string.
        var text = " "

        if let attachmentPointer = genericAttachment.attachmentPointer {
            var textComponents = [String]()

            if let byteCount = attachmentPointer.unencryptedByteCount, byteCount > 0 {
                textComponents.append(OWSFormat.localizedFileSizeString(from: Int64(byteCount)))
            }

            switch genericAttachment.attachment {
            case .stream, .pointer(_, .enqueuedOrDownloading), .backupThumbnail, .undownloadable:
                break
            case .pointer(_, .failed), .pointer(_, .none):
                textComponents.append(OWSLocalizedString("ACTION_TAP_TO_DOWNLOAD", comment: "A label for 'tap to download' buttons."))
            }

            if !textComponents.isEmpty {
                text = textComponents.joined(separator: " • ")
            }
        } else if let attachmentStream = genericAttachment.attachmentStream {
            let fileSize = attachmentStream.unencryptedByteCount
            text = OWSFormat.localizedFileSizeString(from: Int64(fileSize))
        } else if let _ = genericAttachment.attachmentBackupThumbnail {
            // TODO:[Backups]: Handle similar to attachment pointers above
            owsFailDebug("Not implemented yet")
        } else {
            let attributedString = NSAttributedString.composed(of: [
                NSAttributedString.with(
                    image: UIImage(named: "error-circle-20")!,
                    font: font,
                ),
                " ",
                OWSLocalizedString(
                    "FILE_UNAVAILABLE_FOOTER",
                    comment: "Footer for message cell for documents/files when they are expired and unavailable for download",
                ),
            ])

            return CVLabelConfig(
                text: .attributedText(attributedString),
                displayConfig: .forUnstyledText(font: font, textColor: textColor),
                font: font,
                textColor: textColor,
                lineBreakMode: .byTruncatingMiddle,
            )
        }

        return CVLabelConfig.unstyledText(
            text,
            font: font,
            textColor: textColor,
            lineBreakMode: .byTruncatingMiddle,
        )
    }

    private var fileTypeLabelConfig: CVLabelConfig {
        let filename: String = attachment.reference.sourceFilename ?? ""
        var fileExtension: String = (filename as NSString).pathExtension
        if fileExtension.isEmpty {
            fileExtension = MimeTypeUtil.fileExtensionForMimeType(attachment.attachment.mimeType) ?? ""
        }
        let text = (fileExtension as NSString).localizedUppercase

        return CVLabelConfig.unstyledText(
            text,
            font: UIFont.dynamicTypeCaption1.semibold(),
            textColor: .ows_gray90,
            lineBreakMode: .byTruncatingTail,
        )
    }

    private func tryToBuildProgressView() -> UIView? {

        let direction: CVAttachmentProgressView.Direction
        switch CVAttachmentProgressView.progressType(
            forAttachment: genericAttachment.attachment,
            interaction: interaction,
        ) {
        case .none:
            return nil
        case .uploading:
            // We currently only show progress for downloads here.
            return nil
        case .pendingDownload(let attachmentPointer):
            direction = .download(
                attachmentPointer: attachmentPointer,
                downloadState: .none,
            )
        case .downloading(let attachmentPointer, let downloadState):
            direction = .download(
                attachmentPointer: attachmentPointer,
                downloadState: downloadState,
            )
        case .unknown:
            owsFailDebug("Unknown progress type.")
            return nil
        }

        return CVAttachmentProgressView(
            direction: direction,
            diameter: Self.progressSize,
            isDarkThemeEnabled: conversationStyle.isDarkThemeEnabled,
            mediaCache: mediaCache,
        )
    }

    private static func hasProgressView(
        genericAttachment: CVComponentState.GenericAttachment,
        interaction: TSInteraction,
    ) -> Bool {
        switch CVAttachmentProgressView.progressType(
            forAttachment: genericAttachment.attachment,
            interaction: interaction,
        ) {
        case .none,
             .uploading:
            // We currently only show progress for downloads here.
            return false
        case .pendingDownload,
             .downloading:
            return true
        case .unknown:
            owsFailDebug("Unknown progress type.")
            return false
        }
    }

    private static let hSpacing: CGFloat = 8
    private static let labelVSpacing: CGFloat = 1
    private static let iconSize = CGSize(width: 36, height: CGFloat(AvatarBuilder.standardAvatarSizePoints))
    private static let progressSize: CGFloat = 36

    private static let measurementKey_hStack = "CVComponentGenericAttachment.measurementKey_hStack"
    private static let measurementKey_vStack = "CVComponentGenericAttachment.measurementKey_vStack"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        return Self.measure(
            maxWidth: maxWidth,
            measurementBuilder: measurementBuilder,
            genericAttachment: genericAttachment,
            interaction: interaction,
        )
    }

    static func measure(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder,
        genericAttachment: CVComponentState.GenericAttachment,
        interaction: TSInteraction,
    ) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let hasProgressView = Self.hasProgressView(
            genericAttachment: genericAttachment,
            interaction: interaction,
        )
        let leftViewSize: CGSize = (
            hasProgressView
                ? .square(progressSize)
                : iconSize,
        )

        let maxLabelWidth = max(0, maxWidth - (
            leftViewSize.width +
                hSpacing +
                hStackConfig.layoutMargins.totalWidth +
                vStackConfig.layoutMargins.totalWidth
        ))
        let topLabelConfig = Self.topLabelConfig(
            genericAttachment: genericAttachment,
            textColor: .black, // Irrelevant for sizing
        )
        let topLabelSize = CVText.measureLabel(config: topLabelConfig, maxWidth: maxLabelWidth)
        let bottomLabelConfig = Self.bottomLabelConfig(
            genericAttachment: genericAttachment,
            textColor: .black, // Irrelevant for sizing
        )
        let bottomLabelSize = CVText.measureLabel(config: bottomLabelConfig, maxWidth: maxLabelWidth)

        var vSubviewInfos = [ManualStackSubviewInfo]()
        vSubviewInfos.append(topLabelSize.asManualSubviewInfo())
        vSubviewInfos.append(bottomLabelSize.asManualSubviewInfo())

        let vStackMeasurement = ManualStackView.measure(
            config: vStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_vStack,
            subviewInfos: vSubviewInfos,
        )

        var hSubviewInfos = [ManualStackSubviewInfo]()
        hSubviewInfos.append(leftViewSize.asManualSubviewInfo(hasFixedSize: true))
        hSubviewInfos.append(vStackMeasurement.measuredSize.asManualSubviewInfo)
        let hStackMeasurement = ManualStackView.measure(
            config: hStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_hStack,
            subviewInfos: hSubviewInfos,
            maxWidth: maxWidth,
        )
        return hStackMeasurement.measuredSize
    }

    // MARK: - Events

    override public func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> Bool {

        switch genericAttachment.attachment {
        case .stream:
            switch componentDelegate.didTapGenericAttachment(self) {
            case .handledByDelegate:
                break
            case .default:
                showShareUI(from: componentView.rootView)
            }
        case .pointer(_, let downloadState):
            switch downloadState {
            case .failed, .none:
                guard let message = renderItem.interaction as? TSMessage else {
                    owsFailDebug("Invalid interaction.")
                    return true
                }
                componentDelegate.didTapFailedOrPendingDownloads(message)
            case .enqueuedOrDownloading:
                break
            }
        case .backupThumbnail:
            guard let message = renderItem.interaction as? TSMessage else {
                owsFailDebug("Invalid interaction.")
                return true
            }
            componentDelegate.didTapFailedOrPendingDownloads(message)
        case .undownloadable:
            componentDelegate.didTapUndownloadableGenericFile()
        }

        return true
    }

    private var qlPreviewTmpFileUrl: URL? {
        didSet {
            if let oldValue {
                try? OWSFileSystem.deleteFile(url: oldValue)
            }
        }
    }

    public func createQLPreviewController() -> QLPreviewController? {
        guard #available(iOS 14.8, *) else { return nil }

        guard let attachmentStream else {
            return nil
        }

        let sourceFilename = genericAttachment.attachment.attachment.reference.sourceFilename
        guard let url = try? attachmentStream.makeDecryptedCopy(filename: sourceFilename) else {
            return nil
        }
        guard QLPreviewController.canPreview(url as NSURL) else {
            try? OWSFileSystem.deleteFile(url: url)
            return nil
        }
        self.qlPreviewTmpFileUrl = url

        let previewController = QLPreviewController()
        previewController.dataSource = self
        previewController.delegate = self
        return previewController
    }

    /// Returns the `PKPass` represented by this attachment, if any.
    public func representedPKPass() -> PKPass? {
        guard attachmentStream?.mimeType == "application/vnd.apple.pkpass" else {
            return nil
        }
        guard let data = try? attachmentStream?.decryptedRawData() else {
            return nil
        }
        return try? PKPass(data: data)
    }

    public func showShareUI(from view: UIView) {
        guard let attachmentStream = (try? [genericAttachment.attachment.attachment.asReferencedStream].compacted().asShareableAttachments())?.first else {
            owsFailDebug("should not show the share UI unless there's a downloaded attachment")
            return
        }
        // TODO: Ensure share UI is shown from correct location.
        AttachmentSharing.showShareUI(for: attachmentStream, sender: view)
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewGenericAttachment: NSObject, CVComponentView {

        fileprivate let hStackView = ManualStackView(name: "GenericAttachment.hStackView")
        fileprivate let vStackView = ManualStackView(name: "GenericAttachment.vStackView")
        fileprivate let topLabel = CVLabel()
        fileprivate let bottomLabel = CVLabel()
        fileprivate let fileTypeLabel = CVLabel()
        fileprivate let iconImageView = CVImageView()

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

extension CVComponentGenericAttachment: QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }

    public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        owsAssertDebug(index == 0)

        let url: URL? = {
            if attachmentStream != nil {
                return qlPreviewTmpFileUrl
            } else {
                return nil
            }
        }()
        return url.map { $0 as NSURL } ?? UnavailableItem()
    }

    public func previewControllerDidDismiss(_ controller: QLPreviewController) {
        self.qlPreviewTmpFileUrl = nil
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
        OWSLocalizedString(
            "ACCESSIBILITY_LABEL_ATTACHMENT",
            comment: "Accessibility label for attachment.",
        )
    }
}
