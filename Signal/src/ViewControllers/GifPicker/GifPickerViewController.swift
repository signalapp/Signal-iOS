//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

class GifPickerViewController: OWSViewController, UISearchBarDelegate, UICollectionViewDataSource, UICollectionViewDelegate, GifPickerLayoutDelegate {
    let TAG = "[GifPickerViewController]"

    // MARK: Properties

    var thread: TSThread?
    var messageSender: MessageSender?

    let searchBar: UISearchBar
    let layout: GifPickerLayout
    let collectionView: UICollectionView
    var logoImageView: UIImageView?

    var imageInfos = [GiphyImageInfo]()

    private let kCellReuseIdentifier = "kCellReuseIdentifier"

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

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.black

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem:.stop,
                                                                target:self,
                                                                action:#selector(donePressed))
        self.navigationItem.title = NSLocalizedString("GIF_PICKER_VIEW_TITLE",
                                                      comment: "Title for the 'gif picker' dialog.")

        createViews()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        search(query:"funny")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.searchBar.becomeFirstResponder()
    }

    // MARK: Views

    private func createViews() {

        view.backgroundColor = UIColor.black

        // Search
//        searchBar.searchBarStyle = .minimal
        searchBar.searchBarStyle = .default
        searchBar.delegate = self
        searchBar.placeholder = NSLocalizedString("GIF_VIEW_SEARCH_PLACEHOLDER_TEXT",
                                                  comment:"Placeholder text for the search field in gif view")
//        searchBar.backgroundColor = UIColor(white:0.6, alpha:1.0)
//        searchBar.backgroundColor = UIColor.white
//        searchBar.backgroundColor = UIColor.black
//        searchBar.barTintColor = UIColor.red
        searchBar.isTranslucent = false
//        searchBar.backgroundColor = UIColor.white
        searchBar.backgroundImage = UIImage(color:UIColor.clear)
        searchBar.barTintColor = UIColor.black
        searchBar.tintColor = UIColor.white
        self.view.addSubview(searchBar)
        searchBar.autoPinWidthToSuperview()
        searchBar.autoPin(toTopLayoutGuideOf: self, withInset:0)
        //        [searchBar sizeToFit];

//        if #available(iOS 10, *) {
//            self.collectionView.isPrefetchingEnabled = false
//        }
        self.collectionView.delegate = self
        self.collectionView.dataSource = self
        self.collectionView.backgroundColor = UIColor.black
        self.collectionView.register(GifPickerCell.self, forCellWithReuseIdentifier: kCellReuseIdentifier)
        self.view.addSubview(self.collectionView)
        self.collectionView.autoPinWidthToSuperview()
        self.collectionView.autoPinEdge(.top, to:.bottom, of:searchBar)
        self.collectionView.autoPin(toBottomLayoutGuideOf: self, withInset:0)

        let logoImage = UIImage(named:"giphy_logo")
        let logoImageView = UIImageView(image:logoImage)
        self.logoImageView = logoImageView
        self.view.addSubview(logoImageView)
        logoImageView.autoCenterInSuperview()

        self.updateContents()
    }

    private func setContentVisible(_ isVisible: Bool) {
        self.collectionView.isHidden = !isVisible
        if let logoImageView = self.logoImageView {
            logoImageView.isHidden = isVisible
        }
    }

    private func updateContents() {
        if imageInfos.count < 1 {
            setContentVisible(false)
        } else {
            setContentVisible(true)
        }

        self.collectionView.collectionViewLayout.invalidateLayout()
        self.collectionView.reloadData()
    }

    // MARK: - UICollectionViewDataSource

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageInfos.count
    }

    // The cell that is returned must be retrieved from a call to -dequeueReusableCellWithReuseIdentifier:forIndexPath:
    public  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let imageInfo = imageInfos[indexPath.row]

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier:kCellReuseIdentifier, for: indexPath) as! GifPickerCell
        cell.imageInfo = imageInfo
        return cell
    }

    // MARK: - UICollectionViewDelegate

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at:indexPath) as? GifPickerCell else {
            owsFail("\(TAG) unexpected cell.")
            return
        }
        guard let asset = cell.asset else {
            Logger.info("\(TAG) unload cell selected.")
            return
        }
        let filePath = asset.filePath
        guard let dataSource = DataSourcePath.dataSource(withFilePath:filePath) else {
            owsFail("\(TAG) couldn't load asset.")
            return
        }
        let attachment = SignalAttachment(dataSource : dataSource, dataUTI: asset.rendition.utiType())
        guard let thread = thread else {
            owsFail("\(TAG) Missing thread.")
            return
        }
        guard let messageSender = messageSender else {
            owsFail("\(TAG) Missing messageSender.")
            return
        }
        ThreadUtil.sendMessage(with: attachment, in: thread, messageSender: messageSender)

        dismiss(animated: true, completion:nil)
    }

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? GifPickerCell else {
            owsFail("\(TAG) unexpected cell.")
            return
        }
        // We only want to load the cells which are on-screen.
        cell.shouldLoad = true
    }

    public func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? GifPickerCell else {
            owsFail("\(TAG) unexpected cell.")
            return
        }
        cell.shouldLoad = false
    }

    // MARK: - Event Handlers

    func donePressed(sender: UIButton) {
        dismiss(animated: true, completion:nil)
    }

    // MARK: - UISearchBarDelegate

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        // TODO: We could do progressive search as the user types.
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let text = searchBar.text else {
            // TODO: Alert?
            return
        }
        search(query:text)
    }

    private func search(query: String) {
        self.searchBar.resignFirstResponder()
        imageInfos = []
        updateContents()
        self.collectionView.contentOffset = CGPoint.zero

        GifManager.sharedInstance.search(query: query, success: { [weak self] imageInfos in
            guard let strongSelf = self else { return }
            Logger.info("\(strongSelf.TAG) search complete")
            strongSelf.imageInfos = imageInfos
            strongSelf.updateContents()
        },
            failure: { [weak self] in
                guard let strongSelf = self else { return }
                Logger.info("\(strongSelf.TAG) search failed.")
        })
    }

    // MARK: - GifPickerLayoutDelegate

    func imageInfosForLayout() -> [GiphyImageInfo] {
        return imageInfos
    }
}
