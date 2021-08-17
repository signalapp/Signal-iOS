import WebRTC

final class CallVCV2 : UIViewController {
    let roomID = "37923672516" // NOTE: You need to change this every time to ensure the room isn't full
    var room: RoomInfo?
    var socket: WebSocket?
    
    lazy var callManager: WebRTCWrapper = {
        let result = WebRTCWrapper()
        result.delegate = self
        return result
    }()
    
    lazy var cameraManager: CameraManager = {
        let result = CameraManager()
        result.delegate = self
        return result
    }()
    
    lazy var videoCapturer: RTCVideoCapturer = {
        return RTCCameraVideoCapturer(delegate: callManager.localVideoSource)
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpViewHierarchy()
        cameraManager.prepare()
        touch(videoCapturer)
        autoConnectToTestRoom()
    }
    
    func setUpViewHierarchy() {
        // Remote video view
        let remoteVideoView = RTCMTLVideoView()
        remoteVideoView.contentMode = .scaleAspectFill
        callManager.attachRemoteRenderer(remoteVideoView)
        view.addSubview(remoteVideoView)
        remoteVideoView.translatesAutoresizingMaskIntoConstraints = false
        remoteVideoView.pin(to: view)
        // Local video view
        let localVideoView = RTCMTLVideoView()
        localVideoView.contentMode = .scaleAspectFill
        callManager.attachLocalRenderer(localVideoView)
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
    
    // MARK: General
    func autoConnectToTestRoom() {
        // Connect to a random test room
        TestCallServer.join(roomID: roomID).done2 { [weak self] room in
            print("[Calls] Connected to test room.")
            guard let self = self else { return }
            self.room = room
            if let messages = room.messages {
                self.handle(messages)
            }
            let socket = WebSocket(url: URL(string: room.wssURL)!)
            socket.delegate = self
            socket.connect()
            self.socket = socket
        }.catch2 { error in
            SNLog("Couldn't join room due to error: \(error).")
        }
    }
    
    func handle(_ messages: [String]) {
        print("[Calls] Handling messages:")
        messages.forEach { print("[Calls] \($0)") }
        messages.forEach { message in
            let signalingMessage = SignalingMessage.from(message: message)
            switch signalingMessage {
            case .candidate(let candidate): callManager.handleICECandidate(candidate)
            case .answer(let answer): callManager.handleRemoteSDP(answer)
            case .offer(let offer): callManager.handleRemoteSDP(offer)
            default: break
            }
        }
        callManager.drainICECandidateQueue()
    }
}
