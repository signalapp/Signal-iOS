//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import Reachability
import SignalUtilitiesKit
import PromiseKit
import SessionUIKit

class GifPickerViewController: OWSViewController, UISearchBarDelegate, UICollectionViewDataSource, UICollectionViewDelegate, GifPickerLayoutDelegate {

    // MARK: Properties

    enum ViewMode {
        case idle, searching, results, noResults, error
    }

    private var viewMode = ViewMode.idle {
        didSet {
            Logger.info("viewMode: \(viewMode)")

            updateContents()
        }
    }

    var lastQuery: String = ""

    public weak var delegate: GifPickerViewControllerDelegate?

    let searchBar: SearchBar
    let layout: GifPickerLayout
    let collectionView: UICollectionView
    var noResultsView: UILabel?
    var searchErrorView: UILabel?
    var activityIndicator: UIActivityIndicatorView?
    var hasSelectedCell: Bool = false
    var imageInfos = [GiphyImageInfo]()

    var reachability: Reachability?

    private let kCellReuseIdentifier = "kCellReuseIdentifier"

    var progressiveSearchTimer: Timer?

    // MARK: - Initialization

    @available(*, unavailable, message:"use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    required init() {
        self.searchBar = SearchBar()
        self.layout = GifPickerLayout()
        self.collectionView = UICollectionView(frame: CGRect.zero, collectionViewLayout: self.layout)

        super.init(nibName: nil, bundle: nil)

        self.layout.delegate = self
    }

    deinit {
        NotificationCenter.default.removeObserver(self)

        progressiveSearchTimer?.invalidate()
    }

    @objc func didBecomeActive() {
        AssertIsOnMainThread()

        Logger.info("")

        // Prod cells to try to load when app becomes active.
        ensureCellState()
    }

    @objc func reachabilityChanged() {
        AssertIsOnMainThread()

        Logger.info("")

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

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(donePressed)
        )
        
        // Loki: Customize title
        let titleLabel: UILabel = UILabel()
        titleLabel.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        titleLabel.text = "accessibility_gif_button".localized().uppercased()
        titleLabel.themeTextColor = .textPrimary
        navigationItem.titleView = titleLabel

        createViews()

