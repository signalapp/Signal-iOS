//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
protocol GifPickerViewControllerDelegate: class {
    func gifPickerWillSend()
    func gifPickerDidSend(outgoingMessage: TSOutgoingMessage)
}

class GifPickerViewController: OWSViewController, UISearchBarDelegate, UICollectionViewDataSource, UICollectionViewDelegate, GifPickerLayoutDelegate {
    let TAG = "[GifPickerViewController]"

    // MARK: Properties

    enum ViewMode {
        case idle, searching, results, noResults, error
    }

    private var viewMode = ViewMode.idle {
        didSet {
            Logger.info("\(TAG) viewMode: \(viewMode)")

            updateContents()
        }
    }

    public weak var delegate: GifPickerViewControllerDelegate?

    var thread: TSThread?
    var messageSender: MessageSender?

    let searchBar: UISearchBar
    let layout: GifPickerLayout
    let collectionView: UICollectionView
    var noResultsView: UILabel?
    var searchErrorView: UILabel?
    var activityIndicator: UIActivityIndicatorView?

    var imageInfos = [GiphyImageInfo]()

    var reachability: Reachability?

    private let kCellReuseIdentifier = "kCellReuseIdentifier"

    var progressiveSearchTimer: Timer?

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        self.thread = nil
        self.messageSender = nil

        self.searchBar = UISearchBar()
        self.layout = GifPickerLayout()
        self.collectionView = UICollectionView(frame:CGRect.zero, collectionViewLayout:self.layout)

