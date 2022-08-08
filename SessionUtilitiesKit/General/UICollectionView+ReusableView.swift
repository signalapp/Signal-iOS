// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

public extension UICollectionView {
    func register<View>(view: View.Type) where View: UICollectionViewCell {
        register(view.self, forCellWithReuseIdentifier: view.defaultReuseIdentifier)
    }

    func register<View>(view: View.Type, ofKind kind: String) where View: UICollectionReusableView {
        register(view.self, forSupplementaryViewOfKind: kind, withReuseIdentifier: view.defaultReuseIdentifier)
    }

    func dequeue<T>(type: T.Type, for indexPath: IndexPath) -> T where T: UICollectionViewCell {
        // Note: We need to use `type.defaultReuseIdentifier` rather than `T.defaultReuseIdentifier`
        // otherwise we may get a subclass rather than the actual type we specified
        let reuseIdentifier = type.defaultReuseIdentifier
        return dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! T
    }

    func dequeue<T>(type: T.Type, ofKind kind: String, for indexPath: IndexPath) -> T where T: UICollectionReusableView {
        // Note: We need to use `type.defaultReuseIdentifier` rather than `T.defaultReuseIdentifier`
        // otherwise we may get a subclass rather than the actual type we specified
        let reuseIdentifier = type.defaultReuseIdentifier
        return dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: reuseIdentifier, for: indexPath) as! T
    }
}
