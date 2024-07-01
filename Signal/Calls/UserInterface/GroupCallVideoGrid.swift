//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalRingRTC
import SignalServiceKit

class GroupCallVideoGrid: UICollectionView {
    weak var memberViewErrorPresenter: CallMemberErrorPresenter?
    let layout: GroupCallVideoGridLayout
    let call: SignalCall
    let groupCall: GroupCall
    let ringRtcCall: SignalRingRTC.GroupCall

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
}

extension GroupCallVideoGrid: UICollectionViewDelegate {
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
}

extension GroupCallVideoGrid: UICollectionViewDataSource {
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
            for: indexPath
        ) as! GroupCallVideoGridCell

        guard let remoteDevice = gridRemoteDeviceStates[safe: indexPath.row] else {
            owsFailDebug("missing member address")
            return cell
        }

        cell.setMemberViewErrorPresenter(memberViewErrorPresenter)
        cell.configure(call: call, device: remoteDevice)
        return cell
    }
}

extension GroupCallVideoGrid: GroupCallObserver {
    func groupCallRemoteDeviceStatesChanged(_ call: GroupCall) {
        AssertIsOnMainThread()
        reloadData()
    }

    func groupCallPeekChanged(_ call: GroupCall) {
        AssertIsOnMainThread()
        reloadData()
    }

    func groupCallEnded(_ call: GroupCall, reason: GroupCallEndReason) {
        AssertIsOnMainThread()
        reloadData()
    }

    func groupCallReceivedRaisedHands(_ call: GroupCall, raisedHands: [DemuxId]) {
        AssertIsOnMainThread()
        reloadData()
    }
}

extension GroupCallVideoGrid: GroupCallVideoGridLayoutDelegate {
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
