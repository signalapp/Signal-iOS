//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import Photos
import PromiseKit

protocol ImagePickerGridControllerDelegate: AnyObject {
    func imagePickerDidCompleteSelection(_ imagePicker: ImagePickerGridController)
    func imagePickerDidCancel(_ imagePicker: ImagePickerGridController)

    func imagePicker(_ imagePicker: ImagePickerGridController, isAssetSelected asset: PHAsset) -> Bool
    func imagePicker(_ imagePicker: ImagePickerGridController, didSelectAsset asset: PHAsset, attachmentPromise: Promise<SignalAttachment>)
    func imagePicker(_ imagePicker: ImagePickerGridController, didDeselectAsset asset: PHAsset)

    var isInBatchSelectMode: Bool { get }
    var isPickingAsDocument: Bool { get }
    func imagePickerCanSelectMoreItems(_ imagePicker: ImagePickerGridController) -> Bool
    func imagePickerDidTryToSelectTooMany(_ imagePicker: ImagePickerGridController)
}

class ImagePickerGridController: UICollectionViewController, PhotoLibraryDelegate, PhotoCollectionPickerDelegate {

    weak var delegate: ImagePickerGridControllerDelegate?

    private let library: PhotoLibrary = PhotoLibrary()
    private var photoCollection: PhotoCollection
    private var photoCollectionContents: PhotoCollectionContents
    private let photoMediaSize = PhotoMediaSize()

    var collectionViewFlowLayout: UICollectionViewFlowLayout
    var titleView: TitleView!

