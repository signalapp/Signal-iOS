//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SwiftUI
import SignalUI
import SignalServiceKit
import SafariServices

// MARK: View Model

class LinkAndSyncSecondaryProgressViewModel: ObservableObject {
    @Published private(set) var taskProgress: Float = 0
    @Published private(set) var canBeCancelled: Bool = false
    @Published var isIndeterminate = true
    @Published var isFinalizing = false
    @Published var linkNSyncTask: Task<Void, Error>?
    @Published var didTapCancel: Bool = false
    @Published var downloadProgress: (totalByteCount: UInt64, downloadedByteCount: UInt64)?

#if DEBUG
    @Published var currentProgressStep: SecondaryLinkNSyncProgressPhase?
#endif

    private var waitForBackupTimeoutTimer: Timer?
    private var didTimeoutWaitForBackup = false

    var progress: Float {
        didTapCancel ? 0 : taskProgress
    }

    func updateProgress(_ progress: OWSSequentialProgress<SecondaryLinkNSyncProgressPhase>) {
        objectWillChange.send()

#if DEBUG
        currentProgressStep = progress.currentStep
#endif

        let canBeCancelled: Bool
        if didTimeoutWaitForBackup {
            // If enough time has passed, allow cancelling
            // regardless of state.
            canBeCancelled = true
        } else {
            canBeCancelled = progress
                .progress(for: .waitingForBackup)?
                .isFinished
                ?? false
        }

        guard !didTapCancel else { return }

        self.isIndeterminate = progress
            .progress(for: .waitingForBackup)?
            .isFinished.negated
            ?? true

        if
            let downloadSource = progress.progressForChild(
                label: AttachmentDownloads.downloadProgressLabel
            ),
            downloadSource.completedUnitCount > 0,
            !downloadSource.isFinished
        {
            self.downloadProgress = (downloadSource.totalUnitCount, downloadSource.completedUnitCount)
        } else {
            self.downloadProgress = nil
        }

        self.isFinalizing = progress.isFinished

        withAnimation(.smooth) {
            // We leave a single % unfinished at the end, so it doesn't look
            // like we hit 100% and sit there while the UI flows to the next step.
            self.taskProgress = (progress.percentComplete) * 0.99
        }

        self.canBeCancelled = canBeCancelled

        if canBeCancelled {
            waitForBackupTimeoutTimer?.invalidate()
            waitForBackupTimeoutTimer = nil
        } else if !(waitForBackupTimeoutTimer?.isValid ?? false) {
            waitForBackupTimeoutTimer = Timer.scheduledTimer(
                withTimeInterval: 60,
                repeats: false
            ) { [weak self] _ in
                self?.didTimeoutWaitForBackup = true
                self?.canBeCancelled = true
            }
        }
    }

    func cancel(task: Task<Void, Error>) {
        task.cancel()
        withAnimation(.smooth(duration: 0.2)) {
            didTapCancel = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self!.isIndeterminate = true
        }
    }
}

// MARK: Hosting Controller

class LinkAndSyncProvisioningProgressViewController: ProvisioningBaseViewController, LinkAndSyncProgressUI {

    public var shouldSuppressNotifications: Bool { true }

    fileprivate var viewModel: LinkAndSyncSecondaryProgressViewModel

    var linkNSyncTask: Task<Void, Error>? {
        get { viewModel.linkNSyncTask }
        set {
            viewModel.linkNSyncTask = newValue
            viewModel.didTapCancel = newValue?.isCancelled ?? false
        }
    }

