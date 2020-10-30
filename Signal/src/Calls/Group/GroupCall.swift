//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import SignalRingRTC.RingRTC
import WebRTC
import SignalCoreKit

// TODO: Temporary placeholder, will live in RingRTC

/// Represents the connection state to a media server for a group call.
public enum ConnectionState: Int32 {
    case disconnected = 0
    case connecting = 1
    case connected = 2
    case reconnecting = 3
}

/// Represents whether or not a user is joined to a group call and can exchange media.
public enum JoinState: Int32 {
    case notJoined = 0
    case joining = 1
    case joined = 2
}

/// Bandwidth mode for limiting network bandwidth between the device and media server.
public enum BandwidthMode: Int32 {
    case low = 0
    case normal = 1
}

/// If not ended purposely by the user, gives the reason why a group call ended.
public enum GroupCallEndReason: Int32 {
    case connectionFailure = 0
    case internalFailure = 1
}

/// The local device state for a group call.
public class LocalDeviceState {
    public internal(set) var connectionState: ConnectionState
    public internal(set) var joinState: JoinState
    public internal(set) var audioMuted: Bool
    public internal(set) var videoMuted: Bool

    init() {
        self.connectionState = .disconnected
        self.joinState = .notJoined
        self.audioMuted = true
        self.videoMuted = true
    }
}

/// All remote devices in a group call and their associated state.
public class RemoteDeviceState: Hashable {
    public let demuxId: UInt16
    public let userId: UUID

    public internal(set) var audioMuted: Bool?
    public internal(set) var videoMuted: Bool?
    public internal(set) var speakerIndex: UInt16?
    public internal(set) var videoAspectRatio: Float?
    public internal(set) var audioLevel: UInt16?
    public internal(set) var videoTrack: RTCVideoTrack?

    init(demuxId: UInt16, uuid: UUID) {
        self.demuxId = demuxId
        self.userId = uuid
    }

    public static func ==(lhs: RemoteDeviceState, rhs: RemoteDeviceState) -> Bool {
        return lhs.demuxId == rhs.demuxId && lhs.userId == rhs.userId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(demuxId)
        hasher.combine(userId)
    }
}

/// Used to communicate the group membership to RingRTC for a group call.
public struct GroupMemberInfo {
    public let userId: UUID
    public let userIdCipherText: Data

    public init(userId: UUID, userIdCipherText: Data) {
        self.userId = userId
        self.userIdCipherText = userIdCipherText
    }
}

/// The network address of the media server to use for the group call.
public struct SfuInfo {
    let ipv4: Data?
    let ipv6: Data?
    let port: UInt16

    public init(ipv4: Data?, ipv6: Data?, port: UInt16) {
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.port = port
    }
}

/// Used for the application to communicate the actual resolutions of
/// each device in a group call to RingRTC and the media server.
public struct RenderedResolution {
    let demuxId: UInt16
    let width: UInt16
    let height: UInt16
    let framerate: UInt16?

    public init(demuxId: UInt16, width: UInt16, height: UInt16, framerate: UInt16?) {
        self.demuxId = demuxId
        self.width = width
        self.height = height
        self.framerate = framerate
    }
}

/// The group call observer.
public protocol GroupCallDelegate: class {
    /**
     * Indication that the application should retrieve the latest local device
     * state from the group call and refresh the presentation.
     */
    func groupCall(onLocalDeviceStateChanged groupCall: GroupCall)

    /**
     * Indication that the application should retrieve the latest remote device
     * states from the group call and refresh the presentation.
     */
    func groupCall(onRemoteDeviceStatesChanged groupCall: GroupCall)

    /**
     * Indication that the application can retrieve an updated list of users thar
     * are actively in the group call.
     */
    func groupCall(onJoinedMembersChanged groupCall: GroupCall)

    /**
     * Indication that the application should provide an updated proof of members
     * to the group call.
     */
    func groupCall(requestMembershipProof groupCall: GroupCall)

