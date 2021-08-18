import WebRTC
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

final class CallVC : UIViewController, WebRTCSessionDelegate {
    let sessionID: String
    let mode: Mode
    let webRTCSession: WebRTCSession
    
    lazy var cameraManager: CameraManager = {
        let result = CameraManager()
        result.delegate = self
        return result
    }()
    
    lazy var videoCapturer: RTCVideoCapturer = {
        return RTCCameraVideoCapturer(delegate: webRTCSession.localVideoSource)
    }()
    
    // MARK: UI Components
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
    
    private lazy var closeButton: UIButton = {
        let result = UIButton(type: .custom)
        let image = UIImage(named: "X")!.withTint(.white)
        result.setImage(image, for: UIControl.State.normal)
        result.set(.width, to: 60)
        result.set(.height, to: 60)
        result.addTarget(self, action: #selector(close), for: UIControl.Event.touchUpInside)
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
        result.alpha = 0
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
            callInfoLabel.alpha = 1
            callInfoLabel.text = "Ringing..."
            Storage.write { transaction in
                self.webRTCSession.sendOffer(to: self.sessionID, using: transaction).retainUntilComplete()
            }
        } else if case let .answer(sdp) = mode {
            webRTCSession.handleRemoteSDP(sdp, from: sessionID) // This sends an answer message internally
        }
    }
    
    func setUpViewHierarchy() {
        // Remote video view
        webRTCSession.attachRemoteRenderer(remoteVideoView)
        view.addSubview(remoteVideoView)
        remoteVideoView.translatesAutoresizingMaskIntoConstraints = false
        remoteVideoView.pin(to: view)
        // Local video view
        let localVideoView = RTCMTLVideoView()
        localVideoView.contentMode = .scaleAspectFill
        webRTCSession.attachLocalRenderer(localVideoView)
        localVideoView.set(.width, to: 80)
        localVideoView.set(.height, to: 173)
        view.addSubview(localVideoView)
        localVideoView.pin(.right, to: .right, of: view, withInset: -Values.largeSpacing)
        let bottomMargin = UIApplication.shared.keyWindow!.safeAreaInsets.bottom + Values.largeSpacing
        localVideoView.pin(.bottom, to: .bottom, of: view, withInset: -bottomMargin)
        // Fade view
        view.addSubview(fadeView)
        fadeView.translatesAutoresizingMaskIntoConstraints = false
        fadeView.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.top, UIView.HorizontalEdge.right ], to: view)
        // Close button
        view.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.pin(.left, to: .left, of: view)
        closeButton.pin(.top, to: .top, of: view, withInset: 32)
        // Title label
        view.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.center(.vertical, in: closeButton)
        titleLabel.center(.horizontal, in: view)
        // Call info label
        view.addSubview(callInfoLabel)
        callInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        callInfoLabel.center(in: view)
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
        UIView.animate(withDuration: 0.25) {
            self.callInfoLabel.alpha = 0
        }
    }
    
    func handleEndCallMessage(_ message: CallMessage) {
        print("[Calls] Ending call.")
        callInfoLabel.text = "Call Ended"
        WebRTCSession.current?.dropConnection()
        WebRTCSession.current = nil
        UIView.animate(withDuration: 0.25) {
            self.remoteVideoView.alpha = 0
            self.callInfoLabel.alpha = 1
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
            self.presentingViewController?.dismiss(animated: true, completion: nil)
        }
    }
    
    @objc private func close() {
        Storage.write { transaction in
            WebRTCSession.current?.endCall(with: self.sessionID, using: transaction)
        }
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
}
