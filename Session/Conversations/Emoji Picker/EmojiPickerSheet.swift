// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

class EmojiPickerSheet: BaseVC {
    let completionHandler: (EmojiWithSkinTones?) -> Void
    let dismissHandler: () -> Void
    
    // MARK: Components
    
    private lazy var bottomConstraint: NSLayoutConstraint = contentView.pin(.bottom, to: .bottom, of: view)
    
    private lazy var contentView: UIView = {
        let result = UIView()
        
        let backgroundView = UIView()
        backgroundView.themeBackgroundColor = .backgroundSecondary
        backgroundView.alpha = Values.lowOpacity
        result.addSubview(backgroundView)
        backgroundView.pin(to: result)

        let blurView: UIVisualEffectView = UIVisualEffectView()
        result.addSubview(blurView)
        blurView.pin(to: result)

        ThemeManager.onThemeChange(observer: blurView) { [weak blurView] theme, _ in
            switch theme.interfaceStyle {
                case .light: blurView?.effect = UIBlurEffect(style: .light)
                default: blurView?.effect = UIBlurEffect(style: .dark)
            }
        }
        
        let line = UIView()
        line.themeBackgroundColor = .borderSeparator
        result.addSubview(line)
        line.set(.height, to: Values.separatorThickness)
        line.pin([ UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing, UIView.VerticalEdge.top ], to: result)
        
        return result
    }()

    private let collectionView = EmojiPickerCollectionView()

    private lazy var searchBar: SearchBar = {
        let result = SearchBar()
        result.themeTintColor = .textPrimary
        result.themeBackgroundColor = .clear
        result.delegate = self
        
        return result
    }()

    // MARK: - Initialization

    init(completionHandler: @escaping (EmojiWithSkinTones?) -> Void, dismissHandler: @escaping () -> Void) {
        self.completionHandler = completionHandler
        self.dismissHandler = dismissHandler
        
        super.init(nibName: nil, bundle: nil)
        
        self.modalPresentationStyle = .overFullScreen
    }

    public required init() {
        fatalError("init() has not been implemented")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Lifecycle
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        view.themeBackgroundColor = .clear
        
        setUpViewHierarchy()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillChangeFrameNotification(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillHideNotification(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    private func setUpViewHierarchy() {
        view.addSubview(contentView)
        
        contentView.pin(.leading, to: .leading, of: view)
        contentView.pin(.trailing, to: .trailing, of: view)
        contentView.set(.height, to: 440)
        bottomConstraint.isActive = true
        
        let topStackView = UIStackView()
        topStackView.axis = .horizontal
        topStackView.isLayoutMarginsRelativeArrangement = true
        topStackView.spacing = 8
        contentView.addSubview(topStackView)
        topStackView.set(.width, to: .width, of: contentView)
        topStackView.pin(.top, to: .top, of: contentView)
        
        topStackView.addArrangedSubview(searchBar)

        contentView.addSubview(collectionView)
        collectionView.pin(.top, to: .bottom, of: searchBar)
        collectionView.pin(.bottom, to: .bottom, of: contentView)
        collectionView.set(.width, to: .width, of: contentView)
        collectionView.pickerDelegate = self
        collectionView.alwaysBounceVertical = true
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
    }
    
    // MARK: - Keyboard Avoidance

    @objc func handleKeyboardWillChangeFrameNotification(_ notification: Notification) {
        // Please refer to https://github.com/mapbox/mapbox-navigation-ios/issues/1600
        // and https://stackoverflow.com/a/25260930 to better understand what we are
        // doing with the UIViewAnimationOptions
        let userInfo: [AnyHashable: Any] = (notification.userInfo ?? [:])
        let duration = ((userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? 0)
        let curveValue: Int = ((userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? Int(UIView.AnimationOptions.curveEaseInOut.rawValue))
        let options: UIView.AnimationOptions = UIView.AnimationOptions(rawValue: UInt(curveValue << 16))
        let keyboardRect: CGRect = ((userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? CGRect.zero)
        let keyboardTop = (UIScreen.main.bounds.height - keyboardRect.minY)
        
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: options,
            animations: { [weak self] in
                // Note: We don't need to completely avoid the keyboard here for this to be useful (and
                // probably don't want to on smaller screens anyway)
                self?.bottomConstraint.constant = -(keyboardTop / 2)

                self?.view.setNeedsLayout()
                self?.view.layoutIfNeeded()
            },
            completion: nil
        )
    }

    @objc func handleKeyboardWillHideNotification(_ notification: Notification) {
        // Please refer to https://github.com/mapbox/mapbox-navigation-ios/issues/1600
        // and https://stackoverflow.com/a/25260930 to better understand what we are
        // doing with the UIViewAnimationOptions
        let userInfo: [AnyHashable: Any] = (notification.userInfo ?? [:])
        let duration = ((userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? 0)
        let curveValue: Int = ((userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? Int(UIView.AnimationOptions.curveEaseInOut.rawValue))
        let options: UIView.AnimationOptions = UIView.AnimationOptions(rawValue: UInt(curveValue << 16))

        let keyboardRect: CGRect = ((userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? CGRect.zero)
        let keyboardTop = (UIScreen.main.bounds.height - keyboardRect.minY)

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: options,
            animations: { [weak self] in
                self?.bottomConstraint.constant = 0

                self?.view.setNeedsLayout()
                self?.view.layoutIfNeeded()
            },
            completion: nil
        )
    }
    
    // MARK: Interaction
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard
            let touch: UITouch = touches.first,
            contentView.frame.contains(touch.location(in: view))
        else {
            close()
            return
        }
        
        super.touchesBegan(touches, with: event)
    }

    @objc func close() {
        dismiss(animated: true, completion: dismissHandler)
    }
}

extension EmojiPickerSheet: EmojiPickerCollectionViewDelegate {
    func emojiPickerWillBeginDragging(_ emojiPicker: EmojiPickerCollectionView) {
        searchBar.resignFirstResponder()
    }
    
    func emojiPicker(_ emojiPicker: EmojiPickerCollectionView?, didSelectEmoji emoji: EmojiWithSkinTones) {
        completionHandler(emoji)
        dismiss(animated: true, completion: dismissHandler)
    }
}

extension EmojiPickerSheet: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        collectionView.searchText = searchText
    }
}

