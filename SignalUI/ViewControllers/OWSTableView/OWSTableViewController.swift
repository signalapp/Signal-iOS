//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PureLayout
import SignalCoreKit

@objc
public protocol OWSTableViewControllerDelegate: AnyObject {
    func tableViewWillBeginDragging(_ tableView: UITableView)
}

open class OWSTableViewController: OWSViewController {

    public weak var delegate: OWSTableViewControllerDelegate?

    public var contents = OWSTableContents() {
        didSet {
            if oldValue !== contents {
                applyContents()
            }
        }
    }

    public let tableView = UITableView(frame: .zero, style: .grouped)

    public var shouldAvoidKeyboard: Bool = false

    public var layoutMarginsRelativeTableContent: Bool = false

    private enum Constants {
        static let cellReuseIdentifier = "OWSTableCellIdentifier"
    }

    public override func loadView() {
        super.loadView()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.tableFooterView = UIView(frame: .zero)
        view.addSubview(tableView)

        if shouldAvoidKeyboard {
            tableView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
            tableView.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideView)
        } else {
            tableView.autoPinEdgesToSuperviewEdges()
        }

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Constants.cellReuseIdentifier)

        configureTableViewLayoutMargins()
        applyContents()
        applyTheme()
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        tableView.tableFooterView = UIView(frame: .zero)
    }

    /// Reloads table contents when content size category changes.
    ///
    /// Does not reload header/footer views. Subclasses that use header/footer
    /// views that need to update in response to content size category changes
    /// should override this method to do so manually.
    public override func contentSizeCategoryDidChange() {
        super.contentSizeCategoryDidChange()

        // Reload when content size might need to change.
        applyContents()
    }

    // MARK: Appearance

    /// Applies theme and reloads table contents.
    ///
    /// Does not reload header/footer views. Subclasses that use header/footer
    /// views that need to update in response to theme changes should override
    /// this method to do so manually.
    public override func themeDidChange() {
        super.themeDidChange()

        applyTheme()
        tableView.reloadData()
    }

    open func applyTheme() {
        view.backgroundColor = Theme.backgroundColor
        tableView.backgroundColor = Theme.backgroundColor
        tableView.separatorColor = Theme.cellSeparatorColor
    }

    private func configureTableViewLayoutMargins() {
        guard layoutMarginsRelativeTableContent else { return }

        tableView.preservesSuperviewLayoutMargins = true
        tableView.layoutMargins = .zero
    }

    private static var sectionHeaderFooterTextFont: UIFont {
        return UIFont.preferredFont(forTextStyle: .caption1)
    }

    // MARK: Contents

    private func applyContents() {
        if let title = contents.title?.nilIfEmpty {
            self.title = title
        }
        tableView.reloadData()
    }

    private func sectionForIndex(_ index: Int) -> OWSTableSection {
        return contents.sections[index]
    }

    private func itemForIndexPath(_ indexPath: IndexPath) -> OWSTableItem {
        return sectionForIndex(indexPath.section).items[indexPath.item]
    }

    // MARK: Presentation

    public func present(fromViewController viewController: UIViewController) {
        let navigationController = OWSNavigationController(rootViewController: self)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .stop,
            target: self,
            action: #selector(donePressed(sender:)))
        viewController.present(navigationController, animated: true)
    }

    @objc
    private func donePressed(sender: Any) {
        dismiss(animated: true)
    }
}

extension OWSTableViewController: UITableViewDataSource, UITableViewDelegate {

    public func numberOfSections(in tableView: UITableView) -> Int {
        return contents.sections.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sectionForIndex(section).itemCount
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = itemForIndexPath(indexPath)

        item.tableViewController = self

        if let customCell = item.getOrBuildCustomCell(tableView) {
            return customCell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellReuseIdentifier, for: indexPath)
        OWSTableItem.configureCell(cell)
        cell.textLabel?.text = item.title
        return cell
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if let customHeight = itemForIndexPath(indexPath).customRowHeight {
            return customHeight
        }
        return UITableView.automaticDimension
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let section = sectionForIndex(section)

        if let customHeaderView = section.customHeaderView {
            return customHeaderView
        }

        let hasPlainTextTitle = !section.headerTitle.isEmptyOrNil
        let hasAttributedTextTitle = !(section.headerAttributedTitle?.string ?? "").isEmpty
        if hasPlainTextTitle || hasAttributedTextTitle {
            let textView = LinkingTextView()
            textView.textColor = Theme.secondaryTextAndIconColor
            textView.font = OWSTableViewController.sectionHeaderFooterTextFont
            if hasAttributedTextTitle {
                textView.attributedText = section.headerAttributedTitle
            } else {
                textView.text = section.headerTitle?.uppercased()
            }

            let sectionHeaderView = UIView()
            sectionHeaderView.addSubview(textView)
            textView.autoPinHeightToSuperview()

            if layoutMarginsRelativeTableContent {
                sectionHeaderView.preservesSuperviewLayoutMargins = true
                textView.autoPinWidthToSuperviewMargins()
                textView.textContainerInset = UIEdgeInsets(top: 16, leading: 0, bottom: 6, trailing: 0)
            } else {
                textView.autoPinWidthToSuperview()
                let tableEdgeInset: CGFloat = UIDevice.current.isPlusSizePhone ? 20 : 16
                textView.textContainerInset = UIEdgeInsets(top: 16, leading: tableEdgeInset, bottom: 6, trailing: tableEdgeInset)
            }

            return sectionHeaderView
        }

        return nil
    }