    init(provisioningController: ProvisioningController, viewModel: LinkAndSyncSecondaryProgressViewModel) {
        self.viewModel = viewModel

        super.init(provisioningController: provisioningController)

        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
        navigationItem.hidesBackButton = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let linkAndSyncViewHostingContainer = HostingContainer(wrappedView: LinkAndSyncProvisioningProgressView(viewModel: viewModel))
        addChild(linkAndSyncViewHostingContainer)
        view.addSubview(linkAndSyncViewHostingContainer.view)
        linkAndSyncViewHostingContainer.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            linkAndSyncViewHostingContainer.view.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            linkAndSyncViewHostingContainer.view.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            linkAndSyncViewHostingContainer.view.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            linkAndSyncViewHostingContainer.view.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
        ])
        linkAndSyncViewHostingContainer.didMove(toParent: self)
    }

    @objc
    func appDidBackground() {
        guard let linkNSyncTask = viewModel.linkNSyncTask else {
            return
        }
        Logger.error("Backgrounded app while link'n'syncing")
        viewModel.cancel(task: linkNSyncTask)
        Task {
            _ = try? await linkNSyncTask.value
            // Reset the whole app and force quit. If the user
            // exits in the middle of syncing we'll probably
            // crash anyway (dead10cc).
            SignalApp.shared.resetAppDataAndExit(
                keyFetcher: SSKEnvironment.shared.databaseStorageRef.keyFetcher
            )
        }
    }
}

// MARK: SwiftUI View

struct LinkAndSyncProvisioningProgressView: View {

    @ObservedObject fileprivate var viewModel: LinkAndSyncSecondaryProgressViewModel

    @State private var indeterminateProgressShouldShow = false
    private var showIndeterminateProgress: Bool {
        viewModel.isIndeterminate || indeterminateProgressShouldShow
    }
    private var loopMode: LottieLoopMode {
        viewModel.isIndeterminate ? .loop : .playOnce
    }
    private var progressToShow: Float {
        indeterminateProgressShouldShow ? 0 : viewModel.progress
    }

    private var byteCountFormat: ByteCountFormatStyle {
        .byteCount(style: .decimal, allowedUnits: [.mb, .gb], spellsOutZero: false)
    }

