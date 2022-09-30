import WebRTC
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit
import UIKit
import MediaPlayer

final class CallVC: UIViewController, VideoPreviewDelegate {
    let call: SessionCall
    var latestKnownAudioOutputDeviceName: String?
    var durationTimer: Timer?
    var duration: Int = 0
    var shouldRestartCamera = true
    weak var conversationVC: ConversationVC? = nil
    
    lazy var cameraManager: CameraManager = {
        let result = CameraManager()
        result.delegate = self
        return result
    }()
    
    // MARK: UI Components
    private lazy var localVideoView: LocalVideoView = {
        let result = LocalVideoView()
        result.isHidden = !call.isVideoEnabled
        result.layer.cornerRadius = UIDevice.current.isIPad ? 20 : 10
        result.layer.masksToBounds = true
        result.set(.width, to: LocalVideoView.width)
        result.set(.height, to: LocalVideoView.height)
        result.makeViewDraggable()
        return result
    }()
    
    private lazy var remoteVideoView: RemoteVideoView = {
        let result = RemoteVideoView()
        result.alpha = 0
        result.backgroundColor = .black
        result.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleRemoteVieioViewTapped)))
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
    
    private lazy var profilePictureView: UIImageView = {
        let result = UIImageView()
        let radius: CGFloat = isIPhone6OrSmaller ? 100 : 120
        result.image = self.call.profilePicture
        result.set(.width, to: radius * 2)
        result.set(.height, to: radius * 2)
        result.layer.cornerRadius = radius
        result.layer.masksToBounds = true
        result.contentMode = .scaleAspectFill
        return result
    }()
    
    private lazy var minimizeButton: UIButton = {
        let result = UIButton(type: .custom)
        result.isHidden = !call.hasConnected
        let image = UIImage(named: "Minimize")!.withTint(.white)
        result.setImage(image, for: UIControl.State.normal)
        result.set(.width, to: 60)
        result.set(.height, to: 60)
        result.addTarget(self, action: #selector(minimize), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var answerButton: UIButton = {
        let result = UIButton(type: .custom)
        result.isHidden = call.hasStartedConnecting
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
        result.backgroundColor = call.isMuted ? Colors.destructive : UIColor(hex: 0x1F1F1F)
        result.layer.cornerRadius = 30
        result.addTarget(self, action: #selector(switchAudio), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var videoButton: UIButton = {
        let result = UIButton(type: .custom)
        let image = UIImage(named: "VideoCall")?.withRenderingMode(.alwaysTemplate)
        result.setImage(image, for: UIControl.State.normal)
        result.set(.width, to: 60)
        result.set(.height, to: 60)
        result.tintColor = .white
        result.backgroundColor = UIColor(hex: 0x1F1F1F)
        result.layer.cornerRadius = 30
        result.addTarget(self, action: #selector(operateCamera), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var volumeView: MPVolumeView = {
        let result = MPVolumeView()
        let image = UIImage(named: "Speaker")?.withRenderingMode(.alwaysTemplate)
        result.showsVolumeSlider = false
        result.showsRouteButton = true
        result.setRouteButtonImage(image, for: UIControl.State.normal)
        result.set(.width, to: 60)
        result.set(.height, to: 60)
        result.tintColor = .white
        result.backgroundColor = UIColor(hex: 0x1F1F1F)
        result.layer.cornerRadius = 30
        return result
    }()
    
    private lazy var operationPanel: UIStackView = {
        let result = UIStackView(arrangedSubviews: [switchCameraButton, videoButton, switchAudioButton, volumeView])
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
        result.isHidden = call.hasConnected
        result.textColor = .white
        result.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        result.textAlignment = .center
        if call.hasStartedConnecting { result.text = "Connecting..." }
        return result
    }()
    
    private lazy var callDurationLabel: UILabel = {
        let result = UILabel()
        result.isHidden = true
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
                if self.callInfoLabel.alpha < 0.5 {
                    UIView.animate(withDuration: 0.25) {
                        self.operationPanel.alpha = 1
                        self.responsePanel.alpha = 1
                        self.callInfoLabel.alpha = 1
                    }
                }
            }
        }
        self.call.hasStartedConnectingDidChange = {
            DispatchQueue.main.async {
                self.callInfoLabel.text = "Connecting..."
                self.answerButton.alpha = 0
                UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseIn, animations: {
                    self.answerButton.isHidden = true
                }, completion: nil)
            }
        }
        self.call.hasConnectedDidChange = {
            DispatchQueue.main.async {
                CallRingTonePlayer.shared.stopPlayingRingTone()
                self.callInfoLabel.text = "Connected"
                self.minimizeButton.isHidden = false
                self.durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    self.updateDuration()
                }
                self.callInfoLabel.isHidden = true
                self.callDurationLabel.isHidden = false
            }
        }
        self.call.hasEndedDidChange = {
            DispatchQueue.main.async {
                self.durationTimer?.invalidate()
                self.durationTimer = nil
                self.handleEndCallMessage()
            }
        }
        self.call.hasStartedReconnecting = {
            DispatchQueue.main.async {
                self.callInfoLabel.isHidden = false
                self.callDurationLabel.isHidden = true
                self.callInfoLabel.text = "Reconnecting..."
            }
        }
        self.call.hasReconnected = {
            DispatchQueue.main.async {
                self.callInfoLabel.isHidden = true
                self.callDurationLabel.isHidden = false
            }
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
        AppEnvironment.shared.callManager.startCall(call) { error in
            DispatchQueue.main.async {
                if let _ = error {
                    self.callInfoLabel.text = "Can't start a call."
                    self.endCall()
                } else {
                    self.callInfoLabel.text = "Ringing..."
                    self.answerButton.isHidden = true
                }
            }
        }
        setupOrientationMonitoring()
        NotificationCenter.default.addObserver(self, selector: #selector(audioRouteDidChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let layer = CAGradientLayer()
        layer.frame = CGRect(x: 0, y: 0, width: size.width, height: 64)
        layer.colors = [ UIColor(hex: 0x000000).withAlphaComponent(0.4).cgColor, UIColor(hex: 0x000000).withAlphaComponent(0).cgColor ]
        if let existingSublayer = fadeView.layer.sublayers?[0], existingSublayer is CAGradientLayer {
            fadeView.layer.replaceSublayer(existingSublayer, with: layer)
        } else {
            fadeView.layer.insertSublayer(layer, at: 0)
        }
    }
    
    deinit {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.removeObserver(self)
    }
    
    func setUpViewHierarchy() {
        // Profile picture container
        let profilePictureContainer = UIView()
        view.addSubview(profilePictureContainer)
        // Remote video view
        call.attachRemoteVideoRenderer(remoteVideoView)
        view.addSubview(remoteVideoView)
        remoteVideoView.translatesAutoresizingMaskIntoConstraints = false
        remoteVideoView.pin(to: view)
        // Local video view
        call.attachLocalVideoRenderer(localVideoView)
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
        // Profile picture view
        profilePictureContainer.pin(.top, to: .bottom, of: fadeView)
        profilePictureContainer.pin(.bottom, to: .top, of: operationPanel)
        profilePictureContainer.pin([ UIView.HorizontalEdge.left, UIView.HorizontalEdge.right ], to: view)
        profilePictureContainer.addSubview(profilePictureView)
        profilePictureView.center(in: profilePictureContainer)
        // Call info label
        let callInfoLabelContainer = UIView()
        view.addSubview(callInfoLabelContainer)
        callInfoLabelContainer.pin(.top, to: .bottom, of: profilePictureView)
        callInfoLabelContainer.pin(.bottom, to: .bottom, of: profilePictureContainer)
        callInfoLabelContainer.pin([ UIView.HorizontalEdge.left, UIView.HorizontalEdge.right ], to: view)
        callInfoLabelContainer.addSubview(callInfoLabel)
        callInfoLabelContainer.addSubview(callDurationLabel)
        callInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        callInfoLabel.center(in: callInfoLabelContainer)
        callDurationLabel.translatesAutoresizingMaskIntoConstraints = false
        callDurationLabel.center(in: callInfoLabelContainer)
    }
    
    private func addLocalVideoView() {
        let safeAreaInsets = UIApplication.shared.keyWindow!.safeAreaInsets
        let window = CurrentAppContext().mainWindow!
        window.addSubview(localVideoView)
        localVideoView.autoPinEdge(toSuperviewEdge: .right, withInset: Values.smallSpacing)
        let topMargin = safeAreaInsets.top + Values.veryLargeSpacing
        localVideoView.autoPinEdge(toSuperviewEdge: .top, withInset: topMargin)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if (call.isVideoEnabled && shouldRestartCamera) { cameraManager.start() }
        shouldRestartCamera = true
        addLocalVideoView()
        remoteVideoView.alpha = call.isRemoteVideoEnabled ? 1 : 0
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if (call.isVideoEnabled && shouldRestartCamera) { cameraManager.stop() }
        localVideoView.removeFromSuperview()
    }
    
    // MARK: - Orientation

    private func setupOrientationMonitoring() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(self, selector: #selector(didChangeDeviceOrientation), name: UIDevice.orientationDidChangeNotification, object: UIDevice.current)
    }
    
    @objc func didChangeDeviceOrientation(notification: Notification) {
        if UIDevice.current.isIPad { return }
        
        func rotateAllButtons(rotationAngle: CGFloat) {
            let transform = CGAffineTransform(rotationAngle: rotationAngle)
            UIView.animate(withDuration: 0.2) {
                self.answerButton.transform = transform
                self.hangUpButton.transform = transform
                self.switchAudioButton.transform = transform
                self.switchCameraButton.transform = transform
                self.videoButton.transform = transform
                self.volumeView.transform = transform
            }
        }
        
        switch UIDevice.current.orientation {
        case .portrait:
            rotateAllButtons(rotationAngle: 0)
        case .portraitUpsideDown:
            rotateAllButtons(rotationAngle: .pi)
        case .landscapeLeft:
            rotateAllButtons(rotationAngle: .halfPi)
        case .landscapeRight:
            rotateAllButtons(rotationAngle: .pi + .halfPi)
        default:
            break
        }
    }
    
    // MARK: Call signalling
    func handleAnswerMessage(_ message: CallMessage) {
        callInfoLabel.text = "Connecting..."
    }
    
    func handleEndCallMessage() {
        SNLog("[Calls] Ending call.")
        self.callInfoLabel.isHidden = false
        self.callDurationLabel.isHidden = true
        callInfoLabel.text = "Call Ended"
        UIView.animate(withDuration: 0.25) {
            self.remoteVideoView.alpha = 0
            self.operationPanel.alpha = 1
            self.responsePanel.alpha = 1
            self.callInfoLabel.alpha = 1
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
            self.conversationVC?.showInputAccessoryView()
            self.presentingViewController?.dismiss(animated: true, completion: nil)
        }
    }
    
    @objc private func answerCall() {
        AppEnvironment.shared.callManager.answerCall(call) { error in
            DispatchQueue.main.async {
                if let _ = error {
                    self.callInfoLabel.text = "Can't answer the call."
                    self.endCall()
                }
            }
        }
    }
    
    @objc private func endCall() {
        AppEnvironment.shared.callManager.endCall(call) { error in
            if let _ = error {
                self.call.endSessionCall()
                AppEnvironment.shared.callManager.reportCurrentCallEnded(reason: nil)
            }
            DispatchQueue.main.async {
                self.conversationVC?.showInputAccessoryView()
                self.presentingViewController?.dismiss(animated: true, completion: nil)
            }
        }
    }
    
    @objc private func updateDuration() {
        callDurationLabel.text = String(format: "%.2d:%.2d", duration/60, duration%60)
        duration += 1
    }
    
    // MARK: Minimize to a floating view
    @objc private func minimize() {
        self.shouldRestartCamera = false
        let miniCallView = MiniCallView(from: self)
        miniCallView.show()
        self.conversationVC?.showInputAccessoryView()
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    // MARK: Video and Audio
    @objc private func operateCamera() {
        if (call.isVideoEnabled) {
            localVideoView.isHidden = true
            cameraManager.stop()
            videoButton.tintColor = .white
            videoButton.backgroundColor = UIColor(hex: 0x1F1F1F)
            switchCameraButton.isEnabled = false
            call.isVideoEnabled = false
        } else {
            guard requestCameraPermissionIfNeeded() else { return }
            let previewVC = VideoPreviewVC()
            previewVC.delegate = self
            present(previewVC, animated: true, completion: nil)
        }
    }
    
    func cameraDidConfirmTurningOn() {
        localVideoView.isHidden = false
        cameraManager.prepare()
        cameraManager.start()
        videoButton.tintColor = UIColor(hex: 0x1F1F1F)
        videoButton.backgroundColor = .white
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
    
    @objc private func audioRouteDidChange() {
        let currentSession = AVAudioSession.sharedInstance()
        let currentRoute = currentSession.currentRoute
        if let currentOutput = currentRoute.outputs.first {
            if let latestKnownAudioOutputDeviceName = latestKnownAudioOutputDeviceName, currentOutput.portName == latestKnownAudioOutputDeviceName { return }
            latestKnownAudioOutputDeviceName = currentOutput.portName
            switch currentOutput.portType {
            case .builtInSpeaker:
                let image = UIImage(named: "Speaker")?.withRenderingMode(.alwaysTemplate)
                volumeView.setRouteButtonImage(image, for: .normal)
                volumeView.tintColor = UIColor(hex: 0x1F1F1F)
                volumeView.backgroundColor = .white
            case .headphones:
                let image = UIImage(named: "Headsets")?.withRenderingMode(.alwaysTemplate)
                volumeView.setRouteButtonImage(image, for: .normal)
                volumeView.tintColor = UIColor(hex: 0x1F1F1F)
                volumeView.backgroundColor = .white
            case .bluetoothLE: fallthrough
            case .bluetoothA2DP:
                let image = UIImage(named: "Bluetooth")?.withRenderingMode(.alwaysTemplate)
                volumeView.setRouteButtonImage(image, for: .normal)
                volumeView.tintColor = UIColor(hex: 0x1F1F1F)
                volumeView.backgroundColor = .white
            case .bluetoothHFP:
                let image = UIImage(named: "Airpods")?.withRenderingMode(.alwaysTemplate)
                volumeView.setRouteButtonImage(image, for: .normal)
                volumeView.tintColor = UIColor(hex: 0x1F1F1F)
                volumeView.backgroundColor = .white
            case .builtInReceiver: fallthrough
            default:
                let image = UIImage(named: "Speaker")?.withRenderingMode(.alwaysTemplate)
                volumeView.setRouteButtonImage(image, for: .normal)
                volumeView.tintColor = .white
                volumeView.backgroundColor = UIColor(hex: 0x1F1F1F)
            }
        }
    }
    
    @objc private func handleRemoteVieioViewTapped(gesture: UITapGestureRecognizer) {
        let isHidden = callDurationLabel.alpha < 0.5
        UIView.animate(withDuration: 0.5) {
            self.operationPanel.alpha = isHidden ? 1 : 0
            self.responsePanel.alpha = isHidden ? 1 : 0
            self.callDurationLabel.alpha = isHidden ? 1 : 0
        }
    }
}
