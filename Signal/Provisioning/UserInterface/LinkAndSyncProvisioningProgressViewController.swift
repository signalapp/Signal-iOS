//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SwiftUI
import SignalUI
import SignalServiceKit

class LinkAndSyncSecondaryProgressViewModel: ObservableObject {
    @Published private(set) var progress: Float = 0
    @Published private(set) var canBeCancelled: Bool = false
    @Published var linkNSyncTask: Task<Void, Error>?
    @Published var didTapCancel: Bool = false

    func updateProgress(_ progress: OWSProgress) {
        let canBeCancelled: Bool
        if let label = progress.currentSourceLabel {
            canBeCancelled = label != SecondaryLinkNSyncProgressPhase.waitingForBackup.rawValue
        } else {
            canBeCancelled = false
        }
        self.progress = progress.percentComplete
        self.canBeCancelled = canBeCancelled
    }
}

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

struct LinkAndSyncProvisioningProgressView: View {

    @ObservedObject fileprivate var viewModel: LinkAndSyncSecondaryProgressViewModel

    private var subtitle: String {
        if viewModel.progress <= 0 {
            OWSLocalizedString(
                "LINKING_SYNCING_PREPARING_TO_DOWNLOAD",
                comment: "Progress label when the message loading has not yet started during the device linking process"
            )
        } else if viewModel.progress < 1 {
            String(
                format: OWSLocalizedString(
                    "LINK_NEW_DEVICE_SYNC_PROGRESS_PERCENT",
                    comment: "On a progress modal indicating the percent complete the sync process is. Embeds {{ formatted percentage }}"
                ),
                viewModel.progress.formatted(.percent.precision(.fractionLength(0)))
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
            .font(.title2)
            .foregroundStyle(Color.Signal.label)
            .padding(.bottom, 24)

            Group {
                ProgressView(value: viewModel.progress)
                    .frame(maxWidth: 330)
                    .padding(.bottom, 12)
                    // TODO: this should become an "indefinite" animation
                    // when cancelled.
                    .animation(.default, value: viewModel.progress)

                Text(verbatim: subtitle)
                    .font(.footnote.monospacedDigit())
                    .padding(.bottom, 22)

                Text(OWSLocalizedString(
                    "LINKING_SYNCING_TIMING_INFO",
                    comment: "Label below the progress bar when loading messages during linking process"
                ))
                .font(.subheadline)

                Spacer()

                if viewModel.canBeCancelled, let linkNSyncTask = viewModel.linkNSyncTask {
                    Button(CommonStrings.cancelButton) {
                        viewModel.didTapCancel = true
                        linkNSyncTask.cancel()
                    }
                    .disabled(viewModel.didTapCancel)
                }

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
            .tint(Color.Signal.accent)
        }
        .padding()
        .multilineTextAlignment(.center)
    }
}

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
        let nonCancellableProgressSource = await progressSink.addSource(
            withLabel: SecondaryLinkNSyncProgressPhase.waitingForBackup.rawValue,
            unitCount: 50
        )
        let cancellableProgressSource = await progressSink.addSource(withLabel: "", unitCount: 50)

        try? await Task.sleep(for: .seconds(1))

        while nonCancellableProgressSource.completedUnitCount < 50 {
            nonCancellableProgressSource.incrementCompletedUnitCount(by: 1)
            try? await Task.sleep(for: .milliseconds(100))
        }

        while cancellableProgressSource.completedUnitCount < 50 {
            cancellableProgressSource.incrementCompletedUnitCount(by: 1)
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    view.linkNSyncTask = Task {
        await task.value
    }

    return view
}
#endif