    init() {
        collectionViewFlowLayout = type(of: self).buildLayout()
        photoCollection = library.defaultPhotoCollection()
        photoCollectionContents = photoCollection.contents()

        super.init(collectionViewLayout: collectionViewFlowLayout)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle

    override var prefersStatusBarHidden: Bool {
        guard !OWSWindowManager.shared.hasCall else {
            return false
        }

        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        library.add(delegate: self)

        guard let collectionView = collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }
        collectionView.register(PhotoGridViewCell.self, forCellWithReuseIdentifier: PhotoGridViewCell.reuseIdentifier)

        // ensure images at the end of the list can be scrolled above the bottom buttons
        let bottomButtonInset = -1 * SendMediaNavigationController.bottomButtonsCenterOffset + SendMediaNavigationController.bottomButtonWidth / 2
        collectionView.contentInset.bottom = bottomButtonInset + 8
        view.backgroundColor = .ows_gray95

        // The PhotoCaptureVC needs a shadow behind it's cancel button, so we use a custom icon.
        // This VC has a visible navbar so doesn't need the shadow, but because the user can
        // quickly toggle between the Capture and the Picker VC's, we use the same custom "X"
        // icon here rather than the system "stop" icon so that the spacing matches exactly.
        // Otherwise there's a noticable shift in the icon placement.
        if UIDevice.current.isIPad {
            let cancelButton = OWSButton.shadowedCancelButton { [weak self] in
                self?.didPressCancel()
            }
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: cancelButton)
        } else {
            let cancelImage = UIImage(imageLiteralResourceName: "ic_x_with_shadow")
            let cancelButton = UIBarButtonItem(image: cancelImage, style: .plain, target: self, action: #selector(didPressCancel))

            cancelButton.tintColor = .ows_gray05
            navigationItem.leftBarButtonItem = cancelButton
        }

        let titleView = TitleView()
        titleView.delegate = self
        titleView.text = photoCollection.localizedTitle()

        navigationItem.titleView = titleView
        self.titleView = titleView

        collectionView.backgroundColor = .ows_gray95

        let selectionPanGesture = DirectionalPanGestureRecognizer(direction: [.horizontal], target: self, action: #selector(didPanSelection))
        selectionPanGesture.delegate = self
        self.selectionPanGesture = selectionPanGesture
        collectionView.addGestureRecognizer(selectionPanGesture)
    }

    var selectionPanGesture: UIPanGestureRecognizer?
    enum BatchSelectionGestureMode {
        case select, deselect
    }
    var selectionPanGestureMode: BatchSelectionGestureMode = .select

    @objc
    func didPanSelection(_ selectionPanGesture: UIPanGestureRecognizer) {
        guard let collectionView = collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        guard let delegate = delegate else {
            owsFailDebug("delegate was unexpectedly nil")
            return
        }

        guard delegate.isInBatchSelectMode else {
            return
        }

        switch selectionPanGesture.state {
        case .possible:
            break
        case .began:
            collectionView.isUserInteractionEnabled = false
            collectionView.isScrollEnabled = false

            let location = selectionPanGesture.location(in: collectionView)
            guard let indexPath = collectionView.indexPathForItem(at: location) else {
                return
            }
            let asset = photoCollectionContents.asset(at: indexPath.item)
            if delegate.imagePicker(self, isAssetSelected: asset) {
                selectionPanGestureMode = .deselect
            } else {
                selectionPanGestureMode = .select
            }
        case .changed:
            let velocity = selectionPanGesture.velocity(in: view)

            // Bulk selection is a horizontal pan, while scrolling content is a vertical pan.
            // There will be some ambiguity since users gestures are not perfectly cardinal.
            //
            // We try to account for that here.
            //
            // If the `alpha` is too low, the user will inadvertently select items while trying to scroll.
            // If the `alpha` is too high, the user will not be able to easily horizontally select items.
            let alpha: CGFloat = 4.0
            let isDecidedlyHorizontal = abs(velocity.x) > abs(velocity.y) * alpha
            guard isDecidedlyHorizontal else {
                return
            }
            let location = selectionPanGesture.location(in: collectionView)
            guard let indexPath = collectionView.indexPathForItem(at: location) else {
                return
            }
            tryToToggleBatchSelect(at: indexPath)
        case .cancelled, .ended, .failed:
            collectionView.isUserInteractionEnabled = true
            collectionView.isScrollEnabled = true
        @unknown default:
            owsFailDebug("unexpected selectionPanGesture.state: \(selectionPanGesture.state)")
        }
    }

    func tryToToggleBatchSelect(at indexPath: IndexPath) {
        guard let collectionView = collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        guard let delegate = delegate else {
            owsFailDebug("delegate was unexpectedly nil")
            return
        }

        guard delegate.isInBatchSelectMode else {
            owsFailDebug("isInBatchSelectMode was unexpectedly false")
            return
        }

        let asset = photoCollectionContents.asset(at: indexPath.item)
        switch selectionPanGestureMode {
        case .select:
            guard !isSelected(indexPath: indexPath) else {
                return
            }

            guard delegate.imagePickerCanSelectMoreItems(self) else {
                delegate.imagePickerDidTryToSelectTooMany(self)
                return
            }

            let attachmentPromise: Promise<SignalAttachment> = photoCollectionContents.outgoingAttachment(for: asset, imageQuality: imageQuality)
            delegate.imagePicker(self, didSelectAsset: asset, attachmentPromise: attachmentPromise)
            collectionView.selectItem(at: indexPath, animated: true, scrollPosition: [])
        case .deselect:
            guard isSelected(indexPath: indexPath) else {
                return
            }

            delegate.imagePicker(self, didDeselectAsset: asset)
            collectionView.deselectItem(at: indexPath, animated: true)
        }
    }

    var imageQuality: TSImageQuality {
        guard let delegate = delegate else {
            return .medium
        }

        return delegate.isPickingAsDocument ? .original : .medium
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateLayout()
    }

    var hasEverAppeared: Bool = false
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Determine the size of the thumbnails to request
        let scale = UIScreen.main.scale
        let cellSize = collectionViewFlowLayout.itemSize
        photoMediaSize.thumbnailSize = CGSize(width: cellSize.width * scale, height: cellSize.height * scale)

        reloadData()
        if !hasEverAppeared {
            scrollToBottom(animated: false)
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        if !hasEverAppeared {
            // To scroll precisely to the bottom of the content, we have to account for the space
            // taken up by the navbar and any notch.
            //
            // Before iOS11 the system accounts for this by assigning contentInset to the scrollView
            // which is available by the time `viewWillAppear` is called.
            //
            // On iOS11+, contentInsets are not assigned to the scrollView in `viewWillAppear`, but
            // this method, `viewSafeAreaInsetsDidChange` is called *between* `viewWillAppear` and
            // `viewDidAppear` and indicates `safeAreaInsets` have been assigned.
            scrollToBottom(animated: false)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        hasEverAppeared = true

        BenchEventComplete(eventId: "Show-Media-Library")

        DispatchQueue.main.async {
            // pre-layout collectionPicker for snappier response
            self.collectionPickerController.view.layoutIfNeeded()
        }
    }

    // MARK: 

    var lastPageYOffset: CGFloat {
        var yOffset = collectionView.contentSize.height - collectionView.frame.height + collectionView.contentInset.bottom + view.safeAreaInsets.bottom
        return yOffset
    }

    func scrollToBottom(animated: Bool) {
        self.view.layoutIfNeeded()

        guard let collectionView = collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        let yOffset = lastPageYOffset
        guard yOffset > 0 else {
            // less than 1 page of content. Do not offset.
            return
        }

        collectionView.setContentOffset(CGPoint(x: 0, y: yOffset), animated: animated)
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if !hasEverAppeared, collectionView.contentOffset.y != lastPageYOffset {
            // We initially want the user to be scrolled to the bottom of the media library content.
            // However, at least on iOS12, we were finding that when the view finally presented,
            // the content was not *quite* to the bottom (~20px above it).
            //
            // Debugging shows that initially we have the correct offset, but that *something* is
            // causing the content to adjust *after* viewWillAppear and viewSafeAreaInsetsDidChange.
            // Because that something results in `scrollViewDidScroll` we re-adjust the content
            // insets to the bottom.
            Logger.debug("adjusting scroll offset back to bottom")
            scrollToBottom(animated: false)
        }
    }

    public func reloadData() {
        guard let collectionView = collectionView else {
            owsFailDebug("Missing collectionView.")
            return
        }

        collectionView.reloadData()
        collectionView.layoutIfNeeded()
    }

    // MARK: - Actions

    @objc
    func didPressCancel() {
        self.delegate?.imagePickerDidCancel(self)
    }

    // MARK: - Layout

    static let kInterItemSpacing: CGFloat = 2
    private class func buildLayout() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()

        layout.sectionInsetReference = .fromSafeArea
        layout.minimumInteritemSpacing = kInterItemSpacing
        layout.minimumLineSpacing = kInterItemSpacing
        layout.sectionHeadersPinToVisibleBounds = true

        return layout
    }

    func updateLayout() {
        let containerWidth = self.view.safeAreaLayoutGuide.layoutFrame.size.width

        let minItemWidth: CGFloat = 100
        let itemCount = floor(containerWidth / minItemWidth)
        let interSpaceWidth = (itemCount - 1) * type(of: self).kInterItemSpacing

        let availableWidth = max(0, containerWidth - interSpaceWidth)

        let itemWidth = floor(availableWidth / CGFloat(itemCount))
        let newItemSize = CGSize(square: itemWidth)
        let remainingSpace = availableWidth - (itemCount * itemWidth)

        if newItemSize != collectionViewFlowLayout.itemSize {
            collectionViewFlowLayout.itemSize = newItemSize
            // Inset any remaining space around the outside edges to ensure all inter-item spacing is exactly equal, otherwise
            // we may get slightly different gaps between rows vs. columns
            collectionViewFlowLayout.sectionInset = UIEdgeInsets(top: 0, leading: remainingSpace / 2, bottom: 0, trailing: remainingSpace / 2)
            collectionViewFlowLayout.invalidateLayout()
        }
    }

    // MARK: - Batch Selection

    func isSelected(indexPath: IndexPath) -> Bool {
        guard let selectedIndexPaths = collectionView.indexPathsForSelectedItems else {
            return false
        }

        return selectedIndexPaths.contains(indexPath)
    }

    func batchSelectModeDidChange() {
        applyBatchSelectMode()
    }

    func applyBatchSelectMode() {
        guard let delegate = delegate else {
            return
        }

        guard let collectionView = collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        collectionView.allowsMultipleSelection = delegate.isInBatchSelectMode
        updateVisibleCells()
    }

    // MARK: - PhotoLibraryDelegate

    func photoLibraryDidChange(_ photoLibrary: PhotoLibrary) {
        photoCollectionContents = photoCollection.contents()
        reloadData()
    }

    // MARK: - PhotoCollectionPicker Presentation

    var isShowingCollectionPickerController: Bool = false

    lazy var collectionPickerController: PhotoCollectionPickerController = {
        return PhotoCollectionPickerController(library: library,
                                               collectionDelegate: self)
    }()

    func showCollectionPicker() {
        Logger.debug("")

        guard let collectionPickerView = collectionPickerController.view else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        assert(!isShowingCollectionPickerController)
        isShowingCollectionPickerController = true
        addChild(collectionPickerController)

        view.addSubview(collectionPickerView)
        collectionPickerView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
        collectionPickerView.autoPinEdge(toSuperviewSafeArea: .top)
        collectionPickerView.layoutIfNeeded()

        // Initially position offscreen, we'll animate it in.
        collectionPickerView.frame = collectionPickerView.frame.offsetBy(dx: 0, dy: collectionPickerView.frame.height)

        UIView.animate(.promise, duration: 0.25, delay: 0, options: .curveEaseInOut) {
            collectionPickerView.superview?.layoutIfNeeded()
            self.titleView.rotateIcon(.up)
        }
    }

    func hideCollectionPicker() {
        Logger.debug("")

        assert(isShowingCollectionPickerController)
        isShowingCollectionPickerController = false

        UIView.animate(.promise, duration: 0.25, delay: 0, options: .curveEaseInOut) {
            self.collectionPickerController.view.frame = self.collectionPickerController.view.frame.offsetBy(
                dx: 0,
                dy: self.collectionPickerController.view.height
            )
            self.titleView.rotateIcon(.down)
        }.done { _ in
            self.collectionPickerController.view.removeFromSuperview()
            self.collectionPickerController.removeFromParent()
        }
    }

    // MARK: - PhotoCollectionPickerDelegate

    func photoCollectionPicker(_ photoCollectionPicker: PhotoCollectionPickerController, didPickCollection collection: PhotoCollection) {
        BenchEventStart(title: "Picked Collection", eventId: "Picked Collection")
        defer { BenchEventComplete(eventId: "Picked Collection") }
        guard photoCollection != collection else {
            hideCollectionPicker()
            return
        }

        photoCollection = collection
        photoCollectionContents = photoCollection.contents()

        // Any selections are invalid as they refer to indices in a different collection
        reloadData()

        titleView.text = photoCollection.localizedTitle()

        scrollToBottom(animated: false)
        hideCollectionPicker()
    }

    // MARK: - UICollectionView

    override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let delegate = delegate else { return false }

        if delegate.imagePickerCanSelectMoreItems(self) {
            return true
        } else {
            delegate.imagePickerDidTryToSelectTooMany(self)
            return false
        }
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let delegate = delegate else {
            owsFailDebug("delegate was unexpectedly nil")
            return
        }

        let asset: PHAsset = photoCollectionContents.asset(at: indexPath.item)
        let attachmentPromise: Promise<SignalAttachment> = photoCollectionContents.outgoingAttachment(for: asset, imageQuality: imageQuality)
        delegate.imagePicker(self, didSelectAsset: asset, attachmentPromise: attachmentPromise)

        if !delegate.isInBatchSelectMode {
            // Don't show "selected" badge unless we're in batch mode
            collectionView.deselectItem(at: indexPath, animated: false)
            delegate.imagePickerDidCompleteSelection(self)
        }
    }

