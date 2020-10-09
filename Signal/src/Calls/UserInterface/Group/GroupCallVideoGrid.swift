//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class GroupCallVideoGrid: UICollectionView {
    let call: SignalCall
    init(call: SignalCall) {
        self.call = call

        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 178, height: 206)
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 6

        super.init(frame: .zero, collectionViewLayout: layout)

        call.addObserverAndSyncState(observer: self)

        register(GroupCallVideoGridCell.self, forCellWithReuseIdentifier: GroupCallVideoGridCell.reuseIdentifier)
        dataSource = self
        delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var remoteMemberState: [RemoteDeviceState] {
        return call.groupCall
            .remoteDevices
            .filter { call.groupCall.joinedGroupMembers.contains($0.uuid) }
            .filter { !$0.address.isLocalAddress }
            .sorted { $0.speakerIndex ?? .max < $1.speakerIndex ?? .max }
    }
}

extension GroupCallVideoGrid: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // TODO: iPad, local video
        return min(6, remoteMemberState.count)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: GroupCallVideoGridCell.reuseIdentifier,
            for: indexPath
        ) as! GroupCallVideoGridCell

        guard let remoteDevice = remoteMemberState[safe: indexPath.row] else {
            owsFailDebug("missing member address")
            return cell
        }

        cell.configure(device: remoteDevice)

        return cell
    }
}

extension GroupCallVideoGrid: UICollectionViewDelegate {
    func groupCallLocalDeviceStateChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        reloadData()
    }

    func groupCallRemoteDeviceStatesChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        reloadData()
    }

    func groupCallJoinedGroupMembersChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        reloadData()
    }

    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason) {}

    func groupCallUpdateSfuInfo(_ call: SignalCall) {}
    func groupCallUpdateGroupMembershipProof(_ call: SignalCall) {}
    func groupCallUpdateGroupMembers(_ call: SignalCall) {}

    func individualCallStateDidChange(_ call: SignalCall, state: CallState) {}
    func individualCallLocalVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {}
    func individualCallLocalAudioMuteDidChange(_ call: SignalCall, isAudioMuted: Bool) {}
    func individualCallRemoteVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {}
    func individualCallHoldDidChange(_ call: SignalCall, isOnHold: Bool) {}
}

extension GroupCallVideoGrid: CallObserver {

}

class GroupCallVideoGridCell: UICollectionViewCell {
    static let reuseIdentifier = "GroupCallVideoGridCell"
    private let memberView = RemoteGroupMemberView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(memberView)
        memberView.autoPinEdgesToSuperviewEdges()

        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
    }

    func configure(device: RemoteDeviceState) {
        memberView.configure(device: device)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
