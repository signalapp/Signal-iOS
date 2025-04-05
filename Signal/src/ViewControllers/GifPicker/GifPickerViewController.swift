//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

class GifPickerNavigationViewController: OWSNavigationController {

    weak var approvalDelegate: AttachmentApprovalViewControllerDelegate?
    weak var approvalDataSource: AttachmentApprovalViewControllerDataSource?
    private var initialMessageBody: MessageBody?

    lazy var gifPickerViewController: GifPickerViewController = {
        let gifPickerViewController = GifPickerViewController()
        gifPickerViewController.delegate = self
        return gifPickerViewController
    }()

    init(initialMessageBody: MessageBody?) {
        self.initialMessageBody = initialMessageBody
        super.init()
        pushViewController(gifPickerViewController, animated: false)
    }
}

extension GifPickerNavigationViewController: GifPickerViewControllerDelegate {
    func gifPickerDidSelect(attachment: SignalAttachment) {
        AssertIsOnMainThread()

        let attachmentApprovalItem = AttachmentApprovalItem(attachment: attachment, canSave: false)
        let attachmentApproval = AttachmentApprovalViewController(options: [], attachmentApprovalItems: [attachmentApprovalItem])
        attachmentApproval.setMessageBody(initialMessageBody, txProvider: DependenciesBridge.shared.db.readTxProvider)
        attachmentApproval.approvalDelegate = self
        attachmentApproval.approvalDataSource = self
        pushViewController(attachmentApproval, animated: true) {
            // Remove any selected state in case the user returns "back" to the gif picker.
            self.gifPickerViewController.clearSelectedState()
        }
    }

    func gifPickerDidCancel() {
        dismiss(animated: true)
    }
}

extension GifPickerNavigationViewController: AttachmentApprovalViewControllerDelegate {

    public func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController,
                                   didApproveAttachments attachments: [SignalAttachment],
                                   messageBody: MessageBody?) {
        approvalDelegate?.attachmentApproval(attachmentApproval, didApproveAttachments: attachments, messageBody: messageBody)
    }

    public func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController) {
        approvalDelegate?.attachmentApprovalDidCancel(attachmentApproval)
    }

    public func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController,
                                   didChangeMessageBody newMessageBody: MessageBody?) {
        approvalDelegate?.attachmentApproval(attachmentApproval, didChangeMessageBody: newMessageBody)
    }

    public func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachment: SignalAttachment) { }

    public func attachmentApprovalDidTapAddMore(_ attachmentApproval: AttachmentApprovalViewController) { }

    public func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeViewOnceState isViewOnce: Bool) { }
}

extension GifPickerNavigationViewController: AttachmentApprovalViewControllerDataSource {

    public var attachmentApprovalTextInputContextIdentifier: String? {
        return approvalDataSource?.attachmentApprovalTextInputContextIdentifier
    }

    public var attachmentApprovalRecipientNames: [String] {
        approvalDataSource?.attachmentApprovalRecipientNames ?? []
    }

    public func attachmentApprovalMentionableAddresses(tx: DBReadTransaction) -> [SignalServiceAddress] {
        return approvalDataSource?.attachmentApprovalMentionableAddresses(tx: tx) ?? []
    }

    public func attachmentApprovalMentionCacheInvalidationKey() -> String {
        return approvalDataSource?.attachmentApprovalMentionCacheInvalidationKey() ?? UUID().uuidString
    }
}

protocol GifPickerViewControllerDelegate: AnyObject {
    @MainActor func gifPickerDidSelect(attachment: SignalAttachment)
    @MainActor func gifPickerDidCancel()
}

class GifPickerViewController: OWSViewController, UISearchBarDelegate, UICollectionViewDataSource, UICollectionViewDelegate, GifPickerLayoutDelegate, OWSNavigationChildController {

    // MARK: Properties

    enum ViewMode {
        case idle, searching, results, noResults, error, trending
    }

    private var viewMode = ViewMode.idle {
        didSet {
            updateContents()
            if viewMode == .trending {
                Task { await loadTrending() }
            }
        }
    }

