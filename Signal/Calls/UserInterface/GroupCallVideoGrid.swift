//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalRingRTC
import SignalServiceKit

class GroupCallVideoGrid: UICollectionView, UICollectionViewDelegate, UICollectionViewDataSource, GroupCallVideoGridLayoutDelegate, GroupCallObserver {
    weak var memberViewErrorPresenter: CallMemberErrorPresenter?
    let layout: GroupCallVideoGridLayout
    let call: SignalCall
    let groupCall: GroupCall
    let ringRtcCall: SignalRingRTC.GroupCall

    private var contactManager: ContactManager { SSKEnvironment.shared.contactManagerRef }
    private var db: DB { DependenciesBridge.shared.db }

    init(call: SignalCall, groupCall: GroupCall) {
        self.call = call
        self.groupCall = groupCall
        self.ringRtcCall = groupCall.ringRtcCall
        self.layout = GroupCallVideoGridLayout()

        super.init(frame: .zero, collectionViewLayout: layout)

        groupCall.addObserver(self, syncStateImmediately: true)
        layout.delegate = self
        backgroundColor = .clear

        register(GroupCallVideoGridCell.self, forCellWithReuseIdentifier: GroupCallVideoGridCell.reuseIdentifier)
        dataSource = self
        delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? GroupCallVideoGridCell else { return }
        cell.cleanupVideoViews()
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? GroupCallVideoGridCell else { return }
        guard let remoteDevice = gridRemoteDeviceStates[safe: indexPath.row] else {
            return owsFailDebug("missing member address")
        }
        cell.configureRemoteVideo(device: remoteDevice)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard
            indexPaths.count == 1,
            let indexPath = indexPaths.first,
            let remoteDevice = gridRemoteDeviceStates[safe: indexPath.row]
        else {
            return nil
        }

        let contactDisplayName: DisplayName = db.read { tx in
            return contactManager.displayName(
                for: SignalServiceAddress(remoteDevice.aci),
                tx: tx,
            )
        }
        let actions = GroupCallContextMenuActionsBuilder.build(
            demuxId: remoteDevice.demuxId,
            contactAci: remoteDevice.aci,
            isAudioMuted: remoteDevice.audioMuted == true,
            ringRtcGroupCall: ringRtcCall,
        )

        return UIContextMenuConfiguration(
            previewProvider: { [weak self] in
                guard let self else { return nil }

                // The cell itself is unreliable as a preview. Reuse, add/remove
                // actions, etc. make it so a given cell might wrap video views
                // for different members as the call goes on, especially if the
                // call has events like joins/leaves/mutes/unmutes.
                //
                // Instead, use a dedicated "call member" preview.
                return GroupCallVideoGridContextMenuPreviewController(
                    demuxId: remoteDevice.demuxId,
                    call: call,
                    groupCall: groupCall,
                    videoGrid: self,
                )
            },
            actionProvider: { _ in
                UIMenu(title: contactDisplayName.resolvedValue(), children: actions)
            },
        )
    }

    // MARK: - UICollectionViewDataSource

    var gridRemoteDeviceStates: [RemoteDeviceState] {
        let remoteDeviceStates = ringRtcCall.remoteDeviceStates.sortedBySpeakerTime
        return Array(remoteDeviceStates.prefix(maxItems)).sortedByAddedTime
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return gridRemoteDeviceStates.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: GroupCallVideoGridCell.reuseIdentifier,
            for: indexPath,
        ) as! GroupCallVideoGridCell

        guard let remoteDevice = gridRemoteDeviceStates[safe: indexPath.row] else {
            owsFailDebug("missing member address")
            return cell
        }

        cell.setMemberViewErrorPresenter(memberViewErrorPresenter)
        cell.configure(call: call, device: remoteDevice)
        return cell
    }

    // MARK: - GroupCallObserver

    func groupCallRemoteDeviceStatesChanged(_ call: GroupCall) {
        AssertIsOnMainThread()
        reloadData()
    }

    func groupCallPeekChanged(_ call: GroupCall) {
        AssertIsOnMainThread()
        reloadData()
    }

    func groupCallEnded(_ call: GroupCall, reason: CallEndReason) {
        AssertIsOnMainThread()
        reloadData()
    }

    func groupCallReceivedRaisedHands(_ call: GroupCall, raisedHands: [DemuxId]) {
        AssertIsOnMainThread()
        reloadData()
    }

    // MARK: - GroupCallVideoGridLayoutDelegate

    var maxColumns: Int {
        if CurrentAppContext().frame.width > 1080 {
            return 4
        } else if CurrentAppContext().frame.width > 768 {
            return 3
        } else {
            return 2
        }
    }

    var maxRows: Int {
        if CurrentAppContext().frame.height > 1024 {
            return 4
        } else {
            return 3
        }
    }

    var maxItems: Int { maxColumns * maxRows }
}

// MARK: -

private class GroupCallVideoGridCell: UICollectionViewCell {
    static let reuseIdentifier = "GroupCallVideoGridCell"
    private let memberView: CallMemberView

