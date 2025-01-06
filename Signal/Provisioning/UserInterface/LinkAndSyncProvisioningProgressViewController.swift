//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SwiftUI
import SignalUI
import SignalServiceKit

class LinkAndSyncProvisioningProgressViewController: HostingController<LinkAndSyncProvisioningProgressView> {
    private var viewModel: LinkAndSyncProgressViewModel

    var progress: Float {
        get {
            viewModel.progress
        }
        set {
            viewModel.progress = newValue
        }
    }

    init(viewModel: LinkAndSyncProgressViewModel) {
        self.viewModel = viewModel
        super.init(wrappedView: LinkAndSyncProvisioningProgressView(viewModel: viewModel))
        self.modalPresentationStyle = .fullScreen
        self.modalTransitionStyle = .crossDissolve
    }
}

struct LinkAndSyncProvisioningProgressView: View {

    @ObservedObject fileprivate var viewModel: LinkAndSyncProgressViewModel

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
    let view = LinkAndSyncProvisioningProgressViewController(viewModel: LinkAndSyncProgressViewModel())

    Task { @MainActor in
        try? await Task.sleep(for: .seconds(1))

        let loadingPoints = (0..<20)
            .map { _ in Float.random(in: 0...1) }
            .sorted()

        for point in loadingPoints {
            try? await Task.sleep(for: .milliseconds(100))
            view.progress = point
        }

        try? await Task.sleep(for: .milliseconds(100))
        view.progress = 1

        try? await Task.sleep(for: .seconds(1))
    }

    return view
}
#endif
