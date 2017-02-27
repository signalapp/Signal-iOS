//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

class ExperienceUpgradeViewController: UIViewController, UIScrollViewDelegate {
    let TAG = "[ExperienceUpgradeViewController]"

    private let experienceUpgrades: [ExperienceUpgrade]

    private var nextButton: UIButton!
    private var previousButton: UIButton!

    // MARK: - Initializers
    required init(experienceUpgrades: [ExperienceUpgrade]) {
        self.experienceUpgrades = experienceUpgrades
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable, message:"unavailable, use initWithExperienceUpgrade instead")
    required init?(coder aDecoder: NSCoder) {
        assert(false)
        // This should never happen, but so as not to explode we give some bogus data
        self.experienceUpgrades = [ExperienceUpgrade()]
        super.init(coder: aDecoder)
    }

    // MARK: - View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        addDismissGesture()
        showCurrentSlide()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Avoid any possible vertical scrolling, which feels weird for carousel which should only swipe left/right
        // if our carousel content is properly sized to be <= the carousel height. When written this wasn't be an issue, 
        // but it would be easy to introduce a small layout issue in the future which oversizes the content.
        self.carouselView.contentSize = CGSize(width: self.carouselView.contentSize.width, // use actual content width
                                               height: self.carouselView.frame.size.height) // but crop height to frame
    }

    override func loadView() {
        self.view = UIView()
        view.backgroundColor = UIColor.white

        let splashView = UIView()
        view.addSubview(splashView)
        splashView.autoPinEdgesToSuperviewEdges()

        let carouselView = UIScrollView()
        carouselView.delegate = self
        self.carouselView = carouselView
        splashView.addSubview(carouselView)
        self.carouselView.isPagingEnabled = true
        carouselView.showsHorizontalScrollIndicator = false
        carouselView.showsVerticalScrollIndicator = false
        carouselView.bounces = false

        // CarouselView layout
        carouselView.autoPinEdge(toSuperviewEdge: .top)
        carouselView.autoPinEdge(toSuperviewEdge: .left)
        carouselView.autoPinEdge(toSuperviewEdge: .right)

        // Build slides for carousel
        var previousSlideView: UIView?
        for experienceUpgrade in experienceUpgrades {
            let slideView = buildSlideView(header: experienceUpgrade.title, body: experienceUpgrade.body, image: experienceUpgrade.image)
            carouselView.addSubview(slideView)

            slideView.autoPinEdge(toSuperviewEdge: .top, withInset: ScaleFromIPhone5(10))
            slideView.autoPinEdge(toSuperviewEdge: .bottom)
            slideView.autoMatch(.width, to: .width, of: carouselView)

            // pin first slide to the superview
            if previousSlideView == nil {
               slideView.autoPinEdge(toSuperviewEdge: .left)
            } else {
                // pin any subsequent slide to the preveding slide
               slideView.autoPinEdge(.left, to: .right, of: previousSlideView!)
            }

            previousSlideView = slideView
        }
        // we should never be presenting a blank slideshow.
        // but if so, we don't want to crash in prod.
        assert(previousSlideView != nil)

        // ping the last slide to the superview right.
        previousSlideView?.autoPinEdge(toSuperviewEdge: .right)

        // Previous button

        // Lightening the arrows' color to balance their heavy stroke with the thinner text on the page.
        let arrowButtonColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        let previousButton = UIButton()
        self.previousButton = previousButton
        splashView.addSubview(previousButton)
        previousButton.isUserInteractionEnabled = true
        previousButton.setTitleColor(arrowButtonColor, for: .normal)
        previousButton.accessibilityLabel = NSLocalizedString("UPGRADE_CAROUSEL_PREVIOUS_BUTTON", comment: "accessibility label for arrow in slideshow")
        previousButton.setTitle("‹", for: .normal)
        previousButton.titleLabel?.font = UIFont.ows_mediumFont(withSize: ScaleFromIPhone5To7Plus(24, 48))
        previousButton.addTarget(self, action:#selector(didTapPreviousButton), for: .touchUpInside)

        // Previous button layout
        previousButton.autoPinEdge(toSuperviewEdge: .left)
        let arrowButtonInset = ScaleFromIPhone5(200)
        previousButton.autoPinEdge(toSuperviewEdge: .top, withInset: arrowButtonInset)

        // Next button
        let nextButton = UIButton()
        self.nextButton = nextButton
        splashView.addSubview(nextButton)
        nextButton.isUserInteractionEnabled = true
        nextButton.setTitleColor(arrowButtonColor, for: .normal)
        nextButton.accessibilityLabel = NSLocalizedString("UPGRADE_CAROUSEL_NEXT_BUTTON", comment: "accessibility label for arrow in slideshow")
        nextButton.setTitle("›", for: .normal)
        nextButton.titleLabel?.font = UIFont.ows_mediumFont(withSize: ScaleFromIPhone5To7Plus(24, 48))
        nextButton.addTarget(self, action:#selector(didTapNextButton), for: .touchUpInside)

        // Next button layout
        nextButton.autoPinEdge(toSuperviewEdge: .right)
        nextButton.autoPinEdge(toSuperviewEdge: .top, withInset: arrowButtonInset)

        // Dismiss button
        let dismissButton = UIButton()
        splashView.addSubview(dismissButton)
        dismissButton.setTitle(NSLocalizedString("DISMISS_BUTTON_TEXT", comment: ""), for: .normal)
        dismissButton.setTitleColor(UIColor.ows_materialBlue(), for: .normal)
        dismissButton.isUserInteractionEnabled = true
        dismissButton.addTarget(self, action:#selector(didTapDismissButton), for: .touchUpInside)

        // Dismiss button layout
        dismissButton.autoPinWidthToSuperview()
        dismissButton.autoPinEdge(.top, to: .bottom, of: carouselView, withOffset: ScaleFromIPhone5(16))
        dismissButton.autoPinEdge(toSuperviewEdge: .bottom, withInset: ScaleFromIPhone5(32))
    }

    private func buildSlideView(header: String, body: String, image: UIImage?) -> UIView {
        Logger.debug("\(TAG) in \(#function)")

        let containerView = UIView()
        let headerView = UIView()
        containerView.addSubview(headerView)
        headerView.backgroundColor = UIColor.ows_materialBlue()

        headerView.autoPinWidthToSuperview()
        headerView.autoPinEdge(toSuperviewEdge: .top, withInset: -16)
        headerView.autoSetDimension(.height, toSize: ScaleFromIPhone5(100))

        // Title label
        let titleLabel = UILabel()
        headerView.addSubview(titleLabel)
        titleLabel.text = header
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.ows_regularFont(withSize: ScaleFromIPhone5To7Plus(26, 32))
        titleLabel.textColor = UIColor.white
        titleLabel.minimumScaleFactor = 0.5
        titleLabel.adjustsFontSizeToFitWidth = true;

        // Title label layout
        titleLabel.autoPinWidthToSuperview(withMargin: ScaleFromIPhone5To7Plus(16, 24))
        titleLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: ScaleFromIPhone5To7Plus(24, 32))

        let slideView = UIView()
        containerView.addSubview(slideView)

        let containerPadding = ScaleFromIPhone5To7Plus(12, 24)
        slideView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: containerPadding, left: containerPadding, bottom: containerPadding, right: containerPadding))

        // Body label
        let bodyLabel = UILabel()
        slideView.addSubview(bodyLabel)
        bodyLabel.text = body
        bodyLabel.font = UIFont.ows_lightFont(withSize: ScaleFromIPhone5To7Plus(18, 22))
        bodyLabel.textColor = UIColor.black
        bodyLabel.numberOfLines = 0
        bodyLabel.textAlignment = .center

        // Body label layout
        bodyLabel.autoPinWidthToSuperview()
        bodyLabel.sizeToFit()

        // Image
        let imageView = UIImageView(image: image)
        slideView.addSubview(imageView)
        imageView.contentMode = .scaleAspectFit

        // Image layout
        imageView.autoPinWidthToSuperview()
        imageView.autoSetDimension(.height, toSize: ScaleFromIPhone5To7Plus(200, 280))
        imageView.autoPinEdge(.top, to: .bottom, of: headerView, withOffset: ScaleFromIPhone5To7Plus(24, 32))
        imageView.autoPinEdge(.bottom, to: .top, of: bodyLabel, withOffset: -ScaleFromIPhone5To7Plus(24, 32))
        
        return containerView
    }

    private func addDismissGesture() {
        let swipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(handleDismissGesture))
        swipeGesture.direction = .down
        view.addGestureRecognizer(swipeGesture)
    }

    // MARK: Carousel

    private var carouselView: UIScrollView!
    private var currentSlideIndex = 0

    private func showNextSlide() {
        guard hasNextSlide() else {
            Logger.debug("\(TAG) no next slide to show")
            return;
        }

        currentSlideIndex += 1
        showCurrentSlide()
    }

    private func showPreviousSlide() {
        guard hasPreviousSlide() else {
            Logger.debug("\(TAG) no previous slide to show")
            return
        }

        currentSlideIndex -= 1
        showCurrentSlide()
    }

    private func hasPreviousSlide() -> Bool {
        return currentSlideIndex > 0
    }

    private func hasNextSlide() -> Bool {
        return currentSlideIndex < experienceUpgrades.count - 1
    }

    private func updateSlideControls() {
        self.nextButton.isHidden = !hasNextSlide()
        self.previousButton.isHidden = !hasPreviousSlide()
    }

    private func showCurrentSlide() {
        Logger.debug("\(TAG) showing slide: \(currentSlideIndex)")
        updateSlideControls()

        // update the scroll view to the appropriate page
        let bounds = carouselView.bounds

        let point = CGPoint(x: bounds.width * CGFloat(currentSlideIndex), y: 0)
        let pageBounds = CGRect(origin: point, size: bounds.size)

        carouselView.scrollRectToVisible(pageBounds, animated: true)
    }

    // MARK: - Actions

    func didTapNextButton(sender: UIButton) {
        Logger.debug("\(TAG) in \(#function)")
        showNextSlide()
    }

    func didTapPreviousButton(sender: UIButton) {
        Logger.debug("\(TAG) in \(#function)")
        showPreviousSlide()
    }

    func didTapDismissButton(sender: UIButton) {
        Logger.debug("\(TAG) in \(#function)")
        self.dismiss(animated: true)
    }

    func handleDismissGesture(sender: AnyObject) {
        Logger.debug("\(TAG) in \(#function)")
        self.dismiss(animated: true)
    }

    // MARK: - ScrollViewDelegate

    // Update the slider controls to reflect which page we think we'll end up on.
    // we use WillEndDragging instead of (e.g.) didEndDecelerating, else the switch feels too late.
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let pageWidth = scrollView.frame.size.width
        let page = floor(targetContentOffset.pointee.x / pageWidth)
        currentSlideIndex = Int(page)
        updateSlideControls()
    }
}
