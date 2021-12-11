//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

@objc
class EmojiPickerSheet: InteractiveSheetViewController {
    override var interactiveScrollViews: [UIScrollView] { [collectionView] }

    let completionHandler: (EmojiWithSkinTones?) -> Void

    let collectionView = EmojiPickerCollectionView()
    lazy var sectionToolbar = EmojiPickerSectionToolbar(delegate: self)

    lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = NSLocalizedString("HOME_VIEW_CONVERSATION_SEARCHBAR_PLACEHOLDER", comment: "Placeholder text for search bar which filters conversations.")
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_white
        return searchBar
    }()

    init(completionHandler: @escaping (EmojiWithSkinTones?) -> Void) {
        self.completionHandler = completionHandler
        super.init()
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    override func willDismissInteractively() {
        super.willDismissInteractively()
        completionHandler(nil)
    }

    // MARK: -

    override public func viewDidLoad() {
        super.viewDidLoad()
        contentView.addSubview(searchBar)
        searchBar.autoPinWidthToSuperview()
        searchBar.autoPinEdge(toSuperviewEdge: .top)

        contentView.addSubview(collectionView)
        collectionView.autoPinEdge(.top, to: .bottom, of: searchBar)
        collectionView.autoPinEdge(.bottom, to: .bottom, of: contentView)
        collectionView.autoPinWidthToSuperview()
        collectionView.pickerDelegate = self
        collectionView.alwaysBounceVertical = true

        contentView.addSubview(sectionToolbar)
        sectionToolbar.autoPinWidthToSuperview()
        autoPinView(toBottomOfViewControllerOrKeyboard: sectionToolbar, avoidNotch: false, adjustmentWithKeyboardPresented: 32)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.collectionView.reloadData()
        }, completion: nil)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Ensure the scrollView's layout has completed
        // as we're about to use its bounds to calculate
        // the masking view and contentOffset.
        contentView.layoutIfNeeded()

        // Ensure you can scroll to the last emoji without
        // them being stuck behind the toolbar.
        let contentInset = UIEdgeInsets(top: 0, leading: 0, bottom: sectionToolbar.height, trailing: 0)
        collectionView.contentInset = contentInset
        collectionView.scrollIndicatorInsets = contentInset
    }

    private func expandSheetAnimated() {
        guard heightConstraint?.constant != maximizedHeight else { return }

        UIView.animate(withDuration: maxAnimationDuration, delay: 0, options: .curveEaseOut, animations: {
            self.heightConstraint?.constant = self.maximizedHeight
            self.view.layoutIfNeeded()
            self.backdropView?.alpha = 1
        })
    }
}

extension EmojiPickerSheet: EmojiPickerSectionToolbarDelegate {
    func emojiPickerSectionToolbar(_ sectionToolbar: EmojiPickerSectionToolbar, didSelectSection section: Int) {
        if let searchText = collectionView.searchText, searchText.count > 0 {
            searchBar.text = nil
            collectionView.searchText = nil

            // Collection view needs a moment to reload
            DispatchQueue.main.async {
                self.collectionView.scrollToSectionHeader(section, animated: false)
            }
        } else {
            collectionView.scrollToSectionHeader(section, animated: false)
        }

        expandSheetAnimated()
    }

    func emojiPickerSectionToolbarShouldShowRecentsSection(_ sectionToolbar: EmojiPickerSectionToolbar) -> Bool {
        return collectionView.hasRecentEmoji
    }

    func emojiPickerWillBeginDragging(_ emojiPicker: EmojiPickerCollectionView) {
        searchBar.resignFirstResponder()
    }
}

extension EmojiPickerSheet: EmojiPickerCollectionViewDelegate {
    func emojiPicker(_ emojiPicker: EmojiPickerCollectionView, didSelectEmoji emoji: EmojiWithSkinTones) {
        completionHandler(emoji)
        dismiss(animated: true)
    }

    func emojiPicker(_ emojiPicker: EmojiPickerCollectionView, didScrollToSection section: Int) {
        sectionToolbar.setSelectedSection(section)
    }
}

extension EmojiPickerSheet: UISearchBarDelegate {
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        expandSheetAnimated()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        collectionView.searchText = searchText
    }
}
