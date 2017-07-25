//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

private class CallKitExperienceUpgradeViewController: ExperienceUpgradeViewController {

    override func loadView() {
        super.loadView()
        assert(view != nil)
        assert(bodyLabel != nil)

        // Privacy Settings Button
        let privacySettingsButton = UIButton()
        view.addSubview(privacySettingsButton)
        let privacyTitle = NSLocalizedString("UPGRADE_EXPERIENCE_CALLKIT_PRIVACY_SETTINGS_BUTTON", comment: "button label shown once when when user upgrades app, in context of call kit")
        privacySettingsButton.setTitle(privacyTitle, for: .normal)
        privacySettingsButton.setTitleColor(UIColor.ows_signalBrandBlue(), for: .normal)
        privacySettingsButton.isUserInteractionEnabled = true
        privacySettingsButton.addTarget(self, action:#selector(didTapPrivacySettingsButton), for: .touchUpInside)
        privacySettingsButton.titleLabel?.font = bodyLabel.font

        // Privacy Settings Button layout
        privacySettingsButton.autoPinWidthToSuperview(withMargin: bodyMargin)
        privacySettingsButton.autoPinEdge(.top, to: .bottom, of: bodyLabel, withOffset: ScaleFromIPhone5(12))
        privacySettingsButton.sizeToFit()
    }

    // MARK: - Actions

    func didTapPrivacySettingsButton(sender: UIButton) {
        Logger.debug("\(TAG) in \(#function)")

        // dismiss the modally presented view controller, then proceed.
        experienceUpgradesPageViewController.dismiss(animated: true) {
            let fromViewController = UIApplication.shared.frontmostViewController
            assert(fromViewController != nil)

            // Construct the "settings" view & push the "privacy settings" view.
            let navigationController = UINavigationController(rootViewController:SettingsTableViewController())
            navigationController.pushViewController(PrivacySettingsTableViewController(), animated:false)

            fromViewController?.present(navigationController, animated: true, completion: nil)
        }
    }
}

private class ExperienceUpgradeViewController: OWSViewController {
    let TAG = "[ExperienceUpgradeViewController]"

    let header: String
    let body: String
    let image: UIImage?
    let experienceUpgradesPageViewController: ExperienceUpgradesPageViewController

    var bodyLabel: UILabel!
    let bodyMargin = ScaleFromIPhone5To7Plus(12, 24)

    init(experienceUpgrade: ExperienceUpgrade, experienceUpgradesPageViewController: ExperienceUpgradesPageViewController) {
        header = experienceUpgrade.title
        body = experienceUpgrade.body
        image = experienceUpgrade.image
        self.experienceUpgradesPageViewController = experienceUpgradesPageViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        self.view = UIView()

        /// Create Views

        // Title label
        let titleLabel = UILabel()
        view.addSubview(titleLabel)
        titleLabel.text = header
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.ows_regularFont(withSize: ScaleFromIPhone5To7Plus(26, 32))
        titleLabel.textColor = UIColor.white
        titleLabel.minimumScaleFactor = 0.5
        titleLabel.adjustsFontSizeToFitWidth = true

        // Body label
        let bodyLabel = UILabel()
        self.bodyLabel = bodyLabel
        view.addSubview(bodyLabel)
        bodyLabel.text = body
        bodyLabel.font = UIFont.ows_lightFont(withSize: ScaleFromIPhone5To7Plus(17, 22))
        bodyLabel.textColor = UIColor.black
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.textAlignment = .center

        // Image
        let imageView = UIImageView(image: image)
        view.addSubview(imageView)
        imageView.contentMode = .scaleAspectFit

        /// Layout Views

        // Title label layout
        titleLabel.autoPinWidthToSuperview(withMargin: ScaleFromIPhone5To7Plus(16, 24))
        titleLabel.autoPinEdge(toSuperviewEdge: .top)

        // Body label layout
        bodyLabel.autoPinWidthToSuperview(withMargin: bodyMargin)
        bodyLabel.sizeToFit()

        // Image layout
        imageView.autoPinWidthToSuperview()
        imageView.autoSetDimension(.height, toSize: ScaleFromIPhone5To7Plus(200, 280))
        imageView.autoPinEdge(.top, to: .bottom, of: titleLabel, withOffset: ScaleFromIPhone5To7Plus(24, 32))
        imageView.autoPinEdge(.bottom, to: .top, of: bodyLabel, withOffset: -ScaleFromIPhone5To7Plus(18, 28))
    }
}

func setPageControlAppearance() {
    if #available(iOS 9.0, *) {
        let pageControl = UIPageControl.appearance(whenContainedInInstancesOf: [UIPageViewController.self])
        pageControl.pageIndicatorTintColor = UIColor.lightGray
        pageControl.currentPageIndicatorTintColor = UIColor.white
    } else {
        // iOS8 won't see the page controls =(
    }
}

