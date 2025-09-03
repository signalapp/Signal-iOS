//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import GRDB
import SignalServiceKit
import SignalUI

class InternalListMediaViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Backup media debug"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            asyncBlock: { [weak self] modal in
                try? await DependenciesBridge.shared.backupListMediaManager.queryListMediaIfNeeded()
                await MainActor.run {
                    self?.updateTableContents()
                }
                modal.dismiss(animated: true)
            }
        )
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
                try! DependenciesBridge.shared.backupListMediaManager.getLastFailingIntegrityCheckResult(tx: tx),
                try! DependenciesBridge.shared.backupListMediaManager.getMostRecentIntegrityCheckResult(tx: tx)
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
            let vc = ActionSheetController(
                title: "This will schedule the integrity check to run on next app launch, then exit the app. "
                    + "After tapping \"Okay\", please relaunch the app and return to this screen to check the results."
            )
            vc.addAction(.init(title: "Okay", handler: { _ in
                DependenciesBridge.shared.db.write { tx in
                    DependenciesBridge.shared.backupListMediaManager.setManualNeedsListMedia(tx: tx)
                }
                exit(0)
            }))
            vc.addAction(.cancel)
            present(vc, animated: true)
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
            value: "\(listMediaResult.fullsize.ineligibleCount)"
        ))
        section.add(.copyableItem(
            label: "Missing count: Fullsize",
            subtitle: "Bad if > 0",
            value: "\(listMediaResult.fullsize.missingFromCdnCount)"
        ))
        section.add(.copyableItem(label: "Discovered count: Fullsize", value: "\(listMediaResult.fullsize.discoveredOnCdnCount)"))
        section.add(.copyableItem(label: "Uploaded count: Thumbnail", value: "\(listMediaResult.thumbnail.uploadedCount)"))
        section.add(.copyableItem(
            label: "Ineligible count: Thumbnail",
            subtitle: "e.g. DMs, view once, etc",
            value: "\(listMediaResult.thumbnail.ineligibleCount)"
        ))
        section.add(.copyableItem(
            label: "Missing count: Thumbnail",
            subtitle: "Not good if > 0, but nbd",
            value: "\(listMediaResult.thumbnail.missingFromCdnCount)"
        ))
        section.add(.copyableItem(label: "Discovered count: Thumbnail", value: "\(listMediaResult.thumbnail.discoveredOnCdnCount)"))
        section.add(.copyableItem(
            label: "Orphan count",
            subtitle: "Should roughy match pending deletion",
            value: "\(listMediaResult.orphanedObjectCount)"
        ))
    }
}
