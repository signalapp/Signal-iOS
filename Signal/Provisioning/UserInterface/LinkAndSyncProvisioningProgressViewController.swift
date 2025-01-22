//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SwiftUI
import SignalUI
import SignalServiceKit

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
    @Published var progressSourceLabel: String?
#endif

    var progress: Float {
        didTapCancel ? 0 : taskProgress
    }

    func updateProgress(_ progress: OWSProgress) {
        objectWillChange.send()

#if DEBUG
        progressSourceLabel = progress.sourceProgresses
            .lazy
            .filter(\.value.isFinished.negated)
            .filter({ $0.value.completedUnitCount > 0 })
            .max(by: { $0.value.percentComplete < $1.value.percentComplete })?
            .key
            ?? progressSourceLabel
#endif

        let canBeCancelled = progress
            .sourceProgresses[SecondaryLinkNSyncProgressPhase.waitingForBackup.rawValue]?
            .isFinished
            ?? false

        guard !didTapCancel else { return }

        self.isIndeterminate = progress
            .sourceProgresses[SecondaryLinkNSyncProgressPhase.waitingForBackup.rawValue]?
            .isFinished.negated
            ?? true

        if
            let downloadSource = progress.sourceProgresses[AttachmentDownloads.downloadProgressLabel],
            downloadSource.completedUnitCount > 0,
            !downloadSource.isFinished
        {
            self.downloadProgress = (downloadSource.totalUnitCount, downloadSource.completedUnitCount)
        } else {
            self.downloadProgress = nil
        }

        self.isFinalizing = {
            for phase in SecondaryLinkNSyncProgressPhase.allCases {
                let progresses = progress.sourceProgresses.values.lazy
                    .filter({ $0.labels.contains(phase.rawValue) })
                if progresses.contains(where: \.isFinished.negated) || progresses.isEmpty {
                    return false
                }
            }
            return true
        }()

        withAnimation(.smooth) {
            self.taskProgress = progress.percentComplete
        }

        self.canBeCancelled = canBeCancelled
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

class LinkAndSyncProvisioningProgressViewController: HostingController<LinkAndSyncProvisioningProgressView> {
    fileprivate var viewModel: LinkAndSyncSecondaryProgressViewModel

    var linkNSyncTask: Task<Void, Error>? {
        get { viewModel.linkNSyncTask }
        set {
            viewModel.linkNSyncTask = newValue
            viewModel.didTapCancel = newValue?.isCancelled ?? false
        }
    }

    init(viewModel: LinkAndSyncSecondaryProgressViewModel) {
        self.viewModel = viewModel
        super.init(wrappedView: LinkAndSyncProvisioningProgressView(viewModel: viewModel))
        self.modalPresentationStyle = .fullScreen
        self.modalTransitionStyle = .crossDissolve
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
        .byteCount(style: .decimal, allowedUnits: [.mb, .gb])
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
            Text("DEBUG: " + (viewModel.progressSourceLabel ?? "none") + "\n\(viewModel.taskProgress)")
                .padding(.top)
                .foregroundStyle(Color.Signal.quaternaryLabel)
                .animation(.none, value: viewModel.progressSourceLabel)
                .animation(.none, value: viewModel.taskProgress)
#endif

            Spacer()

            if let linkNSyncTask = viewModel.linkNSyncTask {
                Button(CommonStrings.cancelButton) {
                    viewModel.cancel(task: linkNSyncTask)
                }
                .opacity(viewModel.canBeCancelled ? 1 : 0)
                .disabled(!viewModel.canBeCancelled || viewModel.didTapCancel)
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
                    UIApplication.shared.open(URL(string: "https://support.signal.org/hc/articles/360007320551")!)
                }
                .font(.footnote)
                .frame(maxWidth: 412)
            }
            .foregroundStyle(Color.Signal.secondaryLabel)
        }
        .tint(Color.Signal.accent)
        .padding()
        .multilineTextAlignment(.center)
    }

    // MARK: Linear Progress View

    private struct LinearProgressView: View {
        var progress: Float

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .foregroundStyle(Color.Signal.secondaryFill)

                    Capsule()
                        .foregroundStyle(Color.Signal.accent)
                        .frame(width: geo.size.width * CGFloat(progress))
                }
            }
            .frame(width: 360, height: 4)
        }
    }
}

// MARK: Previews

#if DEBUG
@available(iOS 17, *)
#Preview {
    let view = LinkAndSyncProvisioningProgressViewController(viewModel: LinkAndSyncSecondaryProgressViewModel())

    let progressSink = OWSProgress.createSink { progress in
        Task { @MainActor in
            view.viewModel.updateProgress(progress)
        }
    }

    let task = Task { @MainActor in

        let linkNSyncProgress = await progressSink.addChild(
            withLabel: LocalizationNotNeeded("Link'n'sync"),
            unitCount: 99
        )

        let postLinkNSyncProgress = await progressSink.addSource(
            withLabel: LocalizationNotNeeded("Post-link'n'sync"),
            unitCount: 1
        )

        let nonCancellableProgressSource = await linkNSyncProgress.addSource(
            withLabel: SecondaryLinkNSyncProgressPhase.waitingForBackup.rawValue,
            unitCount: 10
        )
        let downloadBackupSink = await linkNSyncProgress.addChild(
            withLabel: SecondaryLinkNSyncProgressPhase.downloadingBackup.rawValue,
            unitCount: 90
        )

        let download = await downloadBackupSink.addSource(withLabel: "download", unitCount: 10_000_000)

        try? await Task.sleep(for: .seconds(1))

        while nonCancellableProgressSource.completedUnitCount < 10 {
            nonCancellableProgressSource.incrementCompletedUnitCount(by: 1)
            try? await Task.sleep(for: .milliseconds(100))
        }

        while download.completedUnitCount < 10_000_000 {
            download.incrementCompletedUnitCount(by: 100_000)
            try await Task.sleep(for: .milliseconds(100))
        }

        postLinkNSyncProgress.incrementCompletedUnitCount(by: 1)
    }

    view.linkNSyncTask = Task {
        try? await task.value
    }

    return view
}
#endif
