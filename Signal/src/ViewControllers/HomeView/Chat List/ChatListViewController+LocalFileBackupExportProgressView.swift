//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PureLayout
import SignalServiceKit
import SignalUI
import UIKit

private extension Notification.Name {
    static let isHiddenDidChange = Notification.Name("CLVLocalFileBackupExportProgressView.isHiddenDidChange")
}

class CLVLocalFileBackupExportProgressView: LocalFileBackupExportProgressView.Delegate {

    struct Store {
        private enum Keys {
            static let isHidden = "isHidden"
        }

        private let kvStore = NewKeyValueStore(collection: "CLVLocalFileBackupExportProgressView")

        func isHidden(tx: DBReadTransaction) -> Bool {
            return kvStore.fetchValue(Bool.self, forKey: Keys.isHidden, tx: tx) ?? false
        }

        func setIsHidden(_ value: Bool, tx: DBWriteTransaction) {
            kvStore.writeValue(value, forKey: Keys.isHidden, tx: tx)

            tx.addSyncCompletion {
                NotificationCenter.default.postOnMainThread(
                    name: .isHiddenDidChange,
                    object: nil,
                )
            }
        }
    }

    private struct State {
        var isVisible: Bool = false
        var deviceSleepBlock: DeviceSleepBlockObject?
        var currentViewState: LocalFileBackupExportProgressView.ViewState?

        var isHidden: Bool = false
        var hasCompletedBackup: Bool = false

        var lastExportJobProgressUpdate: OWSSequentialProgress<LocalFileBackupExportJobStage>??

        var updateStreamTasks: [Task<Void, Never>] = []
    }

    private let localFileBackupExportJobRunner: LocalFileBackupExportJobRunner
    private let localFileBackupStore: LocalFileBackupStore
    private let db: DB
    private let deviceSleepManager: DeviceSleepManager
    private let store: Store

    private let localFileBackupExportProgressView: LocalFileBackupExportProgressView
    private let state: AtomicValue<State>

    weak var chatListViewController: ChatListViewController?
    lazy var localFileBackupExportProgressViewCell: UITableViewCell = Self.tableViewCell(
        wrapping: localFileBackupExportProgressView,
    )

    init() {
        self.localFileBackupExportJobRunner = DependenciesBridge.shared.localFileBackupExportJobRunner
        self.localFileBackupStore = LocalFileBackupStore()
        self.db = DependenciesBridge.shared.db
        self.deviceSleepManager = DependenciesBridge.shared.deviceSleepManager.owsFailUnwrap("Missing DeviceSleepManager!")
        self.store = Store()

        self.localFileBackupExportProgressView = LocalFileBackupExportProgressView(viewState: nil)
        self.state = AtomicValue(State(), lock: .init())

        self.localFileBackupExportProgressView.delegate = self
    }

