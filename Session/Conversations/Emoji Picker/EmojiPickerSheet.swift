// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

class EmojiPickerSheet: BaseVC {
    let completionHandler: (EmojiWithSkinTones?) -> Void
    let dismissHandler: () -> Void
    
    // MARK: Components
    
    private lazy var contentView: UIView = {
        let result = UIView()
        let line = UIView()
        line.set(.height, to: 0.5)
        line.backgroundColor = Colors.border.withAlphaComponent(0.5)
        result.addSubview(line)
        line.pin([ UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing, UIView.VerticalEdge.top ], to: result)
        result.backgroundColor = Colors.modalBackground
        return result
    }()

    private let collectionView = EmojiPickerCollectionView()

    private lazy var searchBar: SearchBar = {
        let result = SearchBar()
        result.tintColor = Colors.text
        result.backgroundColor = .clear
        result.delegate = self
        return result
    }()

    // MARK: Lifecycle

    init(completionHandler: @escaping (EmojiWithSkinTones?) -> Void, dismissHandler: @escaping () -> Void) {
        self.completionHandler = completionHandler
        self.dismissHandler = dismissHandler
        super.init(nibName: nil, bundle: nil)
    }

    public required init() {
        fatalError("init() has not been implemented")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        setUpViewHierarchy()
    }
    
    private func setUpViewHierarchy() {
        view.addSubview(contentView)
        contentView.pin([ UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing, UIView.VerticalEdge.bottom ], to: view)
        contentView.set(.height, to: 440)
        populateContentView()
    }
    
    private func populateContentView() {
        let topStackView = UIStackView()
        topStackView.axis = .horizontal
        topStackView.isLayoutMarginsRelativeArrangement = true
        topStackView.spacing = 8

        topStackView.addArrangedSubview(searchBar)

        contentView.addSubview(topStackView)

        topStackView.autoPinWidthToSuperview()
        topStackView.autoPinEdge(toSuperviewEdge: .top)

        contentView.addSubview(collectionView)
        collectionView.autoPinEdge(.top, to: .bottom, of: searchBar)
        collectionView.autoPinEdge(.bottom, to: .bottom, of: contentView)
        collectionView.autoPinWidthToSuperview()
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
    
    // MARK: Interaction
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first!
        let location = touch.location(in: view)
        if contentView.frame.contains(location) {
            super.touchesBegan(touches, with: event)
        } else {
            close()
        }
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
    
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        searchBar.showsCancelButton = true
        return true
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.showsCancelButton = false
        searchBar.resignFirstResponder()
    }
}

