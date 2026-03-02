//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

public class CLVBackupDownloadProgressView: BackupDownloadProgressView.Delegate {

    private struct State {
        var isVisible: Bool = false
        var didDismissDownloadBanner: Bool = false
        var downloadCompleteBannerByteCount: UInt64?
        var deviceSleepBlock: DeviceSleepBlockObject?

        var latestDownloadUpdate: BackupAttachmentDownloadTracker.DownloadUpdate?
        var currentViewState: BackupDownloadProgressView.ViewState?
    }

    private let state: AtomicValue<State>

    public weak var chatListViewController: ChatListViewController?
    private let backupDownloadProgressView: BackupDownloadProgressView

    private let backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager
    private let backupAttachmentDownloadTracker: BackupAttachmentDownloadTracker
    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB
    private let deviceSleepManager: DeviceSleepManager

    init() {
        AssertIsOnMainThread()

        guard let deviceSleepManager = DependenciesBridge.shared.deviceSleepManager else {
            owsFail("Unexpectedly missing device sleep manager in main app!")
        }

        state = AtomicValue(State(), lock: .init())

        self.backupAttachmentDownloadQueueStatusManager = DependenciesBridge.shared.backupAttachmentDownloadQueueStatusManager
        self.backupAttachmentDownloadTracker = AppEnvironment.shared.backupAttachmentDownloadTracker
        self.backupAttachmentDownloadStore = DependenciesBridge.shared.backupAttachmentDownloadStore
        self.backupSettingsStore = BackupSettingsStore()
        self.db = DependenciesBridge.shared.db
        self.deviceSleepManager = deviceSleepManager

        backupDownloadProgressView = BackupDownloadProgressView(viewState: nil)
        backupDownloadProgressView.delegate = self
    }

    lazy var backupDownloadProgressViewCell: UITableViewCell = Self.tableViewCell(
        wrapping: backupDownloadProgressView,
    )