        super.init(coder: aDecoder)
        owsFail("\(self.TAG) invalid constructor")
    }

    required init(thread: TSThread, messageSender: MessageSender) {
        self.thread = thread
        self.messageSender = messageSender

        self.searchBar = UISearchBar()
        self.layout = GifPickerLayout()
        self.collectionView = UICollectionView(frame:CGRect.zero, collectionViewLayout:self.layout)

        super.init(nibName: nil, bundle: nil)

        self.layout.delegate = self
    }

    deinit {
        NotificationCenter.default.removeObserver(self)

        progressiveSearchTimer?.invalidate()
    }

    func didBecomeActive() {
        AssertIsOnMainThread()

        Logger.info("\(self.TAG) \(#function)")

        // Prod cells to try to load when app becomes active.
        ensureCellState()
    }

    func reachabilityChanged() {
        AssertIsOnMainThread()

        Logger.info("\(self.TAG) \(#function)")

        // Prod cells to try to load when connectivity changes.
        ensureCellState()
    }

    func ensureCellState() {
        for cell in self.collectionView.visibleCells {
            guard let cell = cell as? GifPickerCell else {
                owsFail("\(TAG) unexpected cell.")
                return
            }
            cell.ensureCellState()
        }
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem:.cancel,
                                                                target:self,
                                                                action:#selector(donePressed))
        self.navigationItem.title = NSLocalizedString("GIF_PICKER_VIEW_TITLE",
                                                      comment: "Title for the 'gif picker' dialog.")

        createViews()

        reachability = Reachability.forInternetConnection()
        NotificationCenter.default.addObserver(self,
                                               selector:#selector(reachabilityChanged),
                                               name:NSNotification.Name.reachabilityChanged,
                                               object:nil)
        NotificationCenter.default.addObserver(self,
                                               selector:#selector(didBecomeActive),
                                               name:NSNotification.Name.UIApplicationDidBecomeActive,
                                               object:nil)
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

        view.backgroundColor = UIColor.white

        // Search
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.placeholder = NSLocalizedString("GIF_VIEW_SEARCH_PLACEHOLDER_TEXT",
                                                  comment:"Placeholder text for the search field in gif view")
        searchBar.backgroundColor = UIColor.white

        self.view.addSubview(searchBar)
        searchBar.autoPinWidthToSuperview()
        searchBar.autoPin(toTopLayoutGuideOf: self, withInset:0)

        self.collectionView.delegate = self
        self.collectionView.dataSource = self
        self.collectionView.backgroundColor = UIColor.white
        self.collectionView.register(GifPickerCell.self, forCellWithReuseIdentifier: kCellReuseIdentifier)
        self.view.addSubview(self.collectionView)
        self.collectionView.autoPinWidthToSuperview()
        self.collectionView.autoPinEdge(.top, to:.bottom, of:searchBar)

        let bottomBanner = UIView()
        bottomBanner.backgroundColor = UIColor.black
        self.view.addSubview(bottomBanner)
        bottomBanner.autoPinWidthToSuperview()
        bottomBanner.autoPinEdge(.top, to:.bottom, of:self.collectionView)
        bottomBanner.autoPin(toBottomLayoutGuideOf: self, withInset:0)

        // The Giphy API requires us to "show their trademark prominently" in our GIF experience.
        let logoImage = UIImage(named:"giphy_logo")
        let logoImageView = UIImageView(image:logoImage)
        bottomBanner.addSubview(logoImageView)
        logoImageView.autoPinHeightToSuperview(withMargin:3)
        logoImageView.autoHCenterInSuperview()

        let noResultsView = createErrorLabel(text:NSLocalizedString("GIF_VIEW_SEARCH_NO_RESULTS",
                                                                    comment:"Indicates that the user's search had no results."))
        self.noResultsView = noResultsView
        self.view.addSubview(noResultsView)
        noResultsView.autoPinWidthToSuperview(withMargin:20)
        noResultsView.autoVCenterInSuperview()

        let searchErrorView = createErrorLabel(text:NSLocalizedString("GIF_VIEW_SEARCH_ERROR",
                                                                      comment:"Indicates that an error occured while searching."))
        self.searchErrorView = searchErrorView
        self.view.addSubview(searchErrorView)
        searchErrorView.autoPinWidthToSuperview(withMargin:20)
        searchErrorView.autoVCenterInSuperview()

        searchErrorView.isUserInteractionEnabled = true
        searchErrorView.addGestureRecognizer(UITapGestureRecognizer(target:self, action:#selector(retryTapped)))

        let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle:.gray)
        self.activityIndicator = activityIndicator
        self.view.addSubview(activityIndicator)
        activityIndicator.autoCenterInSuperview()

        self.updateContents()
    }

    private func createErrorLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = UIColor.black
        label.font = UIFont.ows_mediumFont(withSize:20)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private func updateContents() {
        guard let noResultsView = self.noResultsView else {
            owsFail("Missing noResultsView")
            return
        }
        guard let searchErrorView = self.searchErrorView else {
            owsFail("Missing searchErrorView")
            return
        }
        guard let activityIndicator = self.activityIndicator else {
            owsFail("Missing activityIndicator")
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

    // MARK: - UICollectionViewDataSource

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageInfos.count
    }

    public  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let imageInfo = imageInfos[indexPath.row]

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier:kCellReuseIdentifier, for: indexPath)
        guard let gifCell = cell as? GifPickerCell else {
            owsFail("\(TAG) Unexpected cell type.")
            return cell
        }
        gifCell.imageInfo = imageInfo
        return cell
    }

    // MARK: - UICollectionViewDelegate

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at:indexPath) as? GifPickerCell else {
            owsFail("\(TAG) unexpected cell.")
            return
        }
        guard let asset = cell.animatedAsset else {
            Logger.info("\(TAG) unload cell selected.")
            return
        }
        let filePath = asset.filePath
        guard let dataSource = DataSourcePath.dataSource(withFilePath:filePath) else {
            owsFail("\(TAG) couldn't load asset.")
            return
        }
        let attachment = SignalAttachment(dataSource : dataSource, dataUTI: asset.rendition.utiType)
        guard let thread = thread else {
            owsFail("\(TAG) Missing thread.")
            return
        }
        guard let messageSender = messageSender else {
            owsFail("\(TAG) Missing messageSender.")
            return
        }

        self.delegate?.gifPickerWillSend()

        let outgoingMessage = ThreadUtil.sendMessage(with: attachment, in: thread, messageSender: messageSender)

        self.delegate?.gifPickerDidSend(outgoingMessage: outgoingMessage)

        dismiss(animated: true, completion:nil)
    }

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? GifPickerCell else {
            owsFail("\(TAG) unexpected cell.")
            return
        }
        // We only want to load the cells which are on-screen.
        cell.isCellVisible = true
    }

    public func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? GifPickerCell else {
            owsFail("\(TAG) unexpected cell.")
            return
        }
        cell.isCellVisible = false
    }

    // MARK: - Event Handlers

    func donePressed(sender: UIButton) {
        dismiss(animated: true, completion:nil)
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
        let kProgressiveSearchDelaySeconds = 2.0
        progressiveSearchTimer = WeakTimer.scheduledTimer(timeInterval: kProgressiveSearchDelaySeconds, target: self, userInfo: nil, repeats: true) { [weak self] _ in
            guard let strongSelf = self else {
                return
            }

            strongSelf.tryToSearch()
        }
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        tryToSearch()
    }

    public func tryToSearch() {
        progressiveSearchTimer?.invalidate()
        progressiveSearchTimer = nil

        guard let text = searchBar.text else {
            OWSAlerts.showAlert(withTitle: NSLocalizedString("ALERT_ERROR_TITLE",
                                                             comment: ""),
                                message: NSLocalizedString("GIF_PICKER_VIEW_MISSING_QUERY",
                                                           comment: "Alert message shown when user tries to search for GIFs without entering any search terms."))
            return
        }
        search(query:text)
    }

    private func search(query: String) {
        Logger.info("\(TAG) searching: \(query)")

        progressiveSearchTimer?.invalidate()
        progressiveSearchTimer = nil
        self.searchBar.resignFirstResponder()
        imageInfos = []
        viewMode = .searching
        self.collectionView.contentOffset = CGPoint.zero

        GiphyAPI.sharedInstance.search(query: query, success: { [weak self] imageInfos in
            guard let strongSelf = self else { return }
            Logger.info("\(strongSelf.TAG) search complete")
            strongSelf.imageInfos = imageInfos
            if imageInfos.count > 0 {
                strongSelf.viewMode = .results
            } else {
                strongSelf.viewMode = .noResults
            }
        },
            failure: { [weak self] _ in
                guard let strongSelf = self else { return }
                Logger.info("\(strongSelf.TAG) search failed.")
                // TODO: Present this error to the user.
                strongSelf.viewMode = .error
        })
    }

    // MARK: - GifPickerLayoutDelegate

    func imageInfosForLayout() -> [GiphyImageInfo] {
        return imageInfos
    }

    // MARK: - Event Handlers

    func retryTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        guard viewMode == .error else {
            return
        }
        tryToSearch()
    }
}