        reachability = Reachability.forInternetConnection()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reachabilityChanged),
            name: .reachabilityChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil
        )
        
        loadTrending()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.searchBar.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        progressiveSearchTimer?.invalidate()
        progressiveSearchTimer = nil
    }

    // MARK: Views

    private func createViews() {
        self.view.themeBackgroundColor = .backgroundPrimary
        
        // Search
        searchBar.delegate = self

        self.view.addSubview(searchBar)
        searchBar.autoPinWidthToSuperview()
        searchBar.autoPinEdge(.top, to: .top, of: view)

        self.collectionView.delegate = self
        self.collectionView.dataSource = self
        self.collectionView.themeBackgroundColor = .backgroundPrimary
        self.collectionView.register(GifPickerCell.self, forCellWithReuseIdentifier: kCellReuseIdentifier)
        // Inserted below searchbar because we later occlude the collectionview
        // by inserting a masking layer between the search bar and collectionview
        self.view.insertSubview(self.collectionView, belowSubview: searchBar)
        self.collectionView.autoPinEdge(toSuperviewSafeArea: .leading)
        self.collectionView.autoPinEdge(toSuperviewSafeArea: .trailing)
        self.collectionView.autoPinEdge(.top, to: .bottom, of: searchBar)
        
        // Block UIKit from adjust insets of collection view which screws up
        // min/max scroll positions
        self.collectionView.contentInsetAdjustmentBehavior = .never

        // for iPhoneX devices, extends the black background to the bottom edge of the view.
        let bottomBannerContainer = UIView()
        bottomBannerContainer.themeBackgroundColor = .backgroundPrimary
        self.view.addSubview(bottomBannerContainer)
        bottomBannerContainer.autoPinWidthToSuperview()
        bottomBannerContainer.autoPinEdge(.top, to: .bottom, of: self.collectionView)
        bottomBannerContainer.autoPinEdge(toSuperviewEdge: .bottom)

        let bottomBanner = UIView()
        bottomBannerContainer.addSubview(bottomBanner)

        bottomBanner.autoPinEdge(toSuperviewEdge: .top)
        bottomBanner.autoPinWidthToSuperview()
        self.autoPinView(toBottomOfViewControllerOrKeyboard: bottomBanner, avoidNotch: true)

        // The Giphy API requires us to "show their trademark prominently" in our GIF experience.
        let logoImage = UIImage(named: "giphy_logo")
        let logoImageView = UIImageView(image: logoImage)
        bottomBanner.addSubview(logoImageView)
        logoImageView.autoPinHeightToSuperview(withMargin: 3)
        logoImageView.autoHCenterInSuperview()

        let noResultsView = createErrorLabel(text: "GIF_VIEW_SEARCH_NO_RESULTS".localized())
        self.noResultsView = noResultsView
        self.view.addSubview(noResultsView)
        noResultsView.autoPinWidthToSuperview(withMargin: 20)
        noResultsView.autoAlignAxis(.horizontal, toSameAxisOf: self.collectionView)

        let searchErrorView = createErrorLabel(text: "GIF_VIEW_SEARCH_ERROR".localized())
        self.searchErrorView = searchErrorView
        self.view.addSubview(searchErrorView)
        searchErrorView.autoPinWidthToSuperview(withMargin: 20)
        searchErrorView.autoAlignAxis(.horizontal, toSameAxisOf: self.collectionView)

        searchErrorView.isUserInteractionEnabled = true
        searchErrorView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(retryTapped)))

        let activityIndicator = UIActivityIndicatorView(style: .large)
        self.activityIndicator = activityIndicator
        self.view.addSubview(activityIndicator)
        activityIndicator.autoHCenterInSuperview()
        activityIndicator.autoAlignAxis(.horizontal, toSameAxisOf: self.collectionView)
        
        self.updateContents()
    }

    private func createErrorLabel(text: String) -> UILabel {
        let label: UILabel = UILabel()
        label.font = .ows_mediumFont(withSize: 20)
        label.text = text
        label.themeTextColor = .textPrimary
        label.textAlignment = .center
        label.lineBreakMode = .byWordWrapping
        label.numberOfLines = 0
        
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

                self.collectionView.collectionViewLayout.invalidateLayout()
                self.collectionView.reloadData()
                
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

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) as? GifPickerCell else {
            owsFailDebug("unexpected cell.")
            return
        }

        guard cell.stillAsset != nil || cell.animatedAsset != nil else {
            // we don't want to let the user blindly select a gray cell
            Logger.debug("ignoring selection of cell with no preview")
            return
        }

        guard self.hasSelectedCell == false else {
            owsFailDebug("Already selected cell")
            return
        }
        self.hasSelectedCell = true

        // Fade out all cells except the selected one.
        let maskingView = OWSBezierPathView()

        // Selecting cell behind searchbar masks part of search bar.
        // So we insert mask *behind* the searchbar.
        self.view.insertSubview(maskingView, belowSubview: searchBar)
        let cellRect = self.collectionView.convert(cell.frame, to: self.view)
        maskingView.configureShapeLayerBlock = { layer, bounds in
            let path = UIBezierPath(rect: bounds)
            path.append(UIBezierPath(rect: cellRect))

            layer.path = path.cgPath
            layer.fillRule = .evenOdd
            layer.themeFillColor = .black
            layer.opacity = 0.7
        }
        maskingView.autoPinEdgesToSuperviewEdges()

        cell.isCellSelected = true
        self.collectionView.isUserInteractionEnabled = false

        getFileForCell(cell)
    }

    public func getFileForCell(_ cell: GifPickerCell) {
        GiphyDownloader.giphyDownloader.cancelAllRequests()

        firstly {
            cell.requestRenditionForSending()
        }.done { [weak self] (asset: ProxiedContentAsset) in
            guard let strongSelf = self else {
                Logger.info("ignoring send, since VC was dismissed before fetching finished.")
                return
            }
            guard let rendition = asset.assetDescription as? GiphyRendition else {
                owsFailDebug("Invalid asset description.")
                return
            }

            let filePath = asset.filePath
            guard let dataSource = DataSourcePath.dataSource(withFilePath: filePath,
                shouldDeleteOnDeallocation: false) else {
                owsFailDebug("couldn't load asset.")
                return
            }
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: rendition.utiType, imageQuality: .medium)

            strongSelf.dismiss(animated: true) {
                // Delegate presents view controllers, so it's important that *this* controller be dismissed before that occurs.
                strongSelf.delegate?.gifPickerDidSelect(attachment: attachment)
            }
        }.catch { [weak self] error in
            guard let strongSelf = self else {
                Logger.info("ignoring failure, since VC was dismissed before fetching finished.")
                return
            }

            let alert = UIAlertController(
                title: "GIF_PICKER_FAILURE_ALERT_TITLE".localized(),
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: CommonStrings.retryButton, style: .default) { _ in
                    strongSelf.getFileForCell(cell)
            })
            alert.addAction(UIAlertAction(title: CommonStrings.dismissButton, style: .cancel) { _ in
                strongSelf.dismiss(animated: true, completion: nil)
            })

            strongSelf.presentAlert(alert)
        }.retainUntilComplete()
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

    // MARK: - Event Handlers

    @objc func donePressed(sender: UIButton) {
        dismiss(animated: true, completion: nil)
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
        progressiveSearchTimer = WeakTimer.scheduledTimer(timeInterval: kProgressiveSearchDelaySeconds, target: self, userInfo: nil, repeats: true) { [weak self] _ in
            self?.tryToSearch()
        }
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        self.searchBar.resignFirstResponder()

        tryToSearch()
    }

    public func tryToSearch() {
        progressiveSearchTimer?.invalidate()
        progressiveSearchTimer = nil

        guard let text: String = searchBar.text else {
            // Alert message shown when user tries to search for GIFs without entering any search terms
            OWSAlerts.showErrorAlert(message: "GIF_PICKER_VIEW_MISSING_QUERY".localized())
            return
        }
        
        let query: String = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if (viewMode == .searching || viewMode == .results) && lastQuery == query {
            Logger.info("ignoring duplicate search: \(query)")
            return
        }

        guard !query.isEmpty else {
            loadTrending()
            return
        }
        
        search(query: query)
    }
    
    private func loadTrending() {
        assert(progressiveSearchTimer == nil)
        assert(searchBar.text == nil || searchBar.text?.count == 0)

        GiphyAPI.sharedInstance.trending()
            .done { [weak self] imageInfos in
                Logger.info("showing trending")
                
                if imageInfos.count > 0 {
                    self?.imageInfos = imageInfos
                    self?.viewMode = .results
                }
                else {
                    owsFailDebug("trending results was unexpectedly empty")
                }
            }
            .catch { error in
                // Don't both showing error UI feedback for default "trending" results.
                Logger.error("error: \(error)")
            }
    }

    private func search(query: String) {
        Logger.info("searching: \(query)")

        progressiveSearchTimer?.invalidate()
        progressiveSearchTimer = nil
        imageInfos = []
        viewMode = .searching
        lastQuery = query
        self.collectionView.contentOffset = CGPoint.zero

        GiphyAPI.sharedInstance
            .search(
                query: query,
                success: { [weak self] imageInfos in
                    Logger.info("search complete")
                    self?.imageInfos = imageInfos
                    
                    if imageInfos.count > 0 {
                        self?.viewMode = .results
                    }
                    else {
                        self?.viewMode = .noResults
                    }
                },
                failure: { [weak self] _ in
                    Logger.info("search failed.")
                    // TODO: Present this error to the user.
                    self?.viewMode = .error
                }
            )
    }

    // MARK: - GifPickerLayoutDelegate

    func imageInfosForLayout() -> [GiphyImageInfo] {
        return imageInfos
    }

    // MARK: - Event Handlers

    @objc func retryTapped(sender: UIGestureRecognizer) {
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

// MARK: - GifPickerViewControllerDelegate

protocol GifPickerViewControllerDelegate: AnyObject {
    func gifPickerDidSelect(attachment: SignalAttachment)
}
