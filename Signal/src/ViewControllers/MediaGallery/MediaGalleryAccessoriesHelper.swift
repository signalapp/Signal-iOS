//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol MediaGalleryPrimaryViewController: UIViewController {
    var scrollView: UIScrollView { get }
    var mediaGalleryFilterMenuItems: [MediaGalleryAccessoriesHelper.MenuItem] { get }
    var isEmpty: Bool { get }
    var hasSelection: Bool { get }
    func selectionInfo() -> (count: Int, totalSize: Int64)?
    func disableFiltering()
    func batchSelectionModeDidChange(isInBatchSelectMode: Bool)
    func selectAll()
    func didEndSelectMode()
    func deleteSelectedItems()
    func shareSelectedItems(_ sender: Any)
    var mediaCategory: AllMediaCategory { get }
    func set(mediaCategory: AllMediaCategory, isGridLayout: Bool)
}

public class MediaGalleryAccessoriesHelper {
    private var footerBarBottomConstraint: NSLayoutConstraint?
    weak var viewController: MediaGalleryPrimaryViewController?

    private enum Layout {
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

    private var lastUsedLayoutMap = [AllMediaCategory: Layout]()
    private var _layout = Layout.grid
    private var layout: Layout {
        get {
            _layout
        }
        set {
            guard newValue != _layout else { return }
            _layout = newValue
            updateBottomToolbarControls()
            guard let viewController else { return }

            switch layout {
            case .list:
                viewController.set(mediaCategory: viewController.mediaCategory, isGridLayout: false)
            case .grid:
                viewController.set(mediaCategory: viewController.mediaCategory, isGridLayout: true)
            }
        }
    }