    private var subtitle: String {
        if viewModel.didTapCancel {
            OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_PROGRESS_TILE_CANCELLING",
                comment: "Title for a progress modal that would be indicating the sync progress while it's cancelling that sync"
            )
        } else if indeterminateProgressShouldShow && !viewModel.isFinalizing {
            OWSLocalizedString(
                "LINKING_SYNCING_PREPARING_TO_DOWNLOAD",
                comment: "Progress label when the message loading has not yet started during the device linking process"
            )
        } else if let downloadProgress = viewModel.downloadProgress {
            String(
                format: OWSLocalizedString(
                    "LINK_NEW_DEVICE_SYNC_DOWNLOAD_PROGRESS",
                    comment: "Progress label showing the download progress of a linked device sync. Embeds {{ formatted downloaded size (such as megabytes), formatted total download size, formatted percentage }}"
                ),
                downloadProgress.downloadedByteCount.formatted(byteCountFormat),
                downloadProgress.totalByteCount.formatted(byteCountFormat),
                progressToShow.formatted(.percent.precision(.fractionLength(0)))
            )
        } else if !viewModel.isFinalizing {
            String(
                format: OWSLocalizedString(
                    "LINK_NEW_DEVICE_SYNC_PROGRESS_PERCENT",
                    comment: "On a progress modal indicating the percent complete the sync process is. Embeds {{ formatted percentage }}"
                ),
                progressToShow.formatted(.percent.precision(.fractionLength(0)))
            )
        } else {
            OWSLocalizedString(
                "LINKING_SYNCING_FINALIZING",
                comment: "Progress label when the message loading has nearly completed during the device linking process"
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(OWSLocalizedString(
                "LINKING_SYNCING_MESSAGES_TITLE",
                comment: "Title shown when loading messages during linking process"
            ))
            .font(.title2.bold())
            .foregroundStyle(Color.Signal.label)
            .padding(.bottom, 24)

            ZStack {
                LinearProgressView(progress: progressToShow)
                    .animation(.smooth, value: indeterminateProgressShouldShow)

                if showIndeterminateProgress {
                    LottieView(animation: .named("linear_indeterminate"))
                        .playing(loopMode: loopMode)
                        .animationDidFinish { completed in
                            guard completed else { return }
                            indeterminateProgressShouldShow = false
                        }
                        .onAppear {
                            indeterminateProgressShouldShow = true
                        }
                }
            }
            .padding(.bottom, 12)
            .onChange(of: viewModel.isIndeterminate) { isIndeterimate in
                // See LinkAndSyncProgressModal.swift
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.indeterminateProgressShouldShow = false
                }
            }

            Group {
                Text(verbatim: subtitle)
                    .font(.footnote.monospacedDigit())
                    .padding(.bottom, 22)
                    .animation(.none, value: subtitle)

                Text(OWSLocalizedString(
                    "LINKING_SYNCING_TIMING_INFO",
                    comment: "Label below the progress bar when loading messages during linking process"
                ))
                .font(.subheadline)
            }
            .foregroundStyle(Color.Signal.secondaryLabel)

#if DEBUG
            Text("DEBUG: " + (viewModel.currentProgressStep?.rawValue ?? "none") + "\n\(viewModel.taskProgress)")
                .padding(.top)
                .foregroundStyle(Color.Signal.quaternaryLabel)
                .animation(.none, value: viewModel.currentProgressStep)
                .animation(.none, value: viewModel.taskProgress)
#endif

            Spacer()

            if let linkNSyncTask = viewModel.linkNSyncTask {
                Button(CommonStrings.cancelButton) {
                    viewModel.cancel(task: linkNSyncTask)
                }
                .opacity(viewModel.canBeCancelled ? 1 : 0)
                .disabled(!viewModel.canBeCancelled || viewModel.didTapCancel)
                .buttonStyle(Registration.UI.MediumSecondaryButtonStyle())
                .padding(.bottom, 56)
            }

            Group {
                SignalSymbol.lock.text(dynamicTypeBaseSize: 20)
                    .padding(.bottom, 6)

                Text(OWSLocalizedString(
                    "LINKING_SYNCING_FOOTER",
                    comment: "Footer text when loading messages during linking process."
                ))
                .appendLink(CommonStrings.learnMore) {
                    let vc = SFSafariViewController(url: URL.Support.linkedDevices)
                    CurrentAppContext().frontmostViewController()?.present(vc, animated: true)
                }
                .font(.footnote)
            }
            .foregroundStyle(Color.Signal.secondaryLabel)
        }
        .tint(Color.Signal.accent)
        .multilineTextAlignment(.center)
    }
}

// MARK: Previews

#if DEBUG
@available(iOS 17, *)
#Preview {
    let view = LinkAndSyncProvisioningProgressView(viewModel: LinkAndSyncSecondaryProgressViewModel())

    let task = Task { @MainActor in
        let progressSink = await OWSSequentialProgress<SecondaryLinkNSyncProgressPhase>.createSink { progress in
            await MainActor.run {
                view.viewModel.updateProgress(progress)
            }
        }

        let nonCancellableProgressSource = await progressSink.child(for: .waitingForBackup).addSource(
            withLabel: SecondaryLinkNSyncProgressPhase.waitingForBackup.rawValue,
            unitCount: 10
        )
        let download = await progressSink.child(for: .downloadingBackup)
            .addSource(withLabel: "download", unitCount: 10_000_000)

        try? await Task.sleep(for: .seconds(1))

        while nonCancellableProgressSource.completedUnitCount < 10 {
            nonCancellableProgressSource.incrementCompletedUnitCount(by: 1)
            try? await Task.sleep(for: .milliseconds(100))
        }

        while download.completedUnitCount < 10_000_000 {
            download.incrementCompletedUnitCount(by: 100_000)
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    view.viewModel.linkNSyncTask = Task {
        try? await task.value
    }

    return view
}
#endif
