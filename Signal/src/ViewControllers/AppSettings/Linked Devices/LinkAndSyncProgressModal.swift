//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SwiftUI
import SignalUI
import SignalServiceKit

// MARK: View Model

class LinkAndSyncProgressViewModel: ObservableObject {
    @Published var progress: Float = 0
}

// MARK: Hosting Controller

class LinkAndSyncProgressModal: HostingController<LinkAndSyncProgressView> {

    private let viewModel = LinkAndSyncProgressViewModel()

    var progress: Float {
        get { viewModel.progress }
        set { viewModel.progress = newValue }
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
        progress = 1
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
        VStack(spacing: 8) {
            CircleProgressView(progress: progressToShow)
                .padding(.bottom, 12)
                .animation(.linear, value: progressToShow)

            Text(OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_PROGRESS_TITLE",
                comment: "Title for a progress modal indicating the sync progress"
            ))
            .font(.headline)

            Text(String(
                format: OWSLocalizedString(
                    "LINK_NEW_DEVICE_SYNC_PROGRESS_PERCENT",
                    comment: "On a progress modal indicating the percent complete the sync process is. Embeds {{ formatted percentage }}"
                ),
                progressToShow.formatted(.percent.precision(.fractionLength(0)))
            ))
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(Color.Signal.secondaryLabel)
            .animation(.none, value: viewModel.progress)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 42)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32))
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

        Task { @MainActor in
            modal.progress = 0.2
            let loadingPoints = (0..<20)
                .map { _ in Float.random(in: (0.2)...1) }
                .sorted()

            for point in loadingPoints {
                try? await Task.sleep(for: .milliseconds(100))
                modal.progress = point
            }

            try? await Task.sleep(for: .milliseconds(100))
            modal.progress = 1

            await modal.completeAndDismiss()
        }

        return modal
    }
}
#endif