    private lazy var headerView: UISegmentedControl = {
        let items = [
            AllMediaCategory.photoVideo,
            AllMediaCategory.audio,
            AllMediaCategory.otherFiles,
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
        frame.size.width += CGFloat(AllMediaCategory.allCases.count) * 20.0
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
        updateFilterButton()
    }

    // MARK: - Menu

    struct MenuItem {
        var title: String
        var icon: UIImage?
        var isChecked = false
        var handler: () -> Void

        private var state: UIMenuElement.State {
            return isChecked ? .on : .off
        }

        var uiAction: UIAction {
            return UIAction(title: title, image: icon, state: state) { _ in handler() }
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

    private var previousLeftBarButtonItem: UIBarButtonItem?

    private func updateSelectionModeControls() {
        guard let viewController else {
            return
        }
        if isInBatchSelectMode {
            viewController.navigationItem.rightBarButtonItem = .cancelButton { [weak self] in
                self?.didCancelSelect()
            }
            previousLeftBarButtonItem = viewController.navigationItem.leftBarButtonItem
            viewController.navigationItem.leftBarButtonItem = .button(
                title: OWSLocalizedString(
                    "SELECT_ALL",
                    comment: "Button text to select all in any list selection mode"
                ),
                style: .plain,
                action: { [weak self] in
                    self?.didSelectAll()
                })
        } else {
            viewController.navigationItem.rightBarButtonItem = nil // TODO: Search
            viewController.navigationItem.leftBarButtonItem = previousLeftBarButtonItem
            previousLeftBarButtonItem = nil
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

    private func didCancelSelect() {
        endSelectMode()
    }

    private func didSelectAll() {
        self.viewController?.selectAll()
        self.didModifySelection()
    }

    // Call this to exit select mode, for example after completing a deletion.
    func endSelectMode() {
        isInBatchSelectMode = false
        viewController?.didEndSelectMode()
    }

    // MARK: - Filter

    private func filterMenuItemsAndCurrentValue() -> (title: NSAttributedString, items: [MenuItem]) {
        guard let items = viewController?.mediaGalleryFilterMenuItems, !items.isEmpty else {
            return ( NSAttributedString(string: ""), [] )
        }
        let currentTitle = items.first(where: { $0.isChecked })?.title ?? ""
        return (
            NSAttributedString(string: currentTitle, attributes: [ .font: UIFont.dynamicTypeHeadlineClamped ] ),
            items
        )
    }

    private lazy var filterButton: UIBarButtonItem = {
        var configuration = UIButton.Configuration.plain()
        configuration.imagePlacement = .trailing
        configuration.image = UIImage(imageLiteralResourceName: "chevron-down-compact-bold")
        configuration.imagePadding = 4

        let button = UIButton(configuration: configuration, primaryAction: nil)
        button.showsMenuAsPrimaryAction = true
        return UIBarButtonItem(customView: button)
    }()

    func updateFilterButton() {
        if let button = filterButton.customView as? UIButton {
            let (buttonTitle, menuItems) = filterMenuItemsAndCurrentValue()
            button.setAttributedTitle(buttonTitle, for: .normal)
            button.menu = menuItems.menu()
            button.sizeToFit()
            button.isHidden = menuItems.isEmpty
        }
    }

    // MARK: - List/Grid

    private func listMenuItem(isChecked: Bool) -> MenuItem {
        return MenuItem(
            title: Layout.list.titleString,
            icon: UIImage(named: "list-bullet-light"),
            isChecked: isChecked,
            handler: { [weak self] in
                self?.layout = .list
            }
        )
    }

    private func gridMenuItem(isChecked: Bool) -> MenuItem {
        return MenuItem(
            title: Layout.grid.titleString,
            icon: UIImage(named: "grid-square-light"),
            isChecked: isChecked,
            handler: { [weak self] in
                self?.layout = .grid
            }
        )
    }

    private func createLayoutPickerMenu(checkedLayout: Layout) -> UIMenu {
        let menuItems = [
            gridMenuItem(isChecked: checkedLayout == .grid),
            listMenuItem(isChecked: checkedLayout == .list)
        ]
        return menuItems.menu(with: .singleSelection)
    }

    private lazy var listViewButton: UIBarButtonItem = UIBarButtonItem(
        title: nil,
        image: UIImage(imageLiteralResourceName: "list-bullet"),
        primaryAction: nil,
        menu: createLayoutPickerMenu(checkedLayout: .list)
    )

    private lazy var gridViewButton: UIBarButtonItem = UIBarButtonItem(
        title: nil,
        image: UIImage(imageLiteralResourceName: "grid-square"),
        primaryAction: nil,
        menu: createLayoutPickerMenu(checkedLayout: .grid)
    )

    // MARK: - Footer

    private lazy var footerBar = UIToolbar()

    enum FooterBarState {
        // No footer bar.
        case hidden

        // Regular mode, no multi-selection possible.
        case regular

        // User can select one or more items.
        case selection
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

    private func updateBottomToolbarControls() {
        guard footerBarState != .hidden else { return }

        let fixedSpace = { return UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil) }
        let footerBarItems: [UIBarButtonItem]? = {
            switch footerBarState {
            case .hidden:
                return nil
            case .selection:
                return [ shareButton, .flexibleSpace(), selectionInfoButton, .flexibleSpace(), deleteButton ]
            case .regular:
                let firstItem: UIBarButtonItem
                if mediaCategory.supportsGridView {
                    firstItem = layout == .list ? listViewButton : gridViewButton
                } else {
                    firstItem = fixedSpace()
                }

                updateFilterButton()

                return [
                    firstItem,
                    .flexibleSpace(),
                    filterButton,
                    .flexibleSpace(),
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
                return .selection
            }
            if viewController.isEmpty {
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

    private lazy var deleteButton = UIBarButtonItem.button(
        icon: .buttonDelete,
        style: .plain,
        action: { [weak self] in
            self?.didPressDelete()
        }
    )

    private func updateDeleteButton() {
        guard let viewController else { return }
        deleteButton.isEnabled = viewController.hasSelection
    }

    private func didPressDelete() {
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

    private var mediaCategory: AllMediaCategory {
        return AllMediaCategory(rawValue: headerView.selectedSegmentIndex) ?? .defaultValue
    }

    @objc
    private func segmentedControlValueChanged(_ sender: UISegmentedControl) {
        if let mediaCategory = AllMediaCategory(rawValue: sender.selectedSegmentIndex) {
            if let previousMediaCategory = viewController?.mediaCategory {
                lastUsedLayoutMap[previousMediaCategory] = layout
            }
            if mediaCategory.supportsGridView {
                // Return to the previous mode
                _layout = lastUsedLayoutMap[mediaCategory, default: .grid]
            } else if layout == .grid {
                // This file type requires a switch to list mode
                _layout = .list
            }
            updateBottomToolbarControls()
            viewController?.set(mediaCategory: mediaCategory, isGridLayout: layout == .grid)
        }
    }
}

extension AllMediaCategory {
    static var defaultValue = AllMediaCategory.photoVideo

    var supportsGridView: Bool {
        switch self {
        case .photoVideo:
            return true
        case .audio:
            return false
        case .otherFiles:
            return false
        }
    }

    var titleString: String {
        switch self {
        case .photoVideo:
            return OWSLocalizedString("ALL_MEDIA_FILE_TYPE_MEDIA",
                                      comment: "Media (i.e., graphical) file type in All Meda file type picker.")
        case .audio:
            return OWSLocalizedString("ALL_MEDIA_FILE_TYPE_AUDIO",
                                      comment: "Audio file type in All Meda file type picker.")
        case .otherFiles:
            return OWSLocalizedString(
                "ALL_MEDIA_FILE_TYPE_FILES",
                comment: "Generic All Media file type for non-audiovisual files used in file type picker"
            )
        }
    }
}

private extension Array where Element == MediaGalleryAccessoriesHelper.MenuItem {
    func menu(with options: UIMenu.Options = []) -> UIMenu {
        return UIMenu(title: "", options: options, children: reversed().map({ $0.uiAction }))
    }
}