class ExperienceUpgradesPageViewController: OWSViewController, UIPageViewControllerDataSource {

    let TAG = "[ExperienceUpgradeViewController]"

    private let experienceUpgrades: [ExperienceUpgrade]
    private var allViewControllers = [UIViewController]()
    private var viewControllerIndexes = [UIViewController: Int]()

    let pageViewController: UIPageViewController

    // MARK: - Initializers

    required init(experienceUpgrades: [ExperienceUpgrade]) {
        self.experienceUpgrades = experienceUpgrades

        setPageControlAppearance()
        self.pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation:.horizontal, options: nil)
        super.init(nibName: nil, bundle: nil)
        self.pageViewController.dataSource = self

        experienceUpgrades.forEach { addViewController(experienceUpgrade: $0) }
    }

    @available(*, unavailable, message:"unavailable, use initWithExperienceUpgrade instead")
    required init?(coder aDecoder: NSCoder) {
        assert(false)
        // This should never happen, but so as not to explode we give some bogus data
        self.experienceUpgrades = [ExperienceUpgrade()]
        self.pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation:.horizontal, options: nil)
        super.init(coder: aDecoder)
        self.pageViewController.dataSource = self
    }

    // MARK: - View lifecycle

    override func viewDidLoad() {
        guard let firstViewController = allViewControllers.first else {
            owsFail("\(TAG) no pages to show.")
            dismiss(animated: true)
            return
        }

        addDismissGesture()
        self.pageViewController.setViewControllers([ firstViewController ], direction: .forward, animated: false, completion: nil)
    }

    override func loadView() {
        self.view = UIView()
        view.backgroundColor = UIColor.white

        //// Create Views

        // Header Background
        let headerBackgroundView = UIView()
        view.addSubview(headerBackgroundView)
        headerBackgroundView.backgroundColor = UIColor.ows_materialBlue()

        // Footer Background

        let footerBackgroundView = UIView()
        view.addSubview(footerBackgroundView)
        footerBackgroundView.backgroundColor = UIColor.ows_materialBlue()

        // Dismiss button
        let dismissButton = UIButton()
        view.addSubview(dismissButton)
        dismissButton.setTitle(CommonStrings.dismissButton, for: .normal)
        dismissButton.setTitleColor(UIColor.white, for: .normal)
        dismissButton.isUserInteractionEnabled = true
        dismissButton.addTarget(self, action:#selector(didTapDismissButton), for: .touchUpInside)
        dismissButton.titleLabel?.font = UIFont.ows_mediumFont(withSize: ScaleFromIPhone5(20))
        let dismissInsetValue: CGFloat = ScaleFromIPhone5(10)
        dismissButton.contentEdgeInsets = UIEdgeInsets(top: dismissInsetValue, left: dismissInsetValue, bottom: dismissInsetValue, right: dismissInsetValue)

        guard let carouselView = self.pageViewController.view else {
            Logger.error("\(TAG) carousel view was unexpectedly nil")
            return
        }

        self.view.addSubview(carouselView)

        //// Layout Views

        // Header Background layout
        headerBackgroundView.autoPinWidthToSuperview()
        headerBackgroundView.autoPinEdge(toSuperviewEdge: .top)
        headerBackgroundView.autoSetDimension(.height, toSize: ScaleFromIPhone5(80))

        // Footer Background layout
        footerBackgroundView.autoPinWidthToSuperview()
        footerBackgroundView.autoPinEdge(toSuperviewEdge: .bottom)
        footerBackgroundView.autoSetDimension(.height, toSize: ScaleFromIPhone5(95))

        // Dismiss button layout
        dismissButton.autoHCenterInSuperview()
        dismissButton.autoPinEdge(toSuperviewEdge: .bottom, withInset: ScaleFromIPhone5(10))

        // Carousel View layout
        carouselView.autoPinWidthToSuperview()
        // negative inset so as to overlay the header text in the carousel view with the header background which
        // lives outside of the carousel. We do this so that the user can't bounce past the page view controllers
        // width limits, exposing the edge of the header.
        carouselView.autoPinEdge(.top, to: .bottom, of: headerBackgroundView, withOffset: ScaleFromIPhone5(-35))
        carouselView.autoPinEdge(.bottom, to: .top, of: dismissButton, withOffset: ScaleFromIPhone5(-10))
    }

    private func addDismissGesture() {
        let swipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(handleDismissGesture))
        swipeGesture.direction = .down
        view.addGestureRecognizer(swipeGesture)
    }

    // MARK: - UIPageViewControllerDataSource

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        Logger.debug("\(TAG) in \(#function)")
        guard let currentIndex = self.viewControllerIndexes[viewController] else {
            owsFail("\(TAG) unknown view controller: \(viewController)")
            return nil
        }

        if currentIndex + 1 == allViewControllers.count {
            // already at last view controller
            return nil
        }

        return allViewControllers[currentIndex + 1]
    }

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        Logger.debug("\(TAG) in \(#function)")
        guard let currentIndex = self.viewControllerIndexes[viewController] else {
            owsFail("\(TAG) unknown view controller: \(viewController)")
            return nil
        }

        if currentIndex <= 0 {
            // already at first view controller
            return nil
        }

        return allViewControllers[currentIndex - 1]
    }

    public func presentationCount(for pageViewController: UIPageViewController) -> Int {
        // don't show a page indicator if there's only one page.
        return allViewControllers.count == 1 ? 0 : allViewControllers.count
    }

    public func presentationIndex(for pageViewController: UIPageViewController) -> Int {
        guard let currentViewController = pageViewController.viewControllers?.first else {
            Logger.error("\(TAG) unexpectedly empty view controllers.")
            return 0
        }

        guard let currentIndex = self.viewControllerIndexes[currentViewController] else {
            Logger.error("\(TAG) unknown view controller: \(currentViewController)")
            return 0
        }

        return currentIndex
    }

    public func addViewController(experienceUpgrade: ExperienceUpgrade) {
        guard let identifier = ExperienceUpgradeId(rawValue: experienceUpgrade.uniqueId) else {
            owsFail("\(TAG) unknown experience upgrade. skipping")
            return
        }

        let viewController: ExperienceUpgradeViewController = {
            switch identifier {
            case .callKit:
                return CallKitExperienceUpgradeViewController(experienceUpgrade: experienceUpgrade, experienceUpgradesPageViewController: self)
            default:
                return ExperienceUpgradeViewController(experienceUpgrade: experienceUpgrade, experienceUpgradesPageViewController: self)
            }
        }()

        let count = allViewControllers.count
        viewControllerIndexes[viewController] = count
        allViewControllers.append(viewController)
    }

    func didTapDismissButton(sender: UIButton) {
        Logger.debug("\(TAG) in \(#function)")
        self.dismiss(animated: true)
    }

    func handleDismissGesture(sender: AnyObject) {
        Logger.debug("\(TAG) in \(#function)")
        self.dismiss(animated: true)
    }
}