    public override func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        Logger.debug("")
        guard let delegate = delegate else {
            owsFailDebug("delegate was unexpectedly nil")
            return
        }

        let asset = photoCollectionContents.asset(at: indexPath.item)
        delegate.imagePicker(self, didDeselectAsset: asset)
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return photoCollectionContents.assetCount
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoGridViewCell.reuseIdentifier, for: indexPath) as? PhotoGridViewCell else {
            owsFail("cell was unexpectedly nil")
        }

        cell.loadingColor = UIColor(white: 0.2, alpha: 1)
        let assetItem = photoCollectionContents.assetItem(at: indexPath.item, photoMediaSize: photoMediaSize)
        cell.configure(item: assetItem)
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let delegate = delegate else { return }
        guard let photoGridViewCell = cell as? PhotoGridViewCell else {
            owsFailDebug("unexpected cell: \(cell)")
            return
        }
        let assetItem = photoCollectionContents.assetItem(at: indexPath.item, photoMediaSize: photoMediaSize)
        let isSelected = delegate.imagePicker(self, isAssetSelected: assetItem.asset)
        if isSelected {
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        } else {
            collectionView.deselectItem(at: indexPath, animated: false)
        }
        photoGridViewCell.isSelected = isSelected
        photoGridViewCell.allowsMultipleSelection = collectionView.allowsMultipleSelection
    }

    func updateVisibleCells() {
        guard let delegate = delegate else { return }
        for cell in collectionView.visibleCells {
            guard let photoGridViewCell = cell as? PhotoGridViewCell else {
                owsFailDebug("unexpected cell: \(cell)")
                continue
            }

            guard let assetItem = photoGridViewCell.item as? PhotoPickerAssetItem else {
                owsFailDebug("unexpected photoGridViewCell.item: \(String(describing: photoGridViewCell.item))")
                continue
            }

            photoGridViewCell.isSelected = delegate.imagePicker(self, isAssetSelected: assetItem.asset)
            photoGridViewCell.allowsMultipleSelection = collectionView.allowsMultipleSelection
        }
    }
}

