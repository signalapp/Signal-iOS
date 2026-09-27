//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PureLayout
import SignalServiceKit
import SignalUI
import UIKit

public class CLVLocalFileBackupRestoreProgressView: LocalFileBackupRestoreProgressView.Delegate {

    private struct State {
        var isVisible: Bool = false
        var deviceSleepBlock: DeviceSleepBlockObject?
        var completeBannerByteCount: UInt64?

        var latestProgress: OWSProgress?
        var currentViewState: LocalFileBackupRestoreProgressView.ViewState?
    }

    private let state: AtomicValue<State>

    public weak var chatListViewController: ChatListViewController?
    private let localFileBackupRestoreProgressView: LocalFileBackupRestoreProgressView

    private let localFileBackupAttachmentRestoreProgress: LocalFileBackupAttachmentRestoreProgress
    private let deviceSleepManager: DeviceSleepManager
    private var observer: LocalFileBackupAttachmentRestoreProgressObserver?

    init() {
        AssertIsOnMainThread()

        guard let deviceSleepManager = DependenciesBridge.shared.deviceSleepManager else {
            owsFail("Unexpectedly missing device sleep manager in main app!")
        }

        self.state = AtomicValue(State(), lock: .init())
        self.localFileBackupAttachmentRestoreProgress = DependenciesBridge.shared.localFileBackupAttachmentRestoreProgress
        self.deviceSleepManager = deviceSleepManager
        self.localFileBackupRestoreProgressView = LocalFileBackupRestoreProgressView(viewState: nil)
        self.localFileBackupRestoreProgressView.delegate = self
    }

    lazy var localFileBackupRestoreProgressViewCell: UITableViewCell = Self.tableViewCell(
        wrapping: localFileBackupRestoreProgressView,
    )

    fileprivate static func tableViewCell(wrapping progressView: LocalFileBackupRestoreProgressView) -> UITableViewCell {
        let cell = UITableViewCell()
        var backgroundConfiguration = UIBackgroundConfiguration.clear()
        backgroundConfiguration.backgroundColor = .Signal.background
        cell.backgroundConfiguration = backgroundConfiguration

        cell.contentView.addSubview(progressView)
        progressView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(hMargin: 12, vMargin: 12))
        return cell
    }

    var shouldBeVisible: Bool {
        return state.get().currentViewState != nil
    }

    // MARK: -

    @MainActor
    func startTracking() {
        let observer = localFileBackupAttachmentRestoreProgress.addObserver { [weak self] progress in
            Task { @MainActor in
                self?.onProgress(progress)
            }
        }
        self.observer = observer
    }

    @MainActor
    private func onProgress(_ progress: OWSProgress) {
        state.update {
            $0.latestProgress = progress
            updateViewState(state: &$0)
        }
    }

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

    private let updateViewStateTaskQueue = SerialTaskQueue()

    @MainActor
    private func updateViewState(state: inout State) {
        let oldViewState = state.currentViewState
        let newViewState = viewStateForRestoreState(state: state)
        state.currentViewState = newViewState

        updateViewStateTaskQueue.enqueue { @MainActor [self] in
            if oldViewState != newViewState {
                localFileBackupRestoreProgressView.viewState = newViewState
            }

            if (oldViewState == nil) != (newViewState == nil) {
                // We're hiding/showing the view: reload the chat list.
                chatListViewController?.loadCoordinator.loadIfNecessary()
            } else if oldViewState?.id != newViewState?.id {
                chatListViewController?.tableView.recomputeRowHeights()
            }
        }

        manageDeviceSleepBlock(state: &state)
    }

    private func viewStateForRestoreState(state: State) -> LocalFileBackupRestoreProgressView.ViewState? {
        guard
            let progress = state.latestProgress,
            progress.totalUnitCount > 0,
            state.isVisible
        else {
            return nil
        }

        if progress.isFinished {
            return .complete(size: state.latestProgress?.totalUnitCount ?? 0)
        }

        return .restoring(
            bytesRestored: progress.completedUnitCount,
            totalBytesToRestore: progress.totalUnitCount,
            percentComplete: progress.percentComplete,
        )
    }

    @MainActor
    private func manageDeviceSleepBlock(state: inout State) {
        let shouldBlockDeviceSleep = state.currentViewState != nil && state.isVisible

        if
            shouldBlockDeviceSleep,
            state.deviceSleepBlock == nil
        {
            let deviceSleepBlock = DeviceSleepBlockObject(blockReason: "CLVLocalFileBackupRestoreProgressView")
            deviceSleepManager.addBlock(blockObject: deviceSleepBlock)
            state.deviceSleepBlock = deviceSleepBlock
        } else if
            !shouldBlockDeviceSleep,
            let deviceSleepBlock = state.deviceSleepBlock.take()
        {
            deviceSleepManager.removeBlock(blockObject: deviceSleepBlock)
        }
    }

    @MainActor
    func didTapDismiss() {
        state.update {
            $0.isVisible = false
            updateViewState(state: &$0)
        }
    }
}

