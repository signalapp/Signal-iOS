//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import Reachability
import SignalMessaging

@objc
protocol GifPickerViewControllerDelegate: class {
    func gifPickerDidSelect(attachment: SignalAttachment)
}

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

    @objc
    public weak var delegate: GifPickerViewControllerDelegate?

    let thread: TSThread
    let messageSender: MessageSender

    let searchBar: UISearchBar
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

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    required init(thread: TSThread, messageSender: MessageSender) {
        self.thread = thread
        self.messageSender = messageSender

        self.searchBar = OWSSearchBar()
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

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                                target: self,
                                                                action: #selector(donePressed))
        self.navigationItem.title = NSLocalizedString("GIF_PICKER_VIEW_TITLE",
                                                      comment: "Title for the 'GIF picker' dialog.")

        createViews()

        reachability = Reachability.forInternetConnection()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reachabilityChanged),
                                               name: NSNotification.Name.reachabilityChanged,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: NSNotification.Name.OWSApplicationDidBecomeActive,
                                               object: nil)
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

        let backgroundColor = (Theme.isDarkThemeEnabled
            ? UIColor(white: 0.08, alpha: 1.0)
            : Theme.backgroundColor)
        self.view.backgroundColor = backgroundColor

        // Block UIKit from adjust insets of collection view which screws up
        // min/max scroll positions.
        self.automaticallyAdjustsScrollViewInsets = false

        // Search
        searchBar.delegate = self
        searchBar.placeholder = NSLocalizedString("GIF_VIEW_SEARCH_PLACEHOLDER_TEXT",
                                                  comment: "Placeholder text for the search field in GIF view")

        self.view.addSubview(searchBar)
        searchBar.autoPinWidthToSuperview()
        searchBar.autoPin(toTopLayoutGuideOf: self, withInset: 0)

        self.collectionView.delegate = self
        self.collectionView.dataSource = self
        self.collectionView.backgroundColor = backgroundColor
        self.collectionView.register(GifPickerCell.self, forCellWithReuseIdentifier: kCellReuseIdentifier)
        // Inserted below searchbar because we later occlude the collectionview
        // by inserting a masking layer between the search bar and collectionview
        self.view.insertSubview(self.collectionView, belowSubview: searchBar)
        self.collectionView.autoPinWidthToSuperview()
        self.collectionView.autoPinEdge(.top, to: .bottom, of: searchBar)

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
        self.autoPinView(toBottomOfViewControllerOrKeyboard: bottomBanner, avoidNotch: true)

        // The Giphy API requires us to "show their trademark prominently" in our GIF experience.
        let logoImage = UIImage(named: "giphy_logo")
        let logoImageView = UIImageView(image: logoImage)
        bottomBanner.addSubview(logoImageView)
        logoImageView.autoPinHeightToSuperview(withMargin: 3)
        logoImageView.autoHCenterInSuperview()

        let noResultsView = createErrorLabel(text: NSLocalizedString("GIF_VIEW_SEARCH_NO_RESULTS",
                                                                    comment: "Indicates that the user's search had no results."))
        self.noResultsView = noResultsView
        self.view.addSubview(noResultsView)
        noResultsView.autoPinWidthToSuperview(withMargin: 20)
        noResultsView.autoAlignAxis(.horizontal, toSameAxisOf: self.collectionView)

        let searchErrorView = createErrorLabel(text: NSLocalizedString("GIF_VIEW_SEARCH_ERROR",
                                                                      comment: "Indicates that an error occurred while searching."))
        self.searchErrorView = searchErrorView
        self.view.addSubview(searchErrorView)
        searchErrorView.autoPinWidthToSuperview(withMargin: 20)
        searchErrorView.autoAlignAxis(.horizontal, toSameAxisOf: self.collectionView)

        searchErrorView.isUserInteractionEnabled = true
        searchErrorView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(retryTapped)))

        let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
        self.activityIndicator = activityIndicator
        self.view.addSubview(activityIndicator)
        activityIndicator.autoHCenterInSuperview()
        activityIndicator.autoAlignAxis(.horizontal, toSameAxisOf: self.collectionView)

        self.updateContents()
    }

    private func createErrorLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = Theme.primaryColor
        label.font = UIFont.ows_mediumFont(withSize: 20)
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
            layer.fillRule = kCAFillRuleEvenOdd
            layer.fillColor = UIColor.black.cgColor
            layer.opacity = 0.7
        }
        maskingView.autoPinEdgesToSuperviewEdges()

        cell.isCellSelected = true
        self.collectionView.isUserInteractionEnabled = false

        getFileForCell(cell)
    }

    public func getFileForCell(_ cell: GifPickerCell) {
        GiphyDownloader.sharedInstance.cancelAllRequests()
        cell.requestRenditionForSending().then { [weak self] (asset: GiphyAsset) -> Void in
            guard let strongSelf = self else {
                Logger.info("ignoring send, since VC was dismissed before fetching finished.")
                return
            }

            let filePath = asset.filePath
            guard let dataSource = DataSourcePath.dataSource(withFilePath: filePath,
                shouldDeleteOnDeallocation: false) else {
                owsFailDebug("couldn't load asset.")
                return
            }
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: asset.rendition.utiType, imageQuality: .original)

            strongSelf.dismiss(animated: true) {
                // Delegate presents view controllers, so it's important that *this* controller be dismissed before that occurs.
                strongSelf.delegate?.gifPickerDidSelect(attachment: attachment)
            }
        }.catch { [weak self] error in
            guard let strongSelf = self else {
                Logger.info("ignoring failure, since VC was dismissed before fetching finished.")
                return
            }

            let alert = UIAlertController(title: NSLocalizedString("GIF_PICKER_FAILURE_ALERT_TITLE", comment: "Shown when selected GIF couldn't be fetched"),
                                          message: error.localizedDescription,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: CommonStrings.retryButton, style: .default) { _ in
                    strongSelf.getFileForCell(cell)
            })
            alert.addAction(UIAlertAction(title: CommonStrings.dismissButton, style: .cancel) { _ in
                strongSelf.dismiss(animated: true, completion: nil)
            })

            strongSelf.present(alert, animated: true, completion: nil)
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
            OWSAlerts.showErrorAlert(message: NSLocalizedString("GIF_PICKER_VIEW_MISSING_QUERY",
                                                           comment: "Alert message shown when user tries to search for GIFs without entering any search terms."))
            return
        }

        let query = (text as String).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        if (viewMode == .searching || viewMode == .results) && lastQuery == query {
            Logger.info("ignoring duplicate search: \(query)")
            return
        }

        search(query: query)
    }

    private func search(query: String) {
        Logger.info("searching: \(query)")

        progressiveSearchTimer?.invalidate()
        progressiveSearchTimer = nil
        imageInfos = []
        viewMode = .searching
        lastQuery = query
        self.collectionView.contentOffset = CGPoint.zero

        GiphyAPI.sharedInstance.search(query: query, success: { [weak self] imageInfos in
            guard let strongSelf = self else { return }
            Logger.info("search complete")
            strongSelf.imageInfos = imageInfos
            if imageInfos.count > 0 {
                strongSelf.viewMode = .results
            } else {
                strongSelf.viewMode = .noResults
            }
        },
            failure: { [weak self] _ in
                guard let strongSelf = self else { return }
                Logger.info("search failed.")
                // TODO: Present this error to the user.
                strongSelf.viewMode = .error
        })
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
}
