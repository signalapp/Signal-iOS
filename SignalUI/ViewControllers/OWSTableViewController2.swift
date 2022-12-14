//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
    public var contents: OWSTableContents {
        get {
            _contents
        }
        set {
            _contents = newValue
            applyContents()
        }
    }

    private var _contents = OWSTableContents()

    @objc
    public func setContents(_ contents: OWSTableContents, shouldReload: Bool = true) {
        _contents = contents
        applyContents(shouldReload: shouldReload)
    }

    @objc
    public let tableView = OWSTableView(frame: .zero, style: .grouped)

    // This is an alternative to/replacement for UITableView.tableHeaderView.
    //
    // * It should usually be used with buildTopHeader(forView:).
    // * The top header view appears above the table and _does not_
    //   scroll with its content.
    // * The top header view's edge align with the edges of the cells.
    @objc
    open var topHeader: UIView?

    @objc
    open var bottomFooter: UIView?

    @objc
    public var forceDarkMode = false {
        didSet {
            applyTheme()
        }
    }

    @objc
    public var shouldAvoidKeyboard = false

    public enum SelectionBehavior {
        case actionWithAutoDeselect
        case toggleSelectionWithAction
    }
    public var selectionBehavior: SelectionBehavior = .actionWithAutoDeselect

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

        // We never want to show titles on back buttons, so we replace it with
        // blank spaces. We pad it out slightly so that it's more tappable.
        //
        // We also do this in applyTheme(), but we also need to do it here
        // for the case where we push multiple table views at the same time.
        navigationItem.backBarButtonItem = .init(title: "   ", style: .plain, target: nil, action: nil)

        tableView.tableViewDelegate = self
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.tableFooterView = UIView()
        tableView.estimatedRowHeight = defaultCellHeight

        view.addSubview(tableView)

        // Pin top edge of tableView.
        if let topHeader = topHeader {
            view.addSubview(topHeader)
            topHeader.autoPin(toTopLayoutGuideOf: self, withInset: 0)
            topHeader.autoPinEdge(toSuperviewSafeArea: .leading)
            topHeader.autoPinEdge(toSuperviewSafeArea: .trailing)

            tableView.autoPinEdge(.top, to: .bottom, of: topHeader)

            topHeader.setContentHuggingVerticalHigh()
            topHeader.setCompressionResistanceVerticalHigh()
        } else {
            tableView.autoPinEdge(toSuperviewEdge: .top)
        }

        // Pin leading & trailing edges of tableView.
        tableView.autoPinEdge(toSuperviewEdge: .leading)
        tableView.autoPinEdge(toSuperviewEdge: .trailing)
        tableView.setContentHuggingVerticalLow()
        tableView.setCompressionResistanceVerticalLow()

        // Pin bottom edge of tableView.
        if let bottomFooter = bottomFooter {
            view.addSubview(bottomFooter)
            bottomFooter.autoPinEdge(.top, to: .bottom, of: tableView)
            bottomFooter.autoPinEdge(toSuperviewSafeArea: .leading)
            bottomFooter.autoPinEdge(toSuperviewSafeArea: .trailing)
            bottomFooter.setContentHuggingVerticalHigh()
            bottomFooter.setCompressionResistanceVerticalHigh()
        }

        updateBottomConstraint()

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)

        applyContents()
        applyTheme()

        // Reload when dynamic type settings change.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(contentSizeCategoryDidChange),
                                               name: UIContentSizeCategory.didChangeNotification,
                                               object: nil)
    }

    open override func themeDidChange() {
        super.themeDidChange()

        applyTheme()
        applyContents()
    }

    private func applyTheme() {
        applyTheme(to: self)

        tableView.backgroundColor = self.tableBackgroundColor
        tableView.sectionIndexColor = forceDarkMode ? Theme.darkThemePrimaryColor : Theme.primaryTextColor

        updateNavbarStyling()

        tableView.separatorColor = .clear
        tableView.separatorInset = .zero
        tableView.separatorStyle = .none
    }

    public var shouldHideBottomFooter = false {
        didSet {
            let didChange = oldValue != shouldHideBottomFooter
            if didChange, isViewLoaded {
                updateBottomConstraint()
            }
        }
    }

    private var bottomFooterConstraint: NSLayoutConstraint?

    private func updateBottomConstraint() {
        bottomFooterConstraint?.autoRemove()
        bottomFooterConstraint = nil

        // Pin bottom edge of tableView.
        if !shouldHideBottomFooter,
           let bottomFooter = bottomFooter {
            if shouldAvoidKeyboard {
                bottomFooterConstraint = bottomFooter.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)
            } else {
                bottomFooterConstraint = bottomFooter.autoPinEdge(toSuperviewEdge: .bottom)
            }
        } else if shouldAvoidKeyboard {
            bottomFooterConstraint = tableView.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)
        } else {
            bottomFooterConstraint = tableView.autoPinEdge(toSuperviewEdge: .bottom)
        }

        bottomFooter?.isHidden = shouldHideBottomFooter

        guard hasViewAppeared else {
            return
        }

        struct ViewFrame {
            let view: UIView
            let frame: CGRect

            func apply() {
                view.frame = self.frame
            }
        }
        func viewFrames(for views: [UIView]) -> [ViewFrame] {
            views.map { ViewFrame(view: $0, frame: $0.frame) }
        }
        var animatedViews: [UIView] = [ tableView ]
        if let bottomFooter = bottomFooter {
            animatedViews.append(bottomFooter)
        }
        let viewFramesBefore = viewFrames(for: animatedViews)
        self.view.layoutIfNeeded()
        let viewFramesAfter = viewFrames(for: animatedViews)
        for viewFrame in viewFramesBefore { viewFrame.apply() }
        UIView.animate(withDuration: 0.15) {
            for viewFrame in viewFramesAfter { viewFrame.apply() }
        }
    }

    @objc
    private func contentSizeCategoryDidChange(_ notification: Notification) {
        Logger.debug("")

        applyContents()
    }

    private var usesSolidNavbarStyle: Bool {
        return tableView.contentOffset.y <= (defaultSpacingBetweenSections ?? 0) - tableView.adjustedContentInset.top
    }

    open var preferredNavigationBarStyle: OWSNavigationBarStyle {
        return usesSolidNavbarStyle ? .solid : .blur
    }

    open var navbarBackgroundColorOverride: UIColor? {
        return usesSolidNavbarStyle ? tableBackgroundColor : nil
    }

    private var hasViewAppeared = false

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        applyTheme()

        tableView.tableFooterView = UIView()

        hasViewAppeared = true
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

    @objc
    public var shouldDeferInitialLoad = true

    private func applyContents(shouldReload: Bool = true) {
        AssertIsOnMainThread()

        if let title = contents.title, !title.isEmpty {
            self.title = title
        }

        var shouldReload = shouldReload
        if shouldDeferInitialLoad {
            shouldReload = (shouldReload &&
                                self.isViewLoaded &&
                                tableView.width > 0)
        }

        if shouldReload {
            tableView.reloadData()
        }
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
        let layoutMargins = cellOuterInsets(in: wrappedView)
        wrapperStack.layoutMargins = layoutMargins
        return wrapperStack
    }
}

