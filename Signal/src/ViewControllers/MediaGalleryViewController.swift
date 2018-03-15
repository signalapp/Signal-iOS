//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

public struct MediaGalleryItem: Equatable {
    let message: TSMessage
    let attachmentStream: TSAttachmentStream
    let logTag = "[MediaGalleryItem]"

    var isVideo: Bool {
        return attachmentStream.isVideo()
    }

    var image: UIImage {
        guard let image = attachmentStream.image() else {
            owsFail("\(logTag) in \(#function) unexpectedly unable to build attachment image")
            return UIImage()
        }

        return image
    }

    // MARK: Equatable

    public static func == (lhs: MediaGalleryItem, rhs: MediaGalleryItem) -> Bool {
        return lhs.message.uniqueId == rhs.message.uniqueId
    }
}

public struct GalleryDate: Hashable {
    let year: Int
    let month: Int

    init(message: TSMessage) {
        let date = message.dateForSorting()

        self.year = Calendar.current.component(.year, from: date)
        self.month = Calendar.current.component(.month, from: date)
    }

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    private var isThisMonth: Bool {
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        let month = Calendar.current.component(.month, from: now)
        let thisMonth = GalleryDate(year: year, month: month)

        return self == thisMonth
    }

    public var date: Date {
        var components = DateComponents()
        components.month = self.month
        components.year = self.year

        return Calendar.current.date(from: components)!
    }

    private var isThisYear: Bool {
        let now = Date()
        let thisYear = Calendar.current.component(.year, from: now)

        return self.year == thisYear
    }

    static let thisYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"

        return formatter
    }()

    static let olderFormatter: DateFormatter = {
        let formatter = DateFormatter()

        // FIXME localize for RTL, or is there a built in way to do this?
        formatter.dateFormat = "MMMM yyyy"

        return formatter
    }()

    var localizedString: String {
        if isThisMonth {
            return NSLocalizedString("MEDIA_GALLERY_THIS_MONTH_HEADER", comment: "Section header in media gallery collection view")
        } else if isThisYear {
            return type(of: self).thisYearFormatter.string(from: self.date)
        } else {
            return type(of: self).olderFormatter.string(from: self.date)
        }
    }

    // MARK: Hashable

    public var hashValue: Int {
        return month.hashValue ^ year.hashValue
    }

    // MARK: Equatable

    public static func == (lhs: GalleryDate, rhs: GalleryDate) -> Bool {
        return lhs.month == rhs.month && lhs.year == rhs.year
    }
}

protocol MediaGalleryDataSource: class {
    var galleryItems: [MediaGalleryItem] { get }
    var galleryItemCount: Int { get }

    var sections: [GalleryDate: [MediaGalleryItem]] { get }
    var sectionDates: [GalleryDate] { get }

    func galleryItem(before currentItem: MediaGalleryItem) -> MediaGalleryItem?
    func galleryItem(after currentItem: MediaGalleryItem) -> MediaGalleryItem?

    func showAllMedia()

    // TODO this doesn't seem very "data-source"
    func dismissSelf(animated isAnimated: Bool, completion: (() -> Void)?)
}

class MediaGalleryViewController: UINavigationController, MediaGalleryDataSource, MediaTileViewControllerDelegate {

    private var pageViewController: MediaPageViewController?
    //    private let tileViewController: MediaTileViewController
    //
    private let uiDatabaseConnection: YapDatabaseConnection
    private let mediaGalleryFinder: OWSMediaGalleryFinder

    // FIXME get rid of `!`
    private var initialGalleryItem: MediaGalleryItem!
    private let thread: TSThread
    private let includeGallery: Bool

    convenience init(thread: TSThread, mediaMessage: TSMessage) {
        self.init(thread: thread, mediaMessage: mediaMessage, includeGallery: true)
    }

