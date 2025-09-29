//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MultipeerConnectivity
import SignalServiceKit
import SignalUI

final class OutgoingDeviceTransferProgressViewController: DeviceTransferBaseViewController {

    override var requiresDismissConfirmation: Bool {
        switch DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction {
        case .transferringLinkedOutgoing, .transferringPrimaryOutgoing:
            return true
        default:
            return false
        }
    }

    let progressView: TransferProgressView
    init(progress: Progress) {
        self.progressView = TransferProgressView(progress: progress)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let titleLabel = self.titleLabel(
            text: OWSLocalizedString("DEVICE_TRANSFER_TRANSFERRING_TITLE",
                                    comment: "The title on the action sheet that shows transfer progress")
        )
        contentView.addArrangedSubview(titleLabel)

        contentView.addArrangedSubview(.spacer(withHeight: 12))

        let explanationLabel = self.explanationLabel(
            explanationText: OWSLocalizedString("DEVICE_TRANSFER_TRANSFERRING_EXPLANATION",
                                               comment: "The explanation on the action sheet that shows transfer progress")
        )
        contentView.addArrangedSubview(explanationLabel)

        let topSpacer = UIView.vStretchingSpacer()
        contentView.addArrangedSubview(topSpacer)

        contentView.addArrangedSubview(progressView)

        let bottomSpacer = UIView.vStretchingSpacer()
        contentView.addArrangedSubview(bottomSpacer)
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        progressView.startUpdatingProgress()

        AppEnvironment.shared.deviceTransferServiceRef.addObserver(self)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        progressView.stopUpdatingProgress()

        AppEnvironment.shared.deviceTransferServiceRef.removeObserver(self)
        AppEnvironment.shared.deviceTransferServiceRef.cancelTransferFromOldDevice()
    }

    @objc
    private func didTapNext() {
        let qrScanner = OutgoingDeviceTransferQRScanningViewController()
        navigationController?.pushViewController(qrScanner, animated: true)
    }
}

extension OutgoingDeviceTransferProgressViewController: DeviceTransferServiceObserver {
    func deviceTransferServiceDiscoveredNewDevice(peerId: MCPeerID, discoveryInfo: [String: String]?) {}

    func deviceTransferServiceDidStartTransfer(progress: Progress) {}

    func deviceTransferServiceDidEndTransfer(error: DeviceTransferService.Error?) {
        AppEnvironment.shared.deviceTransferServiceRef.removeObserver(self)

        guard let error = error else {
            transferNavigationController?.dismissActionSheet()
            return
        }

        switch error {
        case .assertion:
            progressView.renderError(
                text: OWSLocalizedString("DEVICE_TRANSFER_ERROR_GENERIC",
                                        comment: "An error indicating that something went wrong with the transfer and it could not complete")
            )
        case .backgroundedDevice:
            progressView.renderError(
                text: OWSLocalizedString(
                    "DEVICE_TRANSFER_ERROR_BACKGROUNDED",
                    comment: "An error indicating that the other device closed signal mid-transfer and it could not complete"
                )
            )
        case .cancel:
            // User initiated, nothing to do
            break
        case .certificateMismatch:
            progressView.renderError(
                text: OWSLocalizedString("DEVICE_TRANSFER_ERROR_CERTIFICATE_MISMATCH",
                                        comment: "An error indicating that we were unable to verify the identity of the new device to complete the transfer")
            )
        case .notEnoughSpace:
            owsFailDebug("This should never happen on the old device")
        case .unsupportedVersion:
            progressView.renderError(
                text: OWSLocalizedString("DEVICE_TRANSFER_ERROR_UNSUPPORTED_VERSION",
                                        comment: "An error indicating the user must update their device before trying to transfer.")
            )
        case .modeMismatch:
            owsFailDebug("this should never happen")
        }
    }

    func deviceTransferServiceDidRequestAppRelaunch() {
        owsFail("Relaunch not supported for outgoing transfer; only on the receiving device during transfer")
    }
}
