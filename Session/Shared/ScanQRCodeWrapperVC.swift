// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

final class ScanQRCodeWrapperVC: BaseVC {
    var delegate: (UIViewController & QRScannerDelegate)? = nil
    var isPresentedModally = false
    
    private let message: String?
    private let scanQRCodeVC = QRCodeScanningViewController()
    
    // MARK: - Lifecycle
    
    init(message: String?) {
        self.message = message
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(message:) instead.")
    }
    
    override init(nibName: String?, bundle: Bundle?) {
        preconditionFailure("Use init(message:) instead.")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Scan QR Code"
        
        // Set up navigation bar if needed
        if isPresentedModally {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(close))
        }
        
        // Set up scan QR code VC
        scanQRCodeVC.scanDelegate = delegate
        let scanQRCodeVCView = scanQRCodeVC.view!
        view.addSubview(scanQRCodeVCView)
        scanQRCodeVCView.pin(.leading, to: .leading, of: view)
        scanQRCodeVCView.pin(.trailing, to: .trailing, of: view)
        scanQRCodeVCView.autoPinEdge(.top, to: .top, of: view)
        
        if let message = message {
            scanQRCodeVCView.set(.height, lessThanOrEqualTo: UIScreen.main.bounds.width)
            
            // Set up bottom view
            let bottomView = UIView()
            view.addSubview(bottomView)
            bottomView.pin(.top, to: .bottom, of: scanQRCodeVCView)
            bottomView.pin(.leading, to: .leading, of: view)
            bottomView.pin(.trailing, to: .trailing, of: view)
            bottomView.pin(.bottom, to: .bottom, of: view)
            
            // Set up explanation label
            let explanationLabel: UILabel = UILabel()
            explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
            explanationLabel.text = message
            explanationLabel.themeTextColor = .textPrimary
            explanationLabel.textAlignment = .center
            explanationLabel.lineBreakMode = .byWordWrapping
            explanationLabel.numberOfLines = 0
            bottomView.addSubview(explanationLabel)
            
            explanationLabel.autoPinWidthToSuperview(withMargin: 32)
            explanationLabel.autoPinHeightToSuperview(withMargin: 32)
        }
        else {
            scanQRCodeVCView.autoPinEdge(.bottom, to: .bottom, of: view)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.scanQRCodeVC.startCapture()
    }
    
    // MARK: - Interaction
    
    @objc private func close() {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    public func startCapture() {
        self.scanQRCodeVC.startCapture()
    }
}
