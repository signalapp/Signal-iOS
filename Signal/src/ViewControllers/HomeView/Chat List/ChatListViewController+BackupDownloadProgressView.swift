//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
public import SignalServiceKit
import SignalUI

public class CLVBackupDownloadProgressView {

    public class State {
        var downloadQueueStatus: BackupAttachmentDownloadQueueStatus?
        var backupPlan: BackupPlan?
        var didDismissDownloadCompleteBanner: Bool?
        var totalPendingBackupAttachmentDownloadByteCount: UInt64?
        var downloadProgress: OWSProgress?
        var downloadProgressObserver: BackupAttachmentDownloadProgress.Observer?

        private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore

        init() {
            self.backupAttachmentDownloadStore = DependenciesBridge.shared.backupAttachmentDownloadStore
        }

        func refetchDBState(tx: DBReadTransaction) {
            self.backupPlan = BackupSettingsStore().backupPlan(tx: tx)
            self.didDismissDownloadCompleteBanner = backupAttachmentDownloadStore
                .getDidDismissDownloadCompleteBanner(tx: tx)
            self.totalPendingBackupAttachmentDownloadByteCount =
                try? backupAttachmentDownloadStore.computeEstimatedRemainingByteCount(tx: tx)

        }
    }

    public let backupDownloadProgressViewCell = UITableViewCell()

    fileprivate let backupAttachmentDownloadProgressView: BackupAttachmentDownloadProgressView

    public weak var chatListViewController: ChatListViewController? {
        didSet {
            backupAttachmentDownloadProgressView.chatListViewController = chatListViewController
        }
    }

    private let backupAttachmentDownloadManager: BackupAttachmentDownloadManager
    private let backupAttachmentDownloadQueueStatusReporter: BackupAttachmentDownloadQueueStatusReporter
    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB

    init() {
        AssertIsOnMainThread()

        self.backupAttachmentDownloadManager = DependenciesBridge.shared.backupAttachmentDownloadManager
        self.backupAttachmentDownloadQueueStatusReporter = DependenciesBridge.shared.backupAttachmentDownloadQueueStatusReporter
        self.backupAttachmentDownloadStore = DependenciesBridge.shared.backupAttachmentDownloadStore
        self.backupSettingsStore = BackupSettingsStore()
        self.db = DependenciesBridge.shared.db

        backupAttachmentDownloadProgressView = BackupAttachmentDownloadProgressView(
            backupAttachmentDownloadManager: backupAttachmentDownloadManager,
            backupAttachmentDownloadQueueStatusReporter: backupAttachmentDownloadQueueStatusReporter,
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            backupSettingsStore: backupSettingsStore,
            db: db
        )

        backupDownloadProgressViewCell.contentView.addSubview(backupAttachmentDownloadProgressView)
        backupAttachmentDownloadProgressView.autoPinEdgesToSuperviewEdges()
    }

    public var shouldBeVisible: Bool {
        guard let viewState = chatListViewController?.viewState.backupDownloadProgressViewState else { return false }
        let downloadState = Self.downloadProgressState(
            viewState: viewState,
            // Irrelevant for this bool determination
            completeDismissAction: {},
            backupAttachmentDownloadQueueStatusReporter: backupAttachmentDownloadQueueStatusReporter
        )
        switch downloadState {
        case nil:
            return false
        default:
            return true
        }
    }

    func update(viewState: CLVBackupDownloadProgressView.State) {
        let state = Self.downloadProgressState(
            viewState: viewState,
            completeDismissAction: { [weak self] in
                self?.db.write { tx in
                    self?.backupAttachmentDownloadStore.setDidDismissDownloadCompleteBanner(tx: tx)
                    self?.chatListViewController?.viewState.backupDownloadProgressViewState.refetchDBState(tx: tx)
                }
                guard let viewState = self?.chatListViewController?.viewState.backupDownloadProgressViewState else {
                    return
                }
                self?.update(viewState: viewState)
            },
            backupAttachmentDownloadQueueStatusReporter: backupAttachmentDownloadQueueStatusReporter
        )
        let oldState = backupAttachmentDownloadProgressView.state
        backupAttachmentDownloadProgressView.state = state
        if (oldState == nil) != (state == nil) {
            DispatchQueue.main.async { [weak self] in
                self?.chatListViewController?.loadCoordinator.loadIfNecessary()
            }
        }
    }

