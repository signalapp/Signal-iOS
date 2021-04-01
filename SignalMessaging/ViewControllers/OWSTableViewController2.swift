//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// This class offers a convenient way to build table views
// when performance is not critical, e.g. when the table
// only holds a screenful or two of cells and it's safe to
// retain a view model for each cell in memory at all times.
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
    public let tableView = UITableView(frame: .zero, style: .grouped)

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
    public var shouldAvoidKeyboard = false

    public var defaultHeaderHeight: CGFloat? = 0
    public var defaultFooterHeight: CGFloat? = 0
    public var defaultSpacingBetweenSections: CGFloat? = 20
    public var defaultLastSectionFooter: CGFloat = 20

    @objc
    public lazy var defaultSeparatorInsetLeading: CGFloat = Self.cellHInnerMargin

    @objc
    public var defaultSeparatorInsetTrailing: CGFloat = 0

    @objc
    public var defaultCellHeight: CGFloat = 50

    @objc
    public var isUsingPresentedStyle: Bool {
        return presentingViewController != nil
    }

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
        tableView.estimatedRowHeight = defaultCellHeight

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

        applyTheme()

        tableView.tableFooterView = UIView()
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        removeTheme(from: self)
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

        if let title = contents.title, !title.isEmpty {
            self.title = title
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
        let layoutMargins = UIEdgeInsets(hMargin: OWSTableViewController2.cellHOuterMargin,
                                         vMargin: 0)
        // TODO: Should we apply safeAreaInsets?
        // layoutMargins.left += tableView.safeAreaInsets.left
        // layoutMargins.right += tableView.safeAreaInsets.right
        wrapperStack.layoutMargins = layoutMargins
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
            cell.backgroundView = nil
            cell.selectedBackgroundView?.removeFromSuperview()
            cell.selectedBackgroundView = nil
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear

            guard section.hasBackground else {
                return
            }

            cell.backgroundView = buildCellBackgroundView(indexPath: indexPath, section: section)
            cell.selectedBackgroundView = buildCellSelectedBackgroundView(indexPath: indexPath, section: section)

            // We use cellHOuterMargin _outside_ the background and cellHInnerMargin
            // _inside_.
            //
            // By applying it to the cell, ensure the correct behavior for accesories.
            cell.layoutMargins = UIEdgeInsets(hMargin: Self.cellHOuterMargin + Self.cellHInnerMargin,
                                              vMargin: 0)
            var contentMargins = UIEdgeInsets(hMargin: 0,
                                              vMargin: Self.cellVInnerMargin)
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
            cell.backgroundColor = cellBackgroundColor
        }
    }

    private func buildCellBackgroundView(indexPath: IndexPath,
                                         section: OWSTableSection) -> UIView {

        let isFirstInSection = indexPath.row == 0
        let isLastInSection = indexPath.row == tableView(tableView, numberOfRowsInSection: indexPath.section) - 1

        let pillLayer = CAShapeLayer()
        var separatorLayer: CAShapeLayer?
        let backgroundView = OWSLayerView(frame: .zero) { [weak self] view in
            guard let self = self else { return }
            var pillFrame = view.bounds.inset(by: UIEdgeInsets(hMargin: OWSTableViewController2.cellHOuterMargin,
                                                               vMargin: 0))
            pillFrame.x += view.safeAreaInsets.left
            pillFrame.size.width -= view.safeAreaInsets.left + view.safeAreaInsets.right
            pillLayer.frame = view.bounds
            if pillFrame.width > 0,
               pillFrame.height > 0 {
                var roundingCorners: UIRectCorner = []
                if isFirstInSection {
                    roundingCorners.formUnion(.topLeft)
                    roundingCorners.formUnion(.topRight)
                }
                if isLastInSection {
                    roundingCorners.formUnion(.bottomLeft)
                    roundingCorners.formUnion(.bottomRight)
                }
                let cornerRadii: CGSize = .square(OWSTableViewController2.cellRounding)
                pillLayer.path = UIBezierPath(roundedRect: pillFrame,
                                              byRoundingCorners: roundingCorners,
                                              cornerRadii: cornerRadii).cgPath
            } else {
                pillLayer.path = nil
            }

            if let separatorLayer = separatorLayer {
                separatorLayer.frame = view.bounds
                var separatorFrame = pillFrame
                let separatorThickness: CGFloat = CGHairlineWidth()
                separatorFrame.y = pillFrame.height - separatorThickness
                separatorFrame.size.height = separatorThickness

                let separatorInsetLeading: CGFloat
                if let sectionSeparatorInsetLeading = section.separatorInsetLeading {
                    separatorInsetLeading = CGFloat(sectionSeparatorInsetLeading.floatValue)
                } else {
                    separatorInsetLeading = self.defaultSeparatorInsetLeading
                }

                let separatorInsetTrailing: CGFloat
                if let sectionSeparatorInsetTrailing = section.separatorInsetTrailing {
                    separatorInsetTrailing = CGFloat(sectionSeparatorInsetTrailing.floatValue)
                } else {
                    separatorInsetTrailing = self.defaultSeparatorInsetTrailing
                }

                separatorFrame.x += separatorInsetLeading
                separatorFrame.size.width -= (separatorInsetLeading + separatorInsetTrailing)
                separatorLayer.path = UIBezierPath(rect: separatorFrame).cgPath
            }
        }

        pillLayer.fillColor = cellBackgroundColor.cgColor
        backgroundView.layer.addSublayer(pillLayer)

        if section.hasSeparators,
           !isLastInSection {
            let separator = CAShapeLayer()
            separator.fillColor = separatorColor.cgColor
            backgroundView.layer.addSublayer(separator)
            separatorLayer = separator
        }

        return backgroundView
    }

    private func buildCellSelectedBackgroundView(indexPath: IndexPath,
                                                 section: OWSTableSection) -> UIView {

        let isFirstInSection = indexPath.row == 0
        let isLastInSection = indexPath.row == tableView(tableView, numberOfRowsInSection: indexPath.section) - 1

        let pillLayer = CAShapeLayer()
        let backgroundView = OWSLayerView(frame: .zero) { view in
            var pillFrame = view.bounds.inset(
                by: UIEdgeInsets(
                    hMargin: OWSTableViewController2.cellHOuterMargin,
                    vMargin: 0
                )
            )
            pillFrame.x += view.safeAreaInsets.left
            pillFrame.size.width -= view.safeAreaInsets.left + view.safeAreaInsets.right
            pillLayer.frame = view.bounds
            if pillFrame.width > 0,
               pillFrame.height > 0 {
                var roundingCorners: UIRectCorner = []
                if isFirstInSection {
                    roundingCorners.formUnion(.topLeft)
                    roundingCorners.formUnion(.topRight)
                }
                if isLastInSection {
                    roundingCorners.formUnion(.bottomLeft)
                    roundingCorners.formUnion(.bottomRight)
                }
                let cornerRadii: CGSize = .square(OWSTableViewController2.cellRounding)
                pillLayer.path = UIBezierPath(roundedRect: pillFrame,
                                              byRoundingCorners: roundingCorners,
                                              cornerRadii: cornerRadii).cgPath
            } else {
                pillLayer.path = nil
            }
        }

        pillLayer.fillColor = cellSelectedBackgroundColor.cgColor
        backgroundView.layer.addSublayer(pillLayer)

        return backgroundView
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let item = self.item(for: indexPath) else {
            owsFailDebug("Missing item: \(indexPath)")
            return defaultCellHeight
        }
        if let customRowHeight = item.customRowHeight {
            return CGFloat(customRowHeight.floatValue)
        }
        return defaultCellHeight
    }

    public static let cellRounding: CGFloat = 10

    // The distance from the edge of the view to the cell border.
    @objc
    public static var cellHOuterMargin: CGFloat {
        if CurrentAppContext().interfaceOrientation.isLandscape,
           !UIDevice.current.isIPad {
            // We use a small value in landscape orientation;
            // safeAreaInsets will ensure the correct spacing.
            return 0
        } else {
            return UIDevice.current.isPlusSizePhone ? 20 : 16
        }
    }

    // The distance from the the cell border to the cell content.
    @objc
    public static var cellHInnerMargin: CGFloat {
        UIDevice.current.isPlusSizePhone ? 20 : 16
    }

    // The distance from the the cell border to the cell content.
    public static var cellVInnerMargin: CGFloat {
        13
    }

    private var automaticDimension: CGFloat {
        UITableView.automaticDimension
    }

    private func buildHeaderOrFooterTextView() -> UITextView {
        let textView = LinkingTextView()
        textView.backgroundColor = self.tableBackgroundColor
        return textView
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection sectionIndex: Int) -> UIView? {
        guard let section = contents.sections[safe: sectionIndex] else {
            owsFailDebug("Missing section: \(sectionIndex)")
            return nil
        }

        func buildTextView() -> UITextView {
            let textView = buildHeaderOrFooterTextView()
            textView.textColor = (Theme.isDarkThemeEnabled
                                    ? UIColor.ows_gray05
                                    : UIColor.ows_gray90)
            textView.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold

            let cellHMargin = Self.cellHOuterMargin + Self.cellHInnerMargin * 0.5
            var textContainerInset = UIEdgeInsets(top: (defaultSpacingBetweenSections ?? 0) + 12,
                                                  leading: cellHMargin,
                                                  bottom: 10,
                                                  trailing: cellHMargin)
            textContainerInset.left += tableView.safeAreaInsets.left
            textContainerInset.right += tableView.safeAreaInsets.right
            textView.textContainerInset = textContainerInset

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
        } else if let customHeaderHeight = section.customHeaderHeight,
                  customHeaderHeight.floatValue > 0 {
            return buildDefaultHeaderOrFooter(height: CGFloat(customHeaderHeight.floatValue))
        } else if let defaultHeaderHeight = defaultHeaderHeight,
                  defaultHeaderHeight > 0 {
            return buildDefaultHeaderOrFooter(height: defaultHeaderHeight)
        } else if let defaultSpacingBetweenSections = defaultSpacingBetweenSections,
                  defaultSpacingBetweenSections > 0, !section.items.isEmpty {
            return buildDefaultHeaderOrFooter(height: defaultSpacingBetweenSections)
        } else {
            return nil
        }
    }

    private func buildDefaultHeaderOrFooter(height: CGFloat) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.autoSetDimension(.height, toSize: height)
        return view
    }

    public func tableView(_ tableView: UITableView, viewForFooterInSection sectionIndex: Int) -> UIView? {
        guard let section = contents.sections[safe: sectionIndex] else {
            owsFailDebug("Missing section: \(sectionIndex)")
            return nil
        }

        func buildTextView() -> UITextView {
            let textView = buildHeaderOrFooterTextView()
            textView.textColor = Theme.secondaryTextAndIconColor
            textView.font = UIFont.ows_dynamicTypeCaption1Clamped

            let linkTextAttributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key.foregroundColor: Theme.primaryTextColor,
                NSAttributedString.Key.font: UIFont.ows_dynamicTypeCaption1Clamped,
                NSAttributedString.Key.underlineStyle: 0
            ]
            textView.linkTextAttributes = linkTextAttributes

            let cellHMargin = Self.cellHOuterMargin + Self.cellHInnerMargin
            var textContainerInset = UIEdgeInsets(top: 12,
                                                  leading: cellHMargin,
                                                  bottom: 0,
                                                  trailing: cellHMargin)
            textContainerInset.left += tableView.safeAreaInsets.left
            textContainerInset.right += tableView.safeAreaInsets.right
            textView.textContainerInset = textContainerInset

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
        } else if let customFooterHeight = section.customFooterHeight,
                  customFooterHeight.floatValue > 0 {
            return buildDefaultHeaderOrFooter(height: CGFloat(customFooterHeight.floatValue))
        } else if let defaultFooterHeight = defaultFooterHeight,
                  defaultFooterHeight > 0 {
            return buildDefaultHeaderOrFooter(height: defaultFooterHeight)
        } else if isLastSection(tableView, sectionIndex: sectionIndex),
                  defaultLastSectionFooter > 0 {
            return buildDefaultHeaderOrFooter(height: defaultLastSectionFooter)
        } else {
            return nil
        }
    }

    private func isLastSection(_ tableView: UITableView, sectionIndex: Int) -> Bool {
        sectionIndex == numberOfSections(in: tableView) - 1
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
        tableView.deselectRow(at: indexPath, animated: false)

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
    open func themeDidChange() {
        AssertIsOnMainThread()

        applyTheme()
        tableView.reloadData()
    }

    @objc
    public var tableBackgroundColor: UIColor {
        AssertIsOnMainThread()

        if useNewStyle {
            if isUsingPresentedStyle {
                return Theme.tableView2PresentedBackgroundColor
            } else {
                return Theme.tableView2BackgroundColor
            }
        } else {
            return (useThemeBackgroundColors ? Theme.tableViewBackgroundColor : Theme.backgroundColor)
        }
    }

    @objc
    public var cellBackgroundColor: UIColor {
        if useNewStyle {
            if isUsingPresentedStyle {
                return Theme.tableCell2PresentedBackgroundColor
            } else {
                return Theme.tableCell2BackgroundColor
            }
        } else {
            return (useThemeBackgroundColors ? Theme.tableCellBackgroundColor : Theme.backgroundColor)
        }
    }

    public var cellSelectedBackgroundColor: UIColor {
        if isUsingPresentedStyle {
            return Theme.tableCell2PresentedSelectedBackgroundColor
        } else {
            return Theme.tableCell2SelectedBackgroundColor
        }
    }

    public var separatorColor: UIColor {
        if isUsingPresentedStyle {
            return Theme.tableView2PresentedSeparatorColor
        } else {
            return Theme.tableView2SeparatorColor
        }
    }

    @objc
    open func applyTheme() {
        AssertIsOnMainThread()

        applyTheme(to: self)

        tableView.backgroundColor = self.tableBackgroundColor

        updateNavbarStyling()

        if useNewStyle {
            tableView.separatorColor = .clear
            tableView.separatorInset = .zero
            tableView.separatorStyle = .none
        } else {
            tableView.separatorColor = Theme.cellSeparatorColor
        }
    }

    @objc(applyThemeToViewController:)
    public func applyTheme(to viewController: UIViewController) {
        AssertIsOnMainThread()

        viewController.view.backgroundColor = self.tableBackgroundColor

        if let navigationBar = viewController.navigationController?.navigationBar as? OWSNavigationBar {
            navigationBar.navbarBackgroundColorOverride = tableBackgroundColor
        }

        // We never want to show titles on back buttons, so we replace it with
        // blank spaces. We pad it out slightly so that it's more tappable.
        viewController.navigationItem.backBarButtonItem = .init(title: "   ", style: .plain, target: nil, action: nil)

        if viewController != self { applyTheme() }
    }

    @objc(removeThemeFromViewController:)
    public func removeTheme(from viewController: UIViewController) {
        AssertIsOnMainThread()

        // We don't want to remove the theme if we're being dismissed,
        // as it causes a jarring transition. We must test this on the
        // navigation controller, otherwise it may be set when pushing
        // or popping a view, where we *do* want to remove the theme.
        guard viewController.navigationController?.isBeingDismissed != true else { return }

        if let navigationBar = viewController.navigationController?.navigationBar as? OWSNavigationBar {
            navigationBar.navbarBackgroundColorOverride = nil
            navigationBar.switchToStyle(.default, animated: true)
        }
    }

    func updateNavbarStyling() {
        guard let navigationBar = navigationController?.navigationBar as? OWSNavigationBar else { return }

        if tableView.contentOffset.y <= (defaultSpacingBetweenSections ?? 0) - tableView.adjustedContentInset.top {
            navigationBar.switchToStyle(.solid, animated: true)

            // We always want to treat the bar as translucent, regardless of
            // whether the background image is actually translucent. Otherwise,
            // it messes weirdly with safe area insets.
            navigationBar.isTranslucent = true
        } else {
            navigationBar.switchToStyle(.default, animated: true)
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateNavbarStyling()
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

    open override var isEditing: Bool {
        get { tableView.isEditing }
        set { tableView.isEditing = newValue }
    }

    public override func setEditing(_ editing: Bool, animated: Bool) {
        tableView.setEditing(editing, animated: animated)
    }

    public func setEditing(_ editing: Bool) {
        tableView.setEditing(editing, animated: false)
    }

    // MARK: -

    open override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        guard isViewLoaded else {
            return
        }

        // There is a subtle difference in when the split view controller
        // transitions between collapsed and expanded state on iPad vs
        // when it does on iPhone. We reloadData here in order to ensure
        // the background color of all of our cells is updated to reflect
        // the current state, so it's important that we're only doing this
        // once the state is ready, otherwise there will be a flash of the
        // wrong background color. For iPad, this moment is _before_ the
        // transition occurs. For iPhone, this moment is _during_ the
        // transition. We reload in the right places accordingly.
        if UIDevice.current.isIPad {
            tableView.reloadData()
        }

        coordinator.animate { [weak self] _ in
            self?.tableView.reloadData()
        } completion: { [weak self] _ in
            self?.tableView.reloadData()
        }
    }

    public override func viewSafeAreaInsetsDidChange() {
        tableView.reloadData()
    }
}
