//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI

fileprivate extension AllMediaFileType {
    var titleString: String {
        switch self {
        case .photoVideo:
            return OWSLocalizedString("ALL_MEDIA_FILE_TYPE_MEDIA",
                                      comment: "Media (i.e., graphical) file type in All Meda file type picker.")
        case .audio:
            return OWSLocalizedString("ALL_MEDIA_FILE_TYPE_AUDIO",
                                      comment: "Audio file type in All Meda file type picker.")
        }
    }
}

protocol MediaGalleryPrimaryViewController: UIViewController {
    var scrollView: UIScrollView { get }
    var mediaGalleryFilterMenuActions: [MediaGalleryAccessoriesHelper.MenuAction] { get }
    var isFiltering: Bool { get }
    var isEmpty: Bool { get }
    var hasSelection: Bool { get }
    func selectionInfo() -> (count: Int, totalSize: Int64)?
    func disableFiltering()
    func batchSelectionModeDidChange(isInBatchSelectMode: Bool)
    func didEndSelectMode()
    func deleteSelectedItems()
    func shareSelectedItems(_ sender: Any)
    var fileType: AllMediaFileType { get }
    func set(fileType: AllMediaFileType, isGridLayout: Bool)
}

public class MediaGalleryAccessoriesHelper {
    private var footerBarBottomConstraint: NSLayoutConstraint?
    weak var viewController: MediaGalleryPrimaryViewController?

    private enum Mode {
        case list
        case grid

        var titleString: String {
            switch self {
            case .list:
                return OWSLocalizedString(
                    "ALL_MEDIA_LIST_MODE",
                    comment: "Menu option to show All Media items in a single-column list")

            case .grid:
                return OWSLocalizedString(
                    "ALL_MEDIA_GRID_MODE",
                    comment: "Menu option to show All Media items in a grid of square thumbnails")

            }
        }
    }

    private var savedModes = [AllMediaFileType: Mode]()
    private var _mode = Mode.grid
    private var mode: Mode {
        get {
            _mode
        }
        set {
            guard newValue != _mode else { return }
            _mode = newValue
            updateModeButton()
            guard let viewController else { return }

            switch mode {
            case .list:
                viewController.set(fileType: viewController.fileType, isGridLayout: false)
            case .grid:
                viewController.set(fileType: viewController.fileType, isGridLayout: true)
            }
        }
    }