// MARK: -

extension OWSTableViewController2: UITableViewDataSource, UITableViewDelegate, OWSNavigationChildController {

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

        if let cell = item.getOrBuildCustomCell(tableView) {
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
        guard let section = contents.sections[safe: indexPath.section] else {
            owsFailDebug("Missing section: \(indexPath.section)")
            return
        }

        cell.backgroundView?.removeFromSuperview()
        cell.backgroundView = nil
        cell.selectedBackgroundView?.removeFromSuperview()
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear

        guard section.hasBackground else {
            let selectedBackgroundView = UIView()
            selectedBackgroundView.backgroundColor = forceDarkMode
            ? Theme.darkThemeTableCell2SelectedBackgroundColor
            : Theme.tableCell2SelectedBackgroundColor
            cell.selectedBackgroundView = selectedBackgroundView
            return
        }

        cell.backgroundView = buildCellBackgroundView(indexPath: indexPath, section: section)
        cell.selectedBackgroundView = buildCellSelectedBackgroundView(indexPath: indexPath, section: section)

        // We use cellHOuterMargin _outside_ the background and cellHInnerMargin
        // _inside_.
        //
        // By applying it to the cell, ensure the correct behavior for accessories.
        cell.layoutMargins = cellOuterInsetsWithMargin(hMargin: Self.cellHInnerMargin, vMargin: 0)
        var contentMargins = UIEdgeInsets(
            hMargin: 0,
            vMargin: Self.cellVInnerMargin
        )
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
    }