    fileprivate static func tableViewCell(wrapping backupProgressView: BackupDownloadProgressView) -> UITableViewCell {
        let cell = UITableViewCell()
        var backgroundConfiguration = UIBackgroundConfiguration.clear()
        backgroundConfiguration.backgroundColor = .Signal.background
        cell.backgroundConfiguration = backgroundConfiguration

        cell.contentView.addSubview(backupProgressView)
        backupProgressView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(hMargin: 12, vMargin: 12))
        return cell
    }

    var shouldBeVisible: Bool {
        return state.get().currentViewState != nil
    }

    // MARK: -

    @MainActor
    func startTracking() {
        Task { [weak self, backupAttachmentDownloadTracker] in
            for await downloadUpdate in backupAttachmentDownloadTracker.updates() {
                guard let self else { return }
                onDownloadUpdate(downloadUpdate)
            }
        }
    }

    @MainActor
    private func onDownloadUpdate(_ downloadUpdate: BackupAttachmentDownloadTracker.DownloadUpdate) {
        let downloadUpdateStateChanged = state.update {
            let oldLatestDownloadUpdate = $0.latestDownloadUpdate
            $0.latestDownloadUpdate = downloadUpdate

            return oldLatestDownloadUpdate?.state != downloadUpdate.state
        }

        if downloadUpdateStateChanged {
            // On our first update, and any subsequent time the state of
            // downloads changes, reload our ancillary data. This helps
            // us ensure we show the right view state when the queue is
            // empty while avoiding runaway DB reads.
            loadAncillaryBannerState()
        }

        state.update {
            updateViewState(state: &$0)
        }
    }

    private func loadAncillaryBannerState() {
        db.read { tx in
            let didDismissDownloadBanner = backupAttachmentDownloadStore.getDidDismissDownloadCompleteBanner(tx: tx)
            let downloadCompleteBannerByteCount = backupAttachmentDownloadStore.getDownloadCompleteBannerByteCount(tx: tx)

            state.update {
                $0.didDismissDownloadBanner = didDismissDownloadBanner
                $0.downloadCompleteBannerByteCount = downloadCompleteBannerByteCount
            }
        }
    }

    // MARK: -

    private let updateViewStateTaskQueue = SerialTaskQueue()

    @MainActor
    private func updateViewState(state: inout State) {
        let oldViewState = state.currentViewState
        let newViewState = downloadProgressViewState(state: state)
        state.currentViewState = newViewState

        updateViewStateTaskQueue.enqueue { @MainActor [self] in
            if oldViewState != newViewState {
                backupDownloadProgressView.viewState = newViewState
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

        manageDeviceSleepBlock(state: &state)
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

    @MainActor
    private func manageDeviceSleepBlock(state: inout State) {
        switch state.currentViewState {
        case nil, .complete:
            if let deviceSleepBlock = state.deviceSleepBlock.take() {
                deviceSleepManager.removeBlock(blockObject: deviceSleepBlock)
            }
        case .restoring, .wifiNotReachable, .paused, .outOfDiskSpace:
            if state.deviceSleepBlock == nil {
                let deviceSleepBlock = DeviceSleepBlockObject(blockReason: "CLVBackupDownloadProgressView")
                state.deviceSleepBlock = deviceSleepBlock
                deviceSleepManager.addBlock(blockObject: deviceSleepBlock)
            }
        }
    }

    // MARK: - BackupDownloadProgressView.Delegate

    @MainActor
    func didTapDismiss() {
        db.write { tx in
            self.backupAttachmentDownloadStore.setDidDismissDownloadCompleteBanner(tx: tx)
        }

        // Reload state and update the view, so we learn that the banner is now
        // dismissed.
        loadAncillaryBannerState()

        state.update {
            updateViewState(state: &$0)
        }
    }

    @MainActor
    func didTapResume() {
        db.write { tx in
            backupSettingsStore.setShouldAllowBackupDownloadsOnCellular(true, tx: tx)
        }
    }

    @MainActor
    func didTapOutOfDiskSpaceDetails() {
        guard case .outOfDiskSpace(let spaceRequired) = backupDownloadProgressView.viewState else {
            return
        }
        let spaceRequiredString = OWSByteCountFormatStyle().format(spaceRequired)
        var sheet: HeroSheetViewController?
        sheet = HeroSheetViewController(
            hero: .circleIcon(
                icon: .backupErrorDisplayBold,
                iconSize: 40,
                tintColor: UIColor.Signal.orange,
                backgroundColor: UIColor.color(rgbHex: 0xF9E4B6),
            ),
            title: String(
                format: OWSLocalizedString(
                    "RESTORING_MEDIA_DISK_SPACE_SHEET_TITLE_FORMAT",
                    comment: "Title shown on a bottom sheet for restoring media from a backup when paused because the device has insufficient disk space. Embeds {{ %@ formatted number of bytes downloaded, e.g. '100 MB' }}",
                ),
                spaceRequiredString,
            ),
            body: String(
                format: OWSLocalizedString(
                    "RESTORING_MEDIA_DISK_SPACE_SHEET_SUBTITLE_FORMAT",
                    comment: "Subtitle shown on a bottom sheet for restoring media from a backup when paused because the device has insufficient disk space. Embeds {{ %@ formatted number of bytes downloaded, e.g. '100 MB' }}",
                ),
                spaceRequiredString,
            ),
            primaryButton: .init(
                title: OWSLocalizedString(
                    "ALERT_ACTION_ACKNOWLEDGE",
                    comment: "generic button text to acknowledge that the corresponding text was read.",
                ),
                action: { [self] sheet in
                    self.backupAttachmentDownloadQueueStatusManager.checkAvailableDiskSpace(
                        clearPreviousOutOfSpaceErrors: true,
                    )
                    sheet.dismiss(animated: true)
                },
            ),
            secondaryButton: .init(
                title: OWSLocalizedString(
                    "RESTORING_MEDIA_DISK_SPACE_SHEET_SKIP_BUTTON",
                    comment: "Button to skip restoring media, shown on a bottom sheet for restoring media from a backup when paused because the device has insufficient disk space.",
                ),
                style: .secondary,
                action: .custom({ [weak self] sheet in
                    sheet.dismiss(animated: true) {
                        self?.presentSkipRestoreSheet()
                    }
                }),
            ),
        )
        CurrentAppContext().frontmostViewController()?.present(sheet!, animated: true)
    }

    private func presentSkipRestoreSheet() {
        let backupPlan = db.read { tx in
            backupSettingsStore.backupPlan(tx: tx)
        }

        let message: String = switch backupPlan {
        case .disabled, .disabling, .free, .paid, .paidAsTester:
            OWSLocalizedString(
                "RESTORING_MEDIA_DISK_SPACE_SKIP_SHEET_MESSAGE",
                comment: "Message shown on a bottom sheet to skip restoring media from a backup when paused because the device has insufficient disk space.",
            )
        case .paidExpiringSoon:
            OWSLocalizedString(
                "RESTORING_MEDIA_DISK_SPACE_SKIP_PAID_EXPIRING_SOON_SHEET_MESSAGE",
                comment: "Message shown on a bottom sheet to skip restoring media from a backup when paused because the device has insufficient disk space, and the user's paid subscription is expiring.",
            )
        }

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "RESTORING_MEDIA_DISK_SPACE_SKIP_SHEET_TITLE",
                comment: "Title shown on a bottom sheet to skip restoring media from a backup when paused because the device has insufficient disk space.",
            ),
            message: message,
        )
        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "RESTORING_MEDIA_DISK_SPACE_SKIP_SHEET_SKIP_BUTTON",
                comment: "Button shown on a bottom sheet to skip restoring media from a backup when paused because the device has insufficient disk space.",
            ),
            style: .destructive,
            handler: { [weak self] _ in
                guard let self else { return }

                db.write { tx in
                    self.backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)
                }
            },
        ))
        actionSheet.addAction(.init(
            title: CommonStrings.learnMore,
            style: .default,
            handler: { _ in
                CurrentAppContext().open(
                    URL.Support.backups,
                    completion: nil,
                )
            },
        ))
        actionSheet.addAction(.init(
            title: CommonStrings.cancelButton,
            style: .cancel,
        ))
        CurrentAppContext().frontmostViewController()?.presentActionSheet(actionSheet)
    }

    // MARK: -

    private func downloadProgressViewState(state: State) -> BackupDownloadProgressView.ViewState? {
        guard let latestDownloadUpdate = state.latestDownloadUpdate else {
            return nil
        }

        switch latestDownloadUpdate.state {
        case .suspended, .notRegisteredAndReady:
            return nil
        case .empty:
            if
                !state.didDismissDownloadBanner,
                let byteCount = state.downloadCompleteBannerByteCount
            {
                return .complete(size: byteCount)
            } else {
                return nil
            }
        case .running:
            return .restoring(
                bytesDownloaded: latestDownloadUpdate.bytesDownloaded,
                totalBytesToDownload: latestDownloadUpdate.totalBytesToDownload,
                percentageDownloaded: latestDownloadUpdate.percentageDownloaded,
            )
        case .pausedLowBattery:
            return .paused(reason: .lowBattery)
        case .pausedLowPowerMode:
            return .paused(reason: .lowPowerMode)
        case .pausedNeedsWifi:
            return .wifiNotReachable
        case .pausedNeedsInternet:
            return .paused(reason: .notReachable)
        case .outOfDiskSpace(let bytesRequired):
            return .outOfDiskSpace(spaceRequired: bytesRequired)
        }
    }
}