    init(thread: TSThread, mediaMessage: TSMessage, includeGallery: Bool) {
        self.thread = thread
        self.includeGallery = includeGallery

        self.uiDatabaseConnection = OWSPrimaryStorage.shared().newDatabaseConnection()
        self.mediaGalleryFinder = OWSMediaGalleryFinder()

        super.init(nibName: nil, bundle: nil)

        uiDatabaseConnection.beginLongLivedReadTransaction()

        uiDatabaseConnection.read { transaction in
            self.initialGalleryItem = self.buildGalleryItem(message: mediaMessage, transaction: transaction)!
        }

        updateGalleryItems(thread: thread)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: View Lifecyle

    override func viewDidLoad() {
        super.viewDidLoad()

        // UIModalPresentationCustom retains the current view context behind our VC, allowing us to manually
        // animate in our view, over the existing context, similar to a cross disolve, but allowing us to have
        // more fine grained control
        self.modalPresentationStyle = .custom
        self.navigationBar.barTintColor = UIColor.ows_materialBlue
        self.navigationBar.isTranslucent = false
        self.navigationBar.isOpaque = true

        // The presentationView is only used during present/dismiss animations.
        // It's a static image of the media content.
        let presentationView = UIImageView()
        self.presentationView = presentationView
        self.view.addSubview(presentationView)
        presentationView.isHidden = true
        presentationView.clipsToBounds = true
        presentationView.layer.allowsEdgeAntialiasing = true
        presentationView.layer.minificationFilter = kCAFilterTrilinear
        presentationView.layer.magnificationFilter = kCAFilterTrilinear
        presentationView.contentMode = .scaleAspectFit
    }

    // MARK: Present/Dismiss

    private var replacingView: UIView?
    private var presentationView: UIImageView!
    private var presentationViewConstraints: [NSLayoutConstraint] = []

    // TODO rename to replacingOriginRect
    private var originRect: CGRect?

    public func presentDetailView(fromViewController: UIViewController, replacingView: UIView) {

        let pageViewController = MediaPageViewController(initialItem: self.initialGalleryItem, mediaGalleryDataSource: self, uiDatabaseConnection: self.uiDatabaseConnection, includeGallery: self.includeGallery)

        self.pageViewController = pageViewController
        self.setViewControllers([pageViewController], animated: false)

        self.replacingView = replacingView

        let convertedRect: CGRect = replacingView.convert(replacingView.bounds, to: UIApplication.shared.keyWindow)
        self.originRect = convertedRect

        // loadView hasn't necessarily been called yet.
        self.loadViewIfNeeded()
        self.presentationView.image = self.initialGalleryItem.image
        self.applyInitialMediaViewConstraints()

        // We want to animate the tapped media from it's position in the previous VC
        // to it's resting place in the center of this view controller.
        //
        // Rather than animating the actual media view in place, we animate the presentationView, which is a static
        // image of the media content. Animating the actual media view is problematic for a couple reasons:
        // 1. The media view ultimately lives in a zoomable scrollView. Getting both original positioning and the final positioning
        //    correct, involves manipulating the zoomScale and position simultaneously, which results in non-linear movement,
        //    especially noticeable on high resolution images.
        // 2. For Video views, the AVPlayerLayer content does not scale with the presentation animation. So you instead get a full scale
        //    video, wherein only the cropping is animated.
        // Using a simple image view allows us to address both these problems relatively easily.
        self.view.alpha = 0.0

        guard let detailView = pageViewController.view else {
            owsFail("\(logTag) in \(#function) detailView was unexpectedly nil")
            return
        }

        detailView.isHidden = true

        self.presentationView.isHidden = false
        self.presentationView.layer.cornerRadius = OWSMessageCellCornerRadius

        fromViewController.present(self, animated: false) {

            // 1. Fade in the entire view.
            UIView.animate(withDuration: 0.1) {
                self.replacingView?.alpha = 0.0
                self.view.alpha = 1.0
            }

            self.presentationView.superview?.layoutIfNeeded()
            self.applyFinalMediaViewConstraints()

            // 2. Animate imageView from it's initial position, which should match where it was
            // in the presenting view to it's final position, front and center in this view. This
            // animation duration intentionally overlaps the previous
            UIView.animate(withDuration: 0.2,
                           delay: 0.08,
                           options: .curveEaseOut,
                           animations: {

                            self.presentationView.layer.cornerRadius = 0
                            self.presentationView.superview?.layoutIfNeeded()

                            self.view.backgroundColor = UIColor.white
            },
                           completion: { (_: Bool) in
                            // At this point our presentation view should be overlayed perfectly
                            // with our media view. Swapping them out should be imperceptible.
                            detailView.isHidden = false
                            self.presentationView.isHidden = true

                            self.view.isUserInteractionEnabled = true

                            guard let currentPage = self.currentPage else {
                                owsFail("\(self.logTag) in \(#function) currentPage was unexpectedly nil")
                                self.dismissSelf(animated: false, completion: nil)
                                return
                            }

                            if currentPage.isVideo {
                                currentPage.viewController.playVideo()
                            }
            })
        }
    }

    private var currentPage: MediaGalleryPage? {
        return self.pageViewController!.currentPage
    }

    public func dismissSelf(animated isAnimated: Bool, completion: (() -> Void)? = nil) {
        self.view.isUserInteractionEnabled = false
        UIApplication.shared.isStatusBarHidden = false

        guard let currentPage = self.currentPage else {
            owsFail("\(logTag) in \(#function) currentItem was unexpectedly nil")
            self.presentingViewController?.dismiss(animated: false, completion: completion)
            return
        }

        guard let detailView = pageViewController?.view else {
            owsFail("\(logTag) in \(#function) detailView was unexpectedly nil")
            self.presentingViewController?.dismiss(animated: false, completion: completion)
            return
        }
        detailView.isHidden = true
        self.presentationView.isHidden = false

        // Move the presentationView back to it's initial position, i.e. where
        // it sits on the screen in the conversation view.
        let changedItems = currentPage.galleryItem != initialGalleryItem
        if changedItems {
            self.presentationView.image = currentPage.image
            self.applyOffscreenMediaViewConstraints()
        } else {
            self.applyInitialMediaViewConstraints()
        }

        if isAnimated {
            UIView.animate(withDuration: changedItems ? 0.25 : 0.18,
                           delay: 0.0,
                           options:.curveEaseOut,
                           animations: {
                            self.presentationView.superview?.layoutIfNeeded()

                            // In case user has hidden bars, which changes background to black.
                            self.view.backgroundColor = UIColor.white

                            if changedItems {
                                self.presentationView.alpha = 0
                            } else {
                                self.presentationView.layer.cornerRadius = OWSMessageCellCornerRadius
                            }
            },
                           completion:nil)

            // This intentionally overlaps the previous animation a bit
            UIView.animate(withDuration: 0.1,
                           delay: 0.15,
                           options: .curveEaseInOut,
                           animations: {
                            guard let replacingView = self.replacingView else {
                                owsFail("\(self.logTag) in \(#function) replacingView was unexpectedly nil")
                                self.presentingViewController?.dismiss(animated: false, completion: completion)
                                return
                            }
                            replacingView.alpha = 1.0

                            // fade out content and toolbars
                            self.navigationController?.view.alpha = 0.0
            },
                           completion: { (_: Bool) in
                            self.presentingViewController?.dismiss(animated: false, completion: completion)
            })
        } else {
            guard let replacingView = self.replacingView else {
                owsFail("\(self.logTag) in \(#function) replacingView was unexpectedly nil")
                self.presentingViewController?.dismiss(animated: false, completion: completion)
                return
            }
            replacingView.alpha = 1.0
            self.presentingViewController?.dismiss(animated: false, completion: completion)
        }
    }

    private func applyInitialMediaViewConstraints() {
        if (self.presentationViewConstraints.count > 0) {
            NSLayoutConstraint.deactivate(self.presentationViewConstraints)
            self.presentationViewConstraints = []
        }

        guard let originRect = self.originRect else {
            owsFail("\(logTag) in \(#function) originRect was unexpectedly nil")
            return
        }

        guard let presentationSuperview = self.presentationView.superview else {
            owsFail("\(logTag) in \(#function) presentationView.superview was unexpectedly nil")
            return
        }

        let convertedRect: CGRect = presentationSuperview.convert(originRect, from: UIApplication.shared.keyWindow)

        self.presentationViewConstraints += self.presentationView.autoSetDimensions(to: convertedRect.size)
        self.presentationViewConstraints += [
            self.presentationView.autoPinEdge(toSuperviewEdge: .top, withInset:convertedRect.origin.y),
            self.presentationView.autoPinEdge(toSuperviewEdge: .left, withInset:convertedRect.origin.x)
        ]
    }

    private func applyFinalMediaViewConstraints() {
        if (self.presentationViewConstraints.count > 0) {
            NSLayoutConstraint.deactivate(self.presentationViewConstraints)
            self.presentationViewConstraints = []
        }

        self.presentationViewConstraints = [
            self.presentationView.autoPinEdge(toSuperviewEdge: .leading),
            self.presentationView.autoPinEdge(toSuperviewEdge: .top),
            self.presentationView.autoPinEdge(toSuperviewEdge: .trailing),
            self.presentationView.autoPinEdge(toSuperviewEdge: .bottom)
        ]
    }

    private func applyOffscreenMediaViewConstraints() {
        if (self.presentationViewConstraints.count > 0) {
            NSLayoutConstraint.deactivate(self.presentationViewConstraints)
            self.presentationViewConstraints = []
        }

        self.presentationViewConstraints += [
            self.presentationView.autoPinEdge(toSuperviewEdge: .leading),
            self.presentationView.autoPinEdge(toSuperviewEdge: .trailing),
            self.presentationView.autoPinEdge(.top, to: .bottom, of: self.view)
        ]
    }

    // MARK: MediaGalleryDataSource

    func showAllMedia() {
        // TODO fancy animation - zoom media item into it's tile in the all media grid
        let allMediaController = MediaTileViewController(mediaGalleryDataSource: self, uiDatabaseConnection: self.uiDatabaseConnection)
        allMediaController.delegate = self

        self.pushViewController(allMediaController, animated: true)
    }

    var galleryItems: [MediaGalleryItem] = []
    var sections: [GalleryDate: [MediaGalleryItem]] = [:]
    var sectionDates: [GalleryDate] = []

    func buildGalleryItem(message: TSMessage, transaction: YapDatabaseReadTransaction) -> MediaGalleryItem? {
        guard let attachmentStream = message.attachment(with: transaction) as? TSAttachmentStream else {
            owsFail("\(self.logTag) in \(#function) attachment was unexpectedly empty")
            return nil
        }

        return MediaGalleryItem(message: message, attachmentStream: attachmentStream)
    }

    func updateGalleryItems(thread: TSThread) {
        var galleryItems: [MediaGalleryItem] = []
        var sections: [GalleryDate: [MediaGalleryItem]] = [:]
        var sectionDates: [GalleryDate] = []

        self.uiDatabaseConnection.read { transaction in
            self.mediaGalleryFinder.enumerateMediaMessages(with: thread, transaction: transaction) { (message: TSMessage) in

                guard let item: MediaGalleryItem = self.buildGalleryItem(message: message, transaction: transaction) else {
                    owsFail("\(self.logTag) in \(#function) unexpectedly failed to buildGalleryItem")
                    return
                }

                let date = GalleryDate(message: message)

                // TODO do we need to box this for reasonable perf?
                galleryItems.append(item)
                if sections[date] != nil {
                    // TODO do we need to box this for reasonable perf?
                    sections[date]!.append(item)
                } else {
                    sectionDates.append(date)
                    sections[date] = [item]
                }
            }
        }

        self.galleryItems = galleryItems
        self.sections = sections
        self.sectionDates = sectionDates
    }

    // TODO extract to public extension?
    internal func galleryItem(after currentItem: MediaGalleryItem) -> MediaGalleryItem? {
        Logger.debug("\(logTag) in \(#function)")

        guard let currentIndex = galleryItems.index(of: currentItem) else {
            owsFail("currentIndex was unexpectedly nil in \(#function)")
            return nil
        }

        let index: Int = galleryItems.index(after: currentIndex)
        return galleryItems[safe: index]
    }

    internal func galleryItem(before currentItem: MediaGalleryItem) -> MediaGalleryItem? {
        Logger.debug("\(logTag) in \(#function)")

        guard let currentIndex = galleryItems.index(of: currentItem) else {
            owsFail("currentIndex was unexpectedly nil in \(#function)")
            return nil
        }

        let index: Int = galleryItems.index(before: currentIndex)
        return galleryItems[safe: index]
    }

    var galleryItemCount: Int {
        var count: UInt = 0
        self.uiDatabaseConnection.read { (transaction: YapDatabaseReadTransaction) in
            count = self.mediaGalleryFinder.mediaCount(thread: self.thread, transaction: transaction)
        }
        return Int(count)
    }

    // MARK: MediaTileViewControllerDelegate

    func mediaTileViewController(_ viewController: MediaTileViewController, didTapMediaGalleryItem mediaGalleryItem: MediaGalleryItem) {
        self.pageViewController!.currentItem = mediaGalleryItem
        self.popViewController(animated: true)
    }

}
