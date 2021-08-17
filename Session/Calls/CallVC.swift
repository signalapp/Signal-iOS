import WebRTC
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

final class CallVC : UIViewController, WebRTCWrapperDelegate {
    let sessionID: String
    let mode: Mode
    let webRTCWrapper: WebRTCWrapper
    
    lazy var cameraManager: CameraManager = {
        let result = CameraManager()
        result.delegate = self
        return result
    }()
    
    lazy var videoCapturer: RTCVideoCapturer = {
        return RTCCameraVideoCapturer(delegate: webRTCWrapper.localVideoSource)
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
        self.webRTCWrapper = WebRTCWrapper.current ?? WebRTCWrapper(for: sessionID)
        super.init(nibName: nil, bundle: nil)
        self.webRTCWrapper.delegate = self
    }
    
    required init(coder: NSCoder) { preconditionFailure("Use init(for:) instead.") }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        WebRTCWrapper.current = webRTCWrapper
        setUpViewHierarchy()
        cameraManager.prepare()
        touch(videoCapturer)
        if case .offer = mode {
            Storage.write { transaction in
                self.webRTCWrapper.sendOffer(to: self.sessionID, using: transaction).retainUntilComplete()
            }
        } else if case let .answer(sdp) = mode {
            webRTCWrapper.handleRemoteSDP(sdp, from: sessionID) // This sends an answer message internally
        }
    }
    
    func setUpViewHierarchy() {
        // Remote video view
        let remoteVideoView = RTCMTLVideoView()
        remoteVideoView.contentMode = .scaleAspectFill
        webRTCWrapper.attachRemoteRenderer(remoteVideoView)
        view.addSubview(remoteVideoView)
        remoteVideoView.translatesAutoresizingMaskIntoConstraints = false
        remoteVideoView.pin(to: view)
        // Local video view
        let localVideoView = RTCMTLVideoView()
        localVideoView.contentMode = .scaleAspectFill
        webRTCWrapper.attachLocalRenderer(localVideoView)
        localVideoView.set(.width, to: 80)
        localVideoView.set(.height, to: 173)
        view.addSubview(localVideoView)
        localVideoView.pin(.right, to: .right, of: view, withInset: -Values.largeSpacing)
        let bottomMargin = UIApplication.shared.keyWindow!.safeAreaInsets.bottom + Values.largeSpacing
        localVideoView.pin(.bottom, to: .bottom, of: view, withInset: -bottomMargin)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        cameraManager.start()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraManager.stop()
    }
    
    deinit {
        WebRTCWrapper.current = nil
    }
}
