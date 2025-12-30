//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import BonMot
import SignalServiceKit

public protocol OWSTableViewControllerDelegate: AnyObject {
    func tableViewWillBeginDragging(_ tableView: UITableView)
}

// This class offers a convenient way to build table views
// when performance is not critical, e.g. when the table
// only holds a screenful or two of cells and it's safe to
// retain a view model for each cell in memory at all times.
open class OWSTableViewController2: OWSViewController {

    public weak var delegate: OWSTableViewControllerDelegate?

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

    public func setContents(_ contents: OWSTableContents, shouldReload: Bool = true) {
        _contents = contents
        applyContents(shouldReload: shouldReload)
    }

    public let tableView = OWSTableView(frame: .zero, style: .insetGrouped)

    // This is an alternative to/replacement for UITableView.tableHeaderView.
    //
    // * It should usually be used with buildTopHeader(forView:).
    // * The top header view appears above the table and _does not_
    //   scroll with its content.
    // * The top header view's edge align with the edges of the cells.
    open var topHeader: UIView? {
        willSet {
            if isViewLoaded {
                owsFailBeta("Cannot assign header if the view is already loaded.")
            }
        }
    }

    open var bottomFooter: UIView? {
        willSet {
            if isViewLoaded {
                owsFailBeta("Cannot assign footer if the view is already loaded.")
            }
        }
    }

    public var forceDarkMode = false {
        didSet {
            guard isViewLoaded else { return }
            applyTheme()
        }
    }

    /// Whether or not this table view should avoid being hidden behind the
    /// keyboard.
    public var shouldAvoidKeyboard = false {
        didSet {
            guard isViewLoaded else { return }
            updateBottomConstraint()
        }
    }

    public enum SelectionBehavior {
        case actionWithAutoDeselect
        case toggleSelectionWithAction
    }

    public var selectionBehavior: SelectionBehavior = .actionWithAutoDeselect

    public var defaultSpacingBetweenSections: CGFloat? = 20

    private var defaultLastSectionFooter: CGFloat = 20

    public var defaultSeparatorInsetLeading: CGFloat = OWSTableViewController2.cellHInnerMargin

    public var defaultCellHeight: CGFloat = 50

    private var isUsingPresentedStyle: Bool {
        presentingViewController != nil || traitCollection.userInterfaceLevel == .elevated
    }

    private static let cellIdentifier = "cellIdentifier"

    override public init() {
        super.init()

        // We also do this in applyTheme(), but we also need to do it here
        // for the case where we push multiple table views at the same time.
        Self.removeBackButtonText(viewController: self)

        tableView.tableViewDelegate = self
    }

