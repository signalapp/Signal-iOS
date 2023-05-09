//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class OWSTableSection: NSObject {

    public private(set) var items: [OWSTableItem]

    @objc
    public var itemCount: Int { items.count }

    @objc
    public var headerTitle: String?

    @objc
    public var footerTitle: String?

    public var headerAttributedTitle: NSAttributedString?
    public var footerAttributedTitle: NSAttributedString?

    public var customHeaderView: UIView?
    public var customHeaderHeight: CGFloat?

    public var customFooterView: UIView?
    public var customFooterHeight: CGFloat?

    public var hasBackground = true
    public var hasSeparators = true

    @objc
    public var separatorInsetLeading: NSNumber?

    @objc
    public var separatorInsetTrailing: NSNumber?

    public var shouldDisableCellSelection = false

    public init(title: String?, items: [OWSTableItem], footerTitle: String?) {
        self.headerTitle = title
        self.items = items
        self.footerTitle = footerTitle
        super.init()
    }

    public convenience override init() {
        self.init(title: nil, items: [], footerTitle: nil)
    }

    public convenience init(title: String?) {
        self.init(title: title, items: [], footerTitle: nil)
    }

    public convenience init(items: [OWSTableItem]) {
        self.init(title: nil, items: items, footerTitle: nil)
    }

    public convenience init(title: String?, items: [OWSTableItem]) {
        self.init(title: title, items: items, footerTitle: nil)
    }

    public convenience init(
        title: String?,
        headerView: UIView? = nil,
        footerView: UIView? = nil
    ) {
        self.init(title: title, items: [], footerTitle: nil)
        self.customHeaderView = headerView
        self.customFooterView = footerView
    }

    public convenience init(
        header: (() -> UIView?),
        footer: (() -> UIView?) = {nil}
    ) {
        self.init(title: nil, items: [], footerTitle: nil)
        self.customHeaderView = header()
        self.customFooterView = footer()
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public static func sectionWithTitle(_ title: String?, items: [OWSTableItem]) -> OWSTableSection {
        return OWSTableSection(title: title, items: items)
    }

    @objc(addItem:)
    public func add(_ item: OWSTableItem) {
        items.append(item)
    }

    @objc(addItems:)
    func addItems(_ items: [OWSTableItem]) {
        add(items: items)
    }

    public func add<T: Sequence>(items: T) where T.Element == OWSTableItem {
        self.items.append(contentsOf: items)
    }
}