    /**
     * Indication that the application should provide the list of group members that
     * belong to the group for the purposes of the group call.
     */
    func groupCall(requestGroupMembers groupCall: GroupCall)

    /**
     * Indication that group call ended due to a reason other than the user choosing
     * to disconnect from it.
     */
    func groupCall(onEnded groupCall: GroupCall, reason: GroupCallEndReason)
}

/// Note: This is implemented as a simulation:
/// 1. App creates groupCall.
/// 2. App tries to connect.
/// 3. App must provide dummy SFU information when requested.
/// 4. App must provide a list of group members when requested (make sure there are 3).
/// 5. App can query for joined users (there will be 2).
/// 6. App tries to join.
/// 7. App can set video source/bandwidth mode (as needed).
/// 8. App must provide dummy group membership proof when requested.
/// 9. App can expect a onRemoteDevicesStatesChanged notification and can adjust UI.
/// 10. ...
public class GroupCall {
    weak var delegate: GroupCallDelegate?

    public private(set) var localDeviceState: LocalDeviceState
    public private(set) var remoteDeviceStates: [UInt16: RemoteDeviceState]
    public private(set) var joinedGroupMembers: [UUID]

    // Simulation
    var groupMembers: [GroupMemberInfo]?

    public init() {
        AssertIsOnMainThread()

        localDeviceState = LocalDeviceState()
        remoteDeviceStates = [:]
        joinedGroupMembers = []

        Logger.debug("object! GroupCall created... \(ObjectIdentifier(self))")
    }

    deinit {
        Logger.debug("object! GroupCall destroyed... \(ObjectIdentifier(self))")
    }

    public func connect() {
        AssertIsOnMainThread()
        Logger.debug("connect")

        // Simulation
        DispatchQueue.main.async {
            Logger.debug("connect - main.async")

            self.localDeviceState.connectionState = .connecting
            self.delegate?.groupCall(onLocalDeviceStateChanged: self)
        }
    }

    public func join() {
        AssertIsOnMainThread()
        Logger.debug("join")

        // Simulation
        DispatchQueue.main.async {
            Logger.debug("join - main.async")

            self.localDeviceState.joinState = .joining
            self.delegate?.groupCall(onLocalDeviceStateChanged: self)

            DispatchQueue.main.async {
                Logger.debug("join - main.async - main.async")

                self.delegate?.groupCall(requestMembershipProof: self)
            }
        }
    }

    public func leave() {
        AssertIsOnMainThread()
        Logger.debug("leave")

        // Simulation
        DispatchQueue.main.async {
            Logger.debug("leave - main.async")

            self.localDeviceState.joinState = .notJoined
            self.delegate?.groupCall(onLocalDeviceStateChanged: self)
        }
    }

    public func disconnect() {
        AssertIsOnMainThread()
        Logger.debug("disconnect")

        // Simulation
        DispatchQueue.main.async {
            Logger.debug("disconnect - main.async")

            self.localDeviceState.connectionState = .disconnected
            self.delegate?.groupCall(onLocalDeviceStateChanged: self)
        }
    }

    public var isOutgoingAudioMuted: Bool {
        get { localDeviceState.audioMuted }
        set {
            AssertIsOnMainThread()
            Logger.debug("setOutgoingAudioMuted")

            localDeviceState.audioMuted = newValue

            // Simulation
            DispatchQueue.main.async {
                Logger.debug("setOutgoingAudioMuted - main.async")

                self.delegate?.groupCall(onLocalDeviceStateChanged: self)

                if self.remoteDeviceStates.count > 1 {
                    self.remoteDeviceStates.values.sorted { $0.speakerIndex ?? .max < $1.speakerIndex ?? .max }.first?.audioMuted = self.isOutgoingAudioMuted
                    self.delegate?.groupCall(onRemoteDeviceStatesChanged: self)
                }
            }
        }
    }

