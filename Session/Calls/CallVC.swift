import WebRTC
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit
import UIKit

final class CallVC : UIViewController, WebRTCSessionDelegate {
    let sessionID: String
    let mode: Mode
    let webRTCSession: WebRTCSession
    var isMuted = false
    var conversationVC: ConversationVC? = nil
    
    lazy var cameraManager: CameraManager = {
        let result = CameraManager()
        result.delegate = self
        return result
    }()
    
    lazy var videoCapturer: RTCVideoCapturer = {
        return RTCCameraVideoCapturer(delegate: webRTCSession.localVideoSource)
    }()
    
    // MARK: UI Components
    private lazy var localVideoView: RTCMTLVideoView = {
        let result = RTCMTLVideoView()
        result.contentMode = .scaleAspectFill
        result.set(.width, to: 80)
        result.set(.height, to: 173)
        result.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture)))
        return result
    }()
    
    private lazy var remoteVideoView: RTCMTLVideoView = {
        let result = RTCMTLVideoView()
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
        let image = UIImage(named: "Minimize")!.withTint(.white)
        result.setImage(image, for: UIControl.State.normal)
        result.set(.width, to: 60)
        result.set(.height, to: 60)
        result.addTarget(self, action: #selector(minimize), for: UIControl.Event.touchUpInside)
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
        result.addTarget(self, action: #selector(close), for: UIControl.Event.touchUpInside)
        return result
    }()

    private lazy var switchCameraButton: UIButton = {
        let result = UIButton(type: .custom)
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
    
    // MARK: Mode
    enum Mode {
        case offer
        case answer(sdp: RTCSessionDescription)
    }
    
    // MARK: Lifecycle
    init(for sessionID: String, mode: Mode) {
        self.sessionID = sessionID
        self.mode = mode
        self.webRTCSession = WebRTCSession.current ?? WebRTCSession(for: sessionID)
        super.init(nibName: nil, bundle: nil)
        self.webRTCSession.delegate = self
    }
    
    required init(coder: NSCoder) { preconditionFailure("Use init(for:) instead.") }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        WebRTCSession.current = webRTCSession
        setUpViewHierarchy()
        cameraManager.prepare()
        touch(videoCapturer)
        var contact: Contact?
        Storage.read { transaction in
            contact = Storage.shared.getContact(with: self.sessionID)
        }
        titleLabel.text = contact?.displayName(for: Contact.Context.regular) ?? sessionID
        if case .offer = mode {
            callInfoLabel.text = "Ringing..."
            Storage.write { transaction in
                self.webRTCSession.sendOffer(to: self.sessionID, using: transaction).retainUntilComplete()
            }
        } else if case let .answer(sdp) = mode {
            callInfoLabel.text = "Connecting..."
            webRTCSession.handleRemoteSDP(sdp, from: sessionID) // This sends an answer message internally
        }
    }
    
    func setUpViewHierarchy() {
        // Background
        let background = getBackgroudView()
        view.addSubview(background)
        background.autoPinEdgesToSuperviewEdges()
        // Call info label
        view.addSubview(callInfoLabel)
        callInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        callInfoLabel.center(in: view)
        // Remote video view
        webRTCSession.attachRemoteRenderer(remoteVideoView)
        view.addSubview(remoteVideoView)
        remoteVideoView.translatesAutoresizingMaskIntoConstraints = false
        remoteVideoView.pin(to: view)
        // Local video view
        webRTCSession.attachLocalRenderer(localVideoView)
        view.addSubview(localVideoView)
        localVideoView.pin(.right, to: .right, of: view, withInset: -Values.smallSpacing)
        let topMargin = UIApplication.shared.keyWindow!.safeAreaInsets.top + Values.veryLargeSpacing
        localVideoView.pin(.top, to: .top, of: view, withInset: topMargin)
        // Fade view
        view.addSubview(fadeView)
        fadeView.translatesAutoresizingMaskIntoConstraints = false
        fadeView.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.top, UIView.HorizontalEdge.right ], to: view)
        // Close button
        view.addSubview(minimizeButton)
        minimizeButton.translatesAutoresizingMaskIntoConstraints = false
        minimizeButton.pin(.left, to: .left, of: view)
        minimizeButton.pin(.top, to: .top, of: view, withInset: 32)
        // Title label
        view.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.center(.vertical, in: minimizeButton)
        titleLabel.center(.horizontal, in: view)
        // End call button
        view.addSubview(hangUpButton)
        hangUpButton.translatesAutoresizingMaskIntoConstraints = false
        hangUpButton.center(.horizontal, in: view)
        hangUpButton.pin(.bottom, to: .bottom, of: view, withInset: -Values.newConversationButtonBottomOffset)
        // Switch camera button
        view.addSubview(switchCameraButton)
        switchCameraButton.translatesAutoresizingMaskIntoConstraints = false
        switchCameraButton.center(.vertical, in: hangUpButton)
        switchCameraButton.pin(.right, to: .left, of: hangUpButton, withInset: -Values.veryLargeSpacing)
        // Switch audio button
        view.addSubview(switchAudioButton)
        switchAudioButton.translatesAutoresizingMaskIntoConstraints = false
        switchAudioButton.center(.vertical, in: hangUpButton)
        switchAudioButton.pin(.left, to: .right, of: hangUpButton, withInset: Values.veryLargeSpacing)
    }
    
    private func getBackgroudView() -> UIView {
        let background = UIView()
        let imageView = UIImageView()
        imageView.layer.cornerRadius = 150
        imageView.layer.masksToBounds = true
        imageView.contentMode = .scaleAspectFill
        if let profilePicture = OWSProfileManager.shared().profileAvatar(forRecipientId: sessionID) {
            imageView.image = profilePicture
        } else {
            let displayName = Storage.shared.getContact(with: sessionID)?.name ?? sessionID
            imageView.image = Identicon.generatePlaceholderIcon(seed: sessionID, text: displayName, size: 300)
        }
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
        cameraManager.start()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraManager.stop()
    }
    
    // MARK: Interaction
    func handleAnswerMessage(_ message: CallMessage) {
        callInfoLabel.text = "Connecting..."
    }
    
    func handleEndCallMessage(_ message: CallMessage) {
        print("[Calls] Ending call.")
        callInfoLabel.text = "Call Ended"
        WebRTCSession.current?.dropConnection()
        WebRTCSession.current = nil
        UIView.animate(withDuration: 0.25) {
            self.remoteVideoView.alpha = 0
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
            self.conversationVC?.showInputAccessoryView()
            self.presentingViewController?.dismiss(animated: true, completion: nil)
        }
    }
    
    @objc private func close() {
        Storage.write { transaction in
            WebRTCSession.current?.endCall(with: self.sessionID, using: transaction)
        }
        self.conversationVC?.showInputAccessoryView()
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    @objc private func minimize() {
        if (localVideoView.isHidden) {
            webRTCSession.turnOnVideo()
            localVideoView.isHidden = false
            cameraManager.prepare()
            cameraManager.start()
        } else {
            webRTCSession.turnOffVideo()
            localVideoView.isHidden = true
            cameraManager.stop()
        }
    }
    
    @objc private func switchCamera() {
        cameraManager.switchCamera()
    }
    
    @objc private func switchAudio() {
        if isMuted {
            switchAudioButton.backgroundColor = UIColor(hex: 0x1F1F1F)
            isMuted = false
            webRTCSession.unmute()
        } else {
            switchAudioButton.backgroundColor = Colors.destructive
            isMuted = true
            webRTCSession.mute()
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