// MARK: -

extension ChatListViewController {
    func handleBackupDownloadProgressViewTapped() {
        let db = DependenciesBridge.shared.db
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        let isPrimaryDevice = db.read { tx in
            tsAccountManager.registrationState(tx: tx).isPrimaryDevice ?? false
        }

        if isPrimaryDevice {
            showAppSettings(mode: .backups())
        } else {
            showCancelBackupDownloadsHeroSheet()
        }
    }

    private func showCancelBackupDownloadsHeroSheet() {
        let cancelDownloadsSheet = HeroSheetViewController(
            hero: .image(.backupsLogo),
            title: OWSLocalizedString(
                "RESTORING_MEDIA_BANNER_CANCEL_RESTORE_SHEET_1_TITLE",
                comment: "Title for a sheet allowing users to cancel an in-progress media restore.",
            ),
            body: OWSLocalizedString(
                "RESTORING_MEDIA_BANNER_CANCEL_RESTORE_SHEET_1_BODY",
                comment: "Body for a sheet allowing users to cancel an in-progress media restore.",
            ),
            primaryButton: .dismissing(title: OWSLocalizedString(
                "RESTORING_MEDIA_BANNER_CANCEL_RESTORE_SHEET_1_PRIMARY_BUTTON",
                comment: "Button for a sheet allowing users to cancel an in-progress media restore.",
            )),
            secondaryButton: HeroSheetViewController.Button(
                title: OWSLocalizedString(
                    "RESTORING_MEDIA_BANNER_CANCEL_RESTORE_SHEET_1_SECONDARY_BUTTON",
                    comment: "Button for a sheet allowing users to cancel an in-progress media restore.",
                ),
                style: .secondaryDestructive,
                action: .custom({ sheet in
                    sheet.dismiss(animated: true) { [weak self] in
                        self?.showCancelBackupDownloadsConfirmationActionSheet()
                    }
                }),
            ),
        )

        present(cancelDownloadsSheet, animated: true)
    }

