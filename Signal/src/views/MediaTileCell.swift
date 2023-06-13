//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

protocol MediaTileCell: AnyObject {
    func makePlaceholder()
    func configure(item: AllMediaItem, spoilerReveal: SpoilerRevealState)
    var item: AllMediaItem? { get set }
    var allowsMultipleSelection: Bool { get }
    func setAllowsMultipleSelection(_ allowed: Bool, animated: Bool)
    func mediaPresentationContext(
        collectionView: UICollectionView,
        in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext?
    func indexPathDidChange(_ indexPath: IndexPath, itemCount: Int)
}
