//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI

protocol MediaGalleryPrimaryViewController: UIViewController {
    var mediaGalleryFilterMenuActions: [MediaGalleryAccessoriesHelper.MenuAction] { get }
    var isFiltering: Bool { get }
    var isEmpty: Bool { get }
    var hasSelection: Bool { get }
    func disableFiltering()
    func batchSelectionModeDidChange(isInBatchSelectMode: Bool)
    func didEndSelectMode()
    func deleteSelectedItems()
    func shareSelectedItems(_ sender: Any)
}

public class MediaGalleryAccessoriesHelper: NSObject {
    private var footerBarBottomConstraint: NSLayoutConstraint!
    let kFooterBarHeight: CGFloat = 40
    weak var viewController: MediaGalleryPrimaryViewController?

    func add(toView view: UIView) {
        view.addSubview(footerBar)
        footerBar.autoPinWidthToSuperview()
        footerBar.autoSetDimension(.height, toSize: kFooterBarHeight)
        footerBarBottomConstraint = footerBar.autoPinEdge(toSuperviewEdge: .bottom, withInset: -kFooterBarHeight)
        updateDeleteButton()
        updateSelectButton()
    }

    func applyTheme() {
        footerBar.barTintColor = Theme.navbarBackgroundColor
        footerBar.tintColor = Theme.primaryIconColor
        deleteButton.tintColor = Theme.primaryIconColor
        shareButton.tintColor = Theme.primaryIconColor
    }

    // MARK: - Menu Actions

    struct MenuAction {
        var title: String
        var icon: UIImage?
        var handler: () -> Void

        @available(iOS 13, *)
        var uiAction: UIAction {
            return UIAction(title: title, image: icon) { _ in handler() }
        }

        @available(iOS, deprecated: 14.0)
        var uiAlertAction: UIAlertAction {
            return UIAlertAction(title: title, style: .default) { _ in handler() }
        }
    }

    // MARK: - Batch Selection

    var isInBatchSelectMode = false {
        didSet {
            let didChange = isInBatchSelectMode != oldValue
            if didChange {
                viewController?.batchSelectionModeDidChange(isInBatchSelectMode: isInBatchSelectMode)
                updateSelectButton()
                updateDeleteButton()
                updateShareButton()
            }
        }
    }

    // Call this when an item is selected or deselected.
    func didModifySelection() {
        guard isInBatchSelectMode else {
            return
        }
        updateDeleteButton()
        updateShareButton()
    }