    private func showCancelBackupDownloadsConfirmationActionSheet() {
        let backupSettingsStore = BackupSettingsStore()
        let db = DependenciesBridge.shared.db

        let confirmationActionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "RESTORING_MEDIA_BANNER_CANCEL_RESTORE_SHEET_2_TITLE",
                comment: "Title for a sheet allowing users to cancel an in-progress media restore.",
            ),
            message: OWSLocalizedString(
                "RESTORING_MEDIA_BANNER_CANCEL_RESTORE_SHEET_2_MESSAGE",
                comment: "Message for a sheet allowing users to cancel an in-progress media restore.",
            ),
        )
        confirmationActionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "RESTORING_MEDIA_BANNER_CANCEL_RESTORE_SHEET_2_PRIMARY_BUTTON",
                comment: "Button for a sheet allowing users to cancel an in-progress media restore.",
            ),
            style: .default,
        ))
        confirmationActionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "RESTORING_MEDIA_BANNER_CANCEL_RESTORE_SHEET_2_SECONDARY_BUTTON",
                comment: "Button for a sheet allowing users to cancel an in-progress media restore.",
            ),
            style: .destructive,
            handler: { _ in
                db.write { tx in
                    backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)
                }
            },
        ))

        confirmationActionSheet.isCancelable = true
        presentActionSheet(confirmationActionSheet)
    }
}

// MARK: -

private class BackupDownloadProgressView: ChatListBackupProgressView {

    protocol Delegate: AnyObject {
        @MainActor
        func didTapDismiss()
        @MainActor
        func didTapOutOfDiskSpaceDetails()
        @MainActor
        func didTapResume()
    }

    enum ViewState: Equatable, Identifiable {
        case restoring(
            bytesDownloaded: UInt64,
            totalBytesToDownload: UInt64,
            percentageDownloaded: Float,
        )
        case wifiNotReachable
        case paused(reason: PauseReason)
        case outOfDiskSpace(spaceRequired: UInt64)
        case complete(size: UInt64)

        enum PauseReason: Equatable {
            case notReachable
            case lowBattery
            case lowPowerMode
        }

        var id: String {
            return switch self {
            case .restoring: "restoring"
            case .wifiNotReachable: "wifiNotReachable"
            case .paused(let reason): switch reason {
                case .notReachable: "paused.notReachable"
                case .lowBattery: "paused.lowBattery"
                case .lowPowerMode: "paused.lowPowerMode"
                }
            case .outOfDiskSpace: "outOfDiskSpace"
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
            trailingAccessoryWifiResumeButton,
            trailingAccessoryPausedNoInternetLabel,
            trailingAccessoryPausedLowBatteryLabel,
            trailingAccessoryPausedLowPowerModeLabel,
            trailingAccessoryOutOfDiskSpaceDetailsButton,
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

    private lazy var trailingAccessoryWifiResumeButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = OWSLocalizedString(
            "RESTORING_MEDIA_BANNER_RESUME_WITHOUT_WIFI_BUTTON",
            comment: "Button title shown on chat list banner for restoring media from a backup when paused because the device needs WiFi to continue, to resume downloads without WiFi.",
        )
        configuration.baseForegroundColor = .Signal.label
        configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeSubheadline.semibold())
        return UIButton(
            configuration: configuration,
            primaryAction: UIAction { [weak self] _ in
                self?.delegate?.didTapResume()
            },
        )
    }()