    var lastQuery: String?

    public weak var delegate: GifPickerViewControllerDelegate?

    let searchBar: UISearchBar
    let layout: GifPickerLayout
    let collectionView: UICollectionView
    var noResultsView: UILabel?
    var searchErrorView: UILabel?
    var activityIndicator: UIActivityIndicatorView?
    var hasSelectedCell: Bool = false
    var imageInfos = [GiphyImageInfo]() {
        didSet {
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.reloadData()
        }
    }

    private let kCellReuseIdentifier = "kCellReuseIdentifier"

    var progressiveSearchTimer: Timer?

    // MARK: Initializers

    override init() {
        self.searchBar = OWSSearchBar()
        self.layout = GifPickerLayout()
        self.collectionView = UICollectionView(frame: CGRect.zero, collectionViewLayout: self.layout)

        super.init()

        self.layout.delegate = self
    }

    deinit {
        NotificationCenter.default.removeObserver(self)

        progressiveSearchTimer?.invalidate()
    }

    // MARK: -
    @objc
    private func didBecomeActive() {
        AssertIsOnMainThread()

        // Prod cells to try to load when app becomes active.
        ensureCellState()
    }

    @objc
    private func reachabilityChanged() {
        AssertIsOnMainThread()

        // Prod cells to try to load when connectivity changes.
        ensureCellState()
    }

    func ensureCellState() {
        for cell in self.collectionView.visibleCells {
            guard let cell = cell as? GifPickerCell else {
                owsFailDebug("unexpected cell.")
                return
            }
            cell.ensureCellState()
        }
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            self?.delegate?.gifPickerDidCancel()
        }
        self.navigationItem.title = OWSLocalizedString("GIF_PICKER_VIEW_TITLE",
                                                      comment: "Title for the 'GIF picker' dialog.")

