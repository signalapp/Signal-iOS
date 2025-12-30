//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalServiceKit
import SignalUI
import SwiftUI

// MARK: View Model

class BackupProgressViewModel: ObservableObject {

    @Published var didTapCancel: Bool = false
    @Published var taskProgress: Float = 0
    @Published var isIndeterminate = true
    @Published var canBeCancelled: Bool = false
    @Published var backupTask: Task<Void, Never>?
    @Published var downloadProgress: (totalByteCount: UInt64, downloadedByteCount: UInt64)?

#if DEBUG
    @Published var progressSourceLabel: String?
#endif

    var cancelButtonEnabled: Bool {
        backupTask != nil && canBeCancelled && !didTapCancel
    }

    var progress: Float {
        didTapCancel ? 0 : taskProgress
    }

    private var waitForLinkingTimeoutTimer: Timer?
    private var didTimeoutWaitForLinking = false

    fileprivate func updateProgress(progress: Float, canBeCancelled: Bool) {
        withAnimation(.smooth) {
            self.taskProgress = progress
        }
        self.canBeCancelled = canBeCancelled
    }

    func updateBackupRestoreProgress(progress: OWSSequentialProgress<BackupRestoreProgressPhase>) {
        // This seems to help with the Lottie bug mentioned below
        objectWillChange.send()

        self.isIndeterminate = progress.completedUnitCount == 0

        updateProgress(
            progress: progress.percentComplete,
            canBeCancelled: false,
        )

#if DEBUG
        progressSourceLabel = progress.currentStep.rawValue
#endif

        if
            let downloadSource = progress.progressForChild(label: AttachmentDownloads.downloadProgressLabel),
            downloadSource.completedUnitCount > 0,
            !downloadSource.isFinished
        {
            self.downloadProgress = (downloadSource.totalUnitCount, downloadSource.completedUnitCount)
        } else {
            self.downloadProgress = nil
        }
    }

    func updatePrimaryLinkingProgress(progress: OWSSequentialProgress<PrimaryLinkNSyncProgressPhase>) {
        // This seems to help with the Lottie bug mentioned below
        objectWillChange.send()

        let canBeCancelled: Bool
        if didTimeoutWaitForLinking {
            // If enough time has passed, allow cancelling
            // regardless of state.
            canBeCancelled = true
        } else {
            canBeCancelled = progress
                .progress(for: .waitingForLinking)?
                .isFinished
                ?? false
        }

        if let waitingForLinking = progress.progress(for: .waitingForLinking) {
            self.isIndeterminate = !waitingForLinking.isFinished
        } else {
            self.isIndeterminate = false
        }

        updateProgress(
            progress: progress.percentComplete,
            canBeCancelled: canBeCancelled,
        )

        if canBeCancelled {
            waitForLinkingTimeoutTimer?.invalidate()
            waitForLinkingTimeoutTimer = nil
        } else if !(waitForLinkingTimeoutTimer?.isValid ?? false) {
            waitForLinkingTimeoutTimer = Timer.scheduledTimer(
                withTimeInterval: 60,
                repeats: false,
            ) { [weak self] _ in
                self?.didTimeoutWaitForLinking = true
                self?.canBeCancelled = true
            }
        }

#if DEBUG
        progressSourceLabel = progress.currentStep.rawValue
#endif

        self.downloadProgress = nil
    }

    func cancel() {
        backupTask?.cancel()
        withAnimation(.smooth(duration: 0.2)) {
            didTapCancel = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.isIndeterminate = true
        }
    }
}

// MARK: Hosting Controller

class BackupProgressModal: HostingController<BackupProgressView>, LinkAndSyncProgressUI {

    var shouldSuppressNotifications: Bool { true }

    let viewModel = BackupProgressViewModel()

    var backupTask: Task<Void, Never>? {
        get { viewModel.backupTask }
        set { viewModel.backupTask = newValue }
    }

    init(style: BackupProgressView.Style) {
        super.init(wrappedView: BackupProgressView(
            style: style,
            viewModel: viewModel,
        ))

        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil,
        )
    }

    @objc
    func appDidBackground() {
        guard
            viewModel.canBeCancelled,
            viewModel.backupTask != nil
        else {
            return
        }
        Logger.error("Backgrounded app while link'n'syncing")
        viewModel.cancel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .Signal.backdrop
    }

    @MainActor
    func completeAndDismiss() async {
        viewModel.updateProgress(progress: 1, canBeCancelled: false)
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC / 2)
        await withCheckedContinuation { continuation in
            dismiss(animated: true) {
                continuation.resume()
            }
        }
    }
}