    private func updateSelectButton() {
        guard let viewController else {
            return
        }
        if isInBatchSelectMode {
            viewController.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(didCancelSelect),
                                                                     accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "cancel_select_button"))
        } else {
            viewController.navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("BUTTON_SELECT", comment: "Button text to enable batch selection mode"),
                                                                     style: .plain,
                                                                     target: self,
                                                                     action: #selector(didTapSelect),
                                                                     accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "select_button"))
        }
    }

    @objc
    private func didTapSelect(_ sender: Any) {
        guard let viewController else {
            return
        }
        isInBatchSelectMode = true

        footerBarState = viewController.isFiltering ? .selectionFiltering : .selection

        // Disabled until at least one item is selected.
        self.deleteButton.isEnabled = false
        self.shareButton.isEnabled = false

        // Don't allow the user to leave mid-selection, so they realized they have
        // to cancel (lose) their selection if they leave.
        viewController.navigationItem.hidesBackButton = true
    }

    @objc
    private func didCancelSelect(_ sender: Any) {
        endSelectMode()
    }

    // Call this to exit select mode, for example after completing a deletion.
    func endSelectMode() {
        isInBatchSelectMode = false

        guard let viewController else {
            return
        }

        // hide toolbar
        updateFooterBarState()

        viewController.navigationItem.hidesBackButton = false
        viewController.didEndSelectMode()
        updateDeleteButton()
    }

    // MARK: - Filter

    private lazy var filterMenuActions: [MenuAction] = {
        viewController?.mediaGalleryFilterMenuActions ?? []
    }()

    private lazy var filterButton: UIBarButtonItem? = {
        if #available(iOS 14, *) {
            return modernFilterButton()
        }
        return legacyFilterButton()
    }()

    private lazy var selectedFilterButton: UIBarButtonItem? = {
        return UIBarButtonItem(image: selectedAllMediaFilterIcon,
                               style: .plain,
                               target: self,
                               action: #selector(disableFiltering))
    }()

    private lazy var allMediaFilterIcon: UIImage = {
        UIImage(named: "all-media-filter")!
    }()

    private lazy var selectedAllMediaFilterIcon: UIImage = {
        UIImage(named: "all-media-filter-selected")!
    }()

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

    // MARK: - Footer

    private lazy var footerBar: UIToolbar = {
        let footerBar = UIToolbar()
        return footerBar
    }()

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
                showToolbar()
            } else if !wasHidden && willBeHidden {
                hideToolbar()
            }
            switch newValue {
            case .hidden:
                break
            case .selection, .selectionFiltering:
                let footerItems = [
                    shareButton,
                    UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                    deleteButton
                ]
                footerBar.setItems(footerItems, animated: false)
            case .regular:
                let footerItems = [
                    filterButton!,
                    UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                    deleteButton
                ]
                footerBar.setItems(footerItems, animated: false)
            case .filtering:
                let footerItems = [
                    selectedFilterButton!,
                    UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                    deleteButton
                ]
                footerBar.setItems(footerItems, animated: false)
            }
        }
    }

    // You must call this if you transition between having and not having items.
    func updateFooterBarState() {
        guard let viewController else {
            return
        }
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
            if #unavailable(iOS 13) {
                return .hidden
            }
            return .regular
        }()
    }

    // MARK: - Toolbar

    private func showToolbar() {
        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut, animations: {
            self._showToolbar()
        }, completion: nil)
    }

    private func _showToolbar() {
        guard let viewController else {
            return
        }
        NSLayoutConstraint.deactivate([self.footerBarBottomConstraint])

        self.footerBarBottomConstraint =  self.footerBar.autoPin(toBottomLayoutGuideOf: viewController, withInset: 0)

        self.footerBar.superview?.layoutIfNeeded()
        // ensure toolbar doesn't cover bottom row.
        if let scrollView = viewController.view as? UIScrollView {
            scrollView.contentInset.bottom += self.kFooterBarHeight
            scrollView.scrollIndicatorInsets.bottom += self.kFooterBarHeight
        }
    }

    private func hideToolbar() {
        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut, animations: {
            self._hideToolbar()
        }, completion: nil)
    }

    private func _hideToolbar() {
        guard let viewController else {
            return
        }
        NSLayoutConstraint.deactivate([self.footerBarBottomConstraint])
        self.footerBarBottomConstraint = self.footerBar.autoPinEdge(toSuperviewEdge: .bottom, withInset: -self.kFooterBarHeight)
        self.footerBar.superview?.layoutIfNeeded()

        // Undo "ensure toolbar doesn't cover bottom row.".
        if let scrollView = viewController.view as? UIScrollView {
            scrollView.contentInset.bottom -= self.kFooterBarHeight
            scrollView.scrollIndicatorInsets.bottom -= self.kFooterBarHeight
        }
    }

    // MARK: - Delete

    private lazy var deleteButton: UIBarButtonItem = {
        let deleteButton = UIBarButtonItem(barButtonSystemItem: .trash,
                                           target: self,
                                           action: #selector(didPressDelete),
                                           accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "delete_button"))

        return deleteButton
    }()

    private func updateDeleteButton() {
        guard let viewController else {
            return
        }

        self.deleteButton.isEnabled = viewController.hasSelection
    }

    @objc
    private func didPressDelete(_ sender: Any) {
        Logger.debug("")
        viewController?.deleteSelectedItems()

        guard let viewController else {
            return
        }
        viewController.deleteSelectedItems()
    }

    // MARK: - Share

    private lazy var shareButton: UIBarButtonItem = {
        let shareButton = UIBarButtonItem(barButtonSystemItem: .action,
                                          target: self,
                                          action: #selector(didPressShare),
                                          accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "share_button"))
        return shareButton
    }()

    private func updateShareButton() {
        guard let viewController else {
            return
        }

        self.shareButton.isEnabled = viewController.hasSelection
    }

    @objc
    private func didPressShare(_ sender: Any) {
        Logger.debug("")
        guard let viewController else {
            return
        }
        viewController.shareSelectedItems(sender)
    }
}
