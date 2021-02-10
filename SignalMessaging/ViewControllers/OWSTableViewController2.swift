//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
open class OWSTableViewController2: OWSViewController {

    @objc
    public weak var delegate: OWSTableViewControllerDelegate?

    @objc
    public var contents = OWSTableContents() {
        didSet {
            applyContents()
        }
    }

    @objc
    public let tableView = UITableView(frame: .zero, style: .plain)

    // This is an alternative to/replacement for UITableView.tableHeaderView.
    //
    // * It should usually be used with buildTopHeader(forView:).
    // * The top header view appears above the table and _does not_
    //   scroll with its content.
    // * The top header view's edge align with the edges of the cells.
    @objc
    open var topHeader: UIView?

    // TODO: Remove.
    @objc
    public var tableViewStyle: UITableView.Style {
        tableView.style
    }

    @objc
    public var useThemeBackgroundColors = false {
        didSet {
            applyTheme()
        }
    }

    @objc
    public var useNewStyle = true {
        didSet {
            applyTheme()
        }
    }

    @objc
    public var customSectionHeaderFooterBackgroundColor: UIColor?

    @objc
    public var shouldAvoidKeyboard = false

    private static let cellIdentifier = "cellIdentifier"

    @objc
    public override init() {
        super.init()
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.tableFooterView = UIView()

        view.addSubview(tableView)

        if let topHeader = topHeader {
            view.addSubview(topHeader)
            topHeader.autoPin(toTopLayoutGuideOf: self, withInset: 0)
            topHeader.autoPinEdge(toSuperviewSafeArea: .leading)
            topHeader.autoPinEdge(toSuperviewSafeArea: .trailing)

            tableView.autoPinEdge(.top, to: .bottom, of: topHeader)
            tableView.autoPinEdge(toSuperviewEdge: .leading)
            tableView.autoPinEdge(toSuperviewEdge: .trailing)

            if shouldAvoidKeyboard {
                autoPinView(toBottomOfViewControllerOrKeyboard: tableView, avoidNotch: true)
            } else {
                tableView.autoPinEdge(toSuperviewEdge: .bottom)
            }

            topHeader.setContentHuggingVerticalHigh()
            topHeader.setCompressionResistanceVerticalHigh()
            tableView.setContentHuggingVerticalLow()
            tableView.setCompressionResistanceVerticalLow()
        } else if tableView.applyInsetsFix() {
            // if applyScrollViewInsetsFix disables contentInsetAdjustmentBehavior,
            // we need to pin to the top and bottom layout guides since UIKit
            // won't adjust our content insets.
            tableView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
            tableView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
            tableView.autoPinEdge(toSuperviewSafeArea: .leading)
            tableView.autoPinEdge(toSuperviewSafeArea: .trailing)

            // We don't need a top or bottom insets, since we pin to the top and bottom layout guides.
            automaticallyAdjustsScrollViewInsets = false
        } else {
            if shouldAvoidKeyboard {
                tableView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
                autoPinView(toBottomOfViewControllerOrKeyboard: tableView, avoidNotch: true)
            } else {
                tableView.autoPinEdgesToSuperviewEdges()
            }
        }

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)

        applyContents()
        applyTheme()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: .ThemeDidChange,
                                               object: nil)
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        tableView.tableFooterView = UIView()
    }

    private func section(for index: Int) -> OWSTableSection? {
        AssertIsOnMainThread()

        guard let section = contents.sections[safe: index] else {
            owsFailDebug("Missing section: \(index)")
            return nil
        }
        return section
    }

    private func item(for indexPath: IndexPath) -> OWSTableItem? {
        AssertIsOnMainThread()

        guard let section = contents.sections[safe: indexPath.section] else {
            owsFailDebug("Missing section: \(indexPath.section)")
            return nil
        }
        guard let item = section.items[safe: indexPath.row] else {
            owsFailDebug("Missing item: \(indexPath.row)")
            return nil
        }
        return item
    }

    private func applyContents() {
        AssertIsOnMainThread()

        if let title = contents.title,
           !title.isEmpty {
            self.title = title
        } else {
            self.title = nil
        }

        tableView.reloadData()
    }

    public static func buildTopHeader(forView wrappedView: UIView,
                                      vMargin: CGFloat = 0) -> UIView {
        buildTopHeader(forView: wrappedView,
                       topMargin: vMargin,
                       bottomMargin: vMargin)
    }

    public static func buildTopHeader(forView wrappedView: UIView,
                                      topMargin: CGFloat = 0,
                                      bottomMargin: CGFloat = 0) -> UIView {
        let wrapperStack = UIStackView()
        wrapperStack.addArrangedSubview(wrappedView)
        wrapperStack.axis = .vertical
        wrapperStack.alignment = .fill
        wrapperStack.isLayoutMarginsRelativeArrangement = true
        wrapperStack.layoutMargins = UIEdgeInsets(hMargin: OWSTableViewController2.cellHMargin,
                                                  vMargin: 0)
        return wrapperStack
    }
}

