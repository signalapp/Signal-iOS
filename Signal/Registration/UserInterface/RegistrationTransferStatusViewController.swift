//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalServiceKit
import SignalUI
import SwiftUI

// MARK: - RegistrationTransferStatusPresenter

protocol RegistrationTransferStatusPresenter: AnyObject {
    func cancelTransfer()
}

// MARK: - RegistrationTransferStatusViewController

class RegistrationTransferStatusViewController: HostingController<TransferStatusView> {
    private let state: RegistrationTransferStatusState

    init(
        state: RegistrationTransferStatusState,
        presenter: RegistrationTransferStatusPresenter? = nil
    ) {
        self.state = state

        super.init(wrappedView: TransferStatusView(viewModel: state.transferStatusViewModel))

        state.onCancel = {
            presenter?.cancelTransfer()
        }

        state.onSuccess = { [weak self] in
            let sheet = HeroSheetViewController(
                hero: .image(UIImage(named: "transfer_complete")!),
                title: OWSLocalizedString(
                    "TRANSFER_COMPLETE_SHEET_TITLE",
                    comment: "Title for bottom sheet shown when device transfer completes on the receiving device."
                ),
                body: OWSLocalizedString(
                    "TRANSFER_COMPLETE_SHEET_SUBTITLE",
                    comment: "Subtitle for bottom sheet shown when device transfer completes on the receiving device."
                ),
                primaryButton: .init(
                    title: CommonStrings.okayButton
                ) { _ in
                    // TODO: [Backups] - This should be handled through the presenter
                    Task {
                        SSKEnvironment.shared.notificationPresenterRef.notifyUserToRelaunchAfterTransfer {
                            Logger.info("Deliberately terminating app post-transfer.")
                            exit(0)
                        }
                    }
                    self?.dismiss(animated: true)
                }
            )
            self?.present(sheet, animated: true)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            do {
                try await state.start()
            } catch {
                // TODO: [Backups] - Display an error to the user
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        state.onCancel()
        super.viewDidDisappear(animated)
    }
}

struct TransferStatusView: View {
    @ObservedObject private var viewModel: TransferStatusViewModel
    init(viewModel: TransferStatusViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack {
            LottieView(animation: .named("circular_indeterminate")).playing(loopMode: .loop)
            Text(viewModel.state.label)
                .foregroundStyle(Color.Signal.label)
        }
    }
}

#if DEBUG
private var viewModel = TransferStatusViewModel()
@available(iOS 17, *)
#Preview {
    {
        viewModel.onCancel = { print("onCancel") }
        viewModel.onSuccess = { print("onSuccess") }
        viewModel.state = .transferring(0.12345)
        return TransferStatusView(viewModel: viewModel)
    }()
}
#endif