    private lazy var headerView: UISegmentedControl = {
        let items = [
            AllMediaFileType.photoVideo,
            AllMediaFileType.audio
        ].map { $0.titleString }
        let segmentedControl = UISegmentedControl(items: items)
        segmentedControl.selectedSegmentTintColor = .init(dynamicProvider: { _ in
            Theme.isDarkThemeEnabled ? UIColor.init(rgbHex: 0x636366) : .white
        })
        segmentedControl.backgroundColor = .clear
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(segmentedControlValueChanged), for: .valueChanged)
        return segmentedControl
    }()

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentSizeCategoryDidChange),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil
        )
    }

    func installViews() {
        guard let viewController else { return }

        headerView.sizeToFit()
        var frame = headerView.frame
        frame.size.width += CGFloat(AllMediaFileType.allCases.count) * 20.0
        headerView.frame = frame
        viewController.navigationItem.titleView = headerView

        viewController.view.addSubview(footerBar)
        footerBar.autoPinWidthToSuperview()

        updateDeleteButton()
        updateSelectionModeControls()
    }

    func applyTheme() {
        footerBar.barTintColor = Theme.navbarBackgroundColor
        footerBar.tintColor = Theme.primaryIconColor
        deleteButton.tintColor = Theme.primaryIconColor
        shareButton.tintColor = Theme.primaryIconColor
    }

    @objc
    private func contentSizeCategoryDidChange(_ notification: Notification) {
        updateModeButton()
    }

    // MARK: - Menu Actions

    struct MenuAction {
        var title: String
        var icon: UIImage?
        var handler: () -> Void
        var checked = false

        private var state: UIMenuElement.State {
            return checked ? .on : .off
        }

        var uiAction: UIAction {
            return UIAction(title: title, image: icon, state: state) { _ in handler() }
        }

        @available(iOS, deprecated: 14.0)
        var uiAlertAction: UIAlertAction {
            return UIAlertAction(title: title, style: .default) { _ in handler() }
        }
    }

    // MARK: - Batch Selection

    private lazy var selectButton = UIBarButtonItem(
        title: CommonStrings.selectButton,
        style: .plain,
        target: self,
        action: #selector(didTapSelect)
    )

    var isInBatchSelectMode = false {
        didSet {
            guard isInBatchSelectMode != oldValue else { return }

            viewController?.batchSelectionModeDidChange(isInBatchSelectMode: isInBatchSelectMode)
            updateFooterBarState()
            updateSelectionInfoLabel()
            updateSelectionModeControls()
            updateDeleteButton()
            updateShareButton()
        }
    }

    // Call this when an item is selected or deselected.
    func didModifySelection() {
        guard isInBatchSelectMode else {
            return
        }
        updateSelectionInfoLabel()
        updateDeleteButton()
        updateShareButton()
    }

    private func updateSelectionModeControls() {
        guard let viewController else {
            return
        }
        if isInBatchSelectMode {
            viewController.navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(didCancelSelect)
            )
        } else {
            viewController.navigationItem.rightBarButtonItem = nil // TODO: Search
        }

        headerView.isHidden = isInBatchSelectMode

        // Don't allow the user to leave mid-selection, so they realized they have
        // to cancel (lose) their selection if they leave.
        viewController.navigationItem.hidesBackButton = isInBatchSelectMode
    }

    @objc
    private func didTapSelect(_ sender: Any) {
        isInBatchSelectMode = true
    }

    @objc
    private func didCancelSelect(_ sender: Any) {
        endSelectMode()
    }

    // Call this to exit select mode, for example after completing a deletion.
    func endSelectMode() {
        isInBatchSelectMode = false
        viewController?.didEndSelectMode()
    }

    // MARK: - Filter

    private lazy var filterMenuActions: [MenuAction] = {
        viewController?.mediaGalleryFilterMenuActions ?? []
    }()

    private lazy var filterButton: UIBarButtonItem = {
        if #available(iOS 14, *) {
            return modernFilterButton()
        }
        return legacyFilterButton()
    }()

    private lazy var selectedFilterButton: UIBarButtonItem = {
        return UIBarButtonItem(image: selectedAllMediaFilterIcon,
                               style: .plain,
                               target: self,
                               action: #selector(disableFiltering))
    }()

    private lazy var allMediaFilterIcon = UIImage(imageLiteralResourceName: "filter-circle")
    private lazy var selectedAllMediaFilterIcon = UIImage(imageLiteralResourceName: "filter-circle-fill")

    private func legacyFilterButton() -> UIBarButtonItem {
        return UIBarButtonItem(image: allMediaFilterIcon,
                               style: .plain,
                               target: self,
                               action: #selector(showFilterMenu))
    }

    @available(iOS, deprecated: 14.0)
    @objc
    private func showFilterMenu(_ sender: Any) {
        let menu = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for action in filterMenuActions.map({ $0.uiAlertAction}) {
            menu.addAction(action)
        }
        viewController?.present(menu, animated: true, completion: nil)
    }

    @objc
    private func disableFiltering(_ sender: Any) {
        viewController?.disableFiltering()
        updateFooterBarState()
    }

    @available(iOS 14, *)
    private func modernFilterButton() -> UIBarButtonItem {
        let menu = UIMenu(title: "", children: filterMenuActions.map { $0.uiAction })
        return UIBarButtonItem(image: allMediaFilterIcon, menu: menu)
    }

    // MARK: - List/Grid

    private lazy var listMenuAction = MenuAction(
        title: Mode.list.titleString,
        icon: UIImage(named: "list-bullet-light"),
        handler: { [weak self] in
            self?.mode = .list
        }
    )

    private lazy var gridMenuAction = MenuAction(
        title: Mode.grid.titleString,
        icon: UIImage(named: "grid-square-light"),
        handler: { [weak self] in
            self?.mode = .grid
        }
    )

    private var modeMenuActions: [MenuAction] {
        return [
            listMenuAction,
            gridMenuAction
        ]
    }

    private var currentModeButtonTitle: NSAttributedString {
        return NSAttributedString(string: mode.titleString, attributes: [ .font: UIFont.dynamicTypeHeadlineClamped ])
    }

    private func createModeMenu() -> UIMenu {
        var options = UIMenu.Options()
        if #available(iOS 15, *) {
            options = .singleSelection
        }
        listMenuAction.checked = mode == .list
        gridMenuAction.checked = mode == .grid
        return UIMenu(title: "",
                      options: options,
                      children: modeMenuActions.map { $0.uiAction })
    }

    private lazy var modeButton: UIBarButtonItem = {
        let chevronImage = UIImage(imageLiteralResourceName: "chevron-down-compact-bold")
        let button: UIButton

        if #available(iOS 15, *) {
            var configuration = UIButton.Configuration.plain()
            configuration.imagePlacement = .trailing
            configuration.image = chevronImage
            configuration.imagePadding = 4
            configuration.attributedTitle = AttributedString(currentModeButtonTitle)

            button = UIButton(configuration: configuration, primaryAction: nil)
            button.menu = createModeMenu()
            button.showsMenuAsPrimaryAction = true
        } else {
            button = UIButton(type: .system)
            button.setAttributedTitle(currentModeButtonTitle, for: .normal)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.setImage(chevronImage, for: .normal)
            button.setPaddingBetweenImageAndText(to: 4, isRightToLeft: !CurrentAppContext().isRTL)
            button.semanticContentAttribute = CurrentAppContext().isRTL ? .forceLeftToRight : .forceRightToLeft
            if #available(iOS 14, *) {
                button.menu = createModeMenu()
                button.showsMenuAsPrimaryAction = true
            } else {
                button.addTarget(self, action: #selector(showModeMenu(_:)), for: .touchUpInside)
            }
        }
        return UIBarButtonItem(customView: button)
    }()

    private func updateModeButton() {
        if let button = modeButton.customView as? UIButton {
            button.setAttributedTitle(currentModeButtonTitle, for: .normal)
            button.sizeToFit()
        }
    }

    @objc
    private func showModeMenu(_ sender: Any) {
        let menu = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for action in modeMenuActions.map({ $0.uiAlertAction}) {
            menu.addAction(action)
        }
        viewController?.present(menu, animated: true, completion: nil)
    }

    // MARK: - Footer

    private lazy var footerBar = UIToolbar()

    enum FooterBarState {
        // No footer bar.
        case hidden

        // Filter and other features when not in selection mode.
        case regular

        // Highlighted filter button shown, indicating highlighting is active.
        case filtering

        // In selection mode but not filtering.
        case selection

        // In selection mode and filtering.
        case selectionFiltering
    }

    // You should assign to this when you begin filtering.
    var footerBarState = FooterBarState.hidden {
        willSet {
            let wasHidden = footerBarState == .hidden
            let willBeHidden = newValue == .hidden
            if wasHidden && !willBeHidden {
                showToolbar(animated: footerBar.window != nil)
            } else if !wasHidden && willBeHidden {
                hideToolbar(animated: footerBar.window != nil)
            }
        }
        didSet {
            updateBottomToolbarControls()
        }
    }

    private var isGridViewAllowed: Bool {
        return fileType.supportsGridView
    }

    private var currentFileTypeSupportsFiltering: Bool {
        switch AllMediaFileType(rawValue: headerView.selectedSegmentIndex) {
        case .audio:
            return false
        case .photoVideo:
            return true
        case .none:
            return false
        }
    }

    private func updateBottomToolbarControls() {
        guard footerBarState != .hidden else { return }

        let fixedSpace = { return UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil) }
        let flexibleSpace = { return UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil) }
        let footerBarItems: [UIBarButtonItem]? = {
            switch footerBarState {
            case .hidden:
                return nil
            case .selection, .selectionFiltering:
                return [ shareButton, flexibleSpace(), selectionInfoButton, flexibleSpace(), deleteButton ]
            case .regular:
                return [
                    currentFileTypeSupportsFiltering ? filterButton : fixedSpace(),
                    flexibleSpace(),
                    isGridViewAllowed ? modeButton : fixedSpace(),
                    flexibleSpace(),
                    selectButton
                ]
            case .filtering:
                return [
                    currentFileTypeSupportsFiltering ? selectedFilterButton : fixedSpace(),
                    flexibleSpace(),
                    selectButton
                ]
            }
        }()
        footerBar.setItems(footerBarItems, animated: false)
    }

    // You must call this if you transition between having and not having items.
    func updateFooterBarState() {
        guard let viewController else { return }

        footerBarState = {
            if isInBatchSelectMode {
                if viewController.isFiltering {
                    return .selectionFiltering
                }
                return .selection
            }
            if viewController.isFiltering {
                return .filtering
            }
            if viewController.isEmpty {
                return .hidden
            }
            let allowed = FeatureFlags.isPrerelease
            guard allowed else {
                return .hidden
            }
            return .regular
        }()
    }

    // MARK: - Toolbar

    private func showToolbar(animated: Bool) {
        guard animated else {
            showToolbar()
            return
        }
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
            self.showToolbar()
        }
    }

    private func showToolbar() {
        guard let viewController else { return }

        if let footerBarBottomConstraint {
            NSLayoutConstraint.deactivate([footerBarBottomConstraint])
        }

        footerBarBottomConstraint = footerBar.autoPin(toBottomLayoutGuideOf: viewController, withInset: 0)

        viewController.view.layoutIfNeeded()

        let bottomInset = viewController.view.bounds.maxY - footerBar.frame.minY
        viewController.scrollView.contentInset.bottom = bottomInset
        viewController.scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
    }

    private func hideToolbar(animated: Bool) {
        guard animated else {
            hideToolbar()
            return
        }
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
            self.hideToolbar()
        }
    }

    private func hideToolbar() {
        guard let viewController else { return }

        if let footerBarBottomConstraint {
            NSLayoutConstraint.deactivate([footerBarBottomConstraint])
        }

        footerBarBottomConstraint = footerBar.autoPinEdge(.top, to: .bottom, of: viewController.view)

        viewController.view.layoutIfNeeded()

        viewController.scrollView.contentInset.bottom = 0
        viewController.scrollView.verticalScrollIndicatorInsets.bottom = 0
    }

    // MARK: - Delete

    private lazy var deleteButton = UIBarButtonItem(
        image: Theme.iconImage(.buttonDelete),
        style: .plain,
        target: self,
        action: #selector(didPressDelete)
    )

    private func updateDeleteButton() {
        guard let viewController else { return }
        deleteButton.isEnabled = viewController.hasSelection
    }

    @objc
    private func didPressDelete(_ sender: Any) {
        Logger.debug("")
        viewController?.deleteSelectedItems()
    }

    // MARK: - Share

    private lazy var shareButton = UIBarButtonItem(
        image: Theme.iconImage(.buttonShare),
        style: .plain,
        target: self,
        action: #selector(didPressShare)
    )

    private func updateShareButton() {
        guard let viewController else { return }

        shareButton.isEnabled = viewController.hasSelection
    }

    @objc
    private func didPressShare(_ sender: Any) {
        Logger.debug("")
        viewController?.shareSelectedItems(sender)
    }

    // MARK: - Selection Info

    private lazy var selectionCountLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = UIColor(dynamicProvider: { _ in Theme.primaryTextColor })
        label.font = .dynamicTypeSubheadlineClamped.semibold()
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private lazy var selectionSizeLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = UIColor(dynamicProvider: { _ in Theme.primaryTextColor })
        label.font = .dynamicTypeSubheadlineClamped
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private lazy var selectionInfoButton = UIBarButtonItem(customView: {
        let stackView = UIStackView(arrangedSubviews: [ selectionCountLabel, selectionSizeLabel ])
        stackView.axis = .vertical
        stackView.spacing = 0
        return stackView
    }())

    private func updateSelectionInfoLabel() {
        guard isInBatchSelectMode, let (selectionCount, totalSize) = viewController?.selectionInfo() else {
            selectionCountLabel.text = ""
            selectionSizeLabel.text = ""
            selectionInfoButton.customView?.sizeToFit()
            return
        }
        selectionCountLabel.text = String.localizedStringWithFormat(
            OWSLocalizedString("MESSAGE_ACTIONS_TOOLBAR_CAPTION_%d", tableName: "PluralAware", comment: ""),
            selectionCount
        )
        selectionSizeLabel.text = OWSFormat.localizedFileSizeString(from: totalSize)

        selectionInfoButton.customView?.sizeToFit()
    }

    private var fileType: AllMediaFileType {
        return AllMediaFileType(rawValue: headerView.selectedSegmentIndex) ?? .photoVideo
    }

    @objc
    private func segmentedControlValueChanged(_ sender: UISegmentedControl) {
        if let fileType = AllMediaFileType(rawValue: sender.selectedSegmentIndex) {
            if let previousFileType = viewController?.fileType {
                savedModes[previousFileType] = mode
            }
            if fileType.supportsGridView {
                // Return to the previous mode
                _mode = savedModes[fileType, default: .grid]
            } else if mode == .grid {
                // This file type requires a switch to list mode
                _mode = .list
            }
            updateModeButton()
            viewController?.set(fileType: fileType, isGridLayout: mode == .grid)
        }
    }
}

extension AllMediaFileType {
    static var defaultValue = AllMediaFileType.photoVideo

    var supportsGridView: Bool {
        switch self {
        case .photoVideo:
            return true
        case .audio:
            return false
        }
    }
}