// MARK: SwiftUI View

struct BackupProgressView: View {
    @Environment(\.appearanceTransitionState) private var appearanceTransitionState

    enum Style {
        case linkAndSync
        case backupRestore
    }

    fileprivate var style: Style
    @ObservedObject fileprivate var viewModel: BackupProgressViewModel

    @State private var indeterminateProgressIsPlaying = false
    private var loopMode: LottieLoopMode {
        viewModel.isIndeterminate ? .loop : .playOnce
    }

    private var indeterminateProgressShouldShow: Bool {
        // We want to wait for the indeterminate spinner animation to finish
        // before the actual progress is shown to make it look smoother, but if
        // the progress finishes entirely before that, immediately show 100%.
        indeterminateProgressIsPlaying && viewModel.progress < 1
    }

    // If the first portion fills very quickly before the view is visible,
    // we still want to animate it from 0.
    private var progressToShow: Float {
        switch appearanceTransitionState {
        case .appearing:
            0
        case .cancelled, .finished, .none:
            indeterminateProgressShouldShow ? 0 : viewModel.progress
        }
    }

    private var byteCountFormat: ByteCountFormatStyle {
        .byteCount(style: .decimal, allowedUnits: [.mb, .gb], spellsOutZero: false)
    }

    private var progressString: String {
        switch style {
        case .linkAndSync:
            percentCompleteString
        case .backupRestore:
            if progressToShow.isZero {
                OWSLocalizedString(
                    "BACKUP_RESTORE_MODAL_PREPARING_SUBTITLE",
                    comment: "Subtitle for a progress spinner on a modal when waiting for a backup restore to start",
                )
            } else if let downloadProgress = viewModel.downloadProgress {
                String(
                    format: OWSLocalizedString(
                        "BACKUP_RESTORE_MODAL_DOWNLOAD_PROGRESS_SUBTITLE",
                        comment: "Subtitle for a progress spinner on a modal tracking active downloading. Embeds 1:{{ the amount downloaded as a file size, e.g. 100 MB }}; 2:{{ the total amount to download as a file size, e.g. 1 GB }}; 3:{{ the amount downloaded as a percentage, e.g. 10% }}.",
                    ),
                    downloadProgress.downloadedByteCount.formatted(byteCountFormat),
                    downloadProgress.totalByteCount.formatted(byteCountFormat),
                    progressToShow.formatted(.percent.precision(.fractionLength(0))),
                )
            } else {
                percentCompleteString
            }
        }
    }

