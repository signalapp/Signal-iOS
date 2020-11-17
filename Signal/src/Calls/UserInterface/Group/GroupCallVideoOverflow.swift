//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalRingRTC

protocol GroupCallVideoOverflowDelegate: class {
    var firstOverflowMemberIndex: Int { get }
}

class GroupCallVideoOverflow: UICollectionView {
    weak var overflowDelegate: GroupCallVideoOverflowDelegate?
    let call: SignalCall

    class var itemHeight: CGFloat {
        return UIDevice.current.isIPad ? 96 : 72
    }

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

        register(GroupCallVideoGridCell.self, forCellWithReuseIdentifier: GroupCallVideoGridCell.reuseIdentifier)
        dataSource = self

        call.addObserverAndSyncState(observer: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { call.removeObserver(self) }

    private var isAnimating = false
    private var hadVisibleCells = false
    override func reloadData() {
        guard !isAnimating else { return }

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

extension GroupCallVideoOverflow: UICollectionViewDataSource {
    var overflowedRemoteDeviceStates: [RemoteDeviceState] {
        guard let firstOverflowMemberIndex = overflowDelegate?.firstOverflowMemberIndex else { return [] }

        let joinedRemoteDeviceStates = call.groupCall.sortedRemoteDeviceStates

        guard joinedRemoteDeviceStates.count > firstOverflowMemberIndex else { return [] }

        // We reverse this as we're rendering in the inverted direction.
        return Array(joinedRemoteDeviceStates[firstOverflowMemberIndex..<joinedRemoteDeviceStates.count]).reversed()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return overflowedRemoteDeviceStates.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: GroupCallVideoGridCell.reuseIdentifier,
            for: indexPath
        ) as! GroupCallVideoGridCell

        guard let remoteDevice = overflowedRemoteDeviceStates[safe: indexPath.row] else {
            owsFailDebug("missing member address")
            return cell
        }

        cell.configure(call: call, device: remoteDevice)

        return cell
    }
}

extension GroupCallVideoOverflow: CallObserver {
    func groupCallLocalDeviceStateChanged(_ call: SignalCall) {}

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
}
