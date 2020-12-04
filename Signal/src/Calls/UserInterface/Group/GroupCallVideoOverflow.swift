//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalRingRTC

protocol GroupCallVideoOverflowDelegate: class {
    var firstOverflowMemberIndex: Int { get }
    func updateVideoOverflowTrailingConstraint()
}

class GroupCallVideoOverflow: UICollectionView {
    weak var memberViewDelegate: GroupCallMemberViewDelegate?
    weak var overflowDelegate: GroupCallVideoOverflowDelegate?
    let call: SignalCall

    class var itemHeight: CGFloat {
        return UIDevice.current.isIPad ? 96 : 72
    }

    private var hasInitialized = false

    init(call: SignalCall, delegate: GroupCallVideoOverflowDelegate) {
        self.call = call
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

        call.addObserverAndSyncState(observer: self)
        hasInitialized = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { call.removeObserver(self) }

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
                animations: { self.alpha = hasVisibleCells ? 1 : 0 }
            ) { _ in
                self.isAnimating = false
                self.reloadData()
            }
        } else {
            super.reloadData()
        }
    }
}

extension GroupCallVideoOverflow: UICollectionViewDelegate {
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
}

extension GroupCallVideoOverflow: UICollectionViewDataSource {
    var overflowedRemoteDeviceStates: [RemoteDeviceState] {
        guard let firstOverflowMemberIndex = overflowDelegate?.firstOverflowMemberIndex else { return [] }

        let joinedRemoteDeviceStates = call.groupCall.remoteDeviceStates.sortedBySpeakerTime

        guard joinedRemoteDeviceStates.count > firstOverflowMemberIndex else { return [] }

        // We reverse this as we're rendering in the inverted direction.
        return Array(joinedRemoteDeviceStates[firstOverflowMemberIndex..<joinedRemoteDeviceStates.count]).sortedByAddedTime.reversed()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return overflowedRemoteDeviceStates.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: GroupCallVideoOverflowCell.reuseIdentifier,
            for: indexPath
        ) as! GroupCallVideoOverflowCell

        guard let remoteDevice = overflowedRemoteDeviceStates[safe: indexPath.row] else {
            owsFailDebug("missing member address")
            return cell
        }

        cell.setMemberViewDelegate(memberViewDelegate)
        cell.configure(call: call, device: remoteDevice)
        return cell
    }
}

extension GroupCallVideoOverflow: CallObserver {
    func groupCallRemoteDeviceStatesChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        reloadData()
    }

    func groupCallPeekChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        reloadData()
    }

    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        reloadData()
    }
}

class GroupCallVideoOverflowCell: UICollectionViewCell {
    static let reuseIdentifier = "GroupCallVideoOverflowCell"
    private let memberView = GroupCallRemoteMemberView(mode: .videoOverflow)

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(memberView)
        memberView.autoPinEdgesToSuperviewEdges()

        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
    }

    func configure(call: SignalCall, device: RemoteDeviceState) {
        memberView.configure(call: call, device: device)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func cleanupVideoViews() {
        memberView.cleanupVideoViews()
    }

    func configureRemoteVideo(device: RemoteDeviceState) {
        memberView.configureRemoteVideo(device: device)
    }

    func setMemberViewDelegate(_ delegate: GroupCallMemberViewDelegate?) {
        memberView.delegate = delegate
    }
}
