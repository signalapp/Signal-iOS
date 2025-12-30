//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import GRDB
import SignalServiceKit
import SignalUI

class InternalListMediaViewController: OWSTableViewController2 {

    private var deviceSleepManager: DeviceSleepManager? { DependenciesBridge.shared.deviceSleepManager }
    private var sleepBlockObject: DeviceSleepBlockObject?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Backup media debug"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.sleepBlockObject = DeviceSleepBlockObject(blockReason: "InternalListMedia")
        deviceSleepManager?.addBlock(blockObject: self.sleepBlockObject!)

        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            asyncBlock: { [weak self] modal in
                try? await DependenciesBridge.shared.backupAttachmentCoordinator.queryListMediaIfNeeded()
                await MainActor.run {
                    self?.updateTableContents()
                }
                modal.dismiss(animated: true)
            },
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.sleepBlockObject.take().map { self.deviceSleepManager?.removeBlock(blockObject: $0) }
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let (
            pendingUploadFullsizeCount,
            pendingUploadThumbnailCount,
            pendingOrphanDeleteCount,
            lastListMediaFailure,
            lastListMediaResult,
        ) = DependenciesBridge.shared.db.read { tx in
            return (
                try! QueuedBackupAttachmentUpload
                    .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.state) == QueuedBackupAttachmentUpload.State.ready.rawValue)
                    .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.isFullsize) == true)
                    .fetchCount(tx.database),
                try! QueuedBackupAttachmentUpload
                    .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.state) == QueuedBackupAttachmentUpload.State.ready.rawValue)
                    .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.isFullsize) == false)
                    .fetchCount(tx.database),
                try! OrphanedBackupAttachment.fetchCount(tx.database),
                try! DependenciesBridge.shared.backupListMediaStore.getLastFailingIntegrityCheckResult(tx: tx),
                try! DependenciesBridge.shared.backupListMediaStore.getMostRecentIntegrityCheckResult(tx: tx),
            )
        }

        let pendingUploadSection = OWSTableSection(title: "Pending upload")
        pendingUploadSection.add(.copyableItem(label: "Pending upload: Fullsize", value: "\(pendingUploadFullsizeCount)"))
        pendingUploadSection.add(.copyableItem(label: "Pending upload: Thumbnail", value: "\(pendingUploadThumbnailCount)"))
        pendingUploadSection.add(.copyableItem(label: "Pending remote deletion", value: "\(pendingOrphanDeleteCount)"))
        contents.add(pendingUploadSection)

        let lastFailureSection = OWSTableSection(title: "Last discrepant result")
        if let lastListMediaFailure {
            Self.populate(section: lastFailureSection, with: lastListMediaFailure)
        }
        contents.add(lastFailureSection)

        let lastResultSection = OWSTableSection(title: "Latest result")
        if let lastListMediaResult {
            Self.populate(section: lastResultSection, with: lastListMediaResult)
        }
        lastResultSection.add(.actionItem(withText: "Perform remote integrity check", actionBlock: { [weak self] in
            guard let self else { return }
            ModalActivityIndicatorViewController.present(
                fromViewController: self,
                asyncBlock: { [weak self] _ in
                    await DependenciesBridge.shared.db.awaitableWrite { tx in
                        DependenciesBridge.shared.backupListMediaStore.setManualNeedsListMedia(true, tx: tx)
                    }
                    try? await DependenciesBridge.shared.backupAttachmentCoordinator.queryListMediaIfNeeded()
                    await MainActor.run {
                        self?.updateTableContents()
                        self?.dismiss(animated: false)
                    }
                },
            )
        }))
        contents.add(lastResultSection)

        self.contents = contents
    }

    static func populate(section: OWSTableSection, with listMediaResult: ListMediaIntegrityCheckResult) {
        section.add(.copyableItem(label: "Date", value: "\(Date(millisecondsSince1970: listMediaResult.listMediaStartTimestamp))"))
        section.add(.copyableItem(label: "Uploaded count: Fullsize", value: "\(listMediaResult.fullsize.uploadedCount)"))
        section.add(.copyableItem(
            label: "Ineligible count: Fullsize",
            subtitle: "e.g. DMs, view once, etc",
            value: "\(listMediaResult.fullsize.ineligibleCount)",
        ))
        section.add(.copyableItem(
            label: "Missing count: Fullsize",
            subtitle: "Bad if > 0",
            value: "\(listMediaResult.fullsize.missingFromCdnCount)",
        ))
        section.add(.copyableItem(label: "Unscheduled count: Fullsize", value: "\(listMediaResult.fullsize.notScheduledForUploadCount ?? 0)"))
        section.add(.copyableItem(label: "Discovered count: Fullsize", value: "\(listMediaResult.fullsize.discoveredOnCdnCount)"))
        section.add(.copyableItem(label: "Uploaded count: Thumbnail", value: "\(listMediaResult.thumbnail.uploadedCount)"))
        section.add(.copyableItem(
            label: "Ineligible count: Thumbnail",
            subtitle: "e.g. DMs, view once, etc",
            value: "\(listMediaResult.thumbnail.ineligibleCount)",
        ))
        section.add(.copyableItem(
            label: "Missing count: Thumbnail",
            subtitle: "Not good if > 0, but nbd",
            value: "\(listMediaResult.thumbnail.missingFromCdnCount)",
        ))
        section.add(.copyableItem(label: "Unscheduled count: Thumbnail", value: "\(listMediaResult.thumbnail.notScheduledForUploadCount ?? 0)"))
        section.add(.copyableItem(label: "Discovered count: Thumbnail", value: "\(listMediaResult.thumbnail.discoveredOnCdnCount)"))
        section.add(.copyableItem(
            label: "Orphan count",
            subtitle: "Should roughy match pending deletion",
            value: "\(listMediaResult.orphanedObjectCount)",
        ))
    }
}