    private lazy var trailingAccessoryPausedNoInternetLabel: UILabel = {
        let label = UILabel()
        Self.configure(label: label, color: .Signal.secondaryLabel)
        label.text = OWSLocalizedString(
            "RESTORING_MEDIA_BANNER_PAUSED_NOT_REACHABLE_SUBTITLE",
            comment: "Subtitle shown on chat list banner for restoring media from a backup when paused because the device has no internet connection",
        )
        return label
    }()

    private lazy var trailingAccessoryPausedLowBatteryLabel: UILabel = {
        let label = UILabel()
        Self.configure(label: label, color: .Signal.secondaryLabel)
        label.text = OWSLocalizedString(
            "RESTORING_MEDIA_BANNER_PAUSED_BATTERY_SUBTITLE",
            comment: "Subtitle shown on chat list banner for restoring media from a backup when paused because the device has low battery",
        )
        return label
    }()

    private lazy var trailingAccessoryPausedLowPowerModeLabel: UILabel = {
        let label = UILabel()
        Self.configure(label: label, color: .Signal.secondaryLabel)
        label.text = OWSLocalizedString(
            "RESTORING_MEDIA_BANNER_PAUSED_LOW_POWER_MODE_SUBTITLE",
            comment: "Subtitle shown on chat list banner for restoring media from a backup when paused because the device is in low power mode",
        )
        return label
    }()

    private lazy var trailingAccessoryOutOfDiskSpaceDetailsButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = OWSLocalizedString(
            "RESTORING_MEDIA_BANNER_DISK_SPACE_BUTTON",
            comment: "Button title shown on chat list banner for restoring media from a backup when paused because the device has insufficient disk space, to see a bottom sheet with more details about next steps.",
        )
        configuration.baseForegroundColor = .Signal.label
        configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeSubheadline.semibold())
        return UIButton(
            configuration: configuration,
            primaryAction: UIAction { [weak self] _ in
                self?.delegate?.didTapOutOfDiskSpaceDetails()
            },
        )
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
        // Leading accessory
        let leadingAccessoryImage: UIImage
        let leadingAccessoryImageTintColor: UIColor
        switch viewState {
        case nil,
             .restoring,
             .wifiNotReachable,
             .paused:
            leadingAccessoryImage = .backup
            leadingAccessoryImageTintColor = .Signal.label
        case .outOfDiskSpace:
            leadingAccessoryImage = UIImage(named: "backup-error-bold")!
            leadingAccessoryImageTintColor = .Signal.orange
        case .complete:
            leadingAccessoryImage = .checkCircle
            leadingAccessoryImageTintColor = .Signal.ultramarine
        }

        // Labels
        let titleLabelText: String
        var progressLabelText: String?
        switch viewState {
        case .restoring(let bytesDownloaded, let totalBytesToDownload, _):
            titleLabelText = OWSLocalizedString(
                "RESTORING_MEDIA_BANNER_TITLE",
                comment: "Title shown on chat list banner for restoring media from a backup",
            )
            progressLabelText = String(
                format: OWSLocalizedString(
                    "RESTORING_MEDIA_BANNER_PROGRESS_FORMAT",
                    comment: "Download progress for media from a backup. Embeds {{ %1$@ formatted number of bytes downloaded, e.g. '100 MB', %2$@ formatted total number of bytes to download, e.g. '3 GB' }}",
                ),
                OWSByteCountFormatStyle().format(bytesDownloaded),
                OWSByteCountFormatStyle().format(totalBytesToDownload),
            )
        case .wifiNotReachable:
            titleLabelText = OWSLocalizedString(
                "RESTORING_MEDIA_BANNER_WAITING_FOR_WIFI_TITLE",
                comment: "Title shown on chat list banner for restoring media from a backup when waiting for wifi",
            )
        case .paused:
            titleLabelText = OWSLocalizedString(
                "RESTORING_MEDIA_BANNER_PAUSED_TITLE",
                comment: "Title shown on chat list banner for restoring media from a backup when paused for some reason",
            )
        case .outOfDiskSpace(let spaceRequired):
            titleLabelText = String(
                format: OWSLocalizedString(
                    "RESTORING_MEDIA_BANNER_DISK_SPACE_TITLE_FORMAT",
                    comment: "Title shown on chat list banner for restoring media from a backup when paused because the device has insufficient disk space. Embeds {{ %@ formatted number of bytes downloaded, e.g. '100 MB' }}",
                ),
                OWSByteCountFormatStyle().format(spaceRequired),
            )
        case .complete(let size):
            titleLabelText = OWSLocalizedString(
                "RESTORING_MEDIA_BANNER_FINISHED_TITLE",
                comment: "Title shown on chat list banner for restoring media from a backup is finished",
            )
            progressLabelText = OWSByteCountFormatStyle().format(size)
        case nil:
            titleLabelText = ""
        }