    override init(frame: CGRect) {
        let type = CallMemberView.MemberType.remoteInGroup(.videoGrid)
        memberView = CallMemberView(type: type)

        super.init(frame: frame)

        memberView.applyChangesToCallMemberViewAndVideoView { view in
            contentView.addSubview(view)
            view.autoPinEdgesToSuperviewEdges()
        }

        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
    }

    func configure(call: SignalCall, device: RemoteDeviceState) {
        memberView.configure(call: call, remoteGroupMemberDeviceState: device)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func cleanupVideoViews() {
        memberView.cleanupVideoViews()
    }

    func configureRemoteVideo(device: RemoteDeviceState) {
        memberView.configureRemoteVideo(device: device, context: .videoGrid)
    }

    func setMemberViewErrorPresenter(_ errorPresenter: CallMemberErrorPresenter?) {
        memberView.errorPresenter = errorPresenter
    }
}

// MARK: -

/// Wraps a `CallMemberView` for the purposes of a context-menu preview.
private class GroupCallVideoGridContextMenuPreviewController: UIViewController, GroupCallObserver {
    private let demuxId: DemuxId

    private weak var call: SignalCall?
    private weak var groupCall: GroupCall?
    private weak var videoGrid: GroupCallVideoGrid?

    private lazy var callMemberView = CallMemberView(type: .remoteInGroup(.contextMenuPreview))

    init(
        demuxId: DemuxId,
        call: SignalCall,
        groupCall: GroupCall,
        videoGrid: GroupCallVideoGrid,
    ) {
        self.demuxId = demuxId
        self.call = call
        self.groupCall = groupCall
        self.videoGrid = videoGrid
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { owsFail("") }

    override func viewDidLoad() {
        super.viewDidLoad()

        callMemberView.applyChangesToCallMemberViewAndVideoView { _view in
            view.addSubview(_view)
            _view.autoPinEdgesToSuperviewEdges()
        }

        reconfigureCallMemberView()
        groupCall?.addObserver(self)
    }

    // MARK: - GroupCallObserver

    func groupCallRemoteDeviceStatesChanged(_ call: GroupCall) {
        reconfigureCallMemberView()
    }

    func groupCallPeekChanged(_ call: GroupCall) {
        reconfigureCallMemberView()
    }

    func groupCallEnded(_ call: GroupCall, reason: CallEndReason) {
        reconfigureCallMemberView()
    }

    func groupCallReceivedRaisedHands(_ call: GroupCall, raisedHands: [DemuxId]) {
        reconfigureCallMemberView()
    }

    private func reconfigureCallMemberView() {
        guard
            let call,
            let groupCall,
            let remoteDevice = groupCall.ringRtcCall.remoteDeviceStates[demuxId]
        else {
            return
        }

        callMemberView.configure(call: call, remoteGroupMemberDeviceState: remoteDevice)

        if
            let contextMenuInteraction = videoGrid?.interactions
                .compactMap({ $0 as? UIContextMenuInteraction })
                .first
        {
            let actions = GroupCallContextMenuActionsBuilder.build(
                demuxId: remoteDevice.demuxId,
                contactAci: remoteDevice.aci,
                isAudioMuted: remoteDevice.audioMuted == true,
                ringRtcGroupCall: groupCall.ringRtcCall,
            )

            contextMenuInteraction.updateVisibleMenu { menu in
                return menu.replacingChildren(actions)
            }
        }
    }
}

// MARK: -

extension Sequence where Element: RemoteDeviceState {
    /// The first person to join the call is the first item in the list.
    /// Members that are presenting are always put at the top of the list.
    var sortedByAddedTime: [RemoteDeviceState] {
        return sorted { lhs, rhs in
            if lhs.presenting ?? false != rhs.presenting ?? false {
                return lhs.presenting ?? false
            } else if lhs.mediaKeysReceived != rhs.mediaKeysReceived {
                return lhs.mediaKeysReceived
            } else if lhs.addedTime != rhs.addedTime {
                return lhs.addedTime < rhs.addedTime
            } else {
                return lhs.demuxId < rhs.demuxId
            }
        }
    }

    /// The most recent speaker is the first item in the list.
    /// Members that are presenting are always put at the top of the list.
    var sortedBySpeakerTime: [RemoteDeviceState] {
        return sorted { lhs, rhs in
            if lhs.presenting ?? false != rhs.presenting ?? false {
                return lhs.presenting ?? false
            } else if lhs.mediaKeysReceived != rhs.mediaKeysReceived {
                return lhs.mediaKeysReceived
            } else if lhs.speakerTime != rhs.speakerTime {
                return lhs.speakerTime > rhs.speakerTime
            } else {
                return lhs.demuxId < rhs.demuxId
            }
        }
    }
}

// MARK: -

extension Dictionary where Value: RemoteDeviceState {
    /// The first person to join the call is the first item in the list.
    var sortedByAddedTime: [RemoteDeviceState] {
        return values.sortedByAddedTime
    }

    /// The most recent speaker is the first item in the list.
    var sortedBySpeakerTime: [RemoteDeviceState] {
        return values.sortedBySpeakerTime
    }
}
