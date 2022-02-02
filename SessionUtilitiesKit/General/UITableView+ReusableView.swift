// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

public extension UITableView {
    func register<View>(view: View.Type) where View: UITableViewCell {
        register(view.self, forCellReuseIdentifier: view.defaultReuseIdentifier)
    }

    func registerHeaderFooterView<View>(view: View.Type) where View: UITableViewHeaderFooterView {
        register(view.self, forHeaderFooterViewReuseIdentifier: view.defaultReuseIdentifier)
    }

    func dequeue<T>(type: T.Type, for indexPath: IndexPath) -> T where T: UITableViewCell {
        let reuseIdentifier = T.defaultReuseIdentifier
        return dequeueReusableCell(withIdentifier: reuseIdentifier, for: indexPath) as! T
    }

    func dequeueHeaderFooterView<T>(type: T.Type) -> T where T: UITableViewHeaderFooterView {
        let reuseIdentifier = T.defaultReuseIdentifier
        return dequeueReusableHeaderFooterView(withIdentifier: reuseIdentifier) as! T
    }
}