    fileprivate static func tableViewCell(wrapping progressView: LocalFileBackupExportProgressView) -> UITableViewCell {
        let cell = UITableViewCell()
        var backgroundConfiguration = UIBackgroundConfiguration.clear()
        backgroundConfiguration.backgroundColor = .Signal.background
        cell.backgroundConfiguration = backgroundConfiguration

        cell.contentView.addSubview(progressView)
        progressView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(hMargin: 12, vMargin: 12))
        return cell
    }

    // MARK: -

    var shouldBeVisible: Bool {
        return state.get().currentViewState != nil
    }

    // MARK: -

    @MainActor
    func willAppear() {
        state.update { _state in
            _state.isVisible = true
            manageDeviceSleepBlock(state: &_state)
        }
    }

    @MainActor
    func didDisappear() {
        state.update { _state in
            _state.isVisible = false
            manageDeviceSleepBlock(state: &_state)
        }
    }

    // MARK: -

    func startTracking() {
        let isHidden: Bool
        let hasCompletedBackup: Bool
        (isHidden, hasCompletedBackup) = db.read { tx in
            (
                store.isHidden(tx: tx),
                localFileBackupStore.lastBackupDetails(tx: tx) != nil,
            )
        }

        state.update { _state in
            guard _state.updateStreamTasks.isEmpty else { return }

            _state.isHidden = isHidden
            _state.hasCompletedBackup = hasCompletedBackup

            _state.updateStreamTasks = _startTracking()
        }
    }

    private func _startTracking() -> [Task<Void, Never>] {
        return [
            Task { @MainActor [weak self, localFileBackupExportJobRunner] in
                for await exportJobUpdate in localFileBackupExportJobRunner.updates() {
                    guard let self else { return }

                    state.update { _state in
                        switch exportJobUpdate {
                        case .progress(let progressUpdate):
                            _state.lastExportJobProgressUpdate = progressUpdate
                        case .completion(.success):
                            _state.lastExportJobProgressUpdate = .some(nil)
                            _state.hasCompletedBackup = true
                        case .completion(.failure):
                            _state.lastExportJobProgressUpdate = .some(nil)
                            _state.hasCompletedBackup = false
                        case nil:
                            _state.lastExportJobProgressUpdate = .some(nil)
                        }
                        self.setViewStateForState(state: &_state)
                    }
                }
            },
            Task { @MainActor [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .lastLocalBackupDetailsDidChange) {
                    guard let self else { return }

                    let hasCompletedBackup = db.read { tx in
                        self.localFileBackupStore.lastBackupDetails(tx: tx) != nil
                    }

                    state.update { _state in
                        _state.hasCompletedBackup = hasCompletedBackup
                        self.setViewStateForState(state: &_state)
                    }
                }
            },
            Task { @MainActor [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .isHiddenDidChange) {
                    guard let self else { return }

                    let isHidden = db.read { tx in
                        self.store.isHidden(tx: tx)
                    }

                    state.update { _state in
                        _state.isHidden = isHidden
                        self.setViewStateForState(state: &_state)
                    }
                }
            },
        ]
    }

    // MARK: -

    private let setViewStateTaskQueue = SerialTaskQueue()

    @MainActor
    private func setViewStateForState(state: inout State) {
        let oldViewState = state.currentViewState
        let newViewState = viewStateForState(state: state)
        state.currentViewState = newViewState
        manageDeviceSleepBlock(state: &state)

        setViewStateTaskQueue.enqueue { @MainActor [self] in
            if oldViewState != newViewState {
                localFileBackupExportProgressView.viewState = newViewState
            }

            if (oldViewState == nil) != (newViewState == nil) {
                // We're hiding/showing the view: reload the chat list.
                chatListViewController?.loadCoordinator.loadIfNecessary()
            } else if oldViewState?.id != newViewState?.id {
                // Our height may change when we change view states, so tell the
                // table view to recompute.
                chatListViewController?.tableView.recomputeRowHeights()
            }
        }
    }

    private func viewStateForState(state: State) -> LocalFileBackupExportProgressView.ViewState? {
        guard let lastExportJobProgressUpdate = state.lastExportJobProgressUpdate else {
            // Never show the view until we've received our initial update.
            return nil
        }

        if state.isHidden {
            return nil
        }

        if let progressUpdate = lastExportJobProgressUpdate {
            switch progressUpdate.currentStep {
            case .attachmentMetadataPrep:
                let percentComplete = progressUpdate.progress(for: .attachmentMetadataPrep)?.percentComplete ?? 0
                return .attachmentMetadataPrep(percentComplete: percentComplete)
            case .backupFileExport:
                let percentComplete = progressUpdate.progress(for: .backupFileExport)?.percentComplete ?? 0
                return .backupFileExport(percentComplete: percentComplete)
            case .attachmentCopy:
                let source = progressUpdate.descendantProgresses(withLabel: LocalFileBackupManager.ProgressLabel.writeQueuedAttachment).first
                let completedBytes = source?.completedUnitCount ?? 0
                let totalBytes = source?.totalUnitCount ?? 0
                return .attachmentCopy(
                    completedBytes: completedBytes,
                    totalBytes: totalBytes,
                )
            }
        }

        if state.hasCompletedBackup {
            return .complete
        }

        return nil
    }

    @MainActor
    private func manageDeviceSleepBlock(state: inout State) {
        var shouldBlockDeviceSleep = switch state.currentViewState {
        case .attachmentMetadataPrep: true
        case .backupFileExport: true
        case .attachmentCopy: true
        case .complete: false
        case nil: false
        }

        shouldBlockDeviceSleep = shouldBlockDeviceSleep && state.isVisible

        if
            shouldBlockDeviceSleep,
            state.deviceSleepBlock == nil
        {
            let deviceSleepBlock = DeviceSleepBlockObject(blockReason: "CLVLocalFileBackupExportProgressView")
            deviceSleepManager.addBlock(blockObject: deviceSleepBlock)
            state.deviceSleepBlock = deviceSleepBlock
        } else if
            !shouldBlockDeviceSleep,
            let deviceSleepBlock = state.deviceSleepBlock.take()
        {
            deviceSleepManager.removeBlock(blockObject: deviceSleepBlock)
        }
    }

    // MARK: - LocalFileBackupExportProgressView.Delegate

    func didTapDismissButton() {
        db.write { tx in
            store.setIsHidden(true, tx: tx)
        }
    }

    // MARK: -

    /// Actions to display in a context menu for the owning row in the table
    /// view.
    func contextMenuActions() -> [UIAction] {
        let hideAction = UIAction(
            title: OWSLocalizedString(
                "CHAT_LIST_BACKUP_PROGRESS_VIEW_HIDE_CONTEXT_MENU_ACTION",
                comment: "Title for the context menu action that hides the backup progress view.",
            ),
            image: .eyeSlash,
        ) { [self] _ in
            db.write { tx in
                store.setIsHidden(true, tx: tx)
            }
            chatListViewController?.presentToast(text: OWSLocalizedString(
                "CHAT_LIST_BACKUP_PROGRESS_VIEW_HIDE_TOAST",
                comment: "Toast shown after the user hides the backup progress view.",
            ))
        }

        let cancelAction = UIAction(
            title: OWSLocalizedString(
                "CHAT_LIST_BACKUP_PROGRESS_VIEW_CANCEL_BACKUP_CONTEXT_MENU_ACTION",
                comment: "Title for the context menu action that cancels the backup.",
            ),
            image: .xCircle,
        ) { [self] _ in
            let actionSheet = ActionSheetController(
                title: OWSLocalizedString(
                    "CHAT_LIST_BACKUP_PROGRESS_VIEW_BACKUP_CANCEL_CONFIRMATION_TITLE",
                    comment: "Title for the action sheet shown when the user tries to cancel a backup.",
                ),
                message: OWSLocalizedString(
                    "CHAT_LIST_BACKUP_PROGRESS_VIEW_BACKUP_CANCEL_CONFIRMATION_MESSAGE",
                    comment: "Message shown in an action sheet when the user tries to cancel a backup.",
                ),
            )
            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString(
                    "CHAT_LIST_BACKUP_PROGRESS_VIEW_CANCEL_BACKUP_BUTTON",
                    comment: "Button in the cancel backup action sheet that confirms cancellation.",
                ),
                handler: { [self] _ in
                    _ = localFileBackupExportJobRunner.cancelIfRunning()
                    chatListViewController?.presentToast(text: OWSLocalizedString(
                        "CHAT_LIST_BACKUP_PROGRESS_VIEW_BACKUP_CANCELED_TOAST",
                        comment: "Toast shown after the user cancels the backup.",
                    ))
                },
            ))
            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString(
                    "CHAT_LIST_BACKUP_PROGRESS_VIEW_CONTINUE_BACKUP_BUTTON",
                    comment: "Button in the cancel backup action sheet that dismisses the sheet and continues the backup.",
                ),
            ))
            chatListViewController?.presentActionSheet(actionSheet)
        }

        switch state.get().currentViewState {
        case nil:
            return []
        case .complete:
            return [hideAction]
        case .attachmentMetadataPrep,
             .backupFileExport,
             .attachmentCopy:
            return [hideAction, cancelAction]
        }
    }
}

