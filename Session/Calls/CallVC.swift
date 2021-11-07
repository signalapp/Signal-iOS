import WebRTC
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit
import UIKit

final class CallVC : UIViewController, VideoPreviewDelegate {
    let call: SessionCall
    var shouldAnswer = false
    var shouldRestartCamera = true
    weak var conversationVC: ConversationVC? = nil
    
    lazy var cameraManager: CameraManager = {
        let result = CameraManager()
        result.delegate = self
        return result
    }()
    
    // MARK: UI Components
    private lazy var localVideoView: RTCMTLVideoView = {
        let result = RTCMTLVideoView()
        result.isHidden = !call.isVideoEnabled
        result.contentMode = .scaleAspectFill
        result.set(.width, to: 80)
        result.set(.height, to: 173)
        result.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture)))
        return result
    }()
    
    private lazy var remoteVideoView: RTCMTLVideoView = {
        let result = RTCMTLVideoView()
        result.alpha = 0
        result.contentMode = .scaleAspectFill
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
    
    private lazy var minimizeButton: UIButton = {
        let result = UIButton(type: .custom)
        result.isHidden = true
        let image = UIImage(named: "Minimize")!.withTint(.white)
        result.setImage(image, for: UIControl.State.normal)
        result.set(.width, to: 60)
        result.set(.height, to: 60)
        result.addTarget(self, action: #selector(minimize), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var answerButton: UIButton = {
        let result = UIButton(type: .custom)
        let image = UIImage(named: "AnswerCall")!.withTint(.white)
        result.setImage(image, for: UIControl.State.normal)
        result.set(.width, to: 60)
        result.set(.height, to: 60)
        result.backgroundColor = Colors.accent
        result.layer.cornerRadius = 30
        result.addTarget(self, action: #selector(answerCall), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var hangUpButton: UIButton = {
        let result = UIButton(type: .custom)
        let image = UIImage(named: "EndCall")!.withTint(.white)
        result.setImage(image, for: UIControl.State.normal)
        result.set(.width, to: 60)
        result.set(.height, to: 60)
        result.backgroundColor = Colors.destructive
        result.layer.cornerRadius = 30
        result.addTarget(self, action: #selector(endCall), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var responsePanel: UIStackView = {
        let result = UIStackView(arrangedSubviews: [hangUpButton, answerButton])
        result.axis = .horizontal
        result.spacing = Values.veryLargeSpacing * 2 + 40
        return result
    }()

    private lazy var switchCameraButton: UIButton = {
        let result = UIButton(type: .custom)
        result.isEnabled = call.isVideoEnabled
        let image = UIImage(named: "SwitchCamera")!.withTint(.white)
        result.setImage(image, for: UIControl.State.normal)
        result.set(.width, to: 60)
        result.set(.height, to: 60)
        result.backgroundColor = UIColor(hex: 0x1F1F1F)
        result.layer.cornerRadius = 30
        result.addTarget(self, action: #selector(switchCamera), for: UIControl.Event.touchUpInside)
        return result
    }()

    private lazy var switchAudioButton: UIButton = {
        let result = UIButton(type: .custom)
        let image = UIImage(named: "AudioOff")!.withTint(.white)
        result.setImage(image, for: UIControl.State.normal)
        result.set(.width, to: 60)
        result.set(.height, to: 60)
        result.backgroundColor = UIColor(hex: 0x1F1F1F)
        result.layer.cornerRadius = 30
        result.addTarget(self, action: #selector(switchAudio), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var videoButton: UIButton = {
        let result = UIButton(type: .custom)
        let image = UIImage(named: "VideoCall")!.withTint(.white)
        result.setImage(image, for: UIControl.State.normal)
        result.set(.width, to: 60)
        result.set(.height, to: 60)
        result.backgroundColor = UIColor(hex: 0x1F1F1F)
        result.layer.cornerRadius = 30
        result.alpha = 0.5
        result.addTarget(self, action: #selector(operateCamera), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var operationPanel: UIStackView = {
        let result = UIStackView(arrangedSubviews: [videoButton, switchAudioButton, switchCameraButton])
        result.axis = .horizontal
        result.spacing = Values.veryLargeSpacing
        return result
    }()
    
    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.textColor = .white
        result.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        result.textAlignment = .center
        return result
    }()
    
    private lazy var callInfoLabel: UILabel = {
        let result = UILabel()
        result.textColor = .white
        result.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        result.textAlignment = .center
        return result
    }()
    
    // MARK: Lifecycle
    init(for call: SessionCall) {
        self.call = call
        super.init(nibName: nil, bundle: nil)
        setupStateChangeCallbacks()
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve
    }
    
    func setupStateChangeCallbacks() {
        self.call.remoteVideoStateDidChange = { isEnabled in
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.25) {
                    self.remoteVideoView.alpha = isEnabled ? 1 : 0
                }
            }
        }
        self.call.hasConnectedDidChange = {
            DispatchQueue.main.async {
                self.callInfoLabel.text = "Connected"
                self.minimizeButton.isHidden = false
                UIView.animate(withDuration: 0.5, delay: 1, options: [], animations: {
                    self.callInfoLabel.alpha = 0
                }, completion: { _ in
                    self.callInfoLabel.isHidden = true
                    self.callInfoLabel.alpha = 1
                })
            }
        }
        self.call.hasEndedDidChange = {
            self.conversationVC?.showInputAccessoryView()
            self.presentingViewController?.dismiss(animated: true, completion: nil)
        }
    }
    
    required init(coder: NSCoder) { preconditionFailure("Use init(for:) instead.") }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setUpViewHierarchy()
        if shouldRestartCamera { cameraManager.prepare() }
        touch(call.videoCapturer)
        titleLabel.text = self.call.contactName
        AppEnvironment.shared.callManager.startCall(call) {
            self.callInfoLabel.text = "Ringing..."
            self.answerButton.isHidden = true
        }
        if shouldAnswer { answerCall() }
    }
    
    func setUpViewHierarchy() {
        // Background
        let background = getBackgroudView()
        view.addSubview(background)
        background.pin(to: view)
        // Call info label
        view.addSubview(callInfoLabel)
        callInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        callInfoLabel.center(in: view)
        // Remote video view
        call.attachRemoteVideoRenderer(remoteVideoView)
        view.addSubview(remoteVideoView)
        remoteVideoView.translatesAutoresizingMaskIntoConstraints = false
        remoteVideoView.pin(to: view)
        // Local video view
        call.attachLocalVideoRenderer(localVideoView)
        view.addSubview(localVideoView)
        localVideoView.pin(.right, to: .right, of: view, withInset: -Values.smallSpacing)
        let topMargin = UIApplication.shared.keyWindow!.safeAreaInsets.top + Values.veryLargeSpacing
        localVideoView.pin(.top, to: .top, of: view, withInset: topMargin)
        // Fade view
        view.addSubview(fadeView)
        fadeView.translatesAutoresizingMaskIntoConstraints = false
        fadeView.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.top, UIView.HorizontalEdge.right ], to: view)
        // Minimize button
        view.addSubview(minimizeButton)
        minimizeButton.translatesAutoresizingMaskIntoConstraints = false
        minimizeButton.pin(.left, to: .left, of: view)
        minimizeButton.pin(.top, to: .top, of: view, withInset: 32)
        // Title label
        view.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.center(.vertical, in: minimizeButton)
        titleLabel.center(.horizontal, in: view)
        // Response Panel
        view.addSubview(responsePanel)
        responsePanel.center(.horizontal, in: view)
        responsePanel.pin(.bottom, to: .bottom, of: view, withInset: -Values.newConversationButtonBottomOffset)
        // Operation Panel
        view.addSubview(operationPanel)
        operationPanel.center(.horizontal, in: view)
        operationPanel.pin(.bottom, to: .top, of: responsePanel, withInset: -Values.veryLargeSpacing)
    }
    
    private func getBackgroudView() -> UIView {
        let background = UIView()
        let imageView = UIImageView()
        imageView.layer.cornerRadius = 150
        imageView.layer.masksToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.image = self.call.profilePicture
        background.addSubview(imageView)
        imageView.set(.width, to: 300)
        imageView.set(.height, to: 300)
        imageView.center(in: background)
        let blurView = UIView()
        blurView.alpha = 0.5
        blurView.backgroundColor = .black
        background.addSubview(blurView)
        blurView.autoPinEdgesToSuperviewEdges()
        return background
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if (call.isVideoEnabled && shouldRestartCamera) { cameraManager.start() }
        shouldRestartCamera = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if (call.isVideoEnabled && shouldRestartCamera) { cameraManager.stop() }
    }
    
    // MARK: Interaction
    func handleAnswerMessage(_ message: CallMessage) {
        callInfoLabel.text = "Connecting..."
    }
    
    func handleEndCallMessage(_ message: CallMessage) {
        print("[Calls] Ending call.")
        callInfoLabel.isHidden = false
        callInfoLabel.text = "Call Ended"
        UIView.animate(withDuration: 0.25) {
            self.remoteVideoView.alpha = 0
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
            self.conversationVC?.showInputAccessoryView()
            self.presentingViewController?.dismiss(animated: true, completion: nil)
        }
    }
    
    internal func showCallModal() {
        let callModal = CallModal() { [weak self] in
            self?.answerCall()
        }
        callModal.modalPresentationStyle = .overFullScreen
        callModal.modalTransitionStyle = .crossDissolve
        present(callModal, animated: true, completion: nil)
    }
    
    @objc private func answerCall() {
        let userDefaults = UserDefaults.standard
        if userDefaults[.hasSeenCallIPExposureWarning] {
            self.call.answerSessionCall{
                self.callInfoLabel.text = "Connecting..."
                self.answerButton.alpha = 0
                UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseIn, animations: {
                    self.answerButton.isHidden = true
                }, completion: nil)
            }
        } else {
            userDefaults[.hasSeenCallIPExposureWarning] = true
            showCallModal()
        }
    }
    
    @objc private func endCall() {
        AppEnvironment.shared.callManager.endCall(call, completion: nil)
    }
    
    @objc private func minimize() {
        self.shouldRestartCamera = false
        let miniCallView = MiniCallView(from: self)
        miniCallView.show()
        self.conversationVC?.showInputAccessoryView()
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    @objc private func operateCamera() {
        if (call.isVideoEnabled) {
            localVideoView.isHidden = true
            cameraManager.stop()
            videoButton.alpha = 0.5
            switchCameraButton.isEnabled = false
            call.isVideoEnabled = false
        } else {
            let previewVC = VideoPreviewVC()
            previewVC.delegate = self
            present(previewVC, animated: true, completion: nil)
        }
    }
    
    func cameraDidConfirmTurningOn() {
        localVideoView.isHidden = false
        cameraManager.prepare()
        cameraManager.start()
        videoButton.alpha = 1.0
        switchCameraButton.isEnabled = true
        call.isVideoEnabled = true
    }
    
    @objc private func switchCamera() {
        cameraManager.switchCamera()
    }
    
    @objc private func switchAudio() {
        if call.isMuted {
            switchAudioButton.backgroundColor = UIColor(hex: 0x1F1F1F)
            call.isMuted = false
        } else {
            switchAudioButton.backgroundColor = Colors.destructive
            call.isMuted = true
        }
    }
    
    @objc private func handlePanGesture(gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self.view)
        if let draggedView = gesture.view {
            draggedView.center = location
            if gesture.state == .ended {
                let sideMargin = 40 + Values.verySmallSpacing
                if draggedView.frame.midX >= self.view.layer.frame.width / 2 {
                    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseIn, animations: {
                        draggedView.center.x = self.view.layer.frame.width - sideMargin
                    }, completion: nil)
                }else{
                    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseIn, animations: {
                        draggedView.center.x = sideMargin
                    }, completion: nil)
                }
                let topMargin = UIApplication.shared.keyWindow!.safeAreaInsets.top + Values.veryLargeSpacing
                if draggedView.frame.minY <= topMargin {
                    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseIn, animations: {
                        draggedView.center.y = topMargin + draggedView.frame.size.height / 2
                    }, completion: nil)
                }
                let bottomMargin = UIApplication.shared.keyWindow!.safeAreaInsets.bottom
                if draggedView.frame.maxY >= self.view.layer.frame.height {
                    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseIn, animations: {
                        draggedView.center.y = self.view.layer.frame.height - draggedView.frame.size.height / 2 - bottomMargin
                    }, completion: nil)
                }
            }
        }
    }
}