// MARK: -

private class LocalFileBackupRestoreProgressView: ChatListBackupProgressView {
    protocol Delegate: AnyObject {
        @MainActor
        func didTapDismiss()
    }

    enum ViewState: Equatable, Identifiable {
        case restoring(
            bytesRestored: UInt64,
            totalBytesToRestore: UInt64,
            percentComplete: Float,
        )
        case complete(size: UInt64)

        var id: String {
            switch self {
            case .restoring: "restoring"
            case .complete: "complete"
            }
        }
    }

    weak var delegate: Delegate?

    var viewState: ViewState? {
        didSet { configure(viewState: viewState) }
    }

    init(viewState: ViewState?) {
        self.viewState = viewState
        super.init()

        initializeTrailingAccessoryViews([
            trailingAccessoryArcView,
            trailingAccessoryCompleteDismissButton,
        ])
        configure(viewState: viewState)
    }

    required init?(coder: NSCoder) {
        owsFail("Not implemented")
    }

    // MARK: - Views

    private lazy var trailingAccessoryArcView: ArcView = {
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
                self?.delegate?.didTapDismiss()
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
        let titleLabelText: String
        var progressLabelText: String?
        let trailingAccessoryView: UIView?

        switch viewState {
        case .restoring(let bytesRestored, let totalBytesToRestore, let percentComplete):
            titleLabelText = OWSLocalizedString(
                "CHAT_LIST_LOCAL_FILE_BACKUP_RESTORE_PROGRESS_VIEW_TITLE",
                comment: "Title shown on the chat list banner while restoring attachments from an on-device backup.",
            )
            progressLabelText = String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "CHAT_LIST_LOCAL_FILE_BACKUP_RESTORE_PROGRESS_VIEW_PROGRESS_FORMAT",
                    comment: "Progress label showing bytes restored from an on-device backup. Embeds {{ %1$@ formatted bytes restored, %2$@ formatted total bytes to restore }}.",
                ),
                bytesRestored.formatted(.owsByteCount()),
                totalBytesToRestore.formatted(.owsByteCount()),
            )
            trailingAccessoryArcView.percentComplete = percentComplete
            trailingAccessoryView = trailingAccessoryArcView
        case .complete(let size):
            titleLabelText = OWSLocalizedString(
                "CHAT_LIST_LOCAL_FILE_BACKUP_RESTORE_FINISHED_TITLE",
                comment: "Title shown on chat list banner for restoring media from a backup is finished",
            )
            progressLabelText = OWSByteCountFormatStyle().format(size)
            trailingAccessoryView = trailingAccessoryCompleteDismissButton
        case nil:
            titleLabelText = ""
            progressLabelText = nil
            trailingAccessoryView = nil
        }

        configure(
            leadingAccessoryImage: .backup,
            leadingAccessoryImageTintColor: .Signal.label,
            titleLabelText: titleLabelText,
            progressLabelText: progressLabelText,
            trailingAccessoryView: trailingAccessoryView,
        )
    }
}
