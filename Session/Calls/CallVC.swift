import UIKit
import AVFoundation
import WebRTC

final class CallVC : UIViewController, CameraCaptureDelegate, CallManagerDelegate, MockWebSocketDelegate {
    private let videoCallVC = VideoCallVC()
    let videoCapturer: RTCVideoCapturer = RTCCameraVideoCapturer(delegate: CallManager.shared.localVideoSource)
    private var messageQueue: [String] = []
    private var isConnected = false {
        didSet {
            let title = isConnected ? "Leave" : "Join"
            joinOrLeaveButton.setTitle(title, for: UIControl.State.normal)
        }
    }
    private var currentRoomInfo: RoomInfo?
    
    var isInitiator: Bool {
        return currentRoomInfo?.isInitiator == "true"
    }
    
    // MARK: UI Components
    private lazy var previewView: UIImageView = {
        return UIImageView()
    }()
    
    private lazy var containerView: UIView = {
        return UIView()
    }()
    
    private lazy var joinOrLeaveButton: UIButton = {
        let result = UIButton()
        result.setTitle("Join", for: UIControl.State.normal)
        result.addTarget(self, action: #selector(joinOrLeave), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var roomNumberTextField: UITextField = {
        let result = UITextField()
        result.set(.width, to: 120)
        result.set(.height, to: 40)
        result.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        return result
    }()
    
    private lazy var infoTextView: UITextView = {
        let result = UITextView()
        result.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        touch(CallManager.shared)
        CallManager.shared.delegate = self
        CameraManager.shared.delegate = self
        CameraManager.shared.prepare()
        addChild(videoCallVC)
        containerView.addSubview(videoCallVC.view)
        videoCallVC.view.translatesAutoresizingMaskIntoConstraints = false
        videoCallVC.view.pin(to: containerView)
        view.addSubview(containerView)
        containerView.pin(to: view)
        view.addSubview(joinOrLeaveButton)
        joinOrLeaveButton.translatesAutoresizingMaskIntoConstraints = false
        joinOrLeaveButton.pin([ UIView.VerticalEdge.top, UIView.HorizontalEdge.right ], to: view)
        view.addSubview(roomNumberTextField)
        roomNumberTextField.translatesAutoresizingMaskIntoConstraints = false
        roomNumberTextField.pin([ UIView.VerticalEdge.top, UIView.HorizontalEdge.left ], to: view)
        view.addSubview(infoTextView)
        infoTextView.translatesAutoresizingMaskIntoConstraints = false
        infoTextView.pin([ UIView.HorizontalEdge.left, UIView.HorizontalEdge.right ], to: view)
        infoTextView.center(.vertical, in: view)
        infoTextView.set(.height, to: 200)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        CameraManager.shared.start()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        CameraManager.shared.stop()
    }
    
    // MARK: Interaction
    @objc private func joinOrLeave() {
        guard let roomID = roomNumberTextField.text, !roomID.isEmpty else { return }
        if isConnected {
            disconnect()
        } else {
            isConnected = true
            MockCallServer.join(roomID: roomID).done2 { [weak self] info in
                guard let self = self else { return }
                self.log("Successfully joined room.")
                self.currentRoomInfo = info
                if let messages = info.messages {
                    self.handle(messages)
                }
                MockWebSocket.shared.delegate = self
                MockWebSocket.shared.connect(url: URL(string: info.wssURL)!)
            }.catch2 { [weak self] error in
                guard let self = self else { return }
                self.isConnected = false
                self.log("Couldn't join room due to error: \(error).")
                SNLog("Couldn't join room due to error: \(error).")
            }
            roomNumberTextField.resignFirstResponder()
        }
    }
    
    private func disconnect() {
        guard let info = currentRoomInfo else { return }
        MockCallServer.leave(roomID: info.roomID, userID: info.clientID).done2 { [weak self] in
            guard let self = self else { return }
            self.log("Disconnected.")
        }
        let message = [ "type": "bye" ]
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.prettyPrinted]) else { return }
        MockWebSocket.shared.send(data)
        MockWebSocket.shared.delegate = nil
        currentRoomInfo = nil
        isConnected = false
        CallManager.shared.endCall()
    }
    
    // MARK: Message Handling
    func handle(_ messages: [String]) {
        messageQueue.append(contentsOf: messages)
        drainMessageQueue()
    }
    
    func drainMessageQueue() {
        guard isConnected else { return }
        for message in messageQueue {
            handle(message)
        }
        messageQueue.removeAll()
        CallManager.shared.drainMessageQueue()
    }
    
    func handle(_ message: String) {
        let signalingMessage = SignalingMessage.from(message: message)
        switch signalingMessage {
        case .candidate(let candidate):
            CallManager.shared.handleCandidateMessage(candidate)
            log("Candidate received.")
        case .answer(let answer):
            CallManager.shared.handleRemoteDescription(answer)
            log("Answer received.")
        case .offer(let offer):
            CallManager.shared.handleRemoteDescription(offer)
            log("Offer received.")
        case .bye:
            disconnect()
        default:
            break
        }
    }
    
    // MARK: Streaming
    func webSocketDidConnect(_ webSocket: MockWebSocket) {
        guard let info = currentRoomInfo else { return }
        log("Connected to web socket.")
        let message = [
            "cmd": "register",
            "roomid": info.roomID,
            "clientid": info.clientID
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.prettyPrinted]) else { return }
        MockWebSocket.shared.send(data)
        if isInitiator {
            CallManager.shared.initiateCall().retainUntilComplete()
        }
        drainMessageQueue()
    }
    
    func webSocket(_ webSocket: MockWebSocket, didReceive data: String) {
        log("Received data from web socket.")
        handle(data)
        CallManager.shared.drainMessageQueue()
    }
    
    func webSocketDidDisconnect(_ webSocket: MockWebSocket) {
        MockWebSocket.shared.delegate = nil
        log("Disconnecting from web socket.")
    }
    
    func callManager(_ callManager: CallManager, sendData data: Data) {
        guard let info = currentRoomInfo else { return }
        MockCallServer.send(data, roomID: info.roomID, userID: info.clientID).retainUntilComplete()
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
    private func log(_ string: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.infoTextView.text = self.infoTextView.text + "\n" + string
        }
    }
}
