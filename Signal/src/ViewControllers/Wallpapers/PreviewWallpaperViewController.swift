//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

protocol PreviewWallpaperDelegate: AnyObject {
    func previewWallpaperDidCancel(_ vc: PreviewWallpaperViewController)
    func previewWallpaperDidComplete(_ vc: PreviewWallpaperViewController)
}

class PreviewWallpaperViewController: UIViewController {
    enum Mode {
        case preset(selectedWallpaper: Wallpaper)
        case photo(selectedPhoto: UIImage)
    }
    private(set) var mode: Mode { didSet { modeDidChange() }}
    let thread: TSThread?
    weak var delegate: PreviewWallpaperDelegate?
    lazy var blurButton = BlurButton { [weak self] shouldBlur in self?.standalonePage?.shouldBlur = shouldBlur }

    let pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal,
        options: [:]
    )

    lazy var mockConversationView = MockConversationView(
        model: buildMockConversationModel(),
        hasWallpaper: true,
        customChatColor: nil
    )

    init(mode: Mode, thread: TSThread? = nil, delegate: PreviewWallpaperDelegate) {
        self.mode = mode
        self.thread = thread
        self.delegate = delegate

        super.init(nibName: nil, bundle: nil)

        mockConversationView.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    override func loadView() {
        view = UIView()

        view.backgroundColor = Theme.backgroundColor

        view.addSubview(mockConversationView)
        mockConversationView.autoPinWidthToSuperview()
        mockConversationView.autoPinEdge(toSuperviewSafeArea: .top, withInset: 20)
        mockConversationView.isUserInteractionEnabled = false

        modeDidChange()

        let buttonStack = UIStackView()
        buttonStack.addBackgroundView(withBackgroundColor: Theme.backgroundColor)
        buttonStack.axis = .horizontal

        view.addSubview(buttonStack)
        buttonStack.autoPinWidthToSuperview()
        buttonStack.autoPinEdge(toSuperviewSafeArea: .bottom)
        buttonStack.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)

        let cancelButton = OWSButton(title: CommonStrings.cancelButton) { [weak self] in
            guard let self = self else { return }
            self.delegate?.previewWallpaperDidCancel(self)
        }
        cancelButton.setTitleColor(Theme.primaryTextColor, for: .normal)
        buttonStack.addArrangedSubview(cancelButton)

        let divider = UIView()
        let dividerLine = UIView()
        dividerLine.backgroundColor = UIColor(rgbHex: 0xc4c4c4)
        divider.addSubview(dividerLine)
        dividerLine.autoPinWidthToSuperview()
        dividerLine.autoPinHeightToSuperview(withMargin: 8)
        dividerLine.autoSetDimension(.width, toSize: 1)

        buttonStack.addArrangedSubview(divider)

        let setButton = OWSButton(title: CommonStrings.setButton) { [weak self] in
            self?.setCurrentWallpaperAndDismiss()
        }
        setButton.setTitleColor(Theme.primaryTextColor, for: .normal)
        buttonStack.addArrangedSubview(setButton)

        cancelButton.autoMatch(.width, to: .width, of: setButton)

        let safeAreaCover = UIView()
        safeAreaCover.backgroundColor = Theme.backgroundColor
        view.addSubview(safeAreaCover)
        safeAreaCover.autoPinEdge(toSuperviewEdge: .bottom)
        safeAreaCover.autoPinWidthToSuperview()
        safeAreaCover.autoPinEdge(.top, to: .bottom, of: buttonStack)

        view.addSubview(blurButton)
        blurButton.autoPinEdge(.bottom, to: .top, of: buttonStack, withOffset: -24)
        blurButton.autoHCenterInSuperview()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.hidesBackButton = true
        title = OWSLocalizedString("WALLPAPER_PREVIEW_TITLE", comment: "Title for the wallpaper preview view.")
    }

    func setCurrentWallpaperAndDismiss() {
        databaseStorage.asyncWrite { transaction in
            do {
                switch self.mode {
                case .photo:
                    guard let standalonePage = self.standalonePage else {
                        return owsFailDebug("Missing standalone page for photo")
                    }
                    let croppedAndScaledPhoto = standalonePage.view.renderAsImage()
                    try Wallpaper.setPhoto(croppedAndScaledPhoto, for: self.thread, transaction: transaction)
                case .preset(let selectedWallpaper):
                    try Wallpaper.setBuiltIn(selectedWallpaper, for: self.thread, transaction: transaction)
                }
            } catch {
                owsFailDebug("Failed to set wallpaper \(error)")
            }

            transaction.addAsyncCompletionOnMain {
                self.delegate?.previewWallpaperDidComplete(self)
            }
        }
    }

    private var standalonePage: WallpaperPage?
    func modeDidChange() {
        let resolvedWallpaper: Wallpaper
        switch mode {
        case .photo(let selectedPhoto):
            owsAssertDebug(self.standalonePage == nil)
            resolvedWallpaper = .photo
            let standalonePage = WallpaperPage(wallpaper: resolvedWallpaper, thread: thread, photo: selectedPhoto)
            self.standalonePage = standalonePage
            view.insertSubview(standalonePage.view, at: 0)
            addChild(standalonePage)
            standalonePage.view.autoPinEdgesToSuperviewEdges()
            blurButton.isHidden = false
        case .preset(let selectedWallpaper):
            resolvedWallpaper = selectedWallpaper
            if pageViewController.view.superview == nil {
                view.insertSubview(pageViewController.view, at: 0)
                addChild(pageViewController)
                pageViewController.view.autoPinEdgesToSuperviewEdges()
                pageViewController.dataSource = self
                pageViewController.delegate = self
            }
            currentPage = WallpaperPage(wallpaper: selectedWallpaper, thread: thread)
            blurButton.isHidden = true
        }
        mockConversationView.model = buildMockConversationModel()
        mockConversationView.customChatColor = databaseStorage.read { tx in
            ChatColors.resolvedChatColor(for: thread, previewWallpaper: resolvedWallpaper, tx: tx)
        }
    }

    func buildMockConversationModel() -> MockConversationView.MockModel {
        let outgoingText: String = {
            guard let thread = thread else {
                return OWSLocalizedString(
                    "WALLPAPER_PREVIEW_OUTGOING_MESSAGE_ALL_CHATS",
                    comment: "The outgoing bubble text when setting a wallpaper for all chats."
                )
            }

            let formatString = OWSLocalizedString(
                "WALLPAPER_PREVIEW_OUTGOING_MESSAGE_FORMAT",
                comment: "The outgoing bubble text when setting a wallpaper for specific chat. Embeds {{chat name}}"
            )
            let displayName = databaseStorage.read { tx in contactsManager.displayName(for: thread, transaction: tx) }
            return String(format: formatString, displayName)
        }()

        let incomingText: String
        switch mode {
        case .photo:
            incomingText = OWSLocalizedString(
                "WALLPAPER_PREVIEW_INCOMING_MESSAGE_PHOTO",
                comment: "The incoming bubble text when setting a photo"
            )
        case .preset:
            incomingText = OWSLocalizedString(
                "WALLPAPER_PREVIEW_INCOMING_MESSAGE_PRESET",
                comment: "The incoming bubble text when setting a preset"
            )
        }

        return MockConversationView.MockModel(items: [
            .date,
            .incoming(text: incomingText),
            .outgoing(text: outgoingText)
        ])
    }
}

