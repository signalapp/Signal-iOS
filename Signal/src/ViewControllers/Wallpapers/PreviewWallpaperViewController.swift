//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol PreviewWallpaperDelegate: AnyObject {
    func previewWallpaperDidCancel(_ vc: PreviewWallpaperViewController)
    func previewWallpaperDidComplete(_ vc: PreviewWallpaperViewController)
}

class PreviewWallpaperViewController: OWSViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate,
    MockConversationDelegate
{
    enum Mode {
        case preset(selectedWallpaper: Wallpaper)
        case photo(selectedPhoto: UIImage)
    }

    private(set) var mode: Mode { didSet { modeDidChange() }}

    private var standalonePage: WallpaperPage?

    private let thread: TSThread?

    weak var delegate: PreviewWallpaperDelegate?

    private lazy var blurButton = BlurButton { [weak self] shouldBlur in self?.standalonePage?.shouldBlur = shouldBlur }

    private lazy var pageViewController: UIPageViewController = {
        let viewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [:],
        )
        viewController.dataSource = self
        viewController.delegate = self
        return viewController
    }()

    private lazy var mockConversationView = MockConversationView(
        model: buildMockConversationModel(),
        hasWallpaper: true,
        customChatColor: nil,
    )

    init(mode: Mode, thread: TSThread? = nil, delegate: PreviewWallpaperDelegate) {
        self.mode = mode
        self.thread = thread
        self.delegate = delegate

        super.init()

        mockConversationView.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        if #unavailable(iOS 26), let navigationBar = navigationController?.navigationBar {
            // Make navigation bar have a translucent background.
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            navigationBar.standardAppearance = appearance
            navigationBar.compactAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
        }

        navigationItem.title = OWSLocalizedString(
            "WALLPAPER_PREVIEW_TITLE",
            comment: "Title for the wallpaper preview view.",
        )
        navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            guard let self else { return }
            self.delegate?.previewWallpaperDidCancel(self)
        }
        navigationItem.rightBarButtonItem = .doneButton { [weak self] in
            self?.setCurrentWallpaperAndDismiss()
        }

        mockConversationView.isUserInteractionEnabled = false
        mockConversationView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mockConversationView)

        blurButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blurButton)

        NSLayoutConstraint.activate([
            mockConversationView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            mockConversationView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mockConversationView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            blurButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            blurButton.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor, constant: -24),
        ])

        modeDidChange()
    }

    private func setCurrentWallpaperAndDismiss() {
        let croppedAndScaledPhoto: UIImage?
        let preset: Wallpaper?
        switch self.mode {
        case .photo:
            guard let standalonePage else {
                return owsFailDebug("Missing standalone page for photo")
            }
            croppedAndScaledPhoto = standalonePage.generateSnapshotImage()
            preset = nil

        case .preset(let selectedWallpaper):
            croppedAndScaledPhoto = nil
            preset = selectedWallpaper
        }
        Task { [weak self, thread] in
            do {
                if let croppedAndScaledPhoto {
                    try await DependenciesBridge.shared.wallpaperStore.setPhoto(croppedAndScaledPhoto, for: thread)
                } else if let preset {
                    try await DependenciesBridge.shared.wallpaperStore.setBuiltIn(preset, for: thread)
                }
            } catch {
                owsFailDebug("Failed to set wallpaper \(error)")
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.delegate?.previewWallpaperDidComplete(self)
            }
        }
    }

    private func modeDidChange() {
        let resolvedWallpaper: Wallpaper
        switch mode {
        case .photo(let selectedPhoto):
            owsAssertDebug(self.standalonePage == nil)
            resolvedWallpaper = .photo

            let standalonePage = WallpaperPage(wallpaper: resolvedWallpaper, thread: thread, photo: selectedPhoto)
            view.insertSubview(standalonePage.view, at: 0)
            addChild(standalonePage)
            standalonePage.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                standalonePage.view.topAnchor.constraint(equalTo: view.topAnchor),
                standalonePage.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                standalonePage.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                standalonePage.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])

            blurButton.isHidden = false
            self.standalonePage = standalonePage

        case .preset(let selectedWallpaper):
            resolvedWallpaper = selectedWallpaper
            if pageViewController.view.superview == nil {
                view.insertSubview(pageViewController.view, at: 0)
                addChild(pageViewController)
                pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
                    pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                ])

                pageViewController.dataSource = self
                pageViewController.delegate = self
            }
            currentPage = WallpaperPage(wallpaper: selectedWallpaper, thread: thread)

            blurButton.isHidden = true
        }

        let chatColor = SSKEnvironment.shared.databaseStorageRef.read { tx in
            DependenciesBridge.shared.chatColorSettingStore.resolvedChatColor(
                for: thread,
                previewWallpaper: resolvedWallpaper,
                tx: tx,
            )
        }

        mockConversationView.model = buildMockConversationModel()
        mockConversationView.customChatColor = chatColor

        if #available(iOS 26, *) {
            navigationItem.rightBarButtonItem?.tintColor = chatColor.asValue.asChatUIElementTintColor()
        }
    }

    private func buildMockConversationModel() -> MockConversationView.MockModel {
        let outgoingText: String = {
            guard let thread else {
                return OWSLocalizedString(
                    "WALLPAPER_PREVIEW_OUTGOING_MESSAGE_ALL_CHATS",
                    comment: "The outgoing bubble text when setting a wallpaper for all chats.",
                )
            }

            let formatString = OWSLocalizedString(
                "WALLPAPER_PREVIEW_OUTGOING_MESSAGE_FORMAT",
                comment: "The outgoing bubble text when setting a wallpaper for specific chat. Embeds {{chat name}}",
            )
            let displayName = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx) }
            return String.nonPluralLocalizedStringWithFormat(formatString, displayName)
        }()

        let incomingText: String
        switch mode {
        case .photo:
            incomingText = OWSLocalizedString(
                "WALLPAPER_PREVIEW_INCOMING_MESSAGE_PHOTO",
                comment: "The incoming bubble text when setting a photo",
            )
        case .preset:
            incomingText = OWSLocalizedString(
                "WALLPAPER_PREVIEW_INCOMING_MESSAGE_PRESET",
                comment: "The incoming bubble text when setting a preset",
            )
        }

        return MockConversationView.MockModel(items: [
            .date,
            .incoming(text: incomingText),
            .outgoing(text: outgoingText),
        ])
    }

    // MARK: - UIPageViewController

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController,
    ) -> UIViewController? {
        guard let currentPage, currentPage.wallpaper != .photo else { return nil }
        return WallpaperPage(
            wallpaper: wallpaper(before: currentPage.wallpaper),
            thread: thread,
        )
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController,
    ) -> UIViewController? {
        guard let currentPage, currentPage.wallpaper != .photo else { return nil }
        return WallpaperPage(
            wallpaper: wallpaper(after: currentPage.wallpaper),
            thread: thread,
        )
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool,
    ) {
        guard let currentPage else {
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
            if let newValue {
                viewControllers = [newValue]
            } else {
                viewControllers = []
            }
            pageViewController.setViewControllers(viewControllers, direction: .forward, animated: false)
        }
    }

    private func wallpaper(after: Wallpaper) -> Wallpaper {
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

    private func wallpaper(before: Wallpaper) -> Wallpaper {
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

    // MARK: - MockConversationDelegate

    var mockConversationViewWidth: CGFloat { self.view.width }
}

private class WallpaperPage: UIViewController, UIScrollViewDelegate {

    let wallpaper: Wallpaper
    private let thread: TSThread?
    private let photo: UIImage?

    init(
        wallpaper: Wallpaper,
        thread: TSThread?,
        photo: UIImage? = nil,
    ) {
        self.wallpaper = wallpaper
        self.thread = thread
        self.photo = photo

        super.init(nibName: nil, bundle: nil)

        if photo != nil { prepareBlurredPhoto() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var blurredPhoto: UIImage?
    var shouldBlur = false { didSet { updatePhoto() } }

    private var wallpaperViewHeightPriorityConstraints: [NSLayoutConstraint]!
    private var wallpaperViewWidthPriorityConstraints: [NSLayoutConstraint]!
    private var wallpaperViewHeightAndWidthPriorityConstraints: [NSLayoutConstraint]!

    private var wallpaperView: WallpaperView?
    private var wallpaperPreviewView: UIView?

    private var scrollView: UIScrollView?
    private var previousReferenceSize: CGSize = .zero

    override func loadView() {
        let rootView = ManualLayoutViewWithLayer(name: "rootView")
        rootView.shouldDeactivateConstraints = false
        rootView.translatesAutoresizingMaskIntoConstraints = true
        rootView.backgroundColor = .black
        view = rootView

        let shouldDimInDarkTheme = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            DependenciesBridge.shared.wallpaperStore.fetchDimInDarkModeForRendering(
                for: thread?.uniqueId,
                tx: transaction,
            )
        }
        let wallpaperView = Wallpaper.viewBuilder(
            for: wallpaper,
            customPhoto: { photo },
            shouldDimInDarkTheme: shouldDimInDarkTheme,
        )?.build()
        guard let wallpaperView else {
            owsFailDebug("Failed to create photo wallpaper view")
            return
        }

        let wallpaperPreviewView = wallpaperView.asPreviewView()
        wallpaperPreviewView.translatesAutoresizingMaskIntoConstraints = false

        // If this is a photo, embed it in a scrollView for pinch & zoom
        if case .photo = wallpaper, let photo {
            let scrollView = UIScrollView()
            scrollView.minimumZoomScale = 1.0
            scrollView.maximumZoomScale = 6.0
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.delegate = self
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(scrollView)

            scrollView.addSubview(wallpaperPreviewView)
            self.scrollView = scrollView

            NSLayoutConstraint.activate([
                scrollView.frameLayoutGuide.topAnchor.constraint(equalTo: view.topAnchor),
                scrollView.frameLayoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scrollView.frameLayoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                wallpaperPreviewView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                wallpaperPreviewView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                wallpaperPreviewView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                wallpaperPreviewView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            ])

            wallpaperViewWidthPriorityConstraints = [
                wallpaperPreviewView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
                wallpaperPreviewView.heightAnchor.constraint(
                    equalTo: scrollView.frameLayoutGuide.widthAnchor,
                    multiplier: 1 / photo.size.aspectRatio,
                ),
            ]

            wallpaperViewHeightPriorityConstraints = [
                wallpaperPreviewView.widthAnchor.constraint(
                    equalTo: scrollView.frameLayoutGuide.heightAnchor,
                    multiplier: photo.size.aspectRatio,
                ),
                wallpaperPreviewView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            ]

            wallpaperViewHeightAndWidthPriorityConstraints = [
                wallpaperPreviewView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
                wallpaperPreviewView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            ]

            updateWallpaperConstraints(reference: view.bounds.size)
        } else {
            view.addSubview(wallpaperPreviewView)
            NSLayoutConstraint.activate([
                wallpaperPreviewView.topAnchor.constraint(equalTo: view.topAnchor),
                wallpaperPreviewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                wallpaperPreviewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                wallpaperPreviewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }

        self.wallpaperView = wallpaperView
        self.wallpaperPreviewView = wallpaperPreviewView
    }

    private func updatePhoto() {
        guard let wallpaperImageView = wallpaperView?.contentView as? UIImageView else { return }

        UIView.transition(
            with: wallpaperImageView,
            duration: 0.2,
            options: .transitionCrossDissolve,
        ) {
            wallpaperImageView.image = self.shouldBlur ? self.blurredPhoto : self.photo
        }
    }

    private func prepareBlurredPhoto() {
        Task { [weak self, photo] in
            do {
                let blurredPhoto = try await photo?.withGaussianBlurAsync(
                    radius: 10,
                    resizeToMaxPixelDimension: 1024,
                )
                self?.blurredPhoto = blurredPhoto
                self?.updatePhoto()
            } catch {
                owsFailDebug("Failed to blur image \(error)")
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        guard scrollView != nil else { return }

        coordinator.animate { _ in
            self.updateWallpaperConstraints(reference: size)
        } completion: { _ in }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        guard scrollView != nil else { return }

        let referenceSize = view.bounds.size
        guard referenceSize != previousReferenceSize else { return }
        previousReferenceSize = referenceSize
        updateWallpaperConstraints(reference: referenceSize)
    }

    func updateWallpaperConstraints(reference: CGSize) {
        guard scrollView != nil, let imageSize = photo?.size else { return }

        NSLayoutConstraint.deactivate(wallpaperViewWidthPriorityConstraints)
        NSLayoutConstraint.deactivate(wallpaperViewHeightPriorityConstraints)
        NSLayoutConstraint.deactivate(wallpaperViewHeightAndWidthPriorityConstraints)

        let imageSizeMatchingReferenceHeight = CGSize(
            width: reference.height * imageSize.aspectRatio,
            height: reference.height,
        )

        let imageSizeMatchingReferenceWidth = CGSize(
            width: reference.width,
            height: reference.width / imageSize.aspectRatio,
        )

        if imageSizeMatchingReferenceHeight.width >= reference.width {
            NSLayoutConstraint.activate(wallpaperViewHeightPriorityConstraints)
        } else if imageSizeMatchingReferenceWidth.height >= reference.height {
            NSLayoutConstraint.activate(wallpaperViewWidthPriorityConstraints)
        } else {
            NSLayoutConstraint.activate(wallpaperViewHeightAndWidthPriorityConstraints)
        }
    }

    func generateSnapshotImage() -> UIImage? {
        guard case .photo = wallpaper, let scrollView else {
            return view.renderAsImage()
        }

        let viewForSnapshotting = UIView(frame: scrollView.frame)
        viewForSnapshotting.clipsToBounds = true
        let imageView = UIImageView(image: shouldBlur ? blurredPhoto : photo)
        viewForSnapshotting.addSubview(imageView)
        imageView.frame = CGRect(
            x: -scrollView.contentOffset.x,
            y: -scrollView.contentOffset.y,
            width: scrollView.contentScaleFactor * scrollView.contentSize.width,
            height: scrollView.contentScaleFactor * scrollView.contentSize.height,
        )
        return viewForSnapshotting.renderAsImage()
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return wallpaperPreviewView
    }
}

private class BlurButton: UIButton {

    private let action: (Bool) -> Void

    init(action: @escaping (Bool) -> Void) {
        self.action = action

        super.init(frame: .zero)

        addAction(
            UIAction { [weak self] _ in
                self?.didTap()
            },
            for: .primaryActionTriggered,
        )

        var configuration = UIButton.Configuration.borderless()
        configuration.baseForegroundColor = .white
        configuration.title = OWSLocalizedString(
            "WALLPAPER_PREVIEW_BLUR_BUTTON",
            comment: "Blur button on wallpaper preview.",
        )
        configuration.attributedTitle?.font = .dynamicTypeSubheadline.semibold()
        configuration.image = UIImage(imageLiteralResourceName: "circle-compact")
        configuration.imagePlacement = .leading
        configuration.imageColorTransformer = UIConfigurationColorTransformer { _ in
            .Signal.accent
        }
        configuration.imagePadding = 8
        configuration.contentInsets = .init(top: 6, leading: 8, bottom: 6, trailing: 12)
        configuration.cornerStyle = .capsule
        configuration.background = {
            var background = UIBackgroundConfiguration.clear()
            background.customView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
            return background
        }()

        self.configuration = configuration

        isSelected = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isSelected: Bool {
        didSet {
            let image = isSelected
                ? UIImage(imageLiteralResourceName: "check-circle-fill-compact")
                : UIImage(imageLiteralResourceName: "circle-compact")
            UIView.transition(
                with: self,
                duration: 0.15,
                options: .transitionCrossDissolve,
            ) {
                self.configuration?.image = image
            } completion: { _ in }
        }
    }

    private func didTap() {
        isSelected = !isSelected
        action(isSelected)
    }
}