    static func measureHeight(
        viewState: CLVBackupDownloadProgressView.State,
        width: CGFloat
    ) -> CGFloat {
        BackupAttachmentDownloadProgressView.measureHeight(
            inWidth: width,
            state: downloadProgressState(
                viewState: viewState,
                // Irrelevant in this context
                completeDismissAction: {},
                backupAttachmentDownloadQueueStatusReporter: DependenciesBridge
                    .shared.backupAttachmentDownloadQueueStatusReporter
            )
        )
    }

    private static func downloadProgressState(
        viewState: CLVBackupDownloadProgressView.State,
        completeDismissAction: @escaping () -> Void,
        backupAttachmentDownloadQueueStatusReporter: BackupAttachmentDownloadQueueStatusReporter
    ) -> BackupAttachmentDownloadProgressView.State? {
        switch viewState.backupPlan {
        case nil, .disabled, .free:
            return .none
        case .disabling, .paid, .paidExpiringSoon, .paidAsTester:
            break
        }
        switch viewState.downloadQueueStatus {
        case .none, .notRegisteredAndReady, .suspended:
            return nil
        case .lowBattery:
            return .paused(reason: .lowBattery)
        case .lowDiskSpace:
            let minRequiredDiskSpace = backupAttachmentDownloadQueueStatusReporter
                .minimumRequiredDiskSpaceToCompleteDownloads()
            let requiredDiskSpace = viewState.downloadProgress.map {
                $0.remainingUnitCount
            } ?? minRequiredDiskSpace
            return .outOfDiskSpace(
                spaceRequired: max(minRequiredDiskSpace, requiredDiskSpace)
            )
        case .noWifiReachability:
            return .wifiNotReachable
        case .noReachability:
            return .paused(reason: .notReachable)
        case .running:
            return .restoring(progress: viewState.downloadProgress)
        case .empty:
            if
                viewState.didDismissDownloadCompleteBanner == false,
                let downloadSize = viewState.totalPendingBackupAttachmentDownloadByteCount
            {
                return .complete(size: downloadSize, dismissAction: completeDismissAction)
            } else {
                return nil
            }
        }
    }
}

private class BackupAttachmentDownloadProgressView: UIView {

    enum State {
        case restoring(progress: OWSProgress?)
        case wifiNotReachable
        case paused(reason: PauseReason)
        case outOfDiskSpace(spaceRequired: UInt64)
        case complete(size: UInt64, dismissAction: () -> Void)

        public enum PauseReason {
            case notReachable
            case lowBattery
        }
    }

    weak var chatListViewController: ChatListViewController?

    var state: State? {
        didSet {
            render()
        }
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required public init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable, message: "use other constructor instead.")
    override init(frame: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }

    private let backupAttachmentDownloadManager: BackupAttachmentDownloadManager
    private let backupAttachmentDownloadQueueStatusReporter: BackupAttachmentDownloadQueueStatusReporter
    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB

    init(
        backupAttachmentDownloadManager: BackupAttachmentDownloadManager,
        backupAttachmentDownloadQueueStatusReporter: BackupAttachmentDownloadQueueStatusReporter,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        backupSettingsStore: BackupSettingsStore,
        db: DB
    ) {
        self.backupAttachmentDownloadManager = backupAttachmentDownloadManager
        self.backupAttachmentDownloadQueueStatusReporter = backupAttachmentDownloadQueueStatusReporter
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        super.init(frame: .zero)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(render),
            name: .themeDidChange,
            object: nil
        )

