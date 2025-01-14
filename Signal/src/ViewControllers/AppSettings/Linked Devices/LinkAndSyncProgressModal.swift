//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SwiftUI
import SignalUI
import SignalServiceKit

// MARK: View Model

class LinkAndSyncProgressViewModel: ObservableObject {

    enum Phase {
        case preparing
        case syncing
    }

    @Published private(set) var progress: Float = 0
    @Published private(set) var canBeCancelled: Bool = false
    @Published var phase: Phase = .preparing
    @Published var linkNSyncTask: Task<Void, Never>?
    @Published var didTapCancel: Bool = false

    var cancelButtonEnabled: Bool {
        linkNSyncTask != nil && canBeCancelled && !didTapCancel
    }

    var title: String {
        switch phase {
        case .preparing:
            OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_PROGRESS_TITLE_PREPARING",
                comment: "Title for a progress modal indicating the sync progress while it's preparing for upload"
            )
        case .syncing:
            OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_PROGRESS_TITLE",
                comment: "Title for a progress modal indicating the sync progress"
            )
        }
    }

    func updateProgress(progress: Float, canBeCancelled: Bool) {
        self.progress = progress
        self.canBeCancelled = canBeCancelled
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

    // If the first portion fills very quickly before the view is visible,
    // we still want to animate it from 0.
    private var progressToShow: Float {
        switch appearanceTransitionState {
        case .appearing:
            0
        case .cancelled, .finished, .none:
            viewModel.progress
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // TODO: this should become an "indefinite" animation when cancelled
            CircleProgressView(progress: progressToShow)
                .padding(.top, 14)
                .padding(.bottom, 20)
                .animation(.linear, value: progressToShow)

            Text(viewModel.title)
                .font(.headline)
                .padding(.bottom, 8)

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
                viewModel.linkNSyncTask?.cancel()
                viewModel.didTapCancel = true
            }
            .disabled(!viewModel.cancelButtonEnabled)
            .font(.body.weight(.semibold))
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
                    .animation(.linear, value: progress)
            }
            .frame(width: 52, height: 52)
        }
    }
}

// MARK: Previews

#if DEBUG
@available(iOS 17, *)
#Preview {
    SheetPreviewViewController {
        let modal = LinkAndSyncProgressModal()
        modal.linkNSyncTask = Task {}

        Task { @MainActor in
            modal.viewModel.updateProgress(progress: 0.2, canBeCancelled: false)
            let loadingPoints = (0..<20)
                .map { _ in Float.random(in: (0.2)...1) }
                .sorted()

            for point in loadingPoints {
                try? await Task.sleep(for: .milliseconds(100))
                modal.viewModel.updateProgress(progress: point, canBeCancelled: point >= 0.4)
                modal.viewModel.phase = point >= 0.6 ? .syncing : .preparing
            }

            try? await Task.sleep(for: .milliseconds(100))
            modal.viewModel.updateProgress(progress: 1, canBeCancelled: true)

            await modal.completeAndDismiss()
        }

        return modal
    }
}
#endif
