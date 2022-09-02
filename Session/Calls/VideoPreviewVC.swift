// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import WebRTC
import SessionUIKit

public protocol VideoPreviewDelegate: AnyObject {
    func cameraDidConfirmTurningOn()
}

class VideoPreviewVC: UIViewController, CameraManagerDelegate {
    weak var delegate: VideoPreviewDelegate?
    
    lazy var cameraManager: CameraManager = {
        let result = CameraManager()
        result.delegate = self
        
        return result
    }()
    
    // MARK: - UI Components
    
    private lazy var renderView: RenderView = {
        let result = RenderView()
        
        return result
    }()
    
    private lazy var fadeView: UIView = {
        let height: CGFloat = ((UIApplication.shared.keyWindow?.safeAreaInsets.top).map { $0 + Values.veryLargeSpacing } ?? 64)
        
        let result = UIView()
        var frame = UIScreen.main.bounds
        frame.size.height = height
        
        let layer = CAGradientLayer()
        layer.frame = frame
        result.layer.insertSublayer(layer, at: 0)
        result.set(.height, to: height)
        
        ThemeManager.onThemeChange(observer: result) { [weak layer] theme, _ in
            guard let backgroundPrimary: UIColor = theme.colors[.backgroundPrimary] else { return }
            
            layer?.colors = [
                backgroundPrimary.withAlphaComponent(0.4).cgColor,
                backgroundPrimary.withAlphaComponent(0).cgColor
            ]
        }
        
        return result
    }()
    
    private lazy var closeButton: UIButton = {
        let result = UIButton(type: .custom)
        result.setImage(
            UIImage(named: "X")?
                .withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        result.themeTintColor = .textPrimary
        result.addTarget(self, action: #selector(cancel), for: UIControl.Event.touchUpInside)
        result.set(.width, to: 60)
        result.set(.height, to: 60)
        
        return result
    }()
    
    private lazy var confirmButton: UIButton = {
        let result = UIButton(type: .custom)
        result.setImage(
            UIImage(named: "Check")?
                .withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        result.themeTintColor = .textPrimary
        result.addTarget(self, action: #selector(confirm), for: UIControl.Event.touchUpInside)
        result.set(.width, to: 60)
        result.set(.height, to: 60)
        
        return result
    }()
    
    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        result.text = "Preview"
        result.themeTextColor = .textPrimary
        result.textAlignment = .center
        
        return result
    }()

    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.themeBackgroundColor = .backgroundPrimary
        
        setUpViewHierarchy()
        cameraManager.prepare()
    }
    
    func setUpViewHierarchy() {
        // Preview video view
        view.addSubview(renderView)
        renderView.translatesAutoresizingMaskIntoConstraints = false
        renderView.pin(to: view)
        
        // Fade view
        view.addSubview(fadeView)
        fadeView.translatesAutoresizingMaskIntoConstraints = false
        fadeView.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.top, UIView.HorizontalEdge.right ], to: view)
        
        // Close button
        view.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.pin(.left, to: .left, of: view)
        closeButton.center(.vertical, in: fadeView)
        
        // Confirm button
        view.addSubview(confirmButton)
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.pin(.right, to: .right, of: view)
        confirmButton.center(.vertical, in: fadeView)
        
        // Title label
        view.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.center(.vertical, in: closeButton)
        titleLabel.center(.horizontal, in: view)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        cameraManager.start()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        cameraManager.stop()
    }
    
    // MARK: - Interaction
    
    @objc func confirm() {
        delegate?.cameraDidConfirmTurningOn()
        self.dismiss(animated: true, completion: nil)
    }
    
    @objc func cancel() {
        self.dismiss(animated: true, completion: nil)
    }
    
    // MARK: - CameraManagerDelegate
    
    func handleVideoOutputCaptured(sampleBuffer: CMSampleBuffer) {
        renderView.enqueue(sampleBuffer: sampleBuffer)
    }
}
