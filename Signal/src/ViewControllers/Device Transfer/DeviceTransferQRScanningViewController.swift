//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import ZXingObjC
import MultipeerConnectivity

class DeviceTransferQRScanningViewController: DeviceTransferBaseViewController {
    var deviceTransferService: DeviceTransferService { .shared }

    var capture: ZXCapture?
    var isCapturing = false

    lazy var maskingContainerView: UIView = {
        let view = UIView()
        view.addSubview(maskingView)
        maskingView.autoPinHeightToSuperview()
        maskingView.autoHCenterInSuperview()
        return view
    }()
    lazy var maskingView: UIView = {
        let maskingView = OWSBezierPathView()
        maskingView.autoPinToSquareAspectRatio()
        maskingView.configureShapeLayerBlock = { layer, bounds in
            let path = UIBezierPath(rect: bounds)

            let circlePath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.size.height * 0.5)
            path.append(circlePath)
            path.usesEvenOddFillRule = true

            layer.path = path.cgPath
            layer.fillRule = .evenOdd
            layer.fillColor = Theme.backgroundColor.cgColor
        }
        return maskingView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        let titleLabel = self.titleLabel(
            text: NSLocalizedString("DEVICE_TRANSFER_SCANNING_TITLE",
                                    comment: "The title for the action sheet asking the user to scan the QR code to transfer")
        )
        contentView.addArrangedSubview(titleLabel)

        contentView.addArrangedSubview(.spacer(withHeight: 12))

        let explanationLabel = self.explanationLabel(
            explanationText: NSLocalizedString("DEVICE_TRANSFER_SCANNING_EXPLANATION",
                                               comment: "The explanation for the action sheet asking the user to scan the QR code to transfer")
        )
        contentView.addArrangedSubview(explanationLabel)

        contentView.addArrangedSubview(.spacer(withHeight: 25))

        contentView.addArrangedSubview(maskingContainerView)

        contentView.addArrangedSubview(.vStretchingSpacer())
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        guard !isCapturing else { return }

        DispatchQueue.global().async {
            if let capture = self.capture {
                capture.start()
            } else {
                let capture = ZXCapture()
                self.capture = capture
                capture.camera = capture.back()
                capture.focusMode = .continuousAutoFocus
                capture.delegate = self
            }

            DispatchQueue.main.async {
                guard let capture = self.capture else { return }
                capture.layer.frame = self.maskingView.frame
                self.maskingContainerView.layer.addSublayer(capture.layer)
                self.maskingContainerView.bringSubviewToFront(self.maskingView)
                capture.start()

                self.isCapturing = true
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        capture?.stop()
        isCapturing = false
    }
}

extension DeviceTransferQRScanningViewController: ZXCaptureDelegate {
    func captureResult(_ capture: ZXCapture!, result: ZXResult!) {
        guard isCapturing else { return }

        guard let result = result, let text = result.text, let scannedURL = URL(string: text) else {
            return owsFailDebug("scan returned bad result")
        }

        capture?.stop()
        isCapturing = false

        do {
            let (peerId, certificateHash) = try deviceTransferService.parseTrasnsferURL(scannedURL)
            deviceTransferService.addObserver(self)
            try deviceTransferService.transferAccountToNewDevice(with: peerId, certificateHash: certificateHash)
        } catch {
            owsFailDebug("Something went wrong \(error)")

            if let error = error as? DeviceTransferService.Error {
                switch error {
                case .unsupportedVersion:
                    OWSActionSheets.showActionSheet(
                        title: NSLocalizedString("DEVICE_TRANSFER_ERROR_UNSUPPORTED_VERSION",
                                                 comment: "An error indicating the user must update their device before trying to transfer.")
                    )
                    return
                case .modeMismatch:
                    let desiredMode: DeviceTransferService.TransferMode =
                        TSAccountManager.sharedInstance().isPrimaryDevice ? .linked : .primary
                    switch desiredMode {
                    case .linked:
                        OWSActionSheets.showActionSheet(
                            title: NSLocalizedString("DEVICE_TRANSFER_ERROR_MODE_MISMATCH_LINKED",
                                                     comment: "An error indicating the user must scan this code with a linked device to transfer.")
                        )
                    case .primary:
                        OWSActionSheets.showActionSheet(
                            title: NSLocalizedString("DEVICE_TRANSFER_ERROR_MODE_MISMATCH_PRIMARY",
                                                     comment: "An error indicating the user must scan this code with a primary device to transfer.")
                        )
                    }
                    return
                default:
                    break
                }
            }

            OWSActionSheets.showActionSheet(
                title: NSLocalizedString("DEVICE_TRANSFER_ERROR_GENERIC",
                                         comment: "An error indicating that something went wrong with the transfer and it could not complete")
            )
        }
    }
}

extension DeviceTransferQRScanningViewController: DeviceTransferServiceObserver {
    func deviceTransferServiceDiscoveredNewDevice(peerId: MCPeerID, discoveryInfo: [String: String]?) {}

    func deviceTransferServiceDidStartTransfer(progress: Progress) {
        deviceTransferService.removeObserver(self)
        let vc = DeviceTransferProgressViewController(progress: progress)
        navigationController?.pushViewController(vc, animated: true)
    }

    func deviceTransferServiceDidEndTransfer(error: DeviceTransferService.Error?) {}
}
