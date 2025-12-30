//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalRingRTC
import SignalServiceKit
import WebRTC

@MainActor
class GroupCallRemoteVideoManager {
    private let callServiceState: CallServiceState

    init(callServiceState: CallServiceState) {
        self.callServiceState = callServiceState
    }

    private var currentRingRtcCall: SignalRingRTC.GroupCall? {
        switch callServiceState.currentCall?.mode {
        case nil:
            return nil
        case .individual:
            return nil
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            return call.ringRtcCall
        }
    }

    // MARK: - Remote Video Views

    private var videoViews = [UInt32: [CallMemberVisualContext: GroupCallRemoteVideoView]]()

    func remoteVideoView(for device: RemoteDeviceState, context: CallMemberVisualContext) -> GroupCallRemoteVideoView {
        var currentVideoViewsDevice = videoViews[device.demuxId] ?? [:]

        if let current = currentVideoViewsDevice[context] { return current }

        let videoView = GroupCallRemoteVideoView(demuxId: device.demuxId)
        videoView.sizeDelegate = self
        videoView.isGroupCall = true

        if context == .speaker { videoView.isFullScreen = true }

        currentVideoViewsDevice[context] = videoView
        videoViews[device.demuxId] = currentVideoViewsDevice

        return videoView
    }

    private func destroyRemoteVideoView(for demuxId: UInt32) {
        videoViews[demuxId]?.forEach { $0.value.removeFromSuperview() }
        videoViews[demuxId] = nil
    }

    private var updateVideoRequestsDebounceTimer: Timer?
    private func updateVideoRequests() {
        updateVideoRequestsDebounceTimer?.invalidate()
        updateVideoRequestsDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false, block: { [weak self] _ in
            guard let self else { return }

            // scheduledTimer promises to schedule this block on the same run loop that called scheduled timer so we should be main actor here
            MainActor.assumeIsolated {
                guard let groupCall = self.currentRingRtcCall else { return }

                var activeSpeakerHeight: UInt16 = 0

                let videoRequests: [VideoRequest] = groupCall.remoteDeviceStates.map { demuxId, _ in
                    guard
                        let renderingVideoViews = self.videoViews[demuxId]?.filter({ $0.value.isRenderingVideo }),
                        !renderingVideoViews.isEmpty
                    else {
                        return VideoRequest(demuxId: demuxId, width: 0, height: 0, framerate: nil)
                    }

                    if let activeSpeakerVideoView = renderingVideoViews[.speaker] {
                        activeSpeakerHeight = max(activeSpeakerHeight, UInt16(activeSpeakerVideoView.currentSize.height))
                    }

                    let size = renderingVideoViews.reduce(CGSize.zero) { partialResult, element in
                        partialResult.max(element.value.currentSize)
                    }

                    return VideoRequest(
                        demuxId: demuxId,
                        width: UInt16(size.width),
                        height: UInt16(size.height),
                        framerate: size.height <= GroupCallVideoOverflow.itemHeight ? 15 : 30,
                    )
                }

                groupCall.updateVideoRequests(resolutions: videoRequests, activeSpeakerHeight: activeSpeakerHeight)
            }
        })
    }
}

extension GroupCallRemoteVideoManager: GroupCallRemoteVideoViewSizeDelegate {
    @MainActor
    func groupCallRemoteVideoViewDidChangeSize(remoteVideoView: GroupCallRemoteVideoView) {
        updateVideoRequests()
    }

    @MainActor
    func groupCallRemoteVideoViewDidChangeSuperview(remoteVideoView: GroupCallRemoteVideoView) {
        guard let device = currentRingRtcCall?.remoteDeviceStates[remoteVideoView.demuxId] else { return }
        remoteVideoView.configure(for: device)
        updateVideoRequests()
    }
}

extension GroupCallRemoteVideoManager: CallServiceStateObserver {
    func didUpdateCall(from oldValue: SignalCall?, to newValue: SignalCall?) {
        videoViews.forEach { self.destroyRemoteVideoView(for: $0.key) }
        switch oldValue?.mode {
        case nil, .individual:
            break
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            call.removeObserver(self)
        }
        switch newValue?.mode {
        case nil, .individual:
            break
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            call.addObserver(self, syncStateImmediately: true)
        }
    }
}

extension GroupCallRemoteVideoManager: GroupCallObserver {
    func groupCallRemoteDeviceStatesChanged(_ call: GroupCall) {
        for (demuxId, videoViews) in videoViews {
            guard let device = call.ringRtcCall.remoteDeviceStates[demuxId] else {
                destroyRemoteVideoView(for: demuxId)
                continue
            }
            videoViews.values.forEach { $0.configure(for: device) }
        }
    }

    func groupCallEnded(_ call: GroupCall, reason: CallEndReason) {
        videoViews.keys.forEach { destroyRemoteVideoView(for: $0) }
    }
}

private protocol GroupCallRemoteVideoViewSizeDelegate: AnyObject {
    @MainActor
    func groupCallRemoteVideoViewDidChangeSize(remoteVideoView: GroupCallRemoteVideoView)
    @MainActor
    func groupCallRemoteVideoViewDidChangeSuperview(remoteVideoView: GroupCallRemoteVideoView)
}

class GroupCallRemoteVideoView: UIView {
    fileprivate weak var sizeDelegate: GroupCallRemoteVideoViewSizeDelegate?

    fileprivate private(set) var currentSize: CGSize = .zero {
        didSet {
            guard oldValue != currentSize else { return }
            remoteVideoView.frame = CGRect(origin: .zero, size: currentSize)
            sizeDelegate?.groupCallRemoteVideoViewDidChangeSize(remoteVideoView: self)
        }
    }

    // We cannot subclass this, for some unknown reason WebRTC
    // will not render frames properly if we try to.
    private let remoteVideoView = RemoteVideoView()

    private weak var videoTrack: RTCVideoTrack? {
        didSet {
            guard oldValue != videoTrack else { return }
            oldValue?.remove(remoteVideoView)
            videoTrack?.add(remoteVideoView)
        }
    }

    override var frame: CGRect {
        didSet { currentSize = frame.size }
    }

    override var bounds: CGRect {
        didSet { currentSize = bounds.size }
    }

    override func didMoveToSuperview() {
        sizeDelegate?.groupCallRemoteVideoViewDidChangeSuperview(remoteVideoView: self)
    }

    var isGroupCall: Bool {
        get { remoteVideoView.isGroupCall }
        set { remoteVideoView.isGroupCall = newValue }
    }

    var isFullScreen: Bool {
        get { remoteVideoView.isFullScreen }
        set { remoteVideoView.isFullScreen = newValue }
    }

    var isScreenShare: Bool {
        get { remoteVideoView.isScreenShare }
        set { remoteVideoView.isScreenShare = newValue }
    }

    var isRenderingVideo: Bool { videoTrack != nil }

    fileprivate let demuxId: UInt32
    fileprivate init(demuxId: UInt32) {
        self.demuxId = demuxId
        super.init(frame: .zero)
        addSubview(remoteVideoView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { videoTrack = nil }

    func configure(for device: RemoteDeviceState) {
        guard device.demuxId == demuxId else {
            return owsFailDebug("Tried to configure with incorrect device")
        }

        videoTrack = superview == nil ? nil : device.videoTrack
    }
}