    public var isOutgoingVideoMuted: Bool {
        get { localDeviceState.videoMuted }
        set {
            AssertIsOnMainThread()
            Logger.debug("setOutgoingVideoMuted")

            localDeviceState.videoMuted = newValue

            // Simulation
            DispatchQueue.main.async {
                Logger.debug("setOutgoingVideoMuted - main.async")

                self.delegate?.groupCall(onLocalDeviceStateChanged: self)

                if self.remoteDeviceStates.count > 1 {
                    self.remoteDeviceStates.values.sorted { $0.speakerIndex ?? .max < $1.speakerIndex ?? .max }.first?.videoMuted = self.isOutgoingVideoMuted
                    self.delegate?.groupCall(onRemoteDeviceStatesChanged: self)
                }
            }
        }
    }

    public weak var outgoingVideoSource: VideoCaptureController? {
        didSet {
            AssertIsOnMainThread()
            Logger.debug("setOutgoingVideoSource")
        }
    }

    public var bandwidthMode: BandwidthMode {
        get {
            // TODO:
            return .normal
        }
        set {
            AssertIsOnMainThread()
            Logger.debug("setBandwidthMode \(newValue)")
        }
    }

    public var renderedResolutions: [RenderedResolution] {
        get {
            // TODO:
            return []
        }
        set {
            AssertIsOnMainThread()
            Logger.debug("setRenderedResolutions \(newValue)")
        }
    }

    public func updateRenderedResolutions(resolutions: [RenderedResolution]) {

    }

    private var members = [GroupMemberInfo]()
    public func updateGroupMembers(members: [GroupMemberInfo]) {
        AssertIsOnMainThread()
        Logger.debug("updateGroupMembers")
        self.members = members
    }

    private func joinNextMember() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            Logger.debug("updateGroupMembers - main.async - main.async")

            guard let nextToAdd = self.members.filter({ !self.joinedGroupMembers.contains($0.userId) }).randomElement() else { return }

            self.joinedGroupMembers.append(nextToAdd.userId)
            self.delegate?.groupCall(onJoinedMembersChanged: self)

            let device = RemoteDeviceState(demuxId: .random(in: UInt16.min...UInt16.max), uuid: nextToAdd.userId)
            device.audioMuted = Bool.random()
            device.videoMuted = Bool.random()
            device.speakerIndex = device.demuxId
            self.remoteDeviceStates[device.demuxId] = device
            self.delegate?.groupCall(onRemoteDeviceStatesChanged: self)

            guard self.joinedGroupMembers.count < 16 else { return }

            self.joinNextMember()
        }
    }

    public func updateMembershipProof(proof: Data) {
        AssertIsOnMainThread()
        Logger.debug("updateGroupMembershipProof")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Logger.debug("updateGroupMembershipProof - main.async")

            self.localDeviceState.joinState = .joined
            self.delegate?.groupCall(onLocalDeviceStateChanged: self)

            if !self.joinedGroupMembers.contains(TSAccountManager.shared().localUuid!) {
                self.joinedGroupMembers.append(TSAccountManager.shared().localUuid!)
                self.delegate?.groupCall(onJoinedMembersChanged: self)
            }

            self.joinNextMember()
        }
    }
}

public enum CallManagerHttpMethod: Int32 {
    case get = 0
    case put = 1
    case post = 2
}

// TODO: these are placehoders and actually implemented in ringrtc
extension CallManager {
    public func receivedCallMessage(senderUuid: UUID, senderDeviceId: UInt32, localDeviceId: UInt32, message: Data, messageAgeSec: UInt64) {
        AssertIsOnMainThread()
        Logger.debug("receivedCallMessage")
    }

    public func receivedHttpResponse(requestId: UInt32, statusCode: UInt16, body: Data?) {
        AssertIsOnMainThread()
        Logger.debug("receivedHttpResponse")
    }

    public func httpRequestFailed(requestId: UInt32) {

    }

    // MARK: - Group Call
    public func createGroupCall(groupIdToLog: String, videoCaptureController: VideoCaptureController) -> GroupCall? {
        AssertIsOnMainThread()
        Logger.debug("createGroupCall")

        return GroupCall()
    }
}