// MARK: -

extension PreviewWallpaperViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let currentPage = currentPage, currentPage.wallpaper != .photo else { return nil }
        return WallpaperPage(wallpaper: wallpaper(before: currentPage.wallpaper),
                             thread: thread)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let currentPage = currentPage, currentPage.wallpaper != .photo else { return nil }
        return WallpaperPage(wallpaper: wallpaper(after: currentPage.wallpaper),
                             thread: thread)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard let currentPage = currentPage else {
            return owsFailDebug("Missing current page after transition")
        }

        DispatchQueue.main.async {
            self.mode = .preset(selectedWallpaper: currentPage.wallpaper)
        }
    }

    fileprivate var currentPage: WallpaperPage? {
        get { pageViewController.viewControllers?.first as? WallpaperPage }
        set {
            let viewControllers: [UIViewController]
            if let newValue = newValue {
                viewControllers = [newValue]
            } else {
                viewControllers = []
            }
            pageViewController.setViewControllers(viewControllers, direction: .forward, animated: false)
        }
    }

    func wallpaper(after: Wallpaper) -> Wallpaper {
        guard let index = Wallpaper.defaultWallpapers.firstIndex(where: { $0 == after }) else {
            owsFailDebug("Unexpectedly missing index for wallpaper \(after)")
            return Wallpaper.defaultWallpapers.first!
        }

        if index == Wallpaper.defaultWallpapers.count - 1 {
            return Wallpaper.defaultWallpapers.first!
        } else {
            return Wallpaper.defaultWallpapers[index + 1]
        }
    }

    func wallpaper(before: Wallpaper) -> Wallpaper {
        guard let index = Wallpaper.defaultWallpapers.firstIndex(where: { $0 == before }) else {
            owsFailDebug("Unexpectedly missing index for wallpaper \(before)")
            return Wallpaper.defaultWallpapers.first!
        }

        if index == 0 {
            return Wallpaper.defaultWallpapers.last!
        } else {
            return Wallpaper.defaultWallpapers[index - 1]
        }
    }
}

