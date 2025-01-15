//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SwiftUI
import SignalUI
import SignalServiceKit

// MARK: View Model

class LinkAndSyncProgressViewModel: ObservableObject {

    @Published var didTapCancel: Bool = false
    @Published var taskProgress: Float = 0
    @Published var isIndeterminate = true
    @Published var canBeCancelled: Bool = false
    @Published var linkNSyncTask: Task<Void, Never>?

#if DEBUG
    @Published var progressSourceLabel: String?
#endif

    var cancelButtonEnabled: Bool {
        linkNSyncTask != nil && canBeCancelled && !didTapCancel
    }

    var progress: Float {
        didTapCancel ? 0 : taskProgress
    }

    fileprivate func updateProgress(progress: Float, canBeCancelled: Bool) {
        withAnimation(.smooth) {
            self.taskProgress = progress
        }
        self.canBeCancelled = canBeCancelled
    }

    func updateProgress(progress: OWSProgress) {
        // This seems to help with the Lottie bug mentioned below
        objectWillChange.send()

        let canBeCancelled: Bool
        if let label = progress.currentSourceLabel {
            canBeCancelled = label != PrimaryLinkNSyncProgressPhase.waitingForLinking.rawValue
        } else {
            canBeCancelled = false
        }

        if progress.completedUnitCount > PrimaryLinkNSyncProgressPhase.waitingForLinking.percentOfTotalProgress {
            self.isIndeterminate = false
        }

        updateProgress(
            progress: progress.percentComplete,
            canBeCancelled: canBeCancelled
        )

#if DEBUG
        progressSourceLabel = progress.currentSourceLabel
#endif
    }

    func cancel() {
        linkNSyncTask?.cancel()
        withAnimation(.smooth(duration: 0.2)) {
            taskProgress = 0
        }
        didTapCancel = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.isIndeterminate = true
        }
    }
}

// MARK: Hosting Controller

class LinkAndSyncProgressModal: HostingController<LinkAndSyncProgressView> {

    let viewModel = LinkAndSyncProgressViewModel()

    var linkNSyncTask: Task<Void, Never>? {
        get { viewModel.linkNSyncTask }
        set { viewModel.linkNSyncTask = newValue }
    }