// MARK: -

private class LocalFileBackupExportProgressView: ChatListBackupProgressView {

    protocol Delegate: AnyObject {
        func didTapDismissButton()
    }

    enum ViewState: Equatable, Identifiable {
        case attachmentMetadataPrep(percentComplete: Float)
        case backupFileExport(percentComplete: Float)
        case attachmentCopy(completedBytes: UInt64, totalBytes: UInt64)
        case complete

        var id: String {
            return switch self {
            case .attachmentMetadataPrep: "attachmentMetadataPrep"
            case .backupFileExport: "backupFileExport"
            case .attachmentCopy: "attachmentCopy"
            case .complete: "complete"
            }
        }
    }

    // MARK: -

    var viewState: ViewState? {
        didSet {
            configure(viewState: viewState)
        }
    }

    weak var delegate: Delegate?

    init(viewState: ViewState?) {
        self.viewState = viewState
        super.init()

        initializeTrailingAccessoryViews([
            trailingAccessoryRunningArcView,
            trailingAccessoryCompleteDismissButton,
        ])
        configure(viewState: viewState)
    }

    required init?(coder: NSCoder) {
        owsFail("Not implemented")
    }

    // MARK: - Views

    private lazy var trailingAccessoryRunningArcView: ArcView = {
        let arcView = ArcView()
        NSLayoutConstraint.activate([
            arcView.heightAnchor.constraint(equalToConstant: 24),
            arcView.widthAnchor.constraint(equalToConstant: 24),
        ])
        return arcView
    }()

