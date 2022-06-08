import UIKit
import WebRTC

public protocol VideoPreviewDelegate : AnyObject {
    func cameraDidConfirmTurningOn()
}

class VideoPreviewVC: UIViewController, CameraManagerDelegate {
    weak var delegate: VideoPreviewDelegate?
    
    lazy var cameraManager: CameraManager = {
        let result = CameraManager()
        result.delegate = self
        return result
    }()
    
    // MARK: UI Components
    private lazy var renderView: RenderView = {
        let result = RenderView()
        return result
    }()
    
    private lazy var fadeView: UIView = {
        let result = UIView()
        let height: CGFloat = 64
        var frame = UIScreen.main.bounds
        frame.size.height = height
        let layer = CAGradientLayer()
        layer.frame = frame
        layer.colors = [ UIColor(hex: 0x000000).withAlphaComponent(0.4).cgColor, UIColor(hex: 0x000000).withAlphaComponent(0).cgColor ]
        result.layer.insertSublayer(layer, at: 0)
        result.set(.height, to: height)
        return result
    }()
    
    private lazy var closeButton: UIButton = {
        let result = UIButton(type: .custom)
        let image = UIImage(named: "X")!.withTint(.white)
        result.setImage(image, for: UIControl.State.normal)
        result.set(.width, to: 60)
        result.set(.height, to: 60)
        result.addTarget(self, action: #selector(cancel), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var confirmButton: UIButton = {
        let result = UIButton(type: .custom)
        let image = UIImage(named: "Check")!.withTint(.white)
        result.setImage(image, for: UIControl.State.normal)
        result.set(.width, to: 60)
        result.set(.height, to: 60)
        result.addTarget(self, action: #selector(confirm), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.text = "Preview"
        result.textColor = .white
        result.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        result.textAlignment = .center
        return result
    }()

    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
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
    
    // MARK: Interaction
    @objc func confirm() {
        delegate?.cameraDidConfirmTurningOn()
        self.dismiss(animated: true, completion: nil)
    }
    
    @objc func cancel() {
        self.dismiss(animated: true, completion: nil)
    }
    
    // MARK: CameraManagerDelegate
    func handleVideoOutputCaptured(sampleBuffer: CMSampleBuffer) {
        renderView.enqueue(sampleBuffer: sampleBuffer)
    }
}