    init() {
        super.init(wrappedView: LinkAndSyncProgressView(viewModel: viewModel))

        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = Theme.backdropColor
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

struct LinkAndSyncProgressView: View {
    @Environment(\.appearanceTransitionState) private var appearanceTransitionState

    @ObservedObject fileprivate var viewModel: LinkAndSyncProgressViewModel

    @State private var indeterminateProgressShouldShow = false
    private var loopMode: LottieLoopMode {
        viewModel.isIndeterminate ? .loop : .playOnce
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

    private var showIndeterminateProgress: Bool {
        switch appearanceTransitionState {
        case .none, .appearing, .cancelled:
            false
        case .finished:
            viewModel.isIndeterminate || indeterminateProgressShouldShow
        }
    }

    private var title: String {
        if viewModel.didTapCancel {
            OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_PROGRESS_TILE_CANCELLING",
                comment: "Title for a progress modal that would be indicating the sync progress while it's cancelling that sync"
            )
        } else if indeterminateProgressShouldShow || appearanceTransitionState != .finished {
            OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_PROGRESS_TITLE_PREPARING",
                comment: "Title for a progress modal indicating the sync progress while it's preparing for upload"
            )
        } else {
            OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_PROGRESS_TITLE",
                comment: "Title for a progress modal indicating the sync progress"
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                CircleProgressView(progress: progressToShow)
                    .animation(.smooth, value: appearanceTransitionState)
                    .animation(.smooth, value: indeterminateProgressShouldShow)

                if showIndeterminateProgress {
                    LottieView(animation: .named("circular_indeterminate"))
                        .playing(loopMode: loopMode)
                        .animationDidFinish { completed in
                            print("animationDidFinish: \(completed)")
                            guard completed else { return }
                            indeterminateProgressShouldShow = false
                        }
                        .onAppear {
                            indeterminateProgressShouldShow = true
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
                    self.indeterminateProgressShouldShow = false
                }
            }

            Text(title)
                .font(.headline)
                .padding(.bottom, 8)
                .animation(.none, value: title)

            Text(String(
                format: OWSLocalizedString(
                    "LINK_NEW_DEVICE_SYNC_PROGRESS_PERCENT",
                    comment: "On a progress modal indicating the percent complete the sync process is. Embeds {{ formatted percentage }}"
                ),
                progressToShow.formatted(.percent.precision(.fractionLength(0)))
            ))
            .font(.subheadline.monospacedDigit())
            .animation(.none, value: viewModel.progress)
            .padding(.bottom, 2)

            Text(OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_PROGRESS_DO_NOT_CLOSE_APP",
                comment: "On a progress modal"
            ))
            .font(.subheadline)
            .foregroundStyle(Color.Signal.secondaryLabel)
            .padding(.bottom, 36)

            Button(CommonStrings.cancelButton) {
                viewModel.cancel()
            }
            .disabled(!viewModel.cancelButtonEnabled)
            .font(.body.weight(.semibold))

#if DEBUG
            Text("DEBUG: " + (viewModel.progressSourceLabel ?? "none"))
                .padding(.top)
                .foregroundStyle(Color.Signal.quaternaryLabel)
                .animation(.none, value: viewModel.progressSourceLabel)
#endif
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32))
        .padding(.horizontal, 60)
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

@MainActor
@available(iOS 17, *)
private func setupDemoProgress(
    modal: LinkAndSyncProgressModal,
    slowLinking: Bool
) async throws {
    let progress = OWSProgress.createSink { progress in
        modal.viewModel.updateProgress(progress: progress)
    }

    let waitForLinkingProgress = await progress.addSource(
        withLabel: PrimaryLinkNSyncProgressPhase.waitingForLinking.rawValue,
        unitCount: PrimaryLinkNSyncProgressPhase.waitingForLinking.percentOfTotalProgress
    )
    let exportingBackupProgress = await progress.addSource(
        withLabel: PrimaryLinkNSyncProgressPhase.exportingBackup.rawValue,
        unitCount: PrimaryLinkNSyncProgressPhase.exportingBackup.percentOfTotalProgress
    )
    let uploadingBackupProgress = await progress.addSource(
        withLabel: PrimaryLinkNSyncProgressPhase.uploadingBackup.rawValue,
        unitCount: PrimaryLinkNSyncProgressPhase.uploadingBackup.percentOfTotalProgress
    )
    let markUploadedProgress = await progress.addSource(
        withLabel: PrimaryLinkNSyncProgressPhase.finishing.rawValue,
        unitCount: PrimaryLinkNSyncProgressPhase.finishing.percentOfTotalProgress
    )

    if slowLinking {
        try await Task.sleep(for: .milliseconds(700))
    } else {
        try await Task.sleep(for: .milliseconds(100))
    }

    waitForLinkingProgress.incrementCompletedUnitCount(by: PrimaryLinkNSyncProgressPhase.waitingForLinking.percentOfTotalProgress)

    if slowLinking {
        try await Task.sleep(for: .milliseconds(700))
    } else {
        try await Task.sleep(for: .milliseconds(100))
    }

    func simulateProgress(for source: OWSProgressSource) async throws {
        for _ in 0..<(source.totalUnitCount / 2) {
            source.incrementCompletedUnitCount(by: 2)
            try await Task.sleep(for: .milliseconds(50))
        }

        source.incrementCompletedUnitCount(by: source.totalUnitCount)
    }

    try await simulateProgress(for: exportingBackupProgress)
    try await simulateProgress(for: uploadingBackupProgress)

    try await Task.sleep(for: .milliseconds(500))

    try Task.checkCancellation()
    markUploadedProgress.incrementCompletedUnitCount(by: PrimaryLinkNSyncProgressPhase.finishing.percentOfTotalProgress)

    await modal.completeAndDismiss()
}

@MainActor
@available(iOS 17, *)
func demoTask(
    modal: LinkAndSyncProgressModal,
    slowLinking: Bool
) -> Task<Void, Never> {
    Task {
        do {
            try await setupDemoProgress(modal: modal, slowLinking: slowLinking)
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
        let modal = LinkAndSyncProgressModal()
        modal.linkNSyncTask = demoTask(modal: modal, slowLinking: true)
        return modal
    }
}

@available(iOS 17, *)
#Preview("Fast linking") {
    SheetPreviewViewController(animateFirstAppearance: true) {
        let modal = LinkAndSyncProgressModal()
        modal.linkNSyncTask = demoTask(modal: modal, slowLinking: false)
        return modal
    }
}
#endif
