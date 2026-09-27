//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import DeviceDiscoveryUI
import Lottie
import SignalServiceKit
import SignalUI
import SwiftUI
import WiFiAware

// MARK: - DeviceTransferStatusViewController

class DeviceTransferStatusViewController: HostingController<TransferWrapperView> {
    override var prefersNavigationBarHidden: Bool { true }

    private let coordinator: DeviceTransferCoordinator
    private var pairedPeerListenTask: Task<Void, Error>?

    init(coordinator: DeviceTransferCoordinator) {
        self.coordinator = coordinator

        super.init(
            wrappedView: TransferWrapperView(
                viewModel: coordinator.transferStatusViewModel,
                isNewDevice: true,
            ),
        )

        self.pairedPeerListenTask = Task { [weak self] in
            for try await _ in coordinator.pairedPeerStream {
                guard let vc = self?.presentedViewController else { return }
                vc.dismiss(animated: true)
                self?.presentContinueOnOtherDevicePrompt()
            }
        }

        coordinator.confirmCancellation = { [weak self] in
            guard let self else { return true }
            return await self.confirmCancellation()
        }

        coordinator.onTransferStart = { [weak self] in
            if let vc = self?.presentedViewController {
                vc.dismiss(animated: true)
            }
        }

        coordinator.onSuccess = { [weak self] in
            let sheet = HeroSheetViewController(
                hero: .image(UIImage(named: "transfer_complete")!),
                title: OWSLocalizedString(
                    "TRANSFER_COMPLETE_SHEET_TITLE",
                    comment: "Title for bottom sheet shown when device transfer completes on the receiving device.",
                ),
                body: OWSLocalizedString(
                    "TRANSFER_COMPLETE_SHEET_SUBTITLE",
                    comment: "Subtitle for bottom sheet shown when device transfer completes on the receiving device.",
                ),
                primaryButton: .init(
                    title: CommonStrings.okayButton,
                ) { _ in
                    Task {
                        SSKEnvironment.shared.notificationPresenterRef.notifyUserToRelaunchAfterTransfer {
                            Logger.info("Deliberately terminating app post-transfer.")
                            exit(0)
                        }
                    }
                    self?.dismiss(animated: true)
                },
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
                    comment: "The title of the dialog asking the user if they want to cancel a device transfer",
                ),
                message: OWSLocalizedString(
                    "DEVICE_TRANSFER_CANCEL_CONFIRMATION_MESSAGE",
                    comment: "The message of the dialog asking the user if they want to cancel a device transfer",
                ),
            )

            let okAction = ActionSheetAction(
                title: OWSLocalizedString(
                    "DEVICE_TRANSFER_CANCEL_CONFIRMATION_ACTION",
                    comment: "The stop action of the dialog asking the user if they want to cancel a device transfer",
                ),
                style: .destructive,
            ) { _ in
                continuation.resume(returning: true)
            }
            actionSheet.addAction(okAction)

            let cancelAction = ActionSheetAction(
                title: CommonStrings.cancelButton,
                style: .cancel,
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
                try await coordinator.reportTransferMethodChoice()
                try await coordinator.waitForTransferFromPeer(peer: nil)
            } catch {
                coordinator.onFailure(error)
            }
        }
    }

    private func presentContinueOnOtherDevicePrompt() {
        let sheet = HeroSheetViewController(
            hero: .image(UIImage(resource: .otherTransferDevice)),
            title: OWSLocalizedString(
                "INCOMING_DEVICE_TRANSFER_CONTINUE_TITLE",
                comment: "Title of prompt notifying device transfer will continue on other device.",
            ),
            body: HeroSheetViewController.Body([.text(.plain(OWSLocalizedString(
                "INCOMING_DEVICE_TRANSFER_CONTINUE_BODY",
                comment: "Body of prompt notifying device transfer will continue on other device.",
            )))]),
            primary: .hero(.animation(named: "circular_indeterminate", height: 60)),
            secondary: .button(.dismissing(title: CommonStrings.cancelButton)),
        )
        present(sheet, animated: true)
    }
}

struct TransferWrapperView: View {
    @ObservedObject var viewModel: TransferStatusViewModel
    var isNewDevice: Bool

