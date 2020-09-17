//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import ZXingObjC
import MultipeerConnectivity

class DeviceTransferQRScanningViewController: DeviceTransferBaseViewController {

    var capture: ZXCapture?
    var isCapturing = false

    lazy var activityIndicator: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView(style: .white)
        activityIndicator.color = Theme.primaryIconColor
        return activityIndicator
    }()
    lazy var label: UILabel = {
        let label = UILabel()
        label.font = .ows_dynamicTypeBody2
        label.textColor = Theme.primaryTextColor
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .center
        return label
    }()
    lazy var hStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 6
        stackView.setContentHuggingVerticalLow()
        stackView.setCompressionResistanceVerticalHigh()

        let leadingSpacer = UIView.hStretchingSpacer()
        stackView.addArrangedSubview(leadingSpacer)

        stackView.addArrangedSubview(activityIndicator)

        stackView.addArrangedSubview(label)
        label.setCompressionResistanceHorizontalHigh()
        label.setCompressionResistanceVerticalHigh()

        let trailingSpacer = UIView.hStretchingSpacer()
        stackView.addArrangedSubview(trailingSpacer)

        leadingSpacer.autoMatch(.width, to: .width, of: trailingSpacer)

        return stackView
    }()
    lazy var captureContainerView: UIView = {
        let view = UIView()
        view.addSubview(maskingView)
        maskingView.autoPinHeightToSuperview()
        maskingView.autoHCenterInSuperview()
        return view
    }()
    lazy var maskingView: UIView = {
        let maskingView = OWSBezierPathView()
        maskingView.autoPinToSquareAspectRatio()
        maskingView.autoSetDimension(.height, toSize: 256)
        maskingView.configureShapeLayerBlock = { layer, bounds in
            let path = UIBezierPath(rect: bounds)

            let circlePath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.size.height * 0.5)
            path.append(circlePath)
            path.usesEvenOddFillRule = true

            layer.path = path.cgPath
            layer.fillRule = .evenOdd
            layer.fillColor = Theme.actionSheetBackgroundColor.cgColor
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

        let topSpacer = UIView.vStretchingSpacer()
        contentView.addArrangedSubview(topSpacer)

        contentView.addArrangedSubview(captureContainerView)
        contentView.addArrangedSubview(hStack)
        hStack.isHidden = true

        let bottomSpacer = UIView.vStretchingSpacer()
        contentView.addArrangedSubview(bottomSpacer)
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)
        topSpacer.autoSetDimension(.height, toSize: 25, relation: .greaterThanOrEqual)
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
                self.captureContainerView.layer.addSublayer(capture.layer)
                self.captureContainerView.bringSubviewToFront(self.maskingView)
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

        // Ignore if a non-signal url was scanned
        guard scannedURL.scheme == kURLSchemeSGNLKey else { return }

        capture?.stop()
        isCapturing = false

        showConnecting()

        DispatchQueue.global().async {
            do {
                let (peerId, certificateHash) = try self.deviceTransferService.parseTransferURL(scannedURL)
                self.deviceTransferService.addObserver(self)
                try self.deviceTransferService.transferAccountToNewDevice(with: peerId, certificateHash: certificateHash)
            } catch {
                owsFailDebug("Something went wrong \(error)")

                if let error = error as? DeviceTransferService.Error {
                    switch error {
                    case .unsupportedVersion:
                        self.showError(
                            text: NSLocalizedString("DEVICE_TRANSFER_ERROR_UNSUPPORTED_VERSION",
                                                    comment: "An error indicating the user must update their device before trying to transfer.")
                        )
                        return
                    case .modeMismatch:
                        let desiredMode: DeviceTransferService.TransferMode =
                            TSAccountManager.shared().isPrimaryDevice ? .linked : .primary
                        switch desiredMode {
                        case .linked:
                            self.showError(
                                text: NSLocalizedString("DEVICE_TRANSFER_ERROR_MODE_MISMATCH_LINKED",
                                                        comment: "An error indicating the user must scan this code with a linked device to transfer.")
                            )
                        case .primary:
                            self.showError(
                                text: NSLocalizedString("DEVICE_TRANSFER_ERROR_MODE_MISMATCH_PRIMARY",
                                                        comment: "An error indicating the user must scan this code with a primary device to transfer.")
                            )
                        }
                        return
                    default:
                        break
                    }
                }

                self.showError(
                    text: NSLocalizedString("DEVICE_TRANSFER_ERROR_GENERIC",
                                            comment: "An error indicating that something went wrong with the transfer and it could not complete")
                )
            }
        }
    }

    func showConnecting() {
        captureContainerView.isHidden = true
        hStack.isHidden = false
        label.text = NSLocalizedString("DEVICE_TRANSFER_SCANNING_CONNECTING",
                                       comment: "Text indicating that we are connecting to the scanned device")
        label.textColor = Theme.primaryTextColor
        activityIndicator.isHidden = false
        activityIndicator.startAnimating()
    }

    func showError(text: String) {
        DispatchMainThreadSafe {
            self.captureContainerView.isHidden = true
            self.hStack.isHidden = false
            self.label.text = text
            self.label.textColor = .ows_accentRed
            self.activityIndicator.stopAnimating()
            self.activityIndicator.isHidden = true
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

    func deviceTransferServiceDidEndTransfer(error: DeviceTransferService.Error?) {
        if error != nil {
            showError(
                text: NSLocalizedString("DEVICE_TRANSFER_ERROR_GENERIC",
                                        comment: "An error indicating that something went wrong with the transfer and it could not complete")
            )
        }
    }
}
