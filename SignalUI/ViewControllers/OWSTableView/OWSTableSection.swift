//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class OWSTableSection {

    public private(set) var items: [OWSTableItem]

    public var itemCount: Int { items.count }

    public var headerTitle: String?
    public var footerTitle: String?

    public var headerAttributedTitle: NSAttributedString?
    public var footerAttributedTitle: NSAttributedString?

    public var customHeaderView: UIView?
    public var customHeaderHeight: CGFloat?

    public var customFooterView: UIView?
    public var customFooterHeight: CGFloat?

    public var hasBackground = true
    public var hasSeparators = true

    public var separatorInsetLeading: CGFloat?
    public var separatorInsetTrailing: CGFloat?

    public var shouldDisableCellSelection = false

    public init(title: String?, items: [OWSTableItem], footerTitle: String? = nil) {
        self.headerTitle = title
        self.items = items
        self.footerTitle = footerTitle
    }

    public convenience init() {
        self.init(title: nil, items: [])
    }

    public convenience init(title: String?) {
        self.init(title: title, items: [])
    }

    public convenience init(items: [OWSTableItem]) {
        self.init(title: nil, items: items)
    }

    public convenience init(
        title: String,
        footerView: UIView
    ) {
        self.init(title: title)
        self.customFooterView = footerView
    }

    public convenience init(
        items: [OWSTableItem],
        headerView: UIView
    ) {
        self.init(items: items)
        self.customHeaderView = headerView
    }

    public convenience init(
        header: (() -> UIView?),
        footer: (() -> UIView?) = {nil}
    ) {
        self.init(title: nil, items: [])
        self.customHeaderView = header()
        self.customFooterView = footer()
    }

    public func add(_ item: OWSTableItem) {
        items.append(item)
    }

    public func add<T: Sequence>(items: T) where T.Element == OWSTableItem {
        self.items.append(contentsOf: items)
    }
}