    private func buildCellBackgroundView(indexPath: IndexPath,
                                         section: OWSTableSection) -> UIView {

        let isFirstInSection = indexPath.row == 0
        let isLastInSection = indexPath.row == tableView(tableView, numberOfRowsInSection: indexPath.section) - 1

        let sectionSeparatorInsetLeading = section.separatorInsetLeading
        let sectionSeparatorInsetTrailing = section.separatorInsetTrailing

        let pillLayer = CAShapeLayer()
        var separatorLayer: CAShapeLayer?
        let backgroundView = OWSLayerView(frame: .zero) { [weak self] view in
            guard let self = self else { return }
            var pillFrame = view.bounds.inset(by: self.cellOuterInsets)

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
                if let sectionSeparatorInsetLeading = sectionSeparatorInsetLeading {
                    separatorInsetLeading = CGFloat(sectionSeparatorInsetLeading.floatValue)
                } else {
                    separatorInsetLeading = self.defaultSeparatorInsetLeading
                }

                let separatorInsetTrailing: CGFloat
                if let sectionSeparatorInsetTrailing = sectionSeparatorInsetTrailing {
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
        let backgroundView = OWSLayerView(frame: .zero) { [weak self] view in
            guard let self = self else { return }
            var pillFrame = view.bounds.inset(by: self.cellOuterInsets)

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

    @objc
    public static var maximumInnerWidth: CGFloat { 496 }

    @objc
    public static var defaultHOuterMargin: CGFloat {
        UIDevice.current.isPlusSizePhone ? 20 : 16
    }

    // The distance from the edge of the view to the cell border.
    @objc
    public static func cellOuterInsets(in view: UIView) -> UIEdgeInsets {
        var insets = UIEdgeInsets()

        if view.safeAreaInsets.left <= 0 {
            insets.left = defaultHOuterMargin
        }

        if view.safeAreaInsets.right <= 0 {
            insets.right = defaultHOuterMargin
        }

        let totalInnerWidth = view.width - insets.totalWidth
        if totalInnerWidth > maximumInnerWidth {
            let excessInnerWidth = totalInnerWidth - maximumInnerWidth
            insets.left += excessInnerWidth / 2
            insets.right += excessInnerWidth / 2
        }

        return insets
    }

    @objc
    public var cellOuterInsets: UIEdgeInsets { Self.cellOuterInsets(in: view) }

    @objc
    public func cellOuterInsetsWithMargin(top: CGFloat = .zero, left: CGFloat = .zero, bottom: CGFloat = .zero, right: CGFloat = .zero) -> UIEdgeInsets {
        UIEdgeInsets(
            top: top,
            left: left + cellHOuterLeftMargin,
            bottom: bottom,
            right: right + cellHOuterRightMargin
        )
    }

    @objc
    public func cellOuterInsetsWithMargin(hMargin: CGFloat, vMargin: CGFloat) -> UIEdgeInsets {
        cellOuterInsetsWithMargin(top: vMargin, left: hMargin, bottom: vMargin, right: hMargin)
    }

    @objc
    public static func cellHOuterLeftMargin(in view: UIView) -> CGFloat {
        cellOuterInsets(in: view).left
    }

    @objc
    public var cellHOuterLeftMargin: CGFloat { Self.cellHOuterLeftMargin(in: view) }

    @objc
    public static func cellHOuterRightMargin(in view: UIView) -> CGFloat {
        cellOuterInsets(in: view).right
    }

    @objc
    public var cellHOuterRightMargin: CGFloat { Self.cellHOuterRightMargin(in: view) }

    // The distance from the cell border to the cell content.
    @objc
    public static var cellHInnerMargin: CGFloat {
        UIDevice.current.isPlusSizePhone ? 20 : 16
    }

    // The distance from the cell border to the cell content.
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

    private var headerFont: UIFont { .ows_dynamicTypeBodyClamped.ows_semibold }
    private var footerFont: UIFont { .ows_dynamicTypeCaption1Clamped }

    private func headerTextContainerInsets(for section: OWSTableSection) -> UIEdgeInsets {
        var textContainerInset = cellOuterInsetsWithMargin(
            top: (defaultSpacingBetweenSections ?? 0) + 12,
            bottom: 10
        )

        if section.hasBackground {
            textContainerInset.left += Self.cellHInnerMargin * 0.5
            textContainerInset.right += Self.cellHInnerMargin * 0.5
        }

        textContainerInset.left += tableView.safeAreaInsets.left
        textContainerInset.right += tableView.safeAreaInsets.right
        return textContainerInset
    }

    private func footerTextContainerInsets(for section: OWSTableSection) -> UIEdgeInsets {
        var textContainerInset = cellOuterInsetsWithMargin(top: 12)

        if section.hasBackground {
            textContainerInset.left += Self.cellHInnerMargin
            textContainerInset.right += Self.cellHInnerMargin
        }

        textContainerInset.left += tableView.safeAreaInsets.left
        textContainerInset.right += tableView.safeAreaInsets.right

        return textContainerInset
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection sectionIndex: Int) -> UIView? {
        guard let section = contents.sections[safe: sectionIndex] else {
            owsFailDebug("Missing section: \(sectionIndex)")
            return nil
        }

        func buildTextView() -> UITextView {
            let textView = buildHeaderOrFooterTextView()
            textView.textColor = (Theme.isDarkThemeEnabled || forceDarkMode) ? UIColor.ows_gray05 : UIColor.ows_gray90
            textView.font = headerFont
            textView.textContainerInset = headerTextContainerInsets(for: section)
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
            textView.textColor = forceDarkMode ? Theme.darkThemeSecondaryTextAndIconColor : Theme.secondaryTextAndIconColor
            textView.font = footerFont

            let linkTextAttributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key.foregroundColor: forceDarkMode ? Theme.darkThemePrimaryColor : Theme.primaryTextColor,
                NSAttributedString.Key.font: footerFont,
                NSAttributedString.Key.underlineStyle: 0
            ]
            textView.linkTextAttributes = linkTextAttributes

            textView.textContainerInset = footerTextContainerInsets(for: section)

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
        } else if let headerTitle = section.headerTitle, !headerTitle.isEmpty {
            // Get around a bug sizing UITextView in iOS 16 by manually sizing instead
            // of relying on UITableView.automaticDimension
            if #available(iOS 17, *) { owsFailDebug("Canary to check if this has been fixed") }
            let insets = headerTextContainerInsets(for: section)
            // Reuse sizing code for CVText even though we aren't using a CVText here.
            let height = CVText.measureLabel(
                config: CVLabelConfig(
                    text: headerTitle,
                    font: headerFont,
                    textColor: .black, // doesn't matter for sizing
                    numberOfLines: 0,
                    lineBreakMode: .byWordWrapping,
                    textAlignment: .natural
                ),
                maxWidth: tableView.frame.width - insets.totalWidth
            ).height
            return height + insets.totalHeight
        } else if let headerTitle = section.headerAttributedTitle, !headerTitle.isEmpty {
            // Get around a bug sizing UITextView in iOS 16 by manually sizing instead
            // of relying on UITableView.automaticDimension
            if #available(iOS 17, *) { owsFailDebug("Canary to check if this has been fixed") }
            let insets = headerTextContainerInsets(for: section)
            // Reuse sizing code for CVText even though we aren't using a CVText here.
            let height = CVText.measureLabel(
                config: CVLabelConfig(
                    attributedText: headerTitle,
                    font: headerFont,
                    textColor: .black, // doesn't matter for sizing
                    numberOfLines: 0,
                    lineBreakMode: .byWordWrapping,
                    textAlignment: .natural
                ),
                maxWidth: tableView.frame.width - insets.totalWidth
            ).height
            return height + insets.totalHeight
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
        } else if let footerTitle = section.footerTitle, !footerTitle.isEmpty {
            // Get around a bug sizing UITextView in iOS 16 by manually sizing instead
            // of relying on UITableView.automaticDimension
            if #available(iOS 17, *) { owsFailDebug("Canary to check if this has been fixed") }
            let insets = footerTextContainerInsets(for: section)
            // Reuse sizing code for CVText even though we aren't using a CVText here.
            let height = CVText.measureLabel(
                config: CVLabelConfig(
                    text: footerTitle,
                    font: footerFont,
                    textColor: .black, // doesn't matter for sizing
                    numberOfLines: 0,
                    lineBreakMode: .byWordWrapping,
                    textAlignment: .natural
                ),
                maxWidth: tableView.frame.width - insets.totalWidth
            ).height
            return height + insets.totalHeight
        } else if let footerTitle = section.footerAttributedTitle, !footerTitle.isEmpty {
            // Get around a bug sizing UITextView in iOS 16 by manually sizing instead
            // of relying on UITableView.automaticDimension
            if #available(iOS 17, *) { owsFailDebug("Canary to check if this has been fixed") }
            let insets = footerTextContainerInsets(for: section)
            // Reuse sizing code for CVText even though we aren't using a CVText here.
            let height = CVText.measureLabel(
                config: CVLabelConfig(
                    attributedText: footerTitle,
                    font: footerFont,
                    textColor: .black, // doesn't matter for sizing
                    numberOfLines: 0,
                    lineBreakMode: .byWordWrapping,
                    textAlignment: .natural
                ),
                maxWidth: tableView.frame.width - insets.totalWidth
            ).height
            return height + insets.totalHeight
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
        switch selectionBehavior {
        case .actionWithAutoDeselect:
            tableView.deselectRow(at: indexPath, animated: false)
        case .toggleSelectionWithAction:
            break
        }

        performAction(indexPath: indexPath)
    }

    public func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        switch selectionBehavior {
        case .actionWithAutoDeselect:
            return
        case .toggleSelectionWithAction:
            performAction(indexPath: indexPath)
        }
    }

    private func performAction(indexPath: IndexPath) {
        guard let item = self.item(for: indexPath) else {
            owsFailDebug("Missing item: \(indexPath)")
            return
        }
        if let actionBlock = item.actionBlock {
            actionBlock()
        }
    }

    public func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        guard let section = contents.sections[safe: indexPath.section] else {
            owsFailDebug("Missing section: \(indexPath.section)")
            return true
        }
        return !section.shouldDisableCellSelection
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
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
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
    open var tableBackgroundColor: UIColor {
        AssertIsOnMainThread()

        return Self.tableBackgroundColor(
            isUsingPresentedStyle: isUsingPresentedStyle,
            forceDarkMode: forceDarkMode
        )
    }

    @objc
    public static func tableBackgroundColor(
        isUsingPresentedStyle: Bool,
        forceDarkMode: Bool = false
    ) -> UIColor {
        AssertIsOnMainThread()

        if isUsingPresentedStyle {
            return forceDarkMode ? Theme.darkThemeTableView2PresentedBackgroundColor : Theme.tableView2PresentedBackgroundColor
        } else {
            return forceDarkMode ? Theme.darkThemeTableView2BackgroundColor : Theme.tableView2BackgroundColor
        }
    }

    @objc
    public var cellBackgroundColor: UIColor {
        Self.cellBackgroundColor(
            isUsingPresentedStyle: isUsingPresentedStyle,
            forceDarkMode: forceDarkMode
        )
    }

    public static func cellBackgroundColor(
        isUsingPresentedStyle: Bool,
        forceDarkMode: Bool = false
    ) -> UIColor {
        if isUsingPresentedStyle {
            return forceDarkMode ? Theme.darkThemeTableCell2PresentedBackgroundColor : Theme.tableCell2PresentedBackgroundColor
        } else {
            return forceDarkMode ? Theme.darkThemeTableCell2BackgroundColor : Theme.tableCell2BackgroundColor
        }
    }

    public var cellSelectedBackgroundColor: UIColor {
        if isUsingPresentedStyle {
            return forceDarkMode ? Theme.darkThemeTableCell2PresentedSelectedBackgroundColor : Theme.tableCell2PresentedSelectedBackgroundColor
        } else {
            return forceDarkMode ? Theme.darkThemeTableCell2SelectedBackgroundColor : Theme.tableCell2SelectedBackgroundColor
        }
    }

    public var separatorColor: UIColor {
        if isUsingPresentedStyle {
            return forceDarkMode ? Theme.darkThemeTableView2PresentedSeparatorColor : Theme.tableView2PresentedSeparatorColor
        } else {
            return forceDarkMode ? Theme.darkThemeTableView2SeparatorColor : Theme.tableView2SeparatorColor
        }
    }

    @objc(applyThemeToViewController:)
    public func applyTheme(to viewController: UIViewController) {
        AssertIsOnMainThread()

        viewController.view.backgroundColor = self.tableBackgroundColor

        if
            let owsNavigationController = viewController.owsNavigationController,
            ((viewController as? OWSViewController)?.lifecycle ?? .appeared) == .appeared
        {
            owsNavigationController.updateNavbarAppearance()
        }

        Self.removeBackButtonText(viewController: viewController)

        if viewController != self { applyTheme() }
    }

    public static func removeBackButtonText(viewController: UIViewController) {
        // We never want to show titles on back buttons, so we replace it with
        // blank spaces. We pad it out slightly so that it's more tappable.
        viewController.navigationItem.backBarButtonItem = .init(title: "   ", style: .plain, target: nil, action: nil)
    }

    func updateNavbarStyling() {
        if lifecycle == .appeared {
            owsNavigationController?.updateNavbarAppearance(animated: true)
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
            applyContents()
        }

        coordinator.animate { [weak self] _ in
            self?.applyContents()
        } completion: { [weak self] _ in
            self?.applyContents()
        }
    }

    public override func viewSafeAreaInsetsDidChange() {
        applyContents()
    }
}

// MARK: -

public extension UITableViewCell {
    func addBackgroundView(backgroundColor: UIColor) {
        let backgroundView = UIView()
        backgroundView.backgroundColor = backgroundColor
        contentView.addSubview(backgroundView)
        contentView.sendSubviewToBack(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()
    }
}

// MARK: -

extension OWSTableViewController2: OWSTableViewDelegate {
    func tableViewDidChangeWidth() {
        applyContents()
    }
}

// MARK: -

private protocol OWSTableViewDelegate: AnyObject {
    func tableViewDidChangeWidth()
}

// MARK: -

@objc
public class OWSTableView: UITableView {
    fileprivate weak var tableViewDelegate: OWSTableViewDelegate?

    public override var frame: CGRect {
        didSet {
            let didChangeWidth = frame.width != oldValue.width
            if didChangeWidth {
                tableViewDelegate?.tableViewDidChangeWidth()
            }
        }
    }

    public override var bounds: CGRect {
        didSet {
            let didChangeWidth = bounds.width != oldValue.width
            if didChangeWidth {
                tableViewDelegate?.tableViewDidChangeWidth()
            }
        }
    }
}