    private lazy var trailingAccessoryCompleteDismissButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = .x
        configuration.baseForegroundColor = .Signal.secondaryLabel
        let button = UIButton(
            configuration: configuration,
            primaryAction: UIAction { [weak self] _ in
                self?.delegate?.didTapDismissButton()
            },
        )
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 24),
            button.widthAnchor.constraint(equalToConstant: 24),
        ])
        return button
    }()

    // MARK: -

    private func configure(viewState: ViewState?) {
        // Leading accessory
        let leadingAccessoryImage: UIImage
        let leadingAccessoryImageTintColor: UIColor
        switch viewState {
        case nil,
             .attachmentMetadataPrep,
             .backupFileExport,
             .attachmentCopy:
            leadingAccessoryImage = .backup
            leadingAccessoryImageTintColor = .Signal.label
        case .complete:
            leadingAccessoryImage = .checkCircle
            leadingAccessoryImageTintColor = .Signal.ultramarine
        }

        // Labels
        let titleLabelText: String
        var progressLabelText: String?
        switch viewState {
        case .attachmentMetadataPrep(let percentComplete):
            titleLabelText = OWSLocalizedString(
                "CHAT_LIST_LOCAL_FILE_BACKUPS_PROGRESS_PREPARING_ATTACHMENTS",
                comment: "Title label shown in the chat list local file backup progress view while the attachments are being prepared",
            )
            progressLabelText = percentComplete.formatted(.owsPercent())
        case .backupFileExport(let percentComplete):
            titleLabelText = OWSLocalizedString(
                "CHAT_LIST_LOCAL_FILE_BACKUPS_PROGRESS_PREPARING_BACKUP",
                comment: "Title label shown in the chat list local file backup progress view while the backup file is being prepared.",
            )
            progressLabelText = percentComplete.formatted(.owsPercent())
        case .attachmentCopy(let completedBytes, let totalBytes):
            titleLabelText = OWSLocalizedString(
                "CHAT_LIST_LOCAL_FILE_BACKUPS_PROGRESS_COPYING_ATTACHMENTS_TITLE",
                comment: "Title label shown in the chat list backup progress view while backup attachments are being uploaded.",
            )
            progressLabelText = String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "CHAT_LIST_LOCAL_FILE_BACKUPS_PROGRESS_COPYING_ATTACHMENTS_FORMAT",
                    comment: "Progress label showing the amount uploaded out of the total. Embeds {{ %1$@ bytes uploaded, %2$@ total bytes to upload }}.",
                ),
                completedBytes.formatted(.owsByteCount()),
                totalBytes.formatted(.owsByteCount()),
            )
        case .complete:
            titleLabelText = OWSLocalizedString(
                "CHAT_LIST_BACKUP_PROGRESS_VIEW_BACKUP_COMPLETE_TITLE",
                comment: "Title label shown in the chat list backup progress view when the backup is complete.",
            )
        case nil:
            titleLabelText = ""
        }

        // Trailing accessory
        let trailingAccessoryView: UIView?
        switch viewState {
        case .attachmentMetadataPrep(let percentComplete):
            trailingAccessoryRunningArcView.percentComplete = percentComplete
            trailingAccessoryView = trailingAccessoryRunningArcView
        case .backupFileExport(let percentComplete):
            trailingAccessoryRunningArcView.percentComplete = percentComplete
            trailingAccessoryView = trailingAccessoryRunningArcView
        case .attachmentCopy(let completedBytes, let totalBytes):
            let percent: Float = totalBytes > 0 ? Float(completedBytes) / Float(totalBytes) : 0
            trailingAccessoryRunningArcView.percentComplete = percent
            trailingAccessoryView = trailingAccessoryRunningArcView
        case .complete:
            trailingAccessoryView = trailingAccessoryCompleteDismissButton
        case nil:
            trailingAccessoryView = nil
        }

        configure(
            leadingAccessoryImage: leadingAccessoryImage,
            leadingAccessoryImageTintColor: leadingAccessoryImageTintColor,
            titleLabelText: titleLabelText,
            progressLabelText: progressLabelText,
            trailingAccessoryView: trailingAccessoryView,
        )
    }
}