    var body: some View {
        if
            #available(iOS 26.0, *),
            viewModel.supportsWifiAware
        {
            switch viewModel.state {
            case .idle, .starting:
                TransferPairingView(viewModel: viewModel, isNewDevice: isNewDevice)
            case .cancelled, .connecting, .finishing, .done, .error, .transferring:
                TransferStatusView(viewModel: viewModel, isNewDevice: isNewDevice)
            }
        } else {
            TransferStatusView(viewModel: viewModel, isNewDevice: isNewDevice)
        }
    }
}

@available(iOS 26.0, *)
struct TransferPairingView: View {
    @ObservedObject var viewModel: TransferStatusViewModel
    var isNewDevice: Bool

    func title(isNewDevice: Bool) -> some View {
        let titleText: String
        if isNewDevice {
            titleText = OWSLocalizedString(
                "DEVICE_TRANSFER_PAIR_NEW_DEVICE_TITLE",
                comment: "Title of the device transfer screen for pairing a new device, from the new device",
            )
        } else {
            titleText = OWSLocalizedString(
                "DEVICE_TRANSFER_PAIR_OLD_DEVICE_TITLE",
                comment: "Title of the device transfer screen for pairing a new device, from the old device",
            )
        }
        return Text(titleText)
            .font(.title.weight(.semibold))
            .multilineTextAlignment(.center)
    }

    func body(isNewDevice: Bool) -> some View {
        let bodyText: String
        if isNewDevice {
            bodyText = OWSLocalizedString(
                "DEVICE_TRANSFER_PAIR_NEW_DEVICE_MESSAGE",
                comment: "Body of the device transfer screen for pairing a new device, from the new device",
            )
        } else {
            bodyText = OWSLocalizedString(
                "DEVICE_TRANSFER_PAIR_OLD_DEVICE_MESSAGE",
                comment: "Body of the device transfer screen for pairing a new device, from the old device",
            )
        }
        return Text(bodyText)
            .font(.body)
            .foregroundStyle(Color.Signal.secondaryLabel)
            .multilineTextAlignment(.center)
    }

    var body: some View {
        VStack(spacing: 12) {
            Image("device-transfer")
                .padding(.top, 32)
            title(isNewDevice: isNewDevice)
                .padding(.top, 8)
                .padding(.horizontal, 8)
            body(isNewDevice: isNewDevice)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .padding(.horizontal, 8)
            TutorialStack(isNewDevice: isNewDevice)
            Spacer()
            if !isNewDevice {
                DevicePicker(
                    .wifiAware(
                        .connecting(
                            to: .userSpecifiedDevices,
                            from: .deviceTransferService,
                        ),
                    ),
                ) { endpoint in
                    viewModel.onPeerSelected(WADeviceTransferPeer(pairedDevice: endpoint.device))
                } label: {
                    Button(OWSLocalizedString(
                        "DEVICE_TRANSFER_STATUS_OLD_DEVICE_PAIR_DEVICE",
                        comment: "Title for paring an new device to transfer to.",
                    )) {}
                        .buttonStyle(Registration.UI.LargePrimaryButtonStyle())
                        .allowsHitTesting(false) // necessary to let touches pass to DevicePicker
                } fallback: {}
            } else {
                DevicePairingView(
                    .wifiAware(
                        .connecting(
                            to: .deviceTransferService,
                            from: .allPairedDevices,
                        ),
                    ),
                ) {
                    Button(OWSLocalizedString(
                        "DEVICE_TRANSFER_STATUS_NEW_DEVICE_PAIR_DEVICE",
                        comment: "Title for paring an old device to transfer to.",
                    )) {}
                        .buttonStyle(Registration.UI.LargePrimaryButtonStyle())
                        .allowsHitTesting(false) // necessary to let touches pass to DevicePairingView
                } fallback: {}
            }
            Button(CommonStrings.cancelButton) {
                Task {
                    await viewModel.propmtUserToCancelTransfer()
                }
            }
            .buttonStyle(Registration.UI.LargeSecondaryButtonStyle())
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 32)
    }
}

