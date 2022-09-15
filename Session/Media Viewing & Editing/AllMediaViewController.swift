// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import QuartzCore
import GRDB
import DifferenceKit
import SessionUIKit
import SignalUtilitiesKit

public class AllMediaViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private let pageVC = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
    private var pages: [UIViewController] = []
    private var targetVCIndex: Int?
    
    // MARK: Components
    private lazy var tabBar: TabBar = {
        let tabs = [
            TabBar.Tab(title: MediaStrings.media) { [weak self] in
                guard let self = self else { return }
                self.pageVC.setViewControllers([ self.pages[0] ], direction: .forward, animated: false, completion: nil)
                self.updateSelectButton(updatedData: self.mediaTitleViewController.viewModel.galleryData, inBatchSelectMode: self.mediaTitleViewController.isInBatchSelectMode)
            },
            TabBar.Tab(title: MediaStrings.document) { [weak self] in
                guard let self = self else { return }
                self.pageVC.setViewControllers([ self.pages[1] ], direction: .forward, animated: false, completion: nil)
                self.endSelectMode()
                self.navigationItem.rightBarButtonItem = nil
            }
        ]
        return TabBar(tabs: tabs)
    }()
    
    private var mediaTitleViewController: MediaTileViewController
    private var documentTitleViewController: DocumentTileViewController
    
    init(mediaTitleViewController: MediaTileViewController, documentTitleViewController: DocumentTileViewController) {
        self.mediaTitleViewController = mediaTitleViewController
        self.documentTitleViewController = documentTitleViewController
        
        super.init(nibName: nil, bundle: nil)
        
        self.mediaTitleViewController.delegate = self
        self.documentTitleViewController.delegate = self
        
        addChild(self.mediaTitleViewController)
        addChild(self.documentTitleViewController)
    }
    
    required init?(coder: NSCoder) {
        notImplemented()
    }
    
    // MARK: Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        view.themeBackgroundColor = .backgroundPrimary
        
        // Add a custom back button if this is the only view controller
        if self.navigationController?.viewControllers.first == self {
            let backButton = OWSViewController.createOWSBackButton(withTarget: self, selector: #selector(didPressDismissButton))
            self.navigationItem.leftBarButtonItem = backButton
        }
        
        ViewControllerUtilities.setUpDefaultSessionStyle(
            for: self,
            title: MediaStrings.allMedia,
            hasCustomBackButton: false
        )
        
        // Set up page VC
        pages = [ mediaTitleViewController, documentTitleViewController ]
        pageVC.dataSource = self
        pageVC.delegate = self
        pageVC.setViewControllers([ mediaTitleViewController ], direction: .forward, animated: false, completion: nil)
        addChild(pageVC)
        
        // Set up tab bar
        view.addSubview(tabBar)
        tabBar.pin([ UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing, UIView.VerticalEdge.top ], to: view)
        // Set up page VC constraints
        let pageVCView = pageVC.view!
        view.addSubview(pageVCView)
        pageVCView.pin([ UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing, UIView.VerticalEdge.bottom ], to: view)
        pageVCView.pin(.top, to: .bottom, of: tabBar)
    }
    
    // MARK: General
    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let index = pages.firstIndex(of: viewController), index != 0 else { return nil }
        return pages[index - 1]
    }
    
    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let index = pages.firstIndex(of: viewController), index != (pages.count - 1) else { return nil }
        return pages[index + 1]
    }
    
    // MARK: Updating
    public func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        guard let targetVC = pendingViewControllers.first, let index = pages.firstIndex(of: targetVC) else { return }
        targetVCIndex = index
    }
    
    public func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating isFinished: Bool, previousViewControllers: [UIViewController], transitionCompleted isCompleted: Bool) {
        guard isCompleted, let index = targetVCIndex else { return }
        tabBar.selectTab(at: index)
    }
    
    // MARK: Interaction
    @objc public func didPressDismissButton() {
        dismiss(animated: true, completion: nil)
    }
    
    // MARK: Batch Selection
    @objc func didTapSelect(_ sender: Any) {
        self.mediaTitleViewController.didTapSelect(sender)

        // Don't allow the user to leave mid-selection, so they realized they have
        // to cancel (lose) their selection if they leave.
        self.navigationItem.hidesBackButton = true
    }

    @objc func didCancelSelect(_ sender: Any) {
        endSelectMode()
    }

    func endSelectMode() {
        self.mediaTitleViewController.endSelectMode()
        self.navigationItem.hidesBackButton = false
    }
}

// MARK: - UIDocumentInteractionControllerDelegate

extension AllMediaViewController: UIDocumentInteractionControllerDelegate {
    public func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
}

// MARK: - DocumentTitleViewControllerDelegate

extension AllMediaViewController: DocumentTileViewControllerDelegate {
    public func share(fileUrl: URL) {
        let shareVC = UIActivityViewController(activityItems: [ fileUrl ], applicationActivities: nil)
        
        if UIDevice.current.isIPad {
            shareVC.excludedActivityTypes = []
            shareVC.popoverPresentationController?.permittedArrowDirections = []
            shareVC.popoverPresentationController?.sourceView = self.view
            shareVC.popoverPresentationController?.sourceRect = self.view.bounds
        }
        
        navigationController?.present(shareVC, animated: true, completion: nil)
    }
    
    public func preview(fileUrl: URL) {
        let interactionController: UIDocumentInteractionController = UIDocumentInteractionController(url: fileUrl)
        interactionController.delegate = self
        interactionController.presentPreview(animated: true)
    }
}

// MARK: - DocumentTitleViewControllerDelegate

extension AllMediaViewController: MediaTileViewControllerDelegate {
    public func presentdetailViewController(_ detailViewController: UIViewController, animated: Bool) {
        self.present(detailViewController, animated: animated)
    }
    
    public func updateSelectButton(updatedData: [MediaGalleryViewModel.SectionModel], inBatchSelectMode: Bool) {
        guard !updatedData.isEmpty else {
            self.navigationItem.rightBarButtonItem = nil
            return
        }
        
        if inBatchSelectMode {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(didCancelSelect)
            )
        }
        else {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "BUTTON_SELECT".localized(),
                style: .plain,
                target: self,
                action: #selector(didTapSelect)
            )
        }
    }
}

// MARK: - UIViewControllerTransitioningDelegate

extension AllMediaViewController: UIViewControllerTransitioningDelegate {
    public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return self.mediaTitleViewController.animationController(forPresented: presented, presenting: presenting, source: source)
    }

    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return self.mediaTitleViewController.animationController(forDismissed: dismissed)
    }
}


// MARK: - MediaPresentationContextProvider

extension AllMediaViewController: MediaPresentationContextProvider {
    func mediaPresentationContext(mediaItem: Media, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        return self.mediaTitleViewController.mediaPresentationContext(mediaItem: mediaItem, in: coordinateSpace)
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return self.mediaTitleViewController.snapshotOverlayView(in: coordinateSpace)
    }
}