private class WallpaperPage: UIViewController {
    let wallpaper: Wallpaper
    let thread: TSThread?
    let photo: UIImage?
    var shouldBlur = false { didSet { updatePhoto() } }

    init(wallpaper: Wallpaper,
         thread: TSThread?,
         photo: UIImage? = nil) {
        self.wallpaper = wallpaper
        self.thread = thread
        self.photo = photo

        super.init(nibName: nil, bundle: nil)

        if photo != nil { prepareBlurredPhoto() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var wallpaperViewHeightPriorityConstraints = [NSLayoutConstraint]()
    var wallpaperViewWidthPriorityConstraints = [NSLayoutConstraint]()
    var wallpaperViewHeightAndWidthPriorityConstraints = [NSLayoutConstraint]()

    var wallpaperView: WallpaperView?
    var wallpaperPreviewView: UIView?

    override func loadView() {
        let rootView = ManualLayoutViewWithLayer(name: "rootView")
        rootView.shouldDeactivateConstraints = false
        rootView.translatesAutoresizingMaskIntoConstraints = true
        rootView.backgroundColor = Theme.darkThemeBackgroundColor
        view = rootView

        let shouldDimInDarkTheme = databaseStorage.read { transaction in
            Wallpaper.dimInDarkMode(for: thread, transaction: transaction)
        }
        let wallpaperView = Wallpaper.viewBuilder(
            for: wallpaper,
            customPhoto: { photo },
            shouldDimInDarkTheme: shouldDimInDarkTheme
        )?.build()
        guard let wallpaperView else {
            owsFailDebug("Failed to create photo wallpaper view")
            return
        }
        self.wallpaperView = wallpaperView

        let wallpaperPreviewView = wallpaperView.asPreviewView()
        self.wallpaperPreviewView = wallpaperPreviewView

        // If this is a photo, embed it in a scrollView for pinch & zoom
        if case .photo = wallpaper, let photo = photo {
            let scrollView = UIScrollView()
            scrollView.minimumZoomScale = 1.0
            scrollView.maximumZoomScale = 6.0
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.delegate = self
            view.addSubview(scrollView)
            scrollView.autoPinEdgesToSuperviewEdges()
            scrollView.addSubview(wallpaperPreviewView)

            wallpaperPreviewView.autoPinEdgesToSuperviewEdges()

            wallpaperViewWidthPriorityConstraints = [
                wallpaperPreviewView.autoMatch(
                    .width,
                    to: .width,
                    of: scrollView
                ),
                wallpaperPreviewView.autoMatch(
                    .height,
                    to: .width,
                    of: scrollView,
                    withMultiplier: 1 / photo.size.aspectRatio
                )
            ]
            wallpaperViewWidthPriorityConstraints.forEach { $0.isActive = false }

            wallpaperViewHeightPriorityConstraints = [
                wallpaperPreviewView.autoMatch(
                    .height,
                    to: .height,
                    of: scrollView
                ),
                wallpaperPreviewView.autoMatch(
                    .width,
                    to: .height,
                    of: scrollView,
                    withMultiplier: photo.size.aspectRatio
                )
            ]
            wallpaperViewHeightPriorityConstraints.forEach { $0.isActive = false }

            wallpaperViewHeightAndWidthPriorityConstraints = [
                wallpaperPreviewView.autoMatch(
                    .height,
                    to: .height,
                    of: scrollView
                ),
                wallpaperPreviewView.autoMatch(
                    .width,
                    to: .width,
                    of: scrollView
                )
            ]
            wallpaperViewHeightAndWidthPriorityConstraints.forEach { $0.isActive = false }

            updateWallpaperConstraints(reference: view.bounds.size)
        } else {
            view.addSubview(wallpaperPreviewView)
            wallpaperPreviewView.autoPinEdgesToSuperviewEdges()
        }
    }

    private func updatePhoto() {
        guard let wallpaperImageView = wallpaperView?.contentView as? UIImageView else { return }
        UIView.transition(with: wallpaperImageView, duration: 0.2, options: .transitionCrossDissolve) {
            wallpaperImageView.image = self.shouldBlur ? self.blurredPhoto : self.photo
        } completion: { _ in }
    }

    private var blurredPhoto: UIImage?
    private func prepareBlurredPhoto() {
        photo?.withGaussianBlurPromise(
            radius: 10,
            resizeToMaxPixelDimension: 1024
        ).done(on: DispatchQueue.main) { [weak self] blurredPhoto in
            self?.blurredPhoto = blurredPhoto
            self?.updatePhoto()
        }.catch { error in
            owsFailDebug("Failed to blur image \(error)")
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in
            self.updateWallpaperConstraints(reference: size)
        } completion: { _ in }
    }

    private var previousReferenceSize: CGSize = .zero
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        let referenceSize = view.bounds.size
        guard referenceSize != previousReferenceSize else { return }
        previousReferenceSize = referenceSize
        updateWallpaperConstraints(reference: referenceSize)
    }

    func updateWallpaperConstraints(reference: CGSize) {
        guard let imageSize = photo?.size else { return }

        wallpaperViewWidthPriorityConstraints.forEach { $0.isActive = false }
        wallpaperViewHeightPriorityConstraints.forEach { $0.isActive = false }
        wallpaperViewHeightAndWidthPriorityConstraints.forEach { $0.isActive = false }

        let imageSizeMatchingReferenceHeight = CGSize(
            width: reference.height * imageSize.aspectRatio,
            height: reference.height
        )

        let imageSizeMatchingReferenceWidth = CGSize(
            width: reference.width,
            height: reference.width / imageSize.aspectRatio
        )

        if imageSizeMatchingReferenceHeight.width >= reference.width {
            wallpaperViewHeightPriorityConstraints.forEach { $0.isActive = true }
        } else if imageSizeMatchingReferenceWidth.height >= reference.height {
            wallpaperViewWidthPriorityConstraints.forEach { $0.isActive = true }
        } else {
            wallpaperViewHeightAndWidthPriorityConstraints.forEach { $0.isActive = true }
        }
    }
}

extension WallpaperPage: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return wallpaperPreviewView
    }
}