    private var percentCompleteString: String {
        String(
            format: OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_PROGRESS_PERCENT",
                comment: "On a progress modal indicating the percent complete the sync process is. Embeds {{ formatted percentage }}",
            ),
            progressToShow.formatted(.percent.precision(.fractionLength(0))),
        )
    }

    private var showIndeterminateProgress: Bool {
        switch appearanceTransitionState {
        case .none, .appearing, .cancelled:
            false
        case .finished:
            viewModel.isIndeterminate || indeterminateProgressShouldShow
        }
    }

    private var title: String {
        switch style {
        case .linkAndSync:
            linkAndSyncTitle
        case .backupRestore:
            OWSLocalizedString(
                "BACKUP_RESTORE_MODAL_TITLE",
                comment: "Title for a progress spinner on a modal when restoring messages",
            )
        }
    }

    private var linkAndSyncTitle: String {
        if viewModel.didTapCancel {
            OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_PROGRESS_TILE_CANCELLING",
                comment: "Title for a progress modal that would be indicating the sync progress while it's cancelling that sync",
            )
        } else if indeterminateProgressShouldShow || appearanceTransitionState != .finished {
            OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_PROGRESS_TITLE_PREPARING",
                comment: "Title for a progress modal indicating the sync progress while it's preparing for upload",
            )
        } else {
            OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_PROGRESS_TITLE",
                comment: "Title for a progress modal indicating the sync progress",
            )
        }
    }

    var body: some View {
        switch style {
        case .linkAndSync:
            progressView
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32))
                .padding(.horizontal, 60)
        case .backupRestore:
            progressView
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32))
                .padding(.horizontal, 68)
                .padding(.vertical, 44)
        }
    }

    var progressView: some View {
        VStack(spacing: 0) {
            ZStack {
                CircleProgressView(progress: progressToShow)
                    .animation(.smooth, value: appearanceTransitionState)
                    .animation(.smooth, value: indeterminateProgressShouldShow)

                if showIndeterminateProgress {
                    LottieView(animation: .named("circular_indeterminate"))
                        .playing(loopMode: loopMode)
                        .animationDidFinish { completed in
                            guard completed else { return }
                            indeterminateProgressIsPlaying = false
                        }
                        .onAppear {
                            indeterminateProgressIsPlaying = true
                        }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 20)
            .onChange(of: viewModel.isIndeterminate) { isIndeterminate in
                guard !isIndeterminate else { return }
                // There is a seemingly rng bug where the Lottie
                // view doesn't properly respond to the change of
                // loopMode, leading to .animationDidFinish never
                // being called. The animation is a bit over one
                // second, so if it's not done after two seconds,
                // force hide it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.indeterminateProgressIsPlaying = false
                }
            }

            Text(title)
                .font(.headline)
                .padding(.bottom, 8)
                .animation(.none, value: title)

            Text(progressString)
                .font(.subheadline.monospacedDigit())
                .animation(.none, value: viewModel.progress)
                .padding(.bottom, 2)

            if style == .linkAndSync {
                Text(OWSLocalizedString(
                    "LINK_NEW_DEVICE_SYNC_PROGRESS_DO_NOT_CLOSE_APP",
                    comment: "On a progress modal",
                ))
                .font(.subheadline)
                .foregroundStyle(Color.Signal.secondaryLabel)
                .padding(.bottom, 36)

                Button(CommonStrings.cancelButton) {
                    viewModel.cancel()
                }
                .disabled(!viewModel.cancelButtonEnabled)
                .font(.body.weight(.semibold))
            }

#if DEBUG
            Text("DEBUG: " + (viewModel.progressSourceLabel ?? "none"))
                .padding(.top)
                .foregroundStyle(Color.Signal.quaternaryLabel)
                .animation(.none, value: viewModel.progressSourceLabel)
#endif
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 28)
    }

    private struct CircleProgressView: View {
        var progress: Float

        var body: some View {
            ZStack {
                Circle()
                    .stroke(lineWidth: 4)
                    .foregroundStyle(Color.Signal.tertiaryLabel)

                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .rotation(.degrees(-90))
                    .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.Signal.accent)
            }
            .frame(width: 48, height: 48)
            .padding(2)
        }
    }
}

// MARK: Previews

#if DEBUG

@available(iOS 17, *)
func simulateProgress(for source: OWSProgressSource) async throws {
    for _ in 0..<(source.totalUnitCount / 2) {
        source.incrementCompletedUnitCount(by: 2)
        try await Task.sleep(for: .milliseconds(50))
    }

    source.incrementCompletedUnitCount(by: source.totalUnitCount)
}

@MainActor
@available(iOS 17, *)
private func setupDemoProgressBackupRestore(
    modal: BackupProgressModal,
    instantComplete: Bool,
) async throws {
    let progress = await OWSSequentialProgress<BackupRestoreProgressPhase>.createSink { progress in
        modal.viewModel.updateBackupRestoreProgress(progress: progress)
    }

    let download = await progress.child(for: .downloadingBackup)
        .addSource(withLabel: "download", unitCount: 10_000_000)

    let importingBackupProgress = await progress.child(for: .importingBackup).addSource(
        withLabel: BackupRestoreProgressPhase.importingBackup.rawValue,
        unitCount: BackupRestoreProgressPhase.importingBackup.progressUnitCount,
    )

    let finishingProgress = await progress.child(for: .finishing).addSource(
        withLabel: BackupRestoreProgressPhase.finishing.rawValue,
        unitCount: BackupRestoreProgressPhase.finishing.progressUnitCount,
    )

    try await Task.sleep(for: .milliseconds(700))

    if instantComplete {
        try await Task.sleep(for: .seconds(1))
        await modal.completeAndDismiss()
        return
    }

    while download.completedUnitCount < 10_000_000 {
        download.incrementCompletedUnitCount(by: 100_000)
        try await Task.sleep(for: .milliseconds(100))
    }

    try await simulateProgress(for: importingBackupProgress)

    try await Task.sleep(for: .milliseconds(500))

    finishingProgress.incrementCompletedUnitCount(by: BackupRestoreProgressPhase.finishing.progressUnitCount)

    await modal.completeAndDismiss()
}

