import UIKit
import AVFoundation
import WebRTC

final class MainChatRoomViewController : UIViewController, CameraCaptureDelegate, CallManagerDelegate {
    
    // MARK: UI Components
    private lazy var previewView: UIImageView = {
        return UIImageView()
    }()
    
    private lazy var containerView: UIView = {
        return UIView()
    }()
    
    private lazy var joinButton: UIButton = {
        let result = UIButton()
        result.setTitle("Join", for: UIControl.State.normal)
        return result
    }()
    
    private lazy var roomNumberTextField: UITextField = {
        return UITextField()
    }()
    
    private lazy var infoTextView: UITextView = {
        return UITextView()
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpCamera()
    }
    
    private func setUpCamera() {
        CameraManager.shared.delegate = self
        CameraManager.shared.prepare()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        CameraManager.shared.start()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        CameraManager.shared.stop()
    }
    
    // MARK: Streaming
    func callManager(_ callManager: CallManager, sendData data: Data) {
        // TODO: Implement
    }
    
    // MARK: Camera
    func captureVideoOutput(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvImageBuffer: pixelBuffer)
        let image = UIImage(ciImage: ciImage)
        DispatchQueue.main.async { [weak self] in
            self?.previewView.image = image
        }
    }
    
    // MARK: Logging
    private func log(string: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.infoTextView.text = self.infoTextView.text + "\n" + string
        }
    }
}