private struct TutorialStack: View {
    var isNewDevice: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Label(
                OWSLocalizedString(
                    "DEVICE_TRANSFER_TUTORIAL_ENABLE_WIFI_MESSAGE",
                    comment: "Message informing the user to enable wifi and bluetooth on device",
                ),
                image: "wifi",
            )
            .fixedSize(horizontal: false, vertical: true)
            if isNewDevice {
                Label(
                    OWSLocalizedString(
                        "DEVICE_TRANSFER_TUTORIAL_TAP_PAIR_DEVICE_MESSAGE",
                        comment: "Message informing the user to tap on the pair device button",
                    ),
                    image: "tap-hand",
                )
                .fixedSize(horizontal: false, vertical: true)
                Label(
                    OWSLocalizedString(
                        "DEVICE_TRANSFER_TUTORIAL_CONTINUE_OLD_DEVICE_MESSAGE",
                        comment: "Message informing the user to continue on the old device",
                    ),
                    image: "device-phone",
                )
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(
                    OWSLocalizedString(
                        "DEVICE_TRANSFER_TUTORIAL_TAP_PAIR_NEW_DEVICE_MESSAGE",
                        comment: "Message informing the user to tap on the pair device button",
                    ),
                    image: "tap-hand",
                )
                .fixedSize(horizontal: false, vertical: true)
                Label(
                    OWSLocalizedString(
                        "DEVICE_TRANSFER_TUTORIAL_SELECT_NEW_DEVICE_MESSAGE",
                        comment: "Message informing the user to select the new device when prompted",
                    ),
                    image: "device-phone",
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
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

                let useWiFiAware = if #available(iOS 26.0, *), viewModel.supportsWifiAware {
                    true
                } else {
                    false
                }
                Text(indefinite.title(isNewDevice: isNewDevice, supportsWifiAware: useWiFiAware))
                    .font(.body.bold())
                    .foregroundStyle(Color.Signal.label)
                Text(indefinite.message(isNewDevice: isNewDevice, supportsWifiAware: useWiFiAware))
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
                    comment: "Title for a progress view displayed during device transfer.",
                ))
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.Signal.label)
                .padding(.top, 44)
                .padding(.bottom, 2)
                Text(OWSLocalizedString(
                    "DEVICE_TRANSFER_STATUS_NEW_DEVICE_TRANSFERRING_DESCRIPTION",
                    comment: "Description in the progress view displayed during device transfer.",
                ))
                .font(.body)
                .foregroundStyle(Color.Signal.secondaryLabel)

                Spacer()
                Text("\(progress.formatted(.owsPercent()))")
                    .font(.body.monospacedDigit())
                    .padding(.bottom, 12)
                StyledProgressBar(style: .determinate(percentComplete: Float(progress), pulse: false))
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
            case .finishing:
                Text(OWSLocalizedString(
                    "DEVICE_TRANSFER_STATUS_NEW_DEVICE_TRANSFERRING",
                    comment: "Title for a progress view displayed during device transfer.",
                ))
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.Signal.label)
                .padding(.top, 44)
                .padding(.bottom, 2)
                Text(OWSLocalizedString(
                    "DEVICE_TRANSFER_STATUS_NEW_DEVICE_TRANSFERRING_DESCRIPTION",
                    comment: "Description in the progress view displayed during device transfer.",
                ))
                .font(.body)
                .foregroundStyle(Color.Signal.secondaryLabel)

                Spacer()
                StyledProgressBar(style: .indeterminate)
                    .padding(.top, 42)
                Text(OWSLocalizedString(
                    "DEVICE_TRANSFER_STATUS_DEVICE_FINISHING",
                    comment: "Description in the progress view displayed during device transfer finalization.",
                ))
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
                    comment: "Title for a progress view displayed after failure of device transfer.",
                ))
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.Signal.label)
                .padding(.top, 44)
                .padding(.bottom, 2)
                Text(OWSLocalizedString(
                    "DEVICE_TRANSFER_STATUS_NEW_DEVICE_TRANSFER_FAILED_BODY",
                    comment: "Description in the progress view displayed after failure of device transfer.",
                ))
                .font(.body)
                .foregroundStyle(Color.Signal.secondaryLabel)
                Spacer()
                Button(CommonStrings.tryAgainButton) {
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

@available(iOS 26, *)
#Preview {
    let viewModel = TransferStatusViewModel()
    viewModel.cancelTransferBlock = { print("onCancel") }
    viewModel.onSuccess = { print("onSuccess") }
    return TransferPairingView(viewModel: viewModel, isNewDevice: true)
}
#endif
