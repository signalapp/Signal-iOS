//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import Photos
import PromiseKit

@objc(OWSImagePickerControllerDelegate)
protocol ImagePickerControllerDelegate {
    func imagePicker(_ imagePicker: ImagePickerGridController, didPickImageAttachments attachments: [SignalAttachment], messageText: String?)
}

@objc(OWSImagePickerGridController)
class ImagePickerGridController: UICollectionViewController, PhotoLibraryDelegate, PhotoCollectionPickerDelegate, AttachmentApprovalViewControllerDelegate {

    @objc
    weak var delegate: ImagePickerControllerDelegate?

    private let library: PhotoLibrary = PhotoLibrary()
    private var photoCollection: PhotoCollection
    private var photoCollectionContents: PhotoCollectionContents
    private let photoMediaSize = PhotoMediaSize()

    var collectionViewFlowLayout: UICollectionViewFlowLayout
    var titleView: TitleView!

    // We use NSMutableOrderedSet so that we can honor selection order.
    private let selectedIds = NSMutableOrderedSet()

    // This variable should only be accessed on the main thread.
    private var assetIdToCommentMap = [String: String]()

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

    override func viewDidLoad() {
        super.viewDidLoad()

        library.add(delegate: self)

        guard let collectionView = collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        collectionView.register(PhotoGridViewCell.self, forCellWithReuseIdentifier: PhotoGridViewCell.reuseIdentifier)

        view.backgroundColor = .ows_gray95

        let cancelButton = UIBarButtonItem(barButtonSystemItem: .stop,
                                           target: self,
                                           action: #selector(didPressCancel))
        cancelButton.tintColor = .ows_gray05
        navigationItem.leftBarButtonItem = cancelButton

        let titleView = TitleView()
        titleView.delegate = self
        titleView.text = photoCollection.localizedTitle()

        if #available(iOS 11, *) {
            // do nothing
        } else {
            // must assign titleView frame manually on older iOS
            titleView.frame = CGRect(origin: .zero, size: titleView.systemLayoutSizeFitting(UILayoutFittingCompressedSize))
        }

        navigationItem.titleView = titleView
        self.titleView = titleView

        let featureFlag_isMultiselectEnabled = true
        if featureFlag_isMultiselectEnabled {
            updateSelectButton()
        }

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
        guard isInBatchSelectMode else {
            return
        }

        guard let collectionView = collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
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
            if selectedIds.contains(asset.localIdentifier) {
                selectionPanGestureMode = .deselect
            } else {
                selectionPanGestureMode = .select
            }
        case .changed:
            let location = selectionPanGesture.location(in: collectionView)
            guard let indexPath = collectionView.indexPathForItem(at: location) else {
                return
            }
            tryToToggleBatchSelect(at: indexPath)
        case .cancelled, .ended, .failed:
            collectionView.isUserInteractionEnabled = true
            collectionView.isScrollEnabled = true
        }
    }

    func tryToToggleBatchSelect(at indexPath: IndexPath) {
        guard isInBatchSelectMode else {
            owsFailDebug("isInBatchSelectMode was unexpectedly false")
            return
        }

        guard let collectionView = collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        let asset = photoCollectionContents.asset(at: indexPath.item)
        switch selectionPanGestureMode {
        case .select:
            guard canSelectAdditionalItems else {
                showTooManySelectedToast()
                return
            }

            selectedIds.add(asset.localIdentifier)
            collectionView.selectItem(at: indexPath, animated: true, scrollPosition: [])
        case .deselect:
            selectedIds.remove(asset.localIdentifier)
            collectionView.deselectItem(at: indexPath, animated: true)
        }

        updateDoneButton()
    }

    var canSelectAdditionalItems: Bool {
        return selectedIds.count <= SignalAttachment.maxAttachmentsAllowed
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateLayout()
    }

    var hasEverAppeared: Bool = false
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let navBar = self.navigationController?.navigationBar as? OWSNavigationBar {
            navBar.overrideTheme(type: .alwaysDark)
        } else {
            owsFailDebug("Invalid nav bar.")
        }

        // Determine the size of the thumbnails to request
        let scale = UIScreen.main.scale
        let cellSize = collectionViewFlowLayout.itemSize
        photoMediaSize.thumbnailSize = CGSize(width: cellSize.width * scale, height: cellSize.height * scale)

        reloadDataAndRestoreSelection()
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
        // done button may have been disable from the last time we hit "Done"
        // make sure to re-enable it if appropriate upon returning to the view
        hasPressedDoneSinceAppeared = false
        updateDoneButton()

        // Since we're presenting *over* the ConversationVC, we need to `becomeFirstResponder`.
        //
        // Otherwise, the `ConversationVC.inputAccessoryView` will appear over top of us whenever
        // OWSWindowManager window juggling executes `[rootWindow makeKeyAndVisible]`.
        //
        // We don't need to do this when pushing VCs onto the SignalsNavigationController - only when
        // presenting directly from ConversationVC.
        _ = self.becomeFirstResponder()
    }

    // HACK: Though we don't have an input accessory view, the VC we are presented above (ConversationVC) does.
    // If the app is backgrounded and then foregrounded, when OWSWindowManager calls mainWindow.makeKeyAndVisible
    // the ConversationVC's inputAccessoryView will appear *above* us unless we'd previously become first responder.
    override public var canBecomeFirstResponder: Bool {
        Logger.debug("")
        return true
    }

    // MARK: 

    func scrollToBottom(animated: Bool) {
        self.view.layoutIfNeeded()

        guard let collectionView = collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        let lastSection = collectionView.numberOfSections - 1
        let lastItem = collectionView.numberOfItems(inSection: lastSection) - 1
        if lastSection >= 0 && lastItem >= 0 {
            let lastIndex = IndexPath(item: lastItem, section: lastSection)
            collectionView.scrollToItem(at: lastIndex, at: .bottom, animated: animated)
        }
    }

    private func reloadDataAndRestoreSelection() {
        guard let collectionView = collectionView else {
            owsFailDebug("Missing collectionView.")
            return
        }

        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        let count = photoCollectionContents.assetCount
        for index in 0..<count {
            let asset = photoCollectionContents.asset(at: index)
            let assetId = asset.localIdentifier
            if selectedIds.contains(assetId) {
                collectionView.selectItem(at: IndexPath(row: index, section: 0),
                                          animated: false, scrollPosition: [])
            }
        }
    }

    // MARK: - Actions

    @objc
    func didPressCancel(sender: UIBarButtonItem) {
        self.dismiss(animated: true)
    }

    // MARK: - Layout

    static let kInterItemSpacing: CGFloat = 2
    private class func buildLayout() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()

        if #available(iOS 11, *) {
            layout.sectionInsetReference = .fromSafeArea
        }
        layout.minimumInteritemSpacing = kInterItemSpacing
        layout.minimumLineSpacing = kInterItemSpacing
        layout.sectionHeadersPinToVisibleBounds = true

        return layout
    }

    func updateLayout() {
        let containerWidth: CGFloat
        if #available(iOS 11.0, *) {
            containerWidth = self.view.safeAreaLayoutGuide.layoutFrame.size.width
        } else {
            containerWidth = self.view.frame.size.width
        }

        let kItemsPerPortraitRow = 4
        let screenWidth = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let approxItemWidth = screenWidth / CGFloat(kItemsPerPortraitRow)

        let itemCount = round(containerWidth / approxItemWidth)
        let spaceWidth = (itemCount + 1) * type(of: self).kInterItemSpacing
        let availableWidth = containerWidth - spaceWidth

        let itemWidth = floor(availableWidth / CGFloat(itemCount))
        let newItemSize = CGSize(width: itemWidth, height: itemWidth)

        if (newItemSize != collectionViewFlowLayout.itemSize) {
            collectionViewFlowLayout.itemSize = newItemSize
            collectionViewFlowLayout.invalidateLayout()
        }
    }

    // MARK: - Batch Selection

    lazy var doneButton: UIBarButtonItem = {
        return UIBarButtonItem(barButtonSystemItem: .done,
                               target: self,
                               action: #selector(didPressDone))
    }()

    lazy var selectButton: UIBarButtonItem = {
        return UIBarButtonItem(title: NSLocalizedString("BUTTON_SELECT", comment: "Button text to enable batch selection mode"),
                               style: .plain,
                               target: self,
                               action: #selector(didTapSelect))
    }()

    var isInBatchSelectMode = false {
        didSet {
            collectionView!.allowsMultipleSelection = isInBatchSelectMode
            updateSelectButton()
            updateDoneButton()
        }
    }

    @objc
    func didPressDone(_ sender: Any) {
        Logger.debug("")

        hasPressedDoneSinceAppeared = true
        updateDoneButton()

        // Honor selection order.
        var assetIdToAssetIndexMap = [String: Int]()
        let assetCount = photoCollectionContents.assetCount
        for index in 0..<assetCount {
            let asset = photoCollectionContents.asset(at: index)
            let assetId = asset.localIdentifier
            assetIdToAssetIndexMap[assetId] = index
        }
        var assets = [PHAsset]()
        for selectedIdAny in selectedIds.array {
            guard let selectedId = selectedIdAny as? String else {
                owsFailDebug("Invalid asset id: \(selectedIdAny)")
                continue
            }
            guard let assetIndex = assetIdToAssetIndexMap[selectedId] else {
                owsFailDebug("Missing asset id: \(selectedId)")
                continue
            }
            assets.append(photoCollectionContents.asset(at: assetIndex))
        }

        complete(withAssets: assets)
    }

    func complete(withAssets assets: [PHAsset]) {

        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: false) { (modal) in
                                                        let attachmentPromises: [Promise<SignalAttachment>] = assets.map({
                                                            return self.photoCollectionContents.outgoingAttachment(for: $0)
                                                        })

                                                        firstly {
                                                            when(fulfilled: attachmentPromises)
                                                            }.map { attachments in
                                                                Logger.debug("built all attachments")

                                                                DispatchQueue.main.async {
                                                                    modal.dismiss(completion: {
                                                                        self.didComplete(withAttachments: attachments)
                                                                    })
                                                                }
                                                            }.catch { error in
                                                                Logger.error("failed to prepare attachments. error: \(error)")
                                                                DispatchQueue.main.async {
                                                                    modal.dismiss(completion: {
                                                                        OWSAlerts.showAlert(title: NSLocalizedString("IMAGE_PICKER_FAILED_TO_PROCESS_ATTACHMENTS", comment: "alert title"))
                                                                    })
                                                                }
                                                            }.retainUntilComplete()
        }
    }

    private func didComplete(withAttachments attachments: [SignalAttachment]) {
        AssertIsOnMainThread()

        for attachment in attachments {
            guard let assetId = attachment.assetId else {
                owsFailDebug("Attachment is missing asset id.")
                continue
            }
            // Link the attachment with its asset to ensure caption continuity.
            attachment.assetId = assetId
            // Restore any existing caption for this attachment.
            attachment.captionText = assetIdToCommentMap[assetId]
        }

        let vc = AttachmentApprovalViewController(mode: .sharedNavigation, attachments: attachments)
        vc.approvalDelegate = self
        navigationController?.pushViewController(vc, animated: true)
    }

    var hasPressedDoneSinceAppeared: Bool = false
    func updateDoneButton() {
        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        guard !hasPressedDoneSinceAppeared else {
            doneButton.isEnabled = false
            return
        }

        if let count = collectionView.indexPathsForSelectedItems?.count, count > 0 {
            doneButton.isEnabled = true
        } else {
            doneButton.isEnabled = false
        }
    }

    func updateSelectButton() {
        guard !isShowingCollectionPickerController else {
            navigationItem.rightBarButtonItem = nil
            return
        }

        let button = isInBatchSelectMode ? doneButton : selectButton
        button.tintColor = .ows_gray05
        navigationItem.rightBarButtonItem = button
    }

    @objc
    func didTapSelect(_ sender: Any) {
        isInBatchSelectMode = true

        // disabled until at least one item is selected
        self.doneButton.isEnabled = false
    }

    func deselectAnySelected() {
        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        selectedIds.removeAllObjects()
        collectionView.indexPathsForSelectedItems?.forEach { collectionView.deselectItem(at: $0, animated: false)}

        if isInBatchSelectMode {
            updateDoneButton()
        }
    }

    func showTooManySelectedToast() {
        Logger.info("")

        guard let  collectionView  = collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        let toastFormat = NSLocalizedString("IMAGE_PICKER_CAN_SELECT_NO_MORE_TOAST_FORMAT",
                                            comment: "Momentarily shown to the user when attempting to select more images than is allowed. Embeds {{max number of items}} that can be shared.")

        let toastText = String(format: toastFormat, NSNumber(value: SignalAttachment.maxAttachmentsAllowed))

        let toastController = ToastController(text: toastText)

        let kToastInset: CGFloat = 10
        let bottomInset = kToastInset + collectionView.contentInset.bottom + view.layoutMargins.bottom

        toastController.presentToastView(fromBottomOfView: view, inset: bottomInset)
    }

    // MARK: - PhotoLibraryDelegate

    func photoLibraryDidChange(_ photoLibrary: PhotoLibrary) {
        photoCollectionContents = photoCollection.contents()
        reloadDataAndRestoreSelection()
    }

    // MARK: - PhotoCollectionPicker Presentation

    var isShowingCollectionPickerController: Bool {
        return collectionPickerController != nil
    }

    var collectionPickerController: PhotoCollectionPickerController?
    func showCollectionPicker() {
        Logger.debug("")

        let collectionPickerController = PhotoCollectionPickerController(library: library,
                                                                         previousPhotoCollection: photoCollection,
                                                                         collectionDelegate: self)

        guard let collectionPickerView = collectionPickerController.view else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        assert(self.collectionPickerController == nil)
        self.collectionPickerController = collectionPickerController

        addChildViewController(collectionPickerController)

        view.addSubview(collectionPickerView)
        collectionPickerView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
        collectionPickerView.autoPinEdge(toSuperviewSafeArea: .top)
        collectionPickerView.layoutIfNeeded()

        // Initially position offscreen, we'll animate it in.
        collectionPickerView.frame = collectionPickerView.frame.offsetBy(dx: 0, dy: collectionPickerView.frame.height)

        UIView.animate(.promise, duration: 0.25, delay: 0, options: .curveEaseInOut) {
            collectionPickerView.superview?.layoutIfNeeded()

            self.updateSelectButton()

            self.titleView.rotateIcon(.up)
        }.retainUntilComplete()
    }

    func hideCollectionPicker() {
        Logger.debug("")
        guard let collectionPickerController = collectionPickerController else {
            owsFailDebug("collectionPickerController was unexpectedly nil")
            return
        }
        self.collectionPickerController = nil

        UIView.animate(.promise, duration: 0.25, delay: 0, options: .curveEaseInOut) {
            collectionPickerController.view.frame = self.view.frame.offsetBy(dx: 0, dy: self.view.frame.height)

            self.updateSelectButton()

            self.titleView.rotateIcon(.down)
        }.done { _ in
            collectionPickerController.view.removeFromSuperview()
            collectionPickerController.removeFromParentViewController()
        }.retainUntilComplete()
    }

    // MARK: - PhotoCollectionPickerDelegate

    func photoCollectionPicker(_ photoCollectionPicker: PhotoCollectionPickerController, didPickCollection collection: PhotoCollection) {
        guard photoCollection != collection else {
            hideCollectionPicker()
            return
        }

        // Any selections are invalid as they refer to indices in a different collection
        deselectAnySelected()

        photoCollection = collection
        photoCollectionContents = photoCollection.contents()

        titleView.text = photoCollection.localizedTitle()

        collectionView?.reloadData()
        scrollToBottom(animated: false)
        hideCollectionPicker()
    }

    // MARK: - UICollectionView

    override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let indexPathsForSelectedItems = collectionView.indexPathsForSelectedItems else {
            return true
        }

        if (indexPathsForSelectedItems.count < SignalAttachment.maxAttachmentsAllowed) {
            return true
        } else {
            showTooManySelectedToast()
            return false
        }
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let asset = photoCollectionContents.asset(at: indexPath.item)

        if isInBatchSelectMode {
            let assetId = asset.localIdentifier
            selectedIds.add(assetId)
            updateDoneButton()
        } else {
            // Don't show "selected" badge unless we're in batch mode
            collectionView.deselectItem(at: indexPath, animated: false)
            complete(withAssets: [asset])
        }
    }

    public override func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        Logger.debug("")

        let asset = photoCollectionContents.asset(at: indexPath.item)
        let assetId = asset.localIdentifier
        selectedIds.remove(assetId)

        if isInBatchSelectMode {
            updateDoneButton()
        }
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

        let assetId = assetItem.asset.localIdentifier
        let isSelected = selectedIds.contains(assetId)
        cell.isSelected = isSelected

        return cell
    }

    // MARK: - AttachmentApprovalViewControllerDelegate

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didApproveAttachments attachments: [SignalAttachment], messageText: String?) {
        self.dismiss(animated: true) {
            self.delegate?.imagePicker(self, didPickImageAttachments: attachments, messageText: messageText)
        }
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didCancelAttachments attachments: [SignalAttachment]) {
        navigationController?.popToViewController(self, animated: true)
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, addMoreToAttachments attachments: [SignalAttachment]) {
        // If we re-enter image picking via "add more" button, do so in batch mode.
        isInBatchSelectMode = true

        // clear selection
        deselectAnySelected()

        // removing-and-readding accomplishes two things
        // 1. respect items removed from the rail while in the approval view
        // 2. in the case of the user adding more to what was a single item
        //    which was not selected in batch mode, ensure that item is now
        //    part of the "batch selection"
        for previouslySelected in attachments {
            guard let assetId = previouslySelected.assetId else {
                owsFailDebug("assetId was unexpectedly nil")
                continue
            }

            selectedIds.add(assetId as Any)
        }

        navigationController?.popToViewController(self, animated: true)
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, changedCaptionOfAttachment attachment: SignalAttachment) {
        AssertIsOnMainThread()

        guard let assetId = attachment.assetId else {
            owsFailDebug("Attachment missing source id.")
            return
        }
        guard let captionText = attachment.captionText, captionText.count > 0 else {
            assetIdToCommentMap.removeValue(forKey: assetId)
            return
        }
        assetIdToCommentMap[assetId] = captionText
    }
}

extension ImagePickerGridController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Ensure we can still scroll the collectionView by allowing other gestures to
        // take precedence.
        guard otherGestureRecognizer == selectionPanGesture else {
            return true
        }

        // Once we've startd the selectionPanGesture, don't allow scrolling
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
        label.font = UIFont.ows_dynamicTypeBody.ows_mediumWeight()

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
