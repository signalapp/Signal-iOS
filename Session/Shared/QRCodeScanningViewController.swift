// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import AVFoundation
import ZXingObjC
import SessionUIKit

protocol QRScannerDelegate: AnyObject {
    func controller(_ controller: QRCodeScanningViewController, didDetectQRCodeWith string: String)
}

class QRCodeScanningViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate, ZXCaptureDelegate {
    public weak var scanDelegate: QRScannerDelegate?
    
    private let captureQueue: DispatchQueue = DispatchQueue.global(qos: .default)
    private var capture: ZXCapture?
    private var captureEnabled: Bool = false
    
    // MARK: - Initialization
    
    deinit {
        self.capture?.layer.removeFromSuperlayer()
    }
    
    // MARK: - Components
    
    private let maskingView: UIView = {
        let result: OWSBezierPathView = OWSBezierPathView()
        result.configureShapeLayerBlock = { layer, bounds in
            // Add a circular mask
            let path: UIBezierPath = UIBezierPath(rect: bounds)
            let margin: CGFloat = ScaleFromIPhone5To7Plus(24, 48)
            let radius: CGFloat = ((min(bounds.size.width, bounds.size.height) * 0.5) - margin)

            // Center the circle's bounding rectangle
            let circleRect: CGRect = CGRect(
                x: ((bounds.size.width * 0.5) - radius),
                y: ((bounds.size.height * 0.5) - radius),
                width: (radius * 2),
                height: (radius * 2)
            )
            let circlePath: UIBezierPath = UIBezierPath.init(
                roundedRect: circleRect,
                cornerRadius: 16
            )
            path.append(circlePath)
            path.usesEvenOddFillRule = true

            layer.path = path.cgPath
            layer.fillRule = .evenOdd
            layer.themeFillColor = .black
            layer.opacity = 0.32
        }
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    override func loadView() {
        super.loadView()
        
        self.view.addSubview(maskingView)
        maskingView.pin(to: self.view)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if captureEnabled {
            self.startCapture()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        self.stopCapture()
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        // Note: When accessing 'capture.layer' if the setup hasn't been completed it
        // will result in a layout being triggered which creates an infinite loop, this
        // check prevents that case
        if let capture: ZXCapture = self.capture {
            capture.layer.frame = self.view.bounds
        }
    }

    // MARK: - Functions
    
    public func startCapture() {
        self.captureEnabled = true
        
        // Note: The simulator doesn't support video but if we do try to start an
        // AVCaptureSession it seems to hang on that particular thread indefinitely
        // this will prevent us from trying to start a session on the simulator
        #if targetEnvironment(simulator)
        #else
            if self.capture == nil {
                self.captureQueue.async { [weak self] in
                    let capture: ZXCapture = ZXCapture()
                    capture.camera = capture.back()
                    capture.focusMode = .autoFocus
                    capture.delegate = self
                    capture.start()
                    
                    // Note: When accessing the 'layer' for the first time it will create
                    // an instance of 'AVCaptureVideoPreviewLayer', this can hang a little
                    // so we do this on the background thread first
                    if capture.layer != nil {}

                    DispatchQueue.main.async {
                        capture.layer.frame = (self?.view.bounds ?? .zero)
                        self?.view.layer.addSublayer(capture.layer)
                        
                        if let maskingView: UIView = self?.maskingView {
                            self?.view.bringSubviewToFront(maskingView)
                        }
                    
                        self?.capture = capture
                    }
                }
            }
            else {
                self.capture?.start()
            }
        #endif
    }

    private func stopCapture() {
        self.captureEnabled = false
        self.captureQueue.async { [weak self] in
            self?.capture?.stop()
        }
    }
    
    internal func captureResult(_ capture: ZXCapture, result: ZXResult) {
        guard self.captureEnabled else { return }
        
        self.stopCapture()
        
        // Vibrate
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        
        self.scanDelegate?.controller(self, didDetectQRCodeWith: result.text)
    }
}