    public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let tableSection = sectionForIndex(section)

        if let customFooterView = tableSection.customFooterView {
            return customFooterView
        }

        let hasPlainTextTitle = !tableSection.footerTitle.isEmptyOrNil
        let hasAttributedTextTitle = !(tableSection.footerAttributedTitle?.string ?? "").isEmpty
        if hasPlainTextTitle || hasAttributedTextTitle {
            let textView = LinkingTextView()
            textView.textColor = .ows_gray45
            textView.font = OWSTableViewController.sectionHeaderFooterTextFont
            textView.linkTextAttributes = [
                .foregroundColor: Theme.accentBlueColor,
                .underlineStyle: NSUnderlineStyle(),
                .font: OWSTableViewController.sectionHeaderFooterTextFont
            ]
            if hasAttributedTextTitle {
                textView.attributedText = tableSection.footerAttributedTitle
            } else {
                textView.text = tableSection.footerTitle
            }

            let sectionFooterView = UIView()
            sectionFooterView.addSubview(textView)
            textView.autoPinHeightToSuperview()

            if layoutMarginsRelativeTableContent {
                sectionFooterView.preservesSuperviewLayoutMargins = true
                textView.autoPinWidthToSuperviewMargins()
                textView.textContainerInset = UIEdgeInsets(top: 16, leading: 0, bottom: 6, trailing: 0)
            } else {
                textView.autoPinWidthToSuperview()
                let tableEdgeInset: CGFloat = UIDevice.current.isPlusSizePhone ? 20 : 16
                textView.textContainerInset = UIEdgeInsets(top: 16, leading: tableEdgeInset, bottom: 6, trailing: tableEdgeInset)
            }

            return sectionFooterView
        }

        return nil
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let tableSection = sectionForIndex(section)

        if let customHeight = tableSection.customHeaderHeight {
            owsAssertDebug(customHeight > 0 || customHeight == UITableView.automaticDimension)
            return customHeight
        }

        if self.tableView(tableView, viewForHeaderInSection: section) != nil {
            return UITableView.automaticDimension
        }

        return 0
   }

    public func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        let tableSection = sectionForIndex(section)

        if let customHeight = tableSection.customFooterHeight {
            owsAssertDebug(customHeight > 0 || customHeight == UITableView.automaticDimension)
            return customHeight
        }

        if self.tableView(tableView, viewForFooterInSection: section) != nil {
            return UITableView.automaticDimension
        }

        return 0
    }

    public func tableView(_ tableView: UITableView, willDeselectRowAt indexPath: IndexPath) -> IndexPath? {
        let item = itemForIndexPath(indexPath)
        guard item.actionBlock != nil else { return nil }
        return indexPath
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let actionBlock = itemForIndexPath(indexPath).actionBlock {
            actionBlock()
        }
    }

    // MARK: Index

    public func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        if let sectionForSectionIndexTitleBlock = contents.sectionForSectionIndexTitleBlock {
            return sectionForSectionIndexTitleBlock(title, index)
        }
        return 0
    }

    public func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        if let sectionIndexTitlesForTableViewBlock = contents.sectionIndexTitlesForTableViewBlock {
            return sectionIndexTitlesForTableViewBlock()
        }
        return nil
    }

    // MARK: Editing

    public override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
    }

    public override var isEditing: Bool {
        didSet {
            tableView.isEditing = isEditing
        }
    }

    public func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        let item = itemForIndexPath(indexPath)
        if item.deleteAction != nil {
            return .delete
        }
        return .none
    }

    public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let item = itemForIndexPath(indexPath)
        return item.deleteAction != nil
    }

    public func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? {
        let item = itemForIndexPath(indexPath)
        return item.deleteAction?.title
    }

    public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        let item = itemForIndexPath(indexPath)
        guard editingStyle == .delete, let deleteAction = item.deleteAction else { return }
        deleteAction.block()
    }
}

extension OWSTableViewController: UIScrollViewDelegate {

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.tableViewWillBeginDragging(tableView)
    }
}