// MARK: -

extension OWSTableViewController2: UITableViewDataSource, UITableViewDelegate {

    public func tableView(_ tableView: UITableView, numberOfRowsInSection sectionIndex: Int) -> Int {
        guard let section = self.section(for: sectionIndex) else {
            owsFailDebug("Missing section: \(sectionIndex)")
            return 0
        }
        return section.items.count
    }

    public func numberOfSections(in tableView: UITableView) -> Int {
        contents.sections.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let item = self.item(for: indexPath) else {
            owsFailDebug("Missing item: \(indexPath)")
            let cell = OWSTableItem.newCell()
            configureCellBackground(cell, indexPath: indexPath)
            return cell
        }

        item.tableViewController = self

        if let cell = item.getOrBuildCustomCell() {
            configureCellBackground(cell, indexPath: indexPath)
            return cell
        }

        guard let cell: UITableViewCell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier) else {
            owsFailDebug("Missing cell: \(indexPath)")
            let cell = OWSTableItem.newCell()
            configureCellBackground(cell, indexPath: indexPath)
            return cell
        }

        OWSTableItem.configureCell(cell)

        if let title = item.title {
            cell.textLabel?.text = title
        }

        configureCellBackground(cell, indexPath: indexPath)

        return cell
    }

    private func configureCellBackground(_ cell: UITableViewCell, indexPath: IndexPath) {
        if useNewStyle {
            guard let section = contents.sections[safe: indexPath.section] else {
                owsFailDebug("Missing section: \(indexPath.section)")
                return
            }

            cell.backgroundView?.removeFromSuperview()
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear

            guard section.hasBackground else {
                return
            }

            let backgroundViewOuter = UIView.container()
            cell.backgroundView = backgroundViewOuter
            let backgroundViewInner = UIView.container()
            backgroundViewOuter.addSubview(backgroundViewInner)
            backgroundViewInner.backgroundColor = Theme.tableCell2BackgroundColor
            backgroundViewInner.autoPinEdge(toSuperviewEdge: .leading, withInset: Self.cellHMargin)
            backgroundViewInner.autoPinEdge(toSuperviewEdge: .trailing, withInset: Self.cellHMargin)
            backgroundViewInner.autoPinEdge(toSuperviewEdge: .top)
            backgroundViewInner.autoPinEdge(toSuperviewEdge: .bottom)

            let isFirstInSection = indexPath.row == 0
            let isLastInSection = indexPath.row == tableView(tableView, numberOfRowsInSection: indexPath.section) - 1

            backgroundViewInner.layer.cornerRadius = Self.cellRounding
            var maskedCorners: CACornerMask = []
            if isFirstInSection {
                maskedCorners.formUnion(.layerMinXMinYCorner)
                maskedCorners.formUnion(.layerMaxXMinYCorner)
            }
            if isLastInSection {
                maskedCorners.formUnion(.layerMinXMaxYCorner)
                maskedCorners.formUnion(.layerMaxXMaxYCorner)
            }
            backgroundViewInner.layer.maskedCorners = maskedCorners

            if section.hasSeparators,
               !isLastInSection {
                let separatorView = UIView.container()
                separatorView.backgroundColor = Theme.tableView2BackgroundColor
                backgroundViewInner.addSubview(separatorView)
                separatorView.autoSetDimension(.height, toSize: 1)
                //                separatorView.autoSetDimension(.height, toSize: 2)
                //                separatorView.backgroundColor = .red
                separatorView.autoPinEdge(toSuperviewEdge: .leading, withInset: section.separatorInsetLeading)
                separatorView.autoPinEdge(toSuperviewEdge: .trailing, withInset: section.separatorInsetTrailing)
                separatorView.autoPinEdge(toSuperviewEdge: .bottom)
            }

            // We use cellHMargin _outside_ the background and another cellHMargin _inside_.
            // By applying it to the cell, ensure the correct behavior for accesories.
            cell.layoutMargins = UIEdgeInsets(hMargin: Self.cellHMargin * 2, vMargin: 0)
            var contentMargins: UIEdgeInsets = .zero
            // Our table code is going to be vastly simpler if we DRY up the
            // spacing between the cell content and the accessory here.
            let hasAccessory = (cell.accessoryView != nil || cell.accessoryType != .none)
            if hasAccessory {
                if CurrentAppContext().isRTL {
                    contentMargins.left += 8
                } else {
                    contentMargins.right += 8
                }
            }
            cell.contentView.layoutMargins = contentMargins
        } else if useThemeBackgroundColors {
            cell.backgroundColor = Theme.tableCellBackgroundColor
        }
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let item = self.item(for: indexPath) else {
            owsFailDebug("Missing item: \(indexPath)")
            return kOWSTable_DefaultCellHeight
        }
        if let customRowHeight = item.customRowHeight {
            return CGFloat(customRowHeight.floatValue)
        }
        return kOWSTable_DefaultCellHeight
    }

    private static let cellRounding: CGFloat = 10

    public static var cellHMargin: CGFloat {
        UIDevice.current.isPlusSizePhone ? 20 : 16
    }

    private var automaticDimension: CGFloat {
        UITableView.automaticDimension
    }

    //    private var tableEdgeInsets: UIEdgeInsets {
    //        let cellHMargin = self.cellHMargin
    //        return UIEdgeInsets(top: 16, leading: cellHMargin, bottom: 6, trailing: cellHMargin)
    //    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection sectionIndex: Int) -> UIView? {
        guard let section = contents.sections[safe: sectionIndex] else {
            owsFailDebug("Missing section: \(sectionIndex)")
            return nil
        }

        func buildTextView() -> UITextView {
            let textView = LinkingTextView()
            textView.textColor = Theme.secondaryTextAndIconColor
            textView.font = UIFont.ows_dynamicTypeCaption1Clamped

            let cellHMargin = Self.cellHMargin
            textView.textContainerInset = UIEdgeInsets(top: 16, leading: cellHMargin, bottom: 6, trailing: cellHMargin)

            textView.backgroundColor = self.tableBackgroundColor

            return textView
        }

        if let customHeaderView = section.customHeaderView {
            return customHeaderView
        } else if let headerTitle = section.headerTitle,
                  !headerTitle.isEmpty {
            let textView = buildTextView()
            textView.text = headerTitle
            return textView
        } else if let headerAttributedTitle = section.headerAttributedTitle,
                  !headerAttributedTitle.isEmpty {
            let textView = buildTextView()
            textView.attributedText = headerAttributedTitle
            return textView
        } else {
            let view = UIView()
            view.backgroundColor = self.tableBackgroundColor
            return view
        }
    }

    public func tableView(_ tableView: UITableView, viewForFooterInSection sectionIndex: Int) -> UIView? {
        guard let section = contents.sections[safe: sectionIndex] else {
            owsFailDebug("Missing section: \(sectionIndex)")
            return nil
        }

        func buildTextView() -> UITextView {
            let textView = LinkingTextView()
            textView.textColor = UIColor.ows_gray45
            textView.font = UIFont.ows_dynamicTypeCaption1Clamped

            let cellHMargin = Self.cellHMargin
            textView.textContainerInset = UIEdgeInsets(top: 6, leading: cellHMargin, bottom: 12, trailing: cellHMargin)

            let linkTextAttributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key.foregroundColor: Theme.accentBlueColor,
                NSAttributedString.Key.font: UIFont.ows_dynamicTypeCaption1Clamped,
                NSAttributedString.Key.underlineStyle: 0
            ]
            textView.linkTextAttributes = linkTextAttributes

            textView.backgroundColor = self.tableBackgroundColor

            return textView
        }

        if let customFooterView = section.customFooterView {
            return customFooterView
        } else if let footerTitle = section.footerTitle,
                  !footerTitle.isEmpty {
            let textView = buildTextView()
            textView.text = footerTitle
            return textView
        } else if let footerAttributedTitle = section.footerAttributedTitle,
                  !footerAttributedTitle.isEmpty {
            let textView = buildTextView()
            textView.attributedText = footerAttributedTitle
            return textView
        } else {
            let view = UIView()
            view.backgroundColor = self.tableBackgroundColor
            return view
        }
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection sectionIndex: Int) -> CGFloat {
        guard let section = contents.sections[safe: sectionIndex] else {
            owsFailDebug("Missing section: \(sectionIndex)")
            return 0
        }

        if let customHeaderHeight = section.customHeaderHeight {
            let height = CGFloat(customHeaderHeight.floatValue)
            owsAssertDebug(height > 0 || height == automaticDimension)
            return height
        } else if nil != self.tableView(tableView, viewForHeaderInSection: sectionIndex) {
            return automaticDimension
        } else {
            return 0
        }
    }

    public func tableView(_ tableView: UITableView, heightForFooterInSection sectionIndex: Int) -> CGFloat {
        guard let section = contents.sections[safe: sectionIndex] else {
            owsFailDebug("Missing section: \(sectionIndex)")
            return 0
        }

        if let customFooterHeight = section.customFooterHeight {
            let height = CGFloat(customFooterHeight.floatValue)
            owsAssertDebug(height > 0 || height == automaticDimension)
            return height
        } else if nil != self.tableView(tableView, viewForFooterInSection: sectionIndex) {
            return automaticDimension
        } else {
            return 0
        }
    }

    // Called before the user changes the selection. Return a new indexPath, or nil, to change the proposed selection.
    public func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard let item = self.item(for: indexPath) else {
            owsFailDebug("Missing item: \(indexPath)")
            return nil
        }
        if item.actionBlock != nil {
            return indexPath
        } else {
            return nil
        }
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let item = self.item(for: indexPath) else {
            owsFailDebug("Missing item: \(indexPath)")
            return
        }
        if let actionBlock = item.actionBlock {
            actionBlock()
        }
    }

    // MARK: - Index

    // tell table which section corresponds to section title/index (e.g. "B",1))
    public func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        guard let sectionForSectionIndexTitleBlock = contents.sectionForSectionIndexTitleBlock else {
            return 0
        }
        return sectionForSectionIndexTitleBlock(title, index)
    }

    // return list of section titles to display in section index view (e.g. "ABCD...Z#")
    public func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        guard let sectionIndexTitlesForTableViewBlock = contents.sectionIndexTitlesForTableViewBlock else {
            return nil
        }
        return sectionIndexTitlesForTableViewBlock()
    }

    // MARK: - Presentation

    public func present(fromViewController: UIViewController) {
        let navigationController = OWSNavigationController(rootViewController: self)
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop,
                                                           target: self,
                                                           action: #selector(donePressed))
        fromViewController.present(navigationController, animated: true, completion: nil)
    }

    @objc
    func donePressed() {
        self.dismiss(animated: true, completion: nil)
    }

    // MARK: - UIScrollViewDelegate

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.tableViewWillBeginDragging()
    }

    // MARK: - Theme

    @objc
    func themeDidChange() {
        AssertIsOnMainThread()

        applyTheme()
        tableView.reloadData()
    }

    private var tableBackgroundColor: UIColor {
        AssertIsOnMainThread()

        if useNewStyle {
            return Theme.tableView2BackgroundColor
        } else {
            return (useThemeBackgroundColors ? Theme.tableViewBackgroundColor : Theme.backgroundColor)
        }
    }

    private func applyTheme() {
        AssertIsOnMainThread()

        view.backgroundColor = self.tableBackgroundColor
        tableView.backgroundColor = self.tableBackgroundColor

        if useNewStyle {
            tableView.separatorColor = .clear
            tableView.separatorInset = .zero
            tableView.separatorStyle = .none
        } else {
            tableView.separatorColor = Theme.cellSeparatorColor
        }
    }

    // MARK: - Editing

    public func tableView(_ tableView: UITableView,
                          editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        guard let item = self.item(for: indexPath) else {
            owsFailDebug("Missing item: \(indexPath)")
            return .none
        }
        return (item.deleteAction != nil
                    ? .delete
                    : .none)
    }

    public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard let item = self.item(for: indexPath) else {
            owsFailDebug("Missing item: \(indexPath)")
            return false
        }
        return item.deleteAction != nil
    }

    public func tableView(_ tableView: UITableView,
                          titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? {
        guard let item = self.item(for: indexPath) else {
            owsFailDebug("Missing item: \(indexPath)")
            return nil
        }
        return item.deleteAction?.title
    }

    public func tableView(_ tableView: UITableView,
                          commit editingStyle: UITableViewCell.EditingStyle,
                          forRowAt indexPath: IndexPath) {
        guard let item = self.item(for: indexPath) else {
            owsFailDebug("Missing item: \(indexPath)")
            return
        }
        item.deleteAction?.block()
    }

    public override func setEditing(_ editing: Bool, animated: Bool) {
        tableView.setEditing(editing, animated: animated)
    }

    public func setEditing(_ editing: Bool) {
        tableView.setEditing(editing, animated: false)
    }
}