class BlurButton: UIButton {
    let checkImageView = UIImageView()
    let label = UILabel()
    let action: (Bool) -> Void
    let backgroundView: UIView = {
        if UIAccessibility.isReduceTransparencyEnabled {
            let backgroundView = UIView()
            backgroundView.backgroundColor = .ows_blackAlpha80
            return backgroundView
        } else {
            let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
            return blurView
        }
    }()

    init(action: @escaping (Bool) -> Void) {
        self.action = action
        super.init(frame: .zero)

        addTarget(self, action: #selector(didTap), for: .touchUpInside)

        layoutMargins = UIEdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 12)
        autoSetDimension(.height, toSize: 28, relation: .greaterThanOrEqual)

        backgroundView.clipsToBounds = true
        backgroundView.isUserInteractionEnabled = false
        addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()

        addSubview(checkImageView)
        checkImageView.autoPinEdge(toSuperviewMargin: .leading)
        checkImageView.autoPinHeightToSuperviewMargins()
        checkImageView.autoSetDimension(.width, toSize: 16)
        checkImageView.contentMode = .scaleAspectFit
        checkImageView.isUserInteractionEnabled = false

        label.font = .semiboldFont(ofSize: 14)
        label.textColor = .white
        label.text = OWSLocalizedString("WALLPAPER_PREVIEW_BLUR_BUTTON",
                                       comment: "Blur button on wallpaper preview.")
        addSubview(label)
        label.autoPinHeightToSuperviewMargins()
        label.autoPinEdge(toSuperviewMargin: .trailing)
        label.autoPinEdge(.leading, to: .trailing, of: checkImageView, withOffset: 10)
        label.isUserInteractionEnabled = false

        isSelected = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.layer.cornerRadius = height / 2
    }

    override var isSelected: Bool {
        didSet {
            UIView.transition(with: checkImageView, duration: 0.15, options: .transitionCrossDissolve) {
                self.checkImageView.image = self.isSelected
                    ? UIImage(imageLiteralResourceName: "check-circle-fill-compact")
                    : UIImage(imageLiteralResourceName: "circle-compact")
            } completion: { _ in }
        }
    }

    @objc
    private func didTap() {
        isSelected = !isSelected
        action(isSelected)
    }
}

// MARK: -

extension PreviewWallpaperViewController: MockConversationDelegate {
    var mockConversationViewWidth: CGFloat { self.view.width }
}