extension ImagePickerGridController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Ensure we can still scroll the collectionView by allowing other gestures to
        // take precedence.
        guard otherGestureRecognizer == selectionPanGesture else {
            return true
        }

        // Once we've started the selectionPanGesture, don't allow scrolling
        if otherGestureRecognizer.state == .began || otherGestureRecognizer.state == .changed {
            return false
        }

        return true
    }
}

protocol TitleViewDelegate: class {
    func titleViewWasTapped(_ titleView: TitleView)
}

class TitleView: UIView {

    // MARK: - Private

    private let label = UILabel()
    private let iconView = UIImageView()
    private let stackView: UIStackView

    // MARK: - Initializers

    override init(frame: CGRect) {
        let stackView = UIStackView(arrangedSubviews: [label, iconView])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 5
        stackView.isUserInteractionEnabled = true

        self.stackView = stackView

        super.init(frame: frame)

        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()

        label.textColor = .ows_gray05
        label.font = UIFont.ows_dynamicTypeBody.ows_semibold

        iconView.tintColor = .ows_gray05
        iconView.image = UIImage(named: "navbar_disclosure_down")?.withRenderingMode(.alwaysTemplate)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleTapped)))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public

    weak var delegate: TitleViewDelegate?

    public var text: String? {
        get {
            return label.text
        }
        set {
            label.text = newValue
        }
    }

    public enum TitleViewRotationDirection {
        case up, down
    }

    public func rotateIcon(_ direction: TitleViewRotationDirection) {
        switch direction {
        case .up:
            // *slightly* more than `pi` to ensure the chevron animates counter-clockwise
            let chevronRotationAngle = CGFloat.pi + 0.001
            iconView.transform = CGAffineTransform(rotationAngle: chevronRotationAngle)
        case .down:
            iconView.transform = .identity
        }
    }

    // MARK: - Events

    @objc
    func titleTapped(_ tapGesture: UITapGestureRecognizer) {
        self.delegate?.titleViewWasTapped(self)
    }
}

extension ImagePickerGridController: TitleViewDelegate {
    func titleViewWasTapped(_ titleView: TitleView) {
        if isShowingCollectionPickerController {
            hideCollectionPicker()
        } else {
            showCollectionPicker()
        }
    }
}