        initialRender()
    }

    // MARK: - Rendering

    private lazy var backgroundView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = Constants.spacing
        return view
    }()

    private lazy var iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = Constants.titleLabelFont
        label.adjustsFontSizeToFitWidth = true
        label.textAlignment = .left
        label.numberOfLines = 0
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Constants.subtitleLabelFont
        label.textColor = UIColor.Signal.secondaryLabel
        label.adjustsFontSizeToFitWidth = true
        label.textAlignment = .right
        label.numberOfLines = 0
        return label
    }()

    private lazy var diskSpaceLabel: UILabel = {
        let label = UILabel()
        label.font = Constants.diskSpaceLabelFont
        label.adjustsFontSizeToFitWidth = true
        label.textAlignment = .left
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private lazy var progressIndicatorView = ArcView()

    private lazy var dismissButton: OWSButton = {
        let button = OWSButton(imageName: "x-28", tintColor: UIColor.Signal.secondaryLabel) { [weak self] in
            switch self?.state {
            case .complete(_, let dismissAction):
                dismissAction()
            case nil, .restoring, .wifiNotReachable, .paused, .outOfDiskSpace:
                return
            }
        }
        return button
    }()

    private lazy var detailsButton: OWSButton = {
        let button = OWSButton(
            title: Constants.detailsButtonText
        ) { [weak self] in
            self?.didTapDetails()
        }
        button.setTitleColor(UIColor.Signal.label, for: .normal)
        button.titleLabel?.font = Constants.detailsButtonFont
        button.isHidden = true
        return button
    }()

    private lazy var resumeButton: OWSButton = {
        let button = OWSButton(
            title: Constants.resumeButtonText
        ) { [weak self] in
            self?.didTapResume()
        }
        button.setTitleColor(UIColor.Signal.label, for: .normal)
        button.titleLabel?.font = Constants.detailsButtonFont
        button.isHidden = true
        return button
    }()

    private func initialRender() {
        self.addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges(with: .init(margin: Constants.spacing))
        backgroundView.backgroundColor = UIColor.Signal.secondaryBackground

        backgroundView.addSubview(iconView)

        backgroundView.addSubview(titleLabel)
        backgroundView.addSubview(subtitleLabel)
        backgroundView.addSubview(progressIndicatorView)

        backgroundView.addSubview(dismissButton)

        backgroundView.addSubview(diskSpaceLabel)
        backgroundView.addSubview(detailsButton)

        backgroundView.addSubview(resumeButton)

        render()
    }

    @objc
    private func render() {
        if state == nil {
            return
        }
        renderIcon()
        titleLabel.text = Self.titleLabelText(state: state)
        subtitleLabel.text = Self.subtitleLabelText(state: state)
        renderProgressIndicator()
        diskSpaceLabel.text = Self.diskSpaceLabelText(state: state)
        renderResumeButton()
        renderDetailsButton()
        renderDismissButton()
        layout()
    }

    override var bounds: CGRect {
        get { super.bounds }
        set {
            super.bounds = newValue
            layout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layout()
    }

    private struct Frames {
        let state: State?
        let width: CGFloat
        var backgroundView: CGRect = .zero
        // All below here are in backgroundView's frame
        var iconView: CGRect = .zero
        // Nil = hidden
        var progressIndicatorView: CGRect?
        var titleLabel: CGRect?
        var subtitleLabel: (CGRect, NSTextAlignment)?
        var diskSpaceLabel: CGRect?
        var detailsButton: CGRect?
        var dismissButton: CGRect?
        var resumeButton: CGRect?
    }

    private func layout() {
        let frames = Self.measureFrames(inWidth: bounds.width, state: state)
        backgroundView.frame = frames.backgroundView
        iconView.frame = frames.iconView
        progressIndicatorView.isHidden = frames.progressIndicatorView == nil
        frames.progressIndicatorView.map { progressIndicatorView.frame = $0 }
        titleLabel.isHidden = frames.titleLabel == nil
        frames.titleLabel.map { titleLabel.frame = $0 }
        subtitleLabel.isHidden = frames.subtitleLabel == nil
        frames.subtitleLabel.map { (frame, textAlignment) in
            subtitleLabel.frame = frame
            subtitleLabel.textAlignment = textAlignment
        }
        diskSpaceLabel.isHidden = frames.diskSpaceLabel == nil
        frames.diskSpaceLabel.map { diskSpaceLabel.frame = $0 }
        detailsButton.isHidden = frames.detailsButton == nil
        frames.detailsButton.map { detailsButton.frame = $0 }
        dismissButton.isHidden = frames.dismissButton == nil
        frames.dismissButton.map { dismissButton.frame = $0 }
        resumeButton.isHidden = frames.resumeButton == nil
        frames.resumeButton.map { resumeButton.frame = $0 }
    }

    static func measureHeight(
        inWidth width: CGFloat,
        state: State?
    ) -> CGFloat {
        let frames = measureFrames(inWidth: width, state: state)
        return frames.backgroundView.height + (Constants.spacing * 2)
    }

    private static func measureFrames(
        inWidth width: CGFloat,
        state: State?
    ) -> Frames {
        var frames = Frames(state: state, width: width)

        // Subtract the background view's inset
        frames.backgroundView.x = Constants.spacing
        frames.backgroundView.y = Constants.spacing
        frames.backgroundView.width = width - (Constants.spacing * 2)

        // First we do x axis; ignore y axis values.
        // (except fixed heights which we can just do now).
        frames.iconView.x = Constants.spacing
        frames.iconView.width = Constants.iconSize
        frames.iconView.height = Constants.iconSize

        switch state {
        case .restoring:
            frames.progressIndicatorView = .zero
            frames.progressIndicatorView?.x = frames.backgroundView.width - Constants.spacing - Constants.iconSize
            frames.progressIndicatorView?.width = Constants.iconSize
            frames.progressIndicatorView?.height = Constants.iconSize
        case .complete:
            frames.dismissButton = .zero
            frames.dismissButton?.x = frames.backgroundView.width - Constants.spacing - Constants.iconSize
            frames.dismissButton?.width = Constants.iconSize
            frames.dismissButton?.height = Constants.iconSize
        case .wifiNotReachable:
            let resumeButtonSize = (Constants.resumeButtonText as NSString).boundingRect(
                with: .square(.greatestFiniteMagnitude),
                options: [.usesFontLeading, .usesLineFragmentOrigin],
                attributes: [.font: Constants.resumeButtonFont],
                context: nil
            )
            frames.resumeButton = .zero
            frames.resumeButton?.x = frames.backgroundView.width - Constants.spacing - resumeButtonSize.width
            frames.resumeButton?.width = resumeButtonSize.width
            frames.resumeButton?.height = resumeButtonSize.height
        case nil, .paused, .outOfDiskSpace:
            break
        }

        switch state {
        case .restoring, .wifiNotReachable, .paused, .complete:
            measureTitleSubtitleLabel(&frames)
        case .outOfDiskSpace:
            measureOutOfDiskSpaceViews(&frames)
        case nil:
            break
        }

        // Now that widths were determined and height of the background view
        // was set, we can centerY the relevant frames.
        frames.iconView.y = (frames.backgroundView.height / 2) - (frames.iconView.height / 2)
        let centerYFrames: [WritableKeyPath<Frames, CGRect?>] = [
            \.progressIndicatorView,
            \.dismissButton,
            \.detailsButton,
            \.resumeButton,
        ]
        for frameKeyPath in centerYFrames {
            guard var frame = frames[keyPath: frameKeyPath] else { continue }
            frame.y = (frames.backgroundView.height / 2) - (frame.height / 2)
            frames[keyPath: frameKeyPath] = frame
        }
        return frames
    }

    private static func measureTitleSubtitleLabel(_ frames: inout Frames) {
        let labelsMinXBound = frames.iconView.maxX + Constants.spacing
        let labelsMaxXBounds: [CGFloat?] = [
            frames.progressIndicatorView?.minX,
            frames.dismissButton?.minX,
            frames.resumeButton?.minX,
            frames.backgroundView.width,
        ]
        let labelsMaxXBound = labelsMaxXBounds.compacted().min()! - Constants.spacing
        let labelsAvailableWidth = labelsMaxXBound - labelsMinXBound

        var titleLabelSize = ((titleLabelText(state: frames.state) ?? "") as NSString).boundingRect(
            with: CGSize(width: labelsAvailableWidth, height: .greatestFiniteMagnitude),
            options: [.usesFontLeading, .usesLineFragmentOrigin],
            attributes: [.font: Constants.titleLabelFont],
            context: nil
        )
        titleLabelSize.width = min(titleLabelSize.width, labelsAvailableWidth)

        var subtitleLabelSize = ((subtitleLabelText(state: frames.state) ?? "") as NSString).boundingRect(
            with: CGSize(width: labelsAvailableWidth, height: .greatestFiniteMagnitude),
            options: [.usesFontLeading, .usesLineFragmentOrigin],
            attributes: [.font: Constants.subtitleLabelFont],
            context: nil
        )
        subtitleLabelSize.width = min(subtitleLabelSize.width, labelsAvailableWidth)

        let subtitleLabelAvailableWidth = labelsAvailableWidth - titleLabelSize.width - Constants.spacing

        if
            subtitleLabelSize.width > 0,
            subtitleLabelSize.width > subtitleLabelAvailableWidth
        {
            // We go to two lines
            let labelsHeight = titleLabelSize.height + subtitleLabelSize.height
            frames.backgroundView.height = max(
                labelsHeight,
                frames.iconView.height,
                frames.dismissButton?.height ?? 0,
                frames.progressIndicatorView?.height ?? 0
            ) + (Constants.spacing * 2)
            frames.titleLabel = CGRect(
                x: frames.iconView.maxX + Constants.spacing,
                y: (frames.backgroundView.height / 2) - (labelsHeight / 2),
                width: titleLabelSize.width,
                height: titleLabelSize.height
            )
            frames.subtitleLabel = (
                CGRect(
                    x: frames.titleLabel!.minX,
                    y: frames.titleLabel!.maxY,
                    width: subtitleLabelSize.width,
                    height: subtitleLabelSize.height
                ),
                .left
            )
        } else {
            // Just one line
            let labelsHeight = max(titleLabelSize.height, subtitleLabelSize.height)
            frames.backgroundView.height = max(
                labelsHeight,
                frames.iconView.height,
                frames.dismissButton?.height ?? 0,
                frames.progressIndicatorView?.height ?? 0
            ) + (Constants.spacing * 2)
            frames.titleLabel = CGRect(
                x: frames.iconView.maxX + Constants.spacing,
                y: (frames.backgroundView.height / 2) - (titleLabelSize.height / 2),
                width: titleLabelSize.width,
                height: titleLabelSize.height
            )
            let subtitleMinX = frames.titleLabel!.maxX + Constants.spacing
            frames.subtitleLabel = (
                CGRect(
                    x: subtitleMinX,
                    y: (frames.backgroundView.height / 2) - (subtitleLabelSize.height / 2),
                    width: labelsMaxXBound - subtitleMinX,
                    height: subtitleLabelSize.height
                ),
                .right
            )
        }
    }

    private static func measureOutOfDiskSpaceViews(_ frames: inout Frames) {
        let detailsButtonSize = (Constants.detailsButtonText as NSString).boundingRect(
            with: .square(.greatestFiniteMagnitude),
            options: [.usesFontLeading, .usesLineFragmentOrigin],
            attributes: [.font: Constants.detailsButtonFont],
            context: nil
        )
        frames.detailsButton = .zero
        frames.detailsButton?.x = frames.backgroundView.width - Constants.spacing - detailsButtonSize.width
        frames.detailsButton?.width = detailsButtonSize.width
        frames.detailsButton?.height = detailsButtonSize.height

        let availableLabelWidth =
            (frames.detailsButton!.minX - Constants.spacing)
            - (frames.iconView.maxX + Constants.spacing)
        let diskSpaceLabelSize = ((diskSpaceLabelText(state: frames.state) ?? "") as NSString).boundingRect(
            with: CGSize(width: availableLabelWidth, height: .greatestFiniteMagnitude),
            options: [.usesFontLeading, .usesLineFragmentOrigin],
            attributes: [.font: Constants.diskSpaceLabelFont],
            context: nil
        )

        frames.backgroundView.height = max(
            frames.iconView.height,
            diskSpaceLabelSize.height,
            detailsButtonSize.height
        ) + Constants.spacing * 2
        frames.diskSpaceLabel = CGRect(
            x: frames.iconView.maxX + Constants.spacing,
            y: (frames.backgroundView.height / 2) - (diskSpaceLabelSize.height / 2),
            width: diskSpaceLabelSize.width,
            height: diskSpaceLabelSize.height
        )
    }

    private func renderIcon() {
        let (iconName, tintColor): (String, UIColor) = switch state {
        case .restoring, .wifiNotReachable, .paused, nil:
            ("backup-bold", UIColor.Signal.label)
        case .outOfDiskSpace:
            ("backup-error-bold", UIColor.Signal.orange)
        case .complete:
            ("check-circle", UIColor.Signal.ultramarine)
        }
        iconView.setTemplateImage(UIImage(named: iconName), tintColor: tintColor)
    }

    private static func titleLabelText(state: State?) -> String? {
        return switch state {
        case .restoring:
            OWSLocalizedString(
                "RESTORING_MEDIA_BANNER_TITLE",
                comment: "Title shown on chat list banner for restoring media from a backup"
            )
        case .wifiNotReachable:
            OWSLocalizedString(
                "RESTORING_MEDIA_BANNER_WAITING_FOR_WIFI_TITLE",
                comment: "Title shown on chat list banner for restoring media from a backup when waiting for wifi"
            )
        case .paused:
            OWSLocalizedString(
                "RESTORING_MEDIA_BANNER_PAUSED_TITLE",
                comment: "Title shown on chat list banner for restoring media from a backup when paused for some reason"
            )
        case .outOfDiskSpace:
            nil
        case .complete:
            OWSLocalizedString(
                "RESTORING_MEDIA_BANNER_FINISHED_TITLE",
                comment: "Title shown on chat list banner for restoring media from a backup is finished"
            )
        case nil:
            nil
        }
    }

    private static func subtitleLabelText(state: State?) -> String? {
        return switch state {
        case .restoring(let progress) where (progress?.totalUnitCount ?? 0) > 0:
            String(
                format: OWSLocalizedString(
                    "RESTORING_MEDIA_BANNER_PROGRESS_FORMAT",
                    comment: "Download progress for media from a backup. Embeds {{ %1$@ formatted number of bytes downloaded, e.g. '100 MB', %2$@ formatted total number of bytes to download, e.g. '3 GB' }}"
                ),
                formatByteSize(progress!.completedUnitCount),
                formatByteSize(progress!.totalUnitCount)
            )
        case .restoring:
            nil
        case .wifiNotReachable:
            nil
        case .paused(let reason):
            switch reason {
            case .lowBattery:
                OWSLocalizedString(
                    "RESTORING_MEDIA_BANNER_PAUSED_BATTERY_SUBTITLE",
                    comment: "Subtitle shown on chat list banner for restoring media from a backup when paused because the device has low battery"
                )
            case .notReachable:
                OWSLocalizedString(
                    "RESTORING_MEDIA_BANNER_PAUSED_NOT_REACHABLE_SUBTITLE",
                    comment: "Subtitle shown on chat list banner for restoring media from a backup when paused because the device has no internet connection"
                )
            }
        case .outOfDiskSpace:
            nil
        case .complete(let size, _):
            formatByteSize(size)
        case nil:
            nil
        }
    }

    private func renderProgressIndicator() {
        switch state {
        case .restoring(let progress):
            progressIndicatorView.isHidden = false
            if let progress, progress.totalUnitCount > 0 {
                progressIndicatorView.percentComplete = progress.percentComplete
            } else {
                progressIndicatorView.percentComplete = 0
            }
        case nil, .wifiNotReachable, .paused, .outOfDiskSpace, .complete:
            progressIndicatorView.isHidden = true
        }
    }

    private static func diskSpaceLabelText(state: State?) -> String? {
        return switch state {
        case .outOfDiskSpace(let spaceRequired):
            String(
                format: OWSLocalizedString(
                    "RESTORING_MEDIA_BANNER_DISK_SPACE_TITLE_FORMAT",
                    comment: "Title shown on chat list banner for restoring media from a backup when paused because the device has insufficient disk space. Embeds {{ %@ formatted number of bytes downloaded, e.g. '100 MB' }}"
                ),
                formatByteSize(spaceRequired)
            )
        case nil, .restoring, .wifiNotReachable, .paused, .complete:
            nil
        }
    }

    private func renderDetailsButton() {
        detailsButton.isHidden = switch state {
        case .outOfDiskSpace: false
        case nil, .restoring, .wifiNotReachable, .paused, .complete: true
        }
    }

    private func renderDismissButton() {
        dismissButton.isHidden = switch state {
        case .complete: false
        case nil, .restoring, .wifiNotReachable, .paused, .outOfDiskSpace: true
        }
    }

    private func renderResumeButton() {
        resumeButton.isHidden = switch state {
        case .wifiNotReachable: false
        case nil, .restoring, .paused, .outOfDiskSpace, .complete: true
        }
    }

    private static func formatByteSize(_ byteSize: UInt64) -> String {
        return OWSFormat.formatFileSize(UInt(byteSize), maximumFractionalDigits: 0)
    }

    private func didTapResume() {
        switch state {
        case nil, .restoring, .paused, .outOfDiskSpace, .complete:
            return
        case .wifiNotReachable:
            Task {
                await db.awaitableWrite { tx in
                    backupSettingsStore.setShouldAllowBackupDownloadsOnCellular(tx: tx)
                }
            }
        }
    }

    private func didTapDetails() {
        switch state {
        case .restoring, .wifiNotReachable, .paused, .complete, nil:
            return
        case .outOfDiskSpace(let spaceRequired):
            let spaceRequiredString = Self.formatByteSize(spaceRequired)
            var sheet: HeroSheetViewController?
            sheet = HeroSheetViewController(
                hero: .circleIcon(
                    icon: UIImage(named: "backup-error-display-bold")!.withRenderingMode(.alwaysTemplate),
                    iconSize: 40,
                    tintColor: UIColor.Signal.orange,
                    backgroundColor: UIColor.color(rgbHex: 0xF9E4B6)
                ),
                title: String(
                    format: OWSLocalizedString(
                        "RESTORING_MEDIA_DISK_SPACE_SHEET_TITLE_FORMAT",
                        comment: "Title shown on a bottom sheet for restoring media from a backup when paused because the device has insufficient disk space. Embeds {{ %@ formatted number of bytes downloaded, e.g. '100 MB' }}"
                    ),
                    spaceRequiredString
                ),
                body: String(
                    format: OWSLocalizedString(
                        "RESTORING_MEDIA_DISK_SPACE_SHEET_SUBTITLE_FORMAT",
                        comment: "Subtitle shown on a bottom sheet for restoring media from a backup when paused because the device has insufficient disk space. Embeds {{ %@ formatted number of bytes downloaded, e.g. '100 MB' }}"
                    ),
                    spaceRequiredString
                ),
                primaryButton: .init(
                    title: OWSLocalizedString(
                        "ALERT_ACTION_ACKNOWLEDGE",
                        comment: "generic button text to acknowledge that the corresponding text was read."
                    ),
                    action: { sheet in
                        self.backupAttachmentDownloadQueueStatusReporter.reattemptDiskSpaceChecks()
                        sheet.dismiss(animated: true)
                    }
                ),
                secondaryButton: .init(
                    title: OWSLocalizedString(
                        "RESTORING_MEDIA_DISK_SPACE_SHEET_SKIP_BUTTON",
                        comment: "Button to skip restoring media, shown on a bottom sheet for restoring media from a backup when paused because the device has insufficient disk space."
                    ),
                    style: .secondary,
                    action: .custom({ [weak self] sheet in
                        sheet.dismiss(animated: true) {
                            self?.presentSkipRestoreSheet()
                        }
                    })
                ))
            CurrentAppContext().frontmostViewController()?.present(sheet!, animated: true)
            return
        }
    }

    private func presentSkipRestoreSheet() {
        let backupPlan = chatListViewController?.viewState.backupDownloadProgressViewState.backupPlan

        let message: String = switch backupPlan {
        case nil, .disabled, .disabling, .free, .paid, .paidAsTester:
            OWSLocalizedString(
                "RESTORING_MEDIA_DISK_SPACE_SKIP_SHEET_MESSAGE",
                comment: "Message shown on a bottom sheet to skip restoring media from a backup when paused because the device has insufficient disk space."
            )
        case .paidExpiringSoon:
            OWSLocalizedString(
                "RESTORING_MEDIA_DISK_SPACE_SKIP_PAID_EXPIRING_SOON_SHEET_MESSAGE",
                comment: "Message shown on a bottom sheet to skip restoring media from a backup when paused because the device has insufficient disk space, and the user's paid subscription is expiring."
            )
        }

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "RESTORING_MEDIA_DISK_SPACE_SKIP_SHEET_TITLE",
                comment: "Title shown on a bottom sheet to skip restoring media from a backup when paused because the device has insufficient disk space."
            ),
            message: message
        )
        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "RESTORING_MEDIA_DISK_SPACE_SKIP_SHEET_SKIP_BUTTON",
                comment: "Button shown on a bottom sheet to skip restoring media from a backup when paused because the device has insufficient disk space."
            ),
            style: .destructive,
            handler: { [weak self] _ in
                Task {
                    // Wipe this proactively so we don't briefly flash the completed state.
                    self?.chatListViewController?.viewState.backupDownloadProgressViewState
                        .totalPendingBackupAttachmentDownloadByteCount = nil
                    await self?.db.awaitableWrite { tx in
                        self?.backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)
                    }
                    if let chatListViewController = self?.chatListViewController {
                        self?.db.read { tx in
                            chatListViewController.viewState.backupDownloadProgressViewState.refetchDBState(tx: tx)
                        }
                        chatListViewController.loadCoordinator.loadIfNecessary()
                    }
                }
            }
        ))
        actionSheet.addAction(.init(
            title: CommonStrings.learnMore,
            style: .default,
            handler: { _ in
                CurrentAppContext().open(
                    URL(string: "https://support.signal.org/hc/articles/360007059752")!,
                    completion: nil
                )
            }
        ))
        actionSheet.addAction(.init(
            title: CommonStrings.cancelButton,
            style: .cancel
        ))
        CurrentAppContext().frontmostViewController()?.presentActionSheet(actionSheet)
    }

    // MARK: - Constants

    private enum Constants {
        static let spacing: CGFloat = 12
        static let iconSize: CGFloat = 24

        static var titleLabelFont: UIFont { .dynamicTypeSubheadlineClamped.bold() }
        static var subtitleLabelFont: UIFont { .dynamicTypeSubheadlineClamped }

        static var diskSpaceLabelFont: UIFont { .dynamicTypeSubheadlineClamped }

        static let detailsButtonText = OWSLocalizedString(
            "RESTORING_MEDIA_BANNER_DISK_SPACE_BUTTON",
            comment: "Button title shown on chat list banner for restoring media from a backup when paused because the device has insufficient disk space, to see a bottom sheet with more details about next steps."
        )
        static var detailsButtonFont: UIFont { .dynamicTypeSubheadlineClamped.bold() }

        static let resumeButtonText = OWSLocalizedString(
            "RESTORING_MEDIA_BANNER_RESUME_WITHOUT_WIFI_BUTTON",
            comment: "Button title shown on chat list banner for restoring media from a backup when paused because the device needs WiFi to continue, to resume downloads without WiFi."
        )
        static var resumeButtonFont: UIFont { .dynamicTypeSubheadlineClamped.bold() }
    }

    // MARK: ArcView

    private class ArcView: UIView {

        var percentComplete: Float = 0 {
            didSet {
                setNeedsDisplay()
            }
        }

        init() {
            super.init(frame: .zero)
            self.isOpaque = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("Unimplemented")
        }

        override func draw(_ rect: CGRect) {
            guard let context = UIGraphicsGetCurrentContext() else { return }

            let center = CGPoint(x: rect.midX, y: rect.midY)
            let lineWidth: CGFloat = 3
            let radius = min(rect.width, rect.height) / 2 - lineWidth / 2

            context.setStrokeColor(UIColor.Signal.secondaryLabel.cgColor)
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)

            context.addArc(
                center: center,
                radius: radius,
                startAngle: 0,
                endAngle: 2 * .pi,
                clockwise: false
            )

            context.strokePath()

            let startAngle: CGFloat = -.pi / 2
            let endAngle = 2 * .pi * CGFloat(percentComplete)
            context.setStrokeColor(UIColor.Signal.ultramarine.cgColor)

            context.addArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle + startAngle,
                clockwise: false
            )

            context.strokePath()
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            setNeedsDisplay()
        }
    }
}
