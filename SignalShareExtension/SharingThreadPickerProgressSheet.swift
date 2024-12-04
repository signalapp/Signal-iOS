//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalUI
public import SignalServiceKit

public class SharingThreadPickerProgressSheet: ActionSheetController {

    private var attachmentIds: [Attachment.IDType]
    /// Note: progress for _all_ attachments, not just those in attachmentIds.
    /// Filter down to just attachmentIds for display purposes.
    private var progressPerAttachment: [Attachment.IDType: Float] = [:]

    public init(
        attachmentIds: [Attachment.IDType],
        delegate: ShareViewDelegate?
    ) {
        self.attachmentIds = attachmentIds
        super.init(theme: .default)

        setupSubviews()

        let cancelAction = ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel
        ) { [weak delegate] _ in
            delegate?.shareViewWasCancelled()
        }
        super.addAction(cancelAction)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAttachmentProgressNotification(_:)),
            name: Upload.Constants.attachmentUploadProgressNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - API

    public func updateSendingAttachmentIds(_ ids: [Attachment.IDType]) {
        // the next upload progress update
        self.attachmentIds = ids
        renderProgress()
    }

    // MARK: - UI Elements

    private lazy var headerWithProgress: UIView = {
        let headerWithProgress = UIView()
        headerWithProgress.backgroundColor = Theme.actionSheetBackgroundColor
        headerWithProgress.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        return headerWithProgress
    }()

    private lazy var progressLabel: UILabel = {
        let progressLabel = UILabel()
        progressLabel.textAlignment = .center
        progressLabel.numberOfLines = 0
        progressLabel.lineBreakMode = .byWordWrapping
        progressLabel.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
        progressLabel.textColor = Theme.primaryTextColor
        progressLabel.text = OWSLocalizedString("SHARE_EXTENSION_SENDING_IN_PROGRESS_TITLE", comment: "Alert title")
        return progressLabel
    }()

    private lazy var progressView = UIProgressView(progressViewStyle: .default)

    private func setupSubviews() {
        headerWithProgress.addSubview(progressLabel)
        progressLabel.autoPinWidthToSuperviewMargins()
        progressLabel.autoPinTopToSuperviewMargin()

        headerWithProgress.addSubview(progressView)
        progressView.autoPinWidthToSuperviewMargins()
        progressView.autoPinEdge(.top, to: .bottom, of: progressLabel, withOffset: 8)
        progressView.autoPinBottomToSuperviewMargin()

        super.customHeader = headerWithProgress
    }

    // MARK: - Updating UI

    private func renderProgress() {
        guard attachmentIds.isEmpty.negated else {
            progressLabel.text = OWSLocalizedString(
                "MESSAGE_STATUS_SENDING",
                comment: "message status while message is sending."
            )
            return
        }

        let progressValues = attachmentIds.map { progressPerAttachment[$0] ?? 0 }

        // Attachments can upload in parallel, so we show the progress
        // of the average of all the individual attachment's progress.
        progressView.progress = progressValues.reduce(0, +) / Float(attachmentIds.count)

        // In order to indicate approximately how many attachments remain
        // to upload, we look at the number that have had their progress
        // reach 100%.
        let totalCompleted = progressValues.filter { $0 == 1 }.count

        progressLabel.text = String(
            format: Self.progressFormat,
            OWSFormat.formatInt(min(totalCompleted + 1, attachmentIds.count)),
            OWSFormat.formatInt(attachmentIds.count)
        )
    }

    private static let progressFormat = OWSLocalizedString(
        "SHARE_EXTENSION_SENDING_IN_PROGRESS_FORMAT",
        comment: "Send progress for share extension. Embeds {{ %1$@ number of attachments uploaded, %2$@ total number of attachments}}"
    )

    // MARK: Notifications

    @objc
    private func handleAttachmentProgressNotification(_ notification: NSNotification) {
        // We can safely show the progress for just the first message,
        // all the messages share the same attachment upload progress.
        guard let notificationAttachmentId = notification.userInfo?[Upload.Constants.uploadAttachmentIDKey] as? Attachment.IDType else {
            owsFailDebug("Missing notificationAttachmentId.")
            return
        }
        guard let progress = notification.userInfo?[Upload.Constants.uploadProgressKey] as? NSNumber else {
            owsFailDebug("Missing progress.")
            return
        }

        progressPerAttachment[notificationAttachmentId] = progress.floatValue

        renderProgress()
    }
}
