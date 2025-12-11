//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalServiceKit
import SignalUI
import SwiftUI

// MARK: - DeviceTransferStatusViewController

class DeviceTransferStatusViewController: HostingController<TransferStatusView> {
    override var prefersNavigationBarHidden: Bool { true }

    private let coordinator: DeviceTransferCoordinator

    init(coordinator: DeviceTransferCoordinator) {
        self.coordinator = coordinator

        super.init(wrappedView: TransferStatusView(viewModel: coordinator.transferStatusViewModel, isNewDevice: true))

        coordinator.confirmCancellation = { [weak self] in
            guard let self else { return true }
            return await self.confirmCancellation()
        }

        coordinator.onSuccess = { [weak self] in
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

    @MainActor
    func confirmCancellation() async -> Bool {
        Logger.info("")

        return await withCheckedContinuation { continuation in
            let actionSheet = ActionSheetController(
                title: OWSLocalizedString(
                    "DEVICE_TRANSFER_CANCEL_CONFIRMATION_TITLE",
                    comment: "The title of the dialog asking the user if they want to cancel a device transfer"
                ),
                message: OWSLocalizedString(
                    "DEVICE_TRANSFER_CANCEL_CONFIRMATION_MESSAGE",
                    comment: "The message of the dialog asking the user if they want to cancel a device transfer"
                )
            )

            let okAction = ActionSheetAction(
                title: OWSLocalizedString(
                    "DEVICE_TRANSFER_CANCEL_CONFIRMATION_ACTION",
                    comment: "The stop action of the dialog asking the user if they want to cancel a device transfer"
                ),
                style: .destructive
            ) { _ in
                continuation.resume(returning: true)
            }
            actionSheet.addAction(okAction)

            let cancelAction = ActionSheetAction(
                title: CommonStrings.cancelButton,
                style: .cancel
            ) { _ in
                continuation.resume(returning: false)
            }
            actionSheet.addAction(cancelAction)

            present(actionSheet, animated: true)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            do {
                try await coordinator.start()
            } catch {
                coordinator.onFailure(error)
            }
        }
    }
}

struct TransferStatusView: View {
    @ObservedObject var viewModel: TransferStatusViewModel
    var isNewDevice: Bool

    var body: some View {
        VStack(spacing: 10) {
            switch viewModel.viewState {
            case .indefinite(let indefinite):
                Spacer()
                // The indefinite states are combined into the same view state
                // to maintain the LottieView's identity and prevent the
                // animation from restarting when the state changes.
                LottieView(animation: .named("circular_indeterminate"))
                    .playing(loopMode: .loop)
                    .padding(.bottom, 14)
                Text(indefinite.title(isNewDevice: isNewDevice))
                    .font(.body.bold())
                    .foregroundStyle(Color.Signal.label)
                Text(indefinite.message(isNewDevice: isNewDevice))
                    .font(.body)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                Spacer()
                Button(CommonStrings.cancelButton) {
                    Task {
                        await viewModel.propmtUserToCancelTransfer()
                    }
                }
                .buttonStyle(Registration.UI.MediumSecondaryButtonStyle())
                .padding(.bottom, 32)
            case .transferring(let progress):
                Text(OWSLocalizedString(
                    "DEVICE_TRANSFER_STATUS_NEW_DEVICE_TRANSFERRING",
                    comment: "Title for a progress view displayed during device transfer."
                    ))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.Signal.label)
                    .padding(.top, 44)
                    .padding(.bottom, 2)
                Text(OWSLocalizedString(
                    "DEVICE_TRANSFER_STATUS_NEW_DEVICE_TRANSFERRING_DESCRIPTION",
                    comment: "Description in the progress view displayed during device transfer."
                    ))
                    .font(.body)
                    .foregroundStyle(Color.Signal.secondaryLabel)

                Spacer()
                Text("\(progress.formatted(.percent.precision(.fractionLength(0))))")
                    .font(.body.monospacedDigit())
                    .padding(.bottom, 12)
                LinearProgressView(progress: progress)
                    .animation(.smooth, value: progress)
                    .padding(.bottom, 6)
                Text(viewModel.progressEstimateLabel)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                Spacer()
                Button(CommonStrings.cancelButton) {
                    Task {
                        await viewModel.propmtUserToCancelTransfer()
                    }
                }
                .buttonStyle(Registration.UI.MediumSecondaryButtonStyle())
                .padding(.bottom, 32)
            case .error(let error):
                Text(OWSLocalizedString(
                    "DEVICE_TRANSFER_STATUS_NEW_DEVICE_TRANSFER_FAILED_TITLE",
                    comment: "Title for a progress view displayed after failure of device transfer."
                    ))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.Signal.label)
                    .padding(.top, 44)
                    .padding(.bottom, 2)
                Text(OWSLocalizedString(
                    "DEVICE_TRANSFER_STATUS_NEW_DEVICE_TRANSFER_FAILED_BODY",
                    comment: "Description in the progress view displayed after failure of device transfer."
                    ))
                    .font(.body)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                Spacer()
                Button(OWSLocalizedString(
                    "DEVICE_TRANSFER_TRY_AGAIN_ACTION",
                    comment: "Action asking user to try again after transfer failure."
                )) {
                    viewModel.onFailure(error)
                }
                .buttonStyle(Registration.UI.MediumSecondaryButtonStyle())
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .multilineTextAlignment(.center)
    }
}

// MARK: - Previews

#if DEBUG
@available(iOS 17, *)
#Preview {
    let viewModel = TransferStatusViewModel()
    viewModel.cancelTransferBlock = { print("onCancel") }
    viewModel.onSuccess = { print("onSuccess") }
    var task = Task {
        try? await viewModel.simulateProgressForPreviews()
    }
    return TransferStatusView(viewModel: viewModel, isNewDevice: true)
        .overlay(alignment: .bottom) {
            Button(LocalizationNotNeeded("PREVIEW: Restart")) {
                task.cancel()
                task = Task {
                    try? await viewModel.simulateProgressForPreviews()
                }
            }
            .foregroundStyle(Color(UIColor.red))
            .opacity(0.7)
        }
}
#endif