    override open func viewDidLoad() {
        super.viewDidLoad()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.tableFooterView = UIView()
        tableView.estimatedRowHeight = defaultCellHeight

        view.addSubview(tableView)

        // Pin top edge of tableView.
        if let topHeader {
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
        if let bottomFooter {
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
    }

    /// Applies theme and reloads table contents.
    ///
    /// Does not reload header/footer views. Subclasses that use header/footer
    /// views that need to update in response to theme changes should override
    /// this method to do so manually.
    override open func themeDidChange() {
        super.themeDidChange()

        applyTheme()
        applyContents()
    }

    public enum BackgroundStyle {
        case `default`
        case none
    }

    /// In order for iOS 26 resizable sheets to maintain their background
    /// transition from glass to solid, `.none` must mean the background is
    /// never set, not that it is set to `.clear` or `nil`, as setting it at any
    /// point will remove the system dynamic background.
    public var backgroundStyle: BackgroundStyle = .default

    public var tableBackgroundColor: UIColor {
        AssertIsOnMainThread()

        return Self.tableBackgroundColor(
            isUsingPresentedStyle: isUsingPresentedStyle,
            forceDarkMode: forceDarkMode,
        )
    }

    private func applyTheme() {
        switch backgroundStyle {
        case .default:
            tableView.backgroundColor = self.tableBackgroundColor
        case .none:
            break
        }

        tableView.sectionIndexColor = forceDarkMode ? Theme.darkThemePrimaryColor : Theme.primaryTextColor

        updateNavbarStyling()

        tableView.separatorColor = .clear
        tableView.separatorInset = .zero
        tableView.separatorStyle = .none
    }

    public var shouldHideBottomFooter = false {
        didSet {
            let didChange = oldValue != shouldHideBottomFooter
            guard didChange, isViewLoaded else { return }
            updateBottomConstraint()
        }
    }

    private var bottomFooterConstraint: NSLayoutConstraint?

    private func updateBottomConstraint() {
        if let bottomFooterConstraint {
            NSLayoutConstraint.deactivate([bottomFooterConstraint])
            self.bottomFooterConstraint = nil
        }

        // Pin bottom edge of tableView.
        let bottomFooterConstraint: NSLayoutConstraint
        if !shouldHideBottomFooter, let bottomFooter {
            if shouldAvoidKeyboard {
                bottomFooterConstraint = bottomFooter.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor)
            } else {
                bottomFooterConstraint = bottomFooter.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            }
        } else if shouldAvoidKeyboard {
            bottomFooterConstraint = tableView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor)
        } else {
            bottomFooterConstraint = tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        }
        NSLayoutConstraint.activate([bottomFooterConstraint])

        bottomFooter?.isHidden = shouldHideBottomFooter
        self.bottomFooterConstraint = bottomFooterConstraint

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
        var animatedViews: [UIView] = [tableView]
        if let bottomFooter {
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

    /// Reloads table contents when content size category changes.
    ///
    /// Does not reload header/footer views. Subclasses that use header/footer
    /// views that need to update in response to content size category changes
    /// should override this method to do so manually.
    override open func contentSizeCategoryDidChange() {
        super.contentSizeCategoryDidChange()

        // Reload when content size might need to change.
        applyContents()
    }

    private var usesSolidNavbarStyle: Bool {
        return tableView.contentOffset.y <= (defaultSpacingBetweenSections ?? 0) - tableView.adjustedContentInset.top
    }

    open var preferredNavigationBarStyle: OWSNavigationBarStyle {
        return usesSolidNavbarStyle ? .solid : .blur
    }

    open var navbarBackgroundColorOverride: UIColor? {
        if usesSolidNavbarStyle {
            tableBackgroundColor
        } else if forceDarkMode {
            Theme.darkThemeNavbarBackgroundColor
        } else {
            nil
        }
    }

    open var navbarTintColorOverride: UIColor? {
        forceDarkMode ? Theme.darkThemePrimaryColor : nil
    }

    private var hasViewAppeared = false

    override open func viewWillAppear(_ animated: Bool) {
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

    public var shouldDeferInitialLoad = true

    public func updateTableMargins() {
        tableView.insetsLayoutMarginsFromSafeArea = false
        let hMargin = Self.cellOuterInset(in: view)
        tableView.directionalLayoutMargins.leading = hMargin + view.safeAreaInsets.leading
        tableView.directionalLayoutMargins.trailing = hMargin + view.safeAreaInsets.trailing
    }

    private func applyContents(shouldReload: Bool = true) {
        AssertIsOnMainThread()

        updateTableMargins()

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

    public static func buildTopHeader(
        forView wrappedView: UIView,
        vMargin: CGFloat = 0,
    ) -> UIView {
        buildTopHeader(
            forView: wrappedView,
            topMargin: vMargin,
            bottomMargin: vMargin,
        )
    }

    public static func buildTopHeader(
        forView wrappedView: UIView,
        topMargin: CGFloat = 0,
        bottomMargin: CGFloat = 0,
    ) -> UIView {
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

        if let title = item.title {
            cell.textLabel?.text = title
        }

        // Use the general configureCell(), after which we'll manually configure
        // the cell background further.
        OWSTableItem.configureCell(cell)
        configureCellBackground(cell, indexPath: indexPath)

        return cell
    }

    public func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let item = self.item(for: indexPath) else {
            owsFailDebug("Missing item: \(indexPath)")
            return
        }

        if let willDisplayBlock = item.willDisplayBlock {
            willDisplayBlock(cell)
        }
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

        guard section.hasBackground else { return }

        let cellBackgroundColor: UIColor
        let cellSelectedBackgroundColor: UIColor
        if let customCell = cell as? CustomBackgroundColorCell {
            cellBackgroundColor = customCell.customBackgroundColor(forceDarkMode: forceDarkMode)
            cellSelectedBackgroundColor = customCell.customSelectedBackgroundColor(forceDarkMode: forceDarkMode)
        } else {
            cellBackgroundColor = self.cellBackgroundColor
            cellSelectedBackgroundColor = self.cellSelectedBackgroundColor
        }

        cell.backgroundView = buildCellBackgroundView(
            indexPath: indexPath,
            section: section,
            backgroundColor: cellBackgroundColor,
        )

        let selectedBackground = UIView()
        selectedBackground.backgroundColor = cellSelectedBackgroundColor
        cell.selectedBackgroundView = selectedBackground

        cell.layoutMargins = UIEdgeInsets(
            hMargin: Self.cellHInnerMargin,
            vMargin: Self.cellVInnerMargin,
        )
    }

    private func configureCellSeparatorLayer(
        separatorLayer: CAShapeLayer,
        view: UIView,
        sectionSeparatorInsetLeading: CGFloat?,
        separatorColor: UIColor,
    ) {
        separatorLayer.frame = view.bounds
        separatorLayer.fillColor = separatorColor.cgColor

        var separatorFrame = view.bounds
        let separatorThickness: CGFloat = .hairlineWidth

        separatorFrame.y = separatorFrame.height - separatorThickness
        separatorFrame.size.height = separatorThickness

        let separatorInsetLeading = sectionSeparatorInsetLeading ?? self.defaultSeparatorInsetLeading

        separatorFrame.x += separatorInsetLeading
        separatorFrame.size.width -= separatorInsetLeading
        separatorLayer.path = UIBezierPath(rect: separatorFrame).cgPath
    }

    private func buildCellBackgroundView(
        indexPath: IndexPath,
        section: OWSTableSection,
        backgroundColor: UIColor,
    ) -> UIView {
        let isLastInSection = indexPath.row == tableView(tableView, numberOfRowsInSection: indexPath.section) - 1

        var separatorLayer: CAShapeLayer?

        let backgroundView = OWSLayerView(frame: .zero) { [weak self] view in
            guard let self else { return }

            if let separatorLayer {
                self.configureCellSeparatorLayer(
                    separatorLayer: separatorLayer,
                    view: view,
                    sectionSeparatorInsetLeading: section.separatorInsetLeading,
                    separatorColor: self.separatorColor,
                )
            }
        }

        if
            section.hasSeparators,
            !isLastInSection
        {
            let separator = CAShapeLayer()
            separatorLayer = separator

            backgroundView.layer.addSublayer(separator)
        }

        backgroundView.backgroundColor = backgroundColor

        return backgroundView
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let item = self.item(for: indexPath) else {
            owsFailDebug("Missing item: \(indexPath)")
            return defaultCellHeight
        }
        if let customRowHeight = item.customRowHeight {
            return customRowHeight
        }
        return UITableView.automaticDimension
    }

    /// Approximate cell corner rounding. Now that we use native inset grouped
    /// tables, this is only an approximation and its use should be avoided.
    public static let cellRounding: CGFloat = if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
        22
    } else {
        10
    }

    public static var maximumInnerWidth: CGFloat { 496 }

    public static var defaultHOuterMargin: CGFloat {
        UIDevice.current.isPlusSizePhone ? 20 : 16
    }

    // The distance from the edge of the view to the cell border.
    public static func cellOuterInsets(in view: UIView) -> UIEdgeInsets {
        UIEdgeInsets(hMargin: cellOuterInset(in: view), vMargin: 0)
    }

    public static func cellOuterInset(in view: UIView) -> CGFloat {
        var inset = defaultHOuterMargin
        let totalInnerWidth = view.width - (inset * 2) - view.safeAreaInsets.totalWidth
        if totalInnerWidth > maximumInnerWidth {
            inset += (totalInnerWidth - maximumInnerWidth) / 2
        }
        return inset
    }

    public var cellOuterInsets: UIEdgeInsets { Self.cellOuterInsets(in: view) }

    // The distance from the cell border to the cell content.
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

    public static var defaultHeaderFont: UIFont { .dynamicTypeHeadlineClamped }

    public var defaultHeaderTextColor: UIColor {
        forceDarkMode ? Theme.darkThemePrimaryColor : Theme.primaryTextColor
    }

    public var defaultHeaderTextStyle: BonMot.StringStyle {
        return BonMot.StringStyle([
            .font(Self.defaultHeaderFont),
            .color(defaultHeaderTextColor),
        ])
    }

    public static var defaultFooterFont: UIFont { .dynamicTypeFootnoteClamped }

    public var defaultFooterTextColor: UIColor {
        forceDarkMode ? Theme.darkThemeSecondaryTextAndIconColor : Theme.secondaryTextAndIconColor
    }

    public var defaultFooterTextStyle: BonMot.StringStyle {
        return BonMot.StringStyle([
            .font(Self.defaultFooterFont),
            .color(defaultFooterTextColor),
        ])
    }

    private func headerTextContainerInsets(for section: OWSTableSection) -> UIEdgeInsets {
        headerTextContainerInsets(useDeepInsets: section.hasBackground)
    }

    private func headerTextContainerInsets(useDeepInsets: Bool) -> UIEdgeInsets {
        var textContainerInset = UIEdgeInsets(
            top: (defaultSpacingBetweenSections ?? 0) + 12,
            leading: 0,
            bottom: 10,
            trailing: 0,
        )

        if useDeepInsets {
            textContainerInset.leading += Self.cellHInnerMargin * 0.5
            textContainerInset.trailing += Self.cellHInnerMargin * 0.5
        }

        return textContainerInset
    }

    private func footerTextContainerInsets(for section: OWSTableSection) -> UIEdgeInsets {
        footerTextContainerInsets(useDeepInsets: section.hasBackground)
    }

    private func footerTextContainerInsets(useDeepInsets: Bool) -> UIEdgeInsets {
        var textContainerInset = UIEdgeInsets.zero
        textContainerInset.top = 12

        if useDeepInsets {
            textContainerInset.leading += Self.cellHInnerMargin
            textContainerInset.trailing += Self.cellHInnerMargin
        }

        return textContainerInset
    }

    private func buildDefaultHeaderOrFooter(height: CGFloat) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.autoSetDimension(.height, toSize: height)
        return view
    }

    private func buildHeaderOrFooterTextView() -> UITextView {
        let textView = LinkingTextView()
        switch backgroundStyle {
        case .default:
            textView.backgroundColor = self.tableBackgroundColor
        case .none:
            break
        }
        return textView
    }

    public func buildHeaderTextView(forSection section: OWSTableSection) -> UITextView {
        let textView = buildHeaderTextView(withDeepInsets: section.hasBackground)
        textView.delegate = section.headerTextViewDelegate
        return textView
    }

    public func buildHeaderTextView(withDeepInsets: Bool) -> UITextView {
        let textView = buildHeaderOrFooterTextView()

        textView.textColor = defaultHeaderTextColor
        textView.font = Self.defaultHeaderFont
        textView.textContainerInset = headerTextContainerInsets(useDeepInsets: withDeepInsets)

        return textView
    }

    public func buildFooterTextView(forSection section: OWSTableSection) -> UITextView {
        let textView = buildFooterTextView(withDeepInsets: section.hasBackground)
        textView.delegate = section.footerTextViewDelegate
        return textView
    }

    public func buildFooterTextView(withDeepInsets: Bool) -> UITextView {
        let textView = buildHeaderOrFooterTextView()

        textView.textColor = defaultFooterTextColor
        textView.font = Self.defaultFooterFont
        textView.linkTextAttributes = [
            .foregroundColor: forceDarkMode ? Theme.darkThemePrimaryColor : Theme.primaryTextColor,
        ]
        textView.textContainerInset = footerTextContainerInsets(useDeepInsets: withDeepInsets)

        return textView
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection sectionIndex: Int) -> UIView? {
        guard let section = contents.sections[safe: sectionIndex] else {
            owsFailDebug("Missing section: \(sectionIndex)")
            return nil
        }

        if let customHeaderView = section.customHeaderView {
            return customHeaderView
        } else if
            let headerTitle = section.headerTitle,
            !headerTitle.isEmpty
        {
            let textView = buildHeaderTextView(forSection: section)
            textView.text = headerTitle

            return textView
        } else if
            let headerAttributedTitle = section.headerAttributedTitle,
            !headerAttributedTitle.isEmpty
        {
            let textView = buildHeaderTextView(forSection: section)
            textView.attributedText = headerAttributedTitle

            return textView
        } else if
            let customHeaderHeight = section.customHeaderHeight,
            customHeaderHeight > 0
        {
            return buildDefaultHeaderOrFooter(height: customHeaderHeight)
        } else if
            let defaultSpacingBetweenSections,
            defaultSpacingBetweenSections > 0, !section.items.isEmpty
        {
            return buildDefaultHeaderOrFooter(height: defaultSpacingBetweenSections)
        } else {
            return nil
        }
    }

    public func tableView(_ tableView: UITableView, viewForFooterInSection sectionIndex: Int) -> UIView? {
        guard let section = contents.sections[safe: sectionIndex] else {
            owsFailDebug("Missing section: \(sectionIndex)")
            return nil
        }

        if let customFooterView = section.customFooterView {
            return customFooterView
        } else if
            let footerTitle = section.footerTitle,
            !footerTitle.isEmpty
        {
            let textView = buildFooterTextView(forSection: section)
            textView.text = footerTitle

            return textView
        } else if
            let footerAttributedTitle = section.footerAttributedTitle,
            !footerAttributedTitle.isEmpty
        {
            let textView = buildFooterTextView(forSection: section)
            textView.attributedText = footerAttributedTitle

            return textView
        } else if
            let customFooterHeight = section.customFooterHeight,
            customFooterHeight > 0
        {
            return buildDefaultHeaderOrFooter(height: customFooterHeight)
        } else if
            isLastSection(tableView, sectionIndex: sectionIndex),
            defaultLastSectionFooter > 0
        {
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
            owsAssertDebug(customHeaderHeight > 0 || customHeaderHeight == automaticDimension)
            return customHeaderHeight
        } else if let headerTitle = section.headerTitle, !headerTitle.isEmpty {
            // Get around a bug sizing UITextView in iOS 16 by manually sizing instead
            // of relying on UITableView.automaticDimension
            let insets = headerTextContainerInsets(for: section)
            // Reuse sizing code for CVText even though we aren't using a CVText here.
            let height = CVText.measureLabel(
                config: CVLabelConfig.unstyledText(
                    headerTitle,
                    font: Self.defaultHeaderFont,
                    textColor: .black, // doesn't matter for sizing
                    numberOfLines: 0,
                    lineBreakMode: .byWordWrapping,
                    textAlignment: .natural,
                ),
                maxWidth: tableView.frame.width - tableView.layoutMargins.totalWidth - insets.totalWidth,
            ).height
            return height + insets.totalHeight
        } else if let headerTitle = section.headerAttributedTitle, !headerTitle.isEmpty {
            // Get around a bug sizing UITextView in iOS 16 by manually sizing instead
            // of relying on UITableView.automaticDimension
            let insets = headerTextContainerInsets(for: section)
            // Reuse sizing code for CVText even though we aren't using a CVText here.
            let height = CVText.measureLabel(
                config: CVLabelConfig(
                    text: .attributedText(headerTitle),
                    displayConfig: .forMeasurement(font: Self.defaultHeaderFont),
                    font: Self.defaultHeaderFont,
                    textColor: .black, // doesn't matter for sizing
                    numberOfLines: 0,
                    lineBreakMode: .byWordWrapping,
                    textAlignment: .natural,
                ),
                maxWidth: tableView.frame.width - tableView.layoutMargins.totalWidth - insets.totalWidth,
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
            owsAssertDebug(customFooterHeight > 0 || customFooterHeight == automaticDimension)
            return customFooterHeight
        } else if let footerTitle = section.footerTitle, !footerTitle.isEmpty {
            // Get around a bug sizing UITextView in iOS 16 by manually sizing instead
            // of relying on UITableView.automaticDimension
            let insets = footerTextContainerInsets(for: section)
            // Reuse sizing code for CVText even though we aren't using a CVText here.
            let height = CVText.measureLabel(
                config: CVLabelConfig.unstyledText(
                    footerTitle,
                    font: Self.defaultFooterFont,
                    textColor: .black, // doesn't matter for sizing
                    numberOfLines: 0,
                    lineBreakMode: .byWordWrapping,
                    textAlignment: .natural,
                ),
                maxWidth: tableView.frame.width - tableView.layoutMargins.totalWidth - insets.totalWidth,
            ).height
            return height + insets.totalHeight
        } else if let footerTitle = section.footerAttributedTitle, !footerTitle.isEmpty {
            // Get around a bug sizing UITextView in iOS 16 by manually sizing instead
            // of relying on UITableView.automaticDimension
            let insets = footerTextContainerInsets(for: section)
            // Reuse sizing code for CVText even though we aren't using a CVText here.
            let height = CVText.measureLabel(
                config: CVLabelConfig(
                    text: .attributedText(footerTitle),
                    displayConfig: .forMeasurement(font: Self.defaultFooterFont),
                    font: Self.defaultFooterFont,
                    textColor: .black, // doesn't matter for sizing
                    numberOfLines: 0,
                    lineBreakMode: .byWordWrapping,
                    textAlignment: .natural,
                ),
                maxWidth: tableView.frame.width - tableView.layoutMargins.totalWidth - insets.totalWidth,
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
        navigationItem.rightBarButtonItem = .doneButton(dismissingFrom: self)
        fromViewController.present(navigationController, animated: true, completion: nil)
    }

    // MARK: - UIScrollViewDelegate

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.tableViewWillBeginDragging(tableView)
    }

    // MARK: - Theme

    public static func tableBackgroundColor(
        isUsingPresentedStyle: Bool,
        forceDarkMode: Bool = false,
    ) -> UIColor {
        AssertIsOnMainThread()

        if isUsingPresentedStyle {
            return forceDarkMode
                ? Theme.darkThemeTableView2PresentedBackgroundColor
                : Theme.tableView2PresentedBackgroundColor
        } else {
            return forceDarkMode
                ? Theme.darkThemeTableView2BackgroundColor
                : Theme.tableView2BackgroundColor
        }
    }

    public var cellBackgroundColor: UIColor {
        Self.cellBackgroundColor(
            isUsingPresentedStyle: isUsingPresentedStyle,
            forceDarkMode: forceDarkMode,
        )
    }

    public static func cellBackgroundColor(
        isUsingPresentedStyle: Bool,
        forceDarkMode: Bool = false,
    ) -> UIColor {
        if isUsingPresentedStyle {
            return forceDarkMode
                ? Theme.darkThemeTableCell2PresentedBackgroundColor
                : Theme.tableCell2PresentedBackgroundColor
        } else {
            return forceDarkMode
                ? Theme.darkThemeTableCell2BackgroundColor
                : Theme.tableCell2BackgroundColor
        }
    }

    public var cellSelectedBackgroundColor: UIColor {
        Self.cellSelectedBackgroundColor(forceDarkMode: forceDarkMode)
    }

    public static func cellSelectedBackgroundColor(forceDarkMode: Bool = false) -> UIColor {
        if forceDarkMode {
            return Theme.tableCell2SelectedBackgroundColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        }
        return Theme.tableCell2SelectedBackgroundColor
    }

    public var separatorColor: UIColor {
        if isUsingPresentedStyle {
            return forceDarkMode
                ? Theme.darkThemeTableView2PresentedSeparatorColor
                : Theme.tableView2PresentedSeparatorColor
        } else {
            return forceDarkMode
                ? Theme.darkThemeTableView2SeparatorColor
                : Theme.tableView2SeparatorColor
        }
    }

    public static func removeBackButtonText(viewController: UIViewController) {
        if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable { return }
        // We never want to show titles on back buttons, so we replace it with
        // blank spaces. We pad it out slightly so that it's more tappable.
        viewController.navigationItem.backBarButtonItem = .init(title: "   ", style: .plain, target: nil, action: nil)
    }

    private func updateNavbarStyling() {
        if lifecycle == .appeared {
            owsNavigationController?.updateNavbarAppearance(animated: true)
        }
    }

    open func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateNavbarStyling()
    }

    override open var isEditing: Bool {
        get { tableView.isEditing }
        set { tableView.isEditing = newValue }
    }

    override public func setEditing(_ editing: Bool, animated: Bool) {
        tableView.setEditing(editing, animated: animated)
    }

    public func setEditing(_ editing: Bool) {
        tableView.setEditing(editing, animated: false)
    }

    // MARK: -

    override open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
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

    override open func viewSafeAreaInsetsDidChange() {
        applyContents()
    }

    public func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        if
            let item = self.item(for: indexPath),
            let contextMenuActionProvider = item.contextMenuActionProvider
        {
            return UIContextMenuConfiguration(actionProvider: contextMenuActionProvider)
        }
        return nil
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

public class OWSTableView: UITableView {
    fileprivate weak var tableViewDelegate: OWSTableViewDelegate?

    override public var frame: CGRect {
        didSet {
            let didChangeWidth = frame.width != oldValue.width
            if didChangeWidth {
                tableViewDelegate?.tableViewDidChangeWidth()
            }
        }
    }

    override public var bounds: CGRect {
        didSet {
            let didChangeWidth = bounds.width != oldValue.width
            if didChangeWidth {
                tableViewDelegate?.tableViewDidChangeWidth()
            }
        }
    }
}

// MARK: - TextViewWithPlaceholderDelegate

extension TextViewWithPlaceholderDelegate where Self: OWSTableViewController2 {
    /// Creates an ``OWSTableItem`` with the text view.
    /// - Parameters:
    ///   - textView: The ``TextViewWithPlaceholder`` to use in the cell.
    ///   - minimumHeight: An optional minimum height to constrain the text view to.
    ///   - dataDetectorTypes: The types of data that convert to tappable URLs in the text view.
    /// - Returns: An ``OWSTableItem`` with the `textView` embedded.
    public func textViewItem(
        _ textView: TextViewWithPlaceholder,
        minimumHeight: CGFloat? = nil,
        dataDetectorTypes: UIDataDetectorTypes? = nil,
    ) -> OWSTableItem {
        .init(customCellBlock: { [weak self] in
            guard let self else { return OWSTableItem.newCell() }

            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            cell.contentView.addSubview(textView)

            /// `UITextView` has default top and bottom insets of 8 which we
            /// need to subtract off. See ``TextViewWithPlaceholder``'s
            /// `buildTextView()`  for why they can't just be set to 0.
            textView.autoPinEdgesToSuperviewMargins(with: .init(hMargin: 0, vMargin: -8))

            if let minimumHeight {
                textView.autoSetDimension(
                    .height,
                    toSize: minimumHeight,
                    relation: .greaterThanOrEqual,
                )
            }

            if let dataDetectorTypes {
                textView.dataDetectorTypes = dataDetectorTypes
            }

            if textView.delegate == nil {
                textView.delegate = self
            }

            return cell
        }, actionBlock: {
            textView.becomeFirstResponder()
        })
    }

    /// A default handler for
    /// `TextViewWithPlaceholderDelegate.textViewDidUpdateSelection(_:)`
    /// when used within an ``OWSTableViewController2``.
    public func _textViewDidUpdateSelection(_ textView: TextViewWithPlaceholder) {
        textView.scrollToFocus(in: tableView, animated: true)
    }

    /// A default handler for
    /// `TextViewWithPlaceholderDelegate.textViewDidUpdateText(_:)`
    /// when used with an ``OWSTableViewController2``.
    public func _textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
        // Kick the tableview so it recalculates sizes
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates(nil) { _ in
                // And when the size changes have finished, make sure we're
                // scrolled to the focused line.
                textView.scrollToFocus(in: self.tableView, animated: false)
            }
        }
    }

    // MARK: Default implementation

    public func textViewDidUpdateSelection(_ textView: TextViewWithPlaceholder) {
        _textViewDidUpdateSelection(textView)
    }

    public func textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
        _textViewDidUpdateText(textView)
    }
}