        // Trailing accessory
        let trailingAccessoryView: UIView?
        switch viewState {
        case .restoring(_, _, let percentageDownloaded):
            trailingAccessoryRunningArcView.percentComplete = percentageDownloaded
            trailingAccessoryView = trailingAccessoryRunningArcView
        case .wifiNotReachable:
            trailingAccessoryView = trailingAccessoryWifiResumeButton
        case .paused(let reason):
            switch reason {
            case .notReachable:
                trailingAccessoryView = trailingAccessoryPausedNoInternetLabel
            case .lowBattery:
                trailingAccessoryView = trailingAccessoryPausedLowBatteryLabel
            case .lowPowerMode:
                trailingAccessoryView = trailingAccessoryPausedLowPowerModeLabel
            }
        case .outOfDiskSpace:
            trailingAccessoryView = trailingAccessoryOutOfDiskSpaceDetailsButton
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

// MARK: -

#if DEBUG

private class BackupDownloadProgressPreviewViewController: TablePreviewViewController {
    init(viewState: BackupDownloadProgressView.ViewState?) {
        super.init { _ -> [UITableViewCell] in
            return [
                CLVBackupDownloadProgressView.tableViewCell(wrapping: BackupDownloadProgressView(
                    viewState: viewState,
                )),
                {
                    let cell = UITableViewCell()
                    var content = cell.defaultContentConfiguration()
                    content.text = "Imagine this is a ChatListCell :)"
                    cell.contentConfiguration = content
                    return cell
                }(),
            ]
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

@available(iOS 17, *)
#Preview("Restoring") {
    return BackupDownloadProgressPreviewViewController(viewState: .restoring(
        bytesDownloaded: 1_000_000_000,
        totalBytesToDownload: 2_400_000_000,
        percentageDownloaded: 1 / 2.4,
    ))
}

@available(iOS 17, *)
#Preview("Waiting for WiFi") {
    return BackupDownloadProgressPreviewViewController(viewState: .wifiNotReachable)
}

@available(iOS 17, *)
#Preview("Paused: No Internet") {
    return BackupDownloadProgressPreviewViewController(viewState: .paused(reason: .notReachable))
}

@available(iOS 17, *)
#Preview("Paused: Low Battery") {
    return BackupDownloadProgressPreviewViewController(viewState: .paused(reason: .lowBattery))
}

@available(iOS 17, *)
#Preview("Paused: Low Power Mode") {
    return BackupDownloadProgressPreviewViewController(viewState: .paused(reason: .lowPowerMode))
}

@available(iOS 17, *)
#Preview("Out of Disk Space") {
    return BackupDownloadProgressPreviewViewController(viewState: .outOfDiskSpace(spaceRequired: 5_000_000_000))
}

@available(iOS 17, *)
#Preview("Complete") {
    return BackupDownloadProgressPreviewViewController(viewState: .complete(size: 2_400_000_000))
}

@available(iOS 17, *)
#Preview("Nil") {
    return BackupDownloadProgressPreviewViewController(viewState: nil)
}

#endif