        createViews()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reachabilityChanged),
                                               name: SSKReachability.owsReachabilityDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: .OWSApplicationDidBecomeActive,
                                               object: nil)

        // TODO: This really ought to be cancellable but it was not with promisekit so the refactor carries this for now.
        viewMode = .trending
    }

    var hasEverAppeared = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !hasEverAppeared {
            searchBar.becomeFirstResponder()
        }
        hasEverAppeared = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        progressiveSearchTimer?.invalidate()
        progressiveSearchTimer = nil

        fileForCellTask?.cancel()
        fileForCellTask = nil
    }

    public var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }

    public var navbarBackgroundColorOverride: UIColor? { view.backgroundColor }

    public override func themeDidChange() {
        super.themeDidChange()

        view.backgroundColor = Theme.backgroundColor
        owsNavigationController?.updateNavbarAppearance()
    }

    // MARK: Views

    func clearSelectedState() {
        hasSelectedCell = false
        collectionView.isUserInteractionEnabled = true
        selectedMaskingView.isHidden = true
        if let selectedIndices = collectionView.indexPathsForSelectedItems {
            for index in selectedIndices {
                collectionView.deselectItem(at: index, animated: false)
                if let cell = collectionView.cellForItem(at: index) {
                    cell.isSelected = false
                }
            }
        }
    }

    let selectedMaskingView = BezierPathView()

    private func createViews() {

        let backgroundColor = (Theme.isDarkThemeEnabled
            ? UIColor(white: 0.08, alpha: 1.0)
            : Theme.backgroundColor)
        self.view.backgroundColor = backgroundColor

        self.collectionView.delegate = self
        self.collectionView.dataSource = self
        self.collectionView.backgroundColor = backgroundColor
        self.collectionView.contentInsetAdjustmentBehavior = .never
        self.collectionView.register(GifPickerCell.self, forCellWithReuseIdentifier: kCellReuseIdentifier)
        view.addSubview(self.collectionView)
        self.collectionView.autoPinEdge(toSuperviewSafeArea: .leading)
        self.collectionView.autoPinEdge(toSuperviewSafeArea: .trailing)

        view.addSubview(selectedMaskingView)
        selectedMaskingView.autoPinEdge(.top, to: .top, of: collectionView)
        selectedMaskingView.autoPinEdge(.leading, to: .leading, of: collectionView)
        selectedMaskingView.autoPinEdge(.trailing, to: .trailing, of: collectionView)
        selectedMaskingView.autoPinEdge(.bottom, to: .bottom, of: collectionView)
        selectedMaskingView.isHidden = true

        // Search
        searchBar.delegate = self
        searchBar.placeholder = OWSLocalizedString("GIF_VIEW_SEARCH_PLACEHOLDER_TEXT",
                                                  comment: "Placeholder text for the search field in GIF view")
        view.addSubview(searchBar)
        searchBar.autoPinWidthToSuperview()
        searchBar.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        searchBar.autoPinEdge(.bottom, to: .top, of: collectionView)

        // for iPhoneX devices, extends the black background to the bottom edge of the view.
        let bottomBannerContainer = UIView()
        bottomBannerContainer.backgroundColor = UIColor.black
        self.view.addSubview(bottomBannerContainer)
        bottomBannerContainer.autoPinWidthToSuperview()
        bottomBannerContainer.autoPinEdge(.top, to: .bottom, of: self.collectionView)
        bottomBannerContainer.autoPinEdge(toSuperviewEdge: .bottom)

        let bottomBanner = UIView()
        bottomBannerContainer.addSubview(bottomBanner)

        bottomBanner.autoPinEdge(toSuperviewEdge: .top)
        bottomBanner.autoPinWidthToSuperview()
        bottomBanner.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)

        // The Giphy API requires us to "show their trademark prominently" in our GIF experience.
        let logoImage = UIImage(named: "giphy_logo")
        let logoImageView = UIImageView(image: logoImage)
        bottomBanner.addSubview(logoImageView)
        logoImageView.autoPinHeightToSuperview(withMargin: 3)
        logoImageView.autoHCenterInSuperview()

        let noResultsView = createErrorLabel(text: OWSLocalizedString("GIF_VIEW_SEARCH_NO_RESULTS",
                                                                    comment: "Indicates that the user's search had no results."))
        self.noResultsView = noResultsView
        self.view.addSubview(noResultsView)
        noResultsView.autoPinWidthToSuperview(withMargin: 20)
        noResultsView.autoAlignAxis(.horizontal, toSameAxisOf: self.collectionView)

        let searchErrorView = createErrorLabel(text: OWSLocalizedString("GIF_VIEW_SEARCH_ERROR",
                                                                      comment: "Indicates that an error occurred while searching."))
        self.searchErrorView = searchErrorView
        self.view.addSubview(searchErrorView)
        searchErrorView.autoPinWidthToSuperview(withMargin: 20)
        searchErrorView.autoAlignAxis(.horizontal, toSameAxisOf: self.collectionView)

        searchErrorView.isUserInteractionEnabled = true
        searchErrorView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(retryTapped)))

        let activityIndicator = UIActivityIndicatorView(style: .medium)
        self.activityIndicator = activityIndicator
        self.view.addSubview(activityIndicator)
        activityIndicator.autoHCenterInSuperview()
        activityIndicator.autoAlignAxis(.horizontal, toSameAxisOf: self.collectionView)

        self.updateContents()
    }

    private func createErrorLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = Theme.primaryTextColor
        label.font = UIFont.semiboldFont(ofSize: 20)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private func updateContents() {
        guard let noResultsView = self.noResultsView else {
            owsFailDebug("Missing noResultsView")
            return
        }
        guard let searchErrorView = self.searchErrorView else {
            owsFailDebug("Missing searchErrorView")
            return
        }
        guard let activityIndicator = self.activityIndicator else {
            owsFailDebug("Missing activityIndicator")
            return
        }

        switch viewMode {
        case .idle:
            self.collectionView.isHidden = true
            noResultsView.isHidden = true
            searchErrorView.isHidden = true
            activityIndicator.isHidden = true
            activityIndicator.stopAnimating()
        case .searching:
            self.collectionView.isHidden = true
            noResultsView.isHidden = true
            searchErrorView.isHidden = true
            activityIndicator.isHidden = false
            activityIndicator.startAnimating()
        case .results:
            self.collectionView.isHidden = false
            noResultsView.isHidden = true
            searchErrorView.isHidden = true
            activityIndicator.isHidden = true
            activityIndicator.stopAnimating()
        case .noResults:
            self.collectionView.isHidden = true
            noResultsView.isHidden = false
            searchErrorView.isHidden = true
            activityIndicator.isHidden = true
            activityIndicator.stopAnimating()
        case .error:
            self.collectionView.isHidden = true
            noResultsView.isHidden = true
            searchErrorView.isHidden = false
            activityIndicator.isHidden = true
            activityIndicator.stopAnimating()
        case .trending:
            self.collectionView.isHidden = true
            noResultsView.isHidden = true
            searchErrorView.isHidden = true
            activityIndicator.isHidden = true
            activityIndicator.stopAnimating()
        }
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.searchBar.resignFirstResponder()
    }

    // MARK: - UICollectionViewDataSource

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageInfos.count
    }

    public  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: kCellReuseIdentifier, for: indexPath)

        guard indexPath.row < imageInfos.count else {
            Logger.warn("indexPath: \(indexPath.row) out of range for imageInfo count: \(imageInfos.count) ")
            return cell
        }
        let imageInfo = imageInfos[indexPath.row]

        guard let gifCell = cell as? GifPickerCell else {
            owsFailDebug("Unexpected cell type.")
            return cell
        }
        gifCell.imageInfo = imageInfo
        return cell
    }

    // MARK: - UICollectionViewDelegate

    private func selectableCell(at indexPath: IndexPath) -> GifPickerCell? {
        guard let cell = collectionView.cellForItem(at: indexPath) as? GifPickerCell else {
            owsFailDebug("unexpected cell.")
            return nil
        }

        guard cell.isDisplayingPreview else {
            // we don't want to let the user blindly select a gray cell
            return nil
        }

        guard self.hasSelectedCell == false else {
            owsFailDebug("Already selected cell")
            return nil
        }

        return cell
    }

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return self.selectableCell(at: indexPath) != nil
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let cell = self.selectableCell(at: indexPath) else {
            return
        }
        self.hasSelectedCell = true

        // Fade out all cells except the selected one.
        let cellRect = collectionView.convert(cell.frame, to: selectedMaskingView)
        selectedMaskingView.shapeLayerConfigurationBlock = { layer, bounds in
            let path = UIBezierPath(rect: bounds)
            path.append(UIBezierPath(rect: cellRect))

            layer.path = path.cgPath
            layer.fillRule = .evenOdd
            layer.fillColor = UIColor.black.cgColor
            layer.opacity = 0.7
        }
        selectedMaskingView.isHidden = false

        cell.isSelected = true
        self.collectionView.isUserInteractionEnabled = false

        getFileForCell(cell)
    }

    private var fileForCellTask: Task<Void, Never>?

    public func getFileForCell(_ cell: GifPickerCell) {
        GiphyDownloader.giphyDownloader.cancelAllRequests()

        fileForCellTask?.cancel()
        fileForCellTask = Task.detached(priority: .userInitiated) {
            do {
                let asset = try await cell.requestRenditionForSending()
                guard let giphyAsset = asset.assetDescription as? GiphyAsset else {
                    throw OWSAssertionError("Invalid asset description.")
                }

                let assetTypeIdentifier = giphyAsset.type.utiType
                let assetFileExtension = giphyAsset.type.extension
                let pathForCachedAsset = asset.filePath

                let pathForConsumableFile = OWSFileSystem.temporaryFilePath(fileExtension: assetFileExtension)
                try FileManager.default.copyItem(atPath: pathForCachedAsset, toPath: pathForConsumableFile)
                let dataSource = try DataSourcePath(filePath: pathForConsumableFile, shouldDeleteOnDeallocation: false)

                let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: assetTypeIdentifier)
                attachment.isLoopingVideo = attachment.isVideo

                await self.delegate?.gifPickerDidSelect(attachment: attachment)
            } catch {
                await MainActor.run {
                    let alert = ActionSheetController(title: OWSLocalizedString("GIF_PICKER_FAILURE_ALERT_TITLE", comment: "Shown when selected GIF couldn't be fetched"),
                                                      message: error.userErrorDescription)
                    alert.addAction(ActionSheetAction(title: CommonStrings.retryButton, style: .default) { _ in
                        self.getFileForCell(cell)
                    })
                    alert.addAction(ActionSheetAction(title: CommonStrings.dismissButton, style: .cancel) { _ in
                        self.delegate?.gifPickerDidCancel()
                    })

                    self.presentActionSheet(alert)
                }
            }
        }
    }

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? GifPickerCell else {
            owsFailDebug("unexpected cell.")
            return
        }
        // We only want to load the cells which are on-screen.
        cell.isCellVisible = true
    }

    public func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? GifPickerCell else {
            owsFailDebug("unexpected cell.")
            return
        }
        cell.isCellVisible = false
    }

    // MARK: - UISearchBarDelegate

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        // Clear error messages immediately.
        if viewMode == .error || viewMode == .noResults {
            viewMode = .idle
        }

        // Do progressive search after a delay.
        progressiveSearchTimer?.invalidate()
        progressiveSearchTimer = nil
        let kProgressiveSearchDelaySeconds = 1.0
        progressiveSearchTimer = WeakTimer.scheduledTimer(timeInterval: kProgressiveSearchDelaySeconds, target: self, userInfo: nil, repeats: false) { [weak self] _ in
            guard let strongSelf = self else {
                return
            }

            strongSelf.tryToSearch()
        }
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        self.searchBar.resignFirstResponder()

        tryToSearch()
    }

    public func tryToSearch() {
        progressiveSearchTimer?.invalidate()
        progressiveSearchTimer = nil

        guard let text = searchBar.text else {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString("GIF_PICKER_VIEW_MISSING_QUERY",
                                                           comment: "Alert message shown when user tries to search for GIFs without entering any search terms."))
            return
        }

        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if (viewMode == .searching || viewMode == .results) && lastQuery == query {
            return
        }

        // TODO: This really ought to be cancellable but it was not with promisekit so the refactor carries this for now.
        Task { await search(query: query) }
    }

    private func loadTrending() async {
        assert(progressiveSearchTimer == nil)
        assert(lastQuery == nil)
        assert(searchBar.text.isEmptyOrNil)

        do {
            let imageInfos = try await GiphyAPI.trending()

            guard self.lastQuery == nil else {
                Logger.info("not showing trending results due to subsequent searches.")
                return
            }

            Logger.info("showing trending")
            if imageInfos.count > 0 {
                self.imageInfos = imageInfos
                self.viewMode = .results
            } else {
                owsFailDebug("trending results was unexpectedly empty")
            }
        } catch {
            // Don't both showing error UI feedback for default "trending" results.
            Logger.error("error: \(error)")
        }
    }

    private func search(query: String) async {
        imageInfos = []
        viewMode = .searching
        lastQuery = query.isEmpty ? nil : query
        self.collectionView.contentOffset = CGPoint.zero

        do {
            imageInfos = try await GiphyAPI.search(query: query)
            Logger.info("search complete")
            if imageInfos.count > 0 {
                viewMode = .results
            } else if lastQuery != nil {
                viewMode = .noResults
            } else {
                viewMode = .trending
            }
        } catch {
            owsFailDebugUnlessNetworkFailure(error)

            Logger.warn("search failed.")
            // TODO: Present this error to the user.
            viewMode = .error
        }
    }

    // MARK: - GifPickerLayoutDelegate

    func imageInfosForLayout() -> [GiphyImageInfo] {
        return imageInfos
    }

    // MARK: - Event Handlers

    @objc
    private func retryTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        guard viewMode == .error else {
            return
        }
        tryToSearch()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        layout.invalidateLayout()
    }
}