@MainActor
@available(iOS 17, *)
private func setupDemoProgress(
    modal: BackupProgressModal,
    slowLinking: Bool,
) async throws {
    let progress = await OWSSequentialProgress<PrimaryLinkNSyncProgressPhase>.createSink { progress in
        modal.viewModel.updatePrimaryLinkingProgress(progress: progress)
    }

    let waitForLinkingProgress = await progress.child(for: .waitingForLinking).addSource(
        withLabel: PrimaryLinkNSyncProgressPhase.waitingForLinking.rawValue,
        unitCount: PrimaryLinkNSyncProgressPhase.waitingForLinking.progressUnitCount,
    )
    let exportingBackupProgress = await progress.child(for: .exportingBackup).addSource(
        withLabel: PrimaryLinkNSyncProgressPhase.exportingBackup.rawValue,
        unitCount: PrimaryLinkNSyncProgressPhase.exportingBackup.progressUnitCount,
    )
    let uploadingBackupProgress = await progress.child(for: .uploadingBackup).addSource(
        withLabel: PrimaryLinkNSyncProgressPhase.uploadingBackup.rawValue,
        unitCount: PrimaryLinkNSyncProgressPhase.uploadingBackup.progressUnitCount,
    )
    let markUploadedProgress = await progress.child(for: .finishing).addSource(
        withLabel: PrimaryLinkNSyncProgressPhase.finishing.rawValue,
        unitCount: PrimaryLinkNSyncProgressPhase.finishing.progressUnitCount,
    )

    if slowLinking {
        try await Task.sleep(for: .milliseconds(700))
    } else {
        try await Task.sleep(for: .milliseconds(100))
    }

    waitForLinkingProgress.incrementCompletedUnitCount(by: PrimaryLinkNSyncProgressPhase.waitingForLinking.progressUnitCount)

    if slowLinking {
        try await Task.sleep(for: .milliseconds(700))
    } else {
        try await Task.sleep(for: .milliseconds(100))
    }

    try await simulateProgress(for: exportingBackupProgress)
    try await simulateProgress(for: uploadingBackupProgress)

    try await Task.sleep(for: .milliseconds(500))

    try Task.checkCancellation()
    markUploadedProgress.incrementCompletedUnitCount(by: PrimaryLinkNSyncProgressPhase.finishing.progressUnitCount)

    await modal.completeAndDismiss()
}

@MainActor
@available(iOS 17, *)
func demoTask(
    modal: BackupProgressModal,
    slowLinking: Bool,
) -> Task<Void, Never> {
    Task {
        do {
            try await setupDemoProgress(
                modal: modal,
                slowLinking: slowLinking,
            )
        } catch {
            try? await Task.detached {
                try await Task.sleep(for: slowLinking ? .seconds(3) : .milliseconds(500))
            }.value
            modal.dismiss(animated: true)
        }
    }
}

@available(iOS 17, *)
#Preview("Slow linking") {
    SheetPreviewViewController(animateFirstAppearance: true) {
        let modal = BackupProgressModal(style: .linkAndSync)
        modal.backupTask = demoTask(modal: modal, slowLinking: true)
        return modal
    }
}

@available(iOS 17, *)
#Preview("Fast linking") {
    SheetPreviewViewController(animateFirstAppearance: true) {
        let modal = BackupProgressModal(style: .linkAndSync)
        modal.backupTask = demoTask(modal: modal, slowLinking: false)
        return modal
    }
}

@available(iOS 17, *)
#Preview("Backup restore") {
    SheetPreviewViewController(animateFirstAppearance: true) {
        let modal = BackupProgressModal(style: .backupRestore)
        modal.backupTask = Task {
            try? await setupDemoProgressBackupRestore(modal: modal, instantComplete: false)
        }
        return modal
    }
}

@available(iOS 17, *)
#Preview("Backup restore - instant complete") {
    SheetPreviewViewController(animateFirstAppearance: true) {
        let modal = BackupProgressModal(style: .backupRestore)
        modal.backupTask = Task {
            try? await setupDemoProgressBackupRestore(modal: modal, instantComplete: true)
        }
        return modal
    }
}
#endif
