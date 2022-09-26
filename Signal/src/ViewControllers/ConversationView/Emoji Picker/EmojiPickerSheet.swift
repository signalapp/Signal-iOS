//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalServiceKit

@objc
class EmojiPickerSheet: InteractiveSheetViewController {
    override var interactiveScrollViews: [UIScrollView] { [collectionView] }

    let completionHandler: (EmojiWithSkinTones?) -> Void

    let collectionView = EmojiPickerCollectionView()
    lazy var sectionToolbar = EmojiPickerSectionToolbar(delegate: self)

    let allowReactionConfiguration: Bool

    lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = NSLocalizedString("HOME_VIEW_CONVERSATION_SEARCHBAR_PLACEHOLDER", comment: "Placeholder text for search bar which filters conversations.")
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        return searchBar
    }()

    lazy var configureButton: UIButton = {
        let button = UIButton()

        button.setImage(Theme.iconImage(.emojiSettings), for: .normal)
        button.tintColor = Theme.primaryIconColor

        button.addTarget(self, action: #selector(didSelectConfigureButton), for: .touchUpInside)
        return button
    }()

    override var sheetBackgroundColor: UIColor {
        Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_white
    }

    init(allowReactionConfiguration: Bool = true, completionHandler: @escaping (EmojiWithSkinTones?) -> Void) {
        self.allowReactionConfiguration = allowReactionConfiguration
        self.completionHandler = completionHandler
        super.init()

        if !allowReactionConfiguration {
            self.backdropColor = .clear
        }
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

        let topStackView = UIStackView()
        topStackView.axis = .horizontal
        topStackView.isLayoutMarginsRelativeArrangement = true
        topStackView.spacing = 8

        if allowReactionConfiguration {
            topStackView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 16)
            topStackView.addArrangedSubviews([searchBar, configureButton])
        } else {
            topStackView.addArrangedSubview(searchBar)
        }

        contentView.addSubview(topStackView)

        topStackView.autoPinWidthToSuperview()
        topStackView.autoPinEdge(toSuperviewEdge: .top)

        contentView.addSubview(collectionView)
        collectionView.autoPinEdge(.top, to: .bottom, of: searchBar)
        collectionView.autoPinEdge(.bottom, to: .bottom, of: contentView)
        collectionView.autoPinWidthToSuperview()
        collectionView.pickerDelegate = self
        collectionView.alwaysBounceVertical = true

        contentView.addSubview(sectionToolbar)
        sectionToolbar.autoPinWidthToSuperview()
        let offset: CGFloat = UIDevice.current.hasIPhoneXNotch ? 32 : 0
        autoPinView(toBottomOfViewControllerOrKeyboard: sectionToolbar, avoidNotch: false, adjustmentWithKeyboardPresented: offset)
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

    @objc
    private func didSelectConfigureButton(sender: UIButton) {
        let configVC = EmojiReactionPickerConfigViewController()
        let navController = UINavigationController(rootViewController: configVC)
        self.present(navController, animated: true)
    }
}

extension EmojiPickerSheet: EmojiPickerSectionToolbarDelegate {
    func emojiPickerSectionToolbar(_ sectionToolbar: EmojiPickerSectionToolbar, didSelectSection section: Int) {
        if let searchText = collectionView.searchText, searchText.count > 0 {
            searchBar.text = nil
            collectionView.searchText = nil

            // Collection view needs a moment to reload.
            // Do empty batch of updates to postpone scroll until collection view has updated.
            collectionView.performBatchUpdates(nil) { _ in
                self.collectionView.scrollToSectionHeader(section, animated: false)
            }
        } else {
            collectionView.scrollToSectionHeader(section, animated: false)
        }

        maximizeHeight()
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
        maximizeHeight()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        collectionView.searchText = searchText
    }
}
