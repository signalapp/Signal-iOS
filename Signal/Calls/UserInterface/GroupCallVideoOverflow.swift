//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalRingRTC
import SignalServiceKit
import UIKit

protocol GroupCallVideoOverflowDelegate: AnyObject {
    var firstOverflowMemberIndex: Int { get }
    func updateVideoOverflowTrailingConstraint()
}

class GroupCallVideoOverflow: UICollectionView, UICollectionViewDataSource, UICollectionViewDelegate, GroupCallObserver {
    weak var memberViewErrorPresenter: CallMemberErrorPresenter?
    weak var overflowDelegate: GroupCallVideoOverflowDelegate?

    let call: SignalCall
    let groupCall: GroupCall
    let ringRtcCall: SignalRingRTC.GroupCall

    class var itemHeight: CGFloat {
        return UIDevice.current.isIPad ? 96 : 72
    }

    private var hasInitialized = false

    init(call: SignalCall, groupCall: GroupCall, delegate: GroupCallVideoOverflowDelegate) {
        self.call = call
        self.groupCall = groupCall
        self.ringRtcCall = groupCall.ringRtcCall
        self.overflowDelegate = delegate

        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(square: Self.itemHeight)
        layout.minimumLineSpacing = 4
        layout.scrollDirection = .horizontal

        super.init(frame: .zero, collectionViewLayout: layout)

        backgroundColor = .clear
        alpha = 0

        showsHorizontalScrollIndicator = false

        contentInset = UIEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

        // We want the collection view contents to render in the
        // inverse of the type direction.
        semanticContentAttribute = CurrentAppContext().isRTL ? .forceLeftToRight : .forceRightToLeft

        autoSetDimension(.height, toSize: Self.itemHeight)

        register(GroupCallVideoOverflowCell.self, forCellWithReuseIdentifier: GroupCallVideoOverflowCell.reuseIdentifier)
        dataSource = self
        self.delegate = self

        groupCall.addObserver(self, syncStateImmediately: true)
        hasInitialized = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var isAnimating = false
    private var hadVisibleCells = false
    override func reloadData() {
        guard !isAnimating else { return }

        defer {
            if hasInitialized { overflowDelegate?.updateVideoOverflowTrailingConstraint() }
        }

        let hasVisibleCells = overflowedRemoteDeviceStates.count > 0

        if hasVisibleCells != hadVisibleCells {
            hadVisibleCells = hasVisibleCells
            isAnimating = true
            if hasVisibleCells { super.reloadData() }
            UIView.animate(
                withDuration: 0.15,
                animations: { self.alpha = hasVisibleCells ? 1 : 0 },
            ) { _ in
                self.isAnimating = false
                self.reloadData()
            }
        } else {
            super.reloadData()
        }
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? GroupCallVideoOverflowCell else { return }
        cell.cleanupVideoViews()
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? GroupCallVideoOverflowCell else { return }
        guard let remoteDevice = overflowedRemoteDeviceStates[safe: indexPath.row] else {
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
            let remoteDevice = overflowedRemoteDeviceStates[safe: indexPath.row]
        else {
            return nil
        }

        return GroupCallVideoContextMenuConfiguration.build(
            call: call,
            groupCall: groupCall,
            ringRtcCall: ringRtcCall,
            remoteDevice: remoteDevice,
            interactionProvider: { [weak self] in
                return self?.interactions
                    .compactMap({ $0 as? UIContextMenuInteraction })
                    .first
            },
        )
    }

    // MARK: - UICollectionViewDataSource

    var hasOverflowMembers: Bool { overflowRemoteDeviceCount != 0 }

    private var overflowRemoteDeviceCount: Int {
        guard let firstOverflowMemberIndex = overflowDelegate?.firstOverflowMemberIndex else { return 0 }
        let joinedRemoteDeviceStates = ringRtcCall.remoteDeviceStates
        return max(0, joinedRemoteDeviceStates.count - firstOverflowMemberIndex)
    }

    private var overflowedRemoteDeviceStates: [RemoteDeviceState] {
        guard let firstOverflowMemberIndex = overflowDelegate?.firstOverflowMemberIndex else { return [] }

        let joinedRemoteDeviceStates = ringRtcCall.remoteDeviceStates.sortedBySpeakerTime

        guard joinedRemoteDeviceStates.count > firstOverflowMemberIndex else { return [] }

        // We reverse this as we're rendering in the inverted direction.
        return Array(joinedRemoteDeviceStates[firstOverflowMemberIndex..<joinedRemoteDeviceStates.count]).sortedByAddedTime.reversed()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return overflowRemoteDeviceCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: GroupCallVideoOverflowCell.reuseIdentifier,
            for: indexPath,
        ) as! GroupCallVideoOverflowCell

        guard let remoteDevice = overflowedRemoteDeviceStates[safe: indexPath.row] else {
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
}

class GroupCallVideoOverflowCell: UICollectionViewCell {
    static let reuseIdentifier = "GroupCallVideoOverflowCell"
    private let memberView: CallMemberView

    override init(frame: CGRect) {
        let type = CallMemberView.MemberType.remoteInGroup(.videoOverflow)
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
        memberView.configureRemoteVideo(device: device, context: .videoOverflow)
    }

    func setMemberViewErrorPresenter(_ errorPresenter: CallMemberErrorPresenter?) {
        memberView.errorPresenter = errorPresenter
    }
}
