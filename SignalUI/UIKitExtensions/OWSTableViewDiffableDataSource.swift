//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

/// A `UITableViewDiffableDataSource` that exposes hooks into various
/// `UITableViewDataSource` APIs that callers may be interested in.
public class OWSTableViewDiffableDataSource<
    SectionIdentifier: Hashable,
    ItemIdentifier: Hashable,
>: UITableViewDiffableDataSource<
    SectionIdentifier,
    ItemIdentifier,
> {

    // MARK: Edit rows

    public var canEditRow: ((_ indexPath: IndexPath) -> Bool)?

    override public func tableView(
        _ tableView: UITableView,
        canEditRowAt indexPath: IndexPath,
    ) -> Bool {
        canEditRow?(indexPath) ?? super.tableView(tableView, canEditRowAt: indexPath)
    }

    // MARK: Move rows

    public var canMoveRow: ((_ indexPath: IndexPath) -> Bool)?
    public var didMoveRow: ((_ sourceIndexPath: IndexPath, _ destinationIndexPath: IndexPath) -> Void)?

    override public func tableView(
        _ tableView: UITableView,
        canMoveRowAt indexPath: IndexPath,
    ) -> Bool {
        canMoveRow?(indexPath) ?? true
    }

    override public func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath,
    ) {
        didMoveRow?(sourceIndexPath, destinationIndexPath)
    }

    // MARK: Section index

    public var sectionIndexTitlesProvider: (() -> [String]?)?
    public var sectionForSectionIndexTitleProvider: ((_ title: String, _ index: Int) -> Int)?

    override public func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        if let sectionIndexTitlesProvider {
            sectionIndexTitlesProvider()
        } else {
            super.sectionIndexTitles(for: tableView)
        }
    }

    override public func tableView(
        _ tableView: UITableView,
        sectionForSectionIndexTitle title: String,
        at index: Int,
    ) -> Int {
        if let sectionForSectionIndexTitleProvider {
            sectionForSectionIndexTitleProvider(title, index)
        } else {
            super.tableView(tableView, sectionForSectionIndexTitle: title, at: index)
        }
    }
}
