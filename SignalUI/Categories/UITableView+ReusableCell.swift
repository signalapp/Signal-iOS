//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

public protocol ReusableTableViewCell {
    static var reuseIdentifier: String { get }
}

public extension UITableView {

    /// A typed wrapper around `dequeueReusableCell`.
    ///
    /// - Parameters:
    ///   - type: The `UITableViewCell` subclass that should be dequeued.
    ///   - indexPath: An optional index path for where the cell will be shown.
    ///   - isRegistered:
    ///       If true, indicates that the class was registered using
    ///       `-[UITableView registerClass:forCellReuseIdentifier:]`; in this
    ///       case, the table view will create a new instance if one isn't
    ///       available to dequeue. If false, indicates that the class wasn't
    ///       registered; in this case, the table view will return `nil` if a
    ///       cell isn't available to dequeue.
    /// - Returns:
    ///     A typed `UITableViewCell` subclass. If `isRegistered` is true (and
    ///     the class is properly registered), this won't return `nil`.
    func dequeueReusableCell<T: ReusableTableViewCell & UITableViewCell>(
        _ type: T.Type,
        for indexPath: IndexPath? = nil,
        isRegistered: Bool = true
    ) -> T? {
        let untypedCell: UITableViewCell?
        if let indexPath {
            untypedCell = dequeueReusableCell(withIdentifier: type.reuseIdentifier, for: indexPath)
        } else {
            untypedCell = dequeueReusableCell(withIdentifier: type.reuseIdentifier)
        }
        guard let typedCell = untypedCell as? T else {
            owsAssertDebug(!isRegistered, "Registered cells should exist and have the correct type.")
            return nil
        }
        return typedCell
    }
}
