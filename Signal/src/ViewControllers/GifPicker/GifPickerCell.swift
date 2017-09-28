//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
//import MediaPlayer

class GifPickerCell: UICollectionViewCell
    //, OWSAudioAttachmentPlayerDelegate
{
    let TAG = "[GifPickerCell]"

    // MARK: Properties

    var imageInfo: GiphyImageInfo?
//
//    let searchBar: UISearchBar
//    let layout: GifPickerLayout
//    let collectionView: UICollectionView
//    var logoImageView : UIImageView?
//    
//    var imageInfos = [GiphyImageInfo]()
//    
//    //    let attachment: SignalAttachment
//    //
//    //    var successCompletion : (() -> Void)?
//    //
//    //    var videoPlayer: MPMoviePlayerController?
//    //
//    //    var audioPlayer: OWSAudioAttachmentPlayer?
//    //    var audioStatusLabel: UILabel?
//    //    var audioPlayButton: UIButton?
//    //    var isAudioPlayingFlag = false
//    //    var isAudioPaused = false
//    //    var audioProgressSeconds: CGFloat = 0
//    //    var audioDurationSeconds: CGFloat = 0
//
//    // MARK: Initializers
//
//    @available(*, unavailable, message:"use attachment: constructor instead.")
//    required init?(coder aDecoder: NSCoder) {
//        self.searchBar = UISearchBar()
//        self.layout = GifPickerLayout()
//        self.collectionView = UICollectionView(frame:CGRect.zero, collectionViewLayout:self.layout)
//        //        self.attachment = SignalAttachment.empty()
//        super.init(coder: aDecoder)
//        owsFail("\(self.TAG) invalid constructor")
//    }
//
//    required init() {
//        self.searchBar = UISearchBar()
//        self.layout = GifPickerLayout()
//        self.collectionView = UICollectionView(frame:CGRect.zero, collectionViewLayout:self.layout)
//        //        assert(!attachment.hasError)
//        //        self.attachment = attachment
//        //        self.successCompletion = successCompletion
//        super.init(nibName: nil, bundle: nil)
//    }

    override func prepareForReuse() {
        super.prepareForReuse()
    }
//
//    // MARK: View Lifecycle
//
//    override func viewDidLoad() {
//        super.viewDidLoad()
//
//        view.backgroundColor = UIColor.black
//
//        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem:.stop,
//                                                                target:self,
//                                                                action:#selector(donePressed))
//        self.navigationItem.title = NSLocalizedString("GIF_PICKER_VIEW_TITLE",
//                                                      comment: "Title for the 'gif picker' dialog.")
//
//        createViews()
//    }
//
//    // MARK: Views
//
//    private func createViews() {
//
//        view.backgroundColor = UIColor.black
//
//        // Search
////        searchBar.searchBarStyle = .minimal
//        searchBar.searchBarStyle = .default
//        searchBar.delegate = self
//        searchBar.placeholder = NSLocalizedString("GIF_VIEW_SEARCH_PLACEHOLDER_TEXT",
//                                                  comment:"Placeholder text for the search field in gif view")
////        searchBar.backgroundColor = UIColor(white:0.6, alpha:1.0)
////        searchBar.backgroundColor = UIColor.white
////        searchBar.backgroundColor = UIColor.black
////        searchBar.barTintColor = UIColor.red
//        searchBar.isTranslucent = false
////        searchBar.backgroundColor = UIColor.white
//        searchBar.backgroundImage = UIImage(color:UIColor.clear)
//        searchBar.barTintColor = UIColor.black
//        searchBar.tintColor = UIColor.white
//        self.view.addSubview(searchBar)
//        searchBar.autoPinWidthToSuperview()
//        searchBar.autoPin(toTopLayoutGuideOf: self, withInset:0)
//        //        [searchBar sizeToFit];
//
//        self.collectionView.delegate = self
//        self.collectionView.dataSource = self
//        self.collectionView.backgroundColor = UIColor.black
//        self.view.addSubview(self.collectionView)
//        self.collectionView.autoPinWidthToSuperview()
//        self.collectionView.autoPinEdge(.top, to:.bottom, of:searchBar)
//        self.collectionView.autoPin(toBottomLayoutGuideOf: self, withInset:0)
//        
//        let logoImage = UIImage(named:"giphy_logo")
//        let logoImageView = UIImageView(image:logoImage)
//        self.logoImageView = logoImageView
//        self.view.addSubview(logoImageView)
//        logoImageView.autoCenterInSuperview()
//
//        self.updateContents()
//        //        [self updateTableContents];
//    }
//    
//    private func setContentVisible(_ isVisible:Bool) {
//        self.collectionView.isHidden = !isVisible
//        if let logoImageView = self.logoImageView {
//            logoImageView.isHidden = isVisible
//        }
//    }
//    
//    private func updateContents() {
//        if imageInfos.count < 1 {
//            setContentVisible(false)
//        } else {
//            setContentVisible(true)
//        }
//        
//        self.collectionView.collectionViewLayout.invalidateLayout()
//        self.collectionView.reloadData()
//    }
//
//    //    override func viewDidLoad() {
//    //        super.viewDidLoad()
//    //
//    //        view.backgroundColor = UIColor.white
//    //
//    //        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem:.stop,
//    //                                                                target:self,
//    //                                                                action:#selector(donePressed))
//    //        self.navigationItem.title = dialogTitle()
//    //
//    //        createViews()
//    //    }
//    //
//    //    private func dialogTitle() -> String {
//    //        guard let filename = formattedFileName() else {
//    //            return NSLocalizedString("ATTACHMENT_APPROVAL_DIALOG_TITLE",
//    //                                     comment: "Title for the 'attachment approval' dialog.")
//    //        }
//    //        return filename
//    //    }
//    //
//    //    override func viewWillAppear(_ animated: Bool) {
//    //        super.viewWillAppear(animated)
//    //
//    //        ViewControllerUtils.setAudioIgnoresHardwareMuteSwitch(true)
//    //    }
//    //
//    //    override func viewWillDisappear(_ animated: Bool) {
//    //        super.viewWillDisappear(animated)
//    //
//    //        ViewControllerUtils.setAudioIgnoresHardwareMuteSwitch(false)
//    //    }
//    //
//    //    // MARK: - Create Views
//    //
//    //    private func createViews() {
//    //        let previewTopMargin: CGFloat = 30
//    //        let previewHMargin: CGFloat = 20
//    //
//    //        let attachmentPreviewView = UIView()
//    //        self.view.addSubview(attachmentPreviewView)
//    //        attachmentPreviewView.autoPinWidthToSuperview(withMargin:previewHMargin)
//    //        attachmentPreviewView.autoPin(toTopLayoutGuideOf: self, withInset:previewTopMargin)
//    //
//    //        createButtonRow(attachmentPreviewView:attachmentPreviewView)
//    //
//    //        if attachment.isAnimatedImage {
//    //            createAnimatedPreview(attachmentPreviewView:attachmentPreviewView)
//    //        } else if attachment.isImage {
//    //            createImagePreview(attachmentPreviewView:attachmentPreviewView)
//    //        } else if attachment.isVideo {
//    //            createVideoPreview(attachmentPreviewView:attachmentPreviewView)
//    //        } else if attachment.isAudio {
//    //            createAudioPreview(attachmentPreviewView:attachmentPreviewView)
//    //        } else {
//    //            createGenericPreview(attachmentPreviewView:attachmentPreviewView)
//    //        }
//    //    }
//    //
//    //    private func wrapViewsInVerticalStack(subviews: [UIView]) -> UIView {
//    //        assert(subviews.count > 0)
//    //
//    //        let stackView = UIView()
//    //
//    //        var lastView: UIView?
//    //        for subview in subviews {
//    //
//    //            stackView.addSubview(subview)
//    //            subview.autoHCenterInSuperview()
//    //
//    //            if lastView == nil {
//    //                subview.autoPinEdge(toSuperviewEdge:.top)
//    //            } else {
//    //                subview.autoPinEdge(.top, to:.bottom, of:lastView!, withOffset:10)
//    //            }
//    //
//    //            lastView = subview
//    //        }
//    //
//    //        lastView?.autoPinEdge(toSuperviewEdge:.bottom)
//    //
//    //        return stackView
//    //    }
//    //
//    //    private func createAudioPreview(attachmentPreviewView: UIView) {
//    //        guard let dataUrl = attachment.dataUrl else {
//    //            createGenericPreview(attachmentPreviewView:attachmentPreviewView)
//    //            return
//    //        }
//    //
//    //        audioPlayer = OWSAudioAttachmentPlayer(mediaUrl: dataUrl, delegate: self)
//    //
//    //        var subviews = [UIView]()
//    //
//    //        let audioPlayButton = UIButton()
//    //        self.audioPlayButton = audioPlayButton
//    //        setAudioIconToPlay()
//    //        audioPlayButton.imageView?.layer.minificationFilter = kCAFilterTrilinear
//    //        audioPlayButton.imageView?.layer.magnificationFilter = kCAFilterTrilinear
//    //        audioPlayButton.addTarget(self, action:#selector(audioPlayButtonPressed), for:.touchUpInside)
//    //        let buttonSize = createHeroViewSize()
//    //        audioPlayButton.autoSetDimension(.width, toSize:buttonSize)
//    //        audioPlayButton.autoSetDimension(.height, toSize:buttonSize)
//    //        subviews.append(audioPlayButton)
//    //
//    //        let fileNameLabel = createFileNameLabel()
//    //        if let fileNameLabel = fileNameLabel {
//    //            subviews.append(fileNameLabel)
//    //        }
//    //
//    //        let fileSizeLabel = createFileSizeLabel()
//    //        subviews.append(fileSizeLabel)
//    //
//    //        let audioStatusLabel = createAudioStatusLabel()
//    //        self.audioStatusLabel = audioStatusLabel
//    //        updateAudioStatusLabel()
//    //        subviews.append(audioStatusLabel)
//    //
//    //        let stackView = wrapViewsInVerticalStack(subviews:subviews)
//    //        attachmentPreviewView.addSubview(stackView)
//    //        fileNameLabel?.autoPinWidthToSuperview(withMargin: 32)
//    //        stackView.autoPinWidthToSuperview()
//    //        stackView.autoVCenterInSuperview()
//    //    }
//    //
//    //    private func createAnimatedPreview(attachmentPreviewView: UIView) {
//    //        guard attachment.isValidImage else {
//    //            return
//    //        }
//    //        let data = attachment.data
//    //        // Use Flipboard FLAnimatedImage library to display gifs
//    //        guard let animatedImage = FLAnimatedImage(gifData:data) else {
//    //            createGenericPreview(attachmentPreviewView:attachmentPreviewView)
//    //            return
//    //        }
//    //        let animatedImageView = FLAnimatedImageView()
//    //        animatedImageView.animatedImage = animatedImage
//    //        animatedImageView.contentMode = .scaleAspectFit
//    //        attachmentPreviewView.addSubview(animatedImageView)
//    //        animatedImageView.autoPinWidthToSuperview()
//    //        animatedImageView.autoPinHeightToSuperview()
//    //    }
//    //
//    //    private func createImagePreview(attachmentPreviewView: UIView) {
//    //        var image = attachment.image
//    //        if image == nil {
//    //            image = UIImage(data:attachment.data)
//    //        }
//    //        guard image != nil else {
//    //            createGenericPreview(attachmentPreviewView:attachmentPreviewView)
//    //            return
//    //        }
//    //
//    //        let imageView = UIImageView(image:image)
//    //        imageView.layer.minificationFilter = kCAFilterTrilinear
//    //        imageView.layer.magnificationFilter = kCAFilterTrilinear
//    //        imageView.contentMode = .scaleAspectFit
//    //        attachmentPreviewView.addSubview(imageView)
//    //        imageView.autoPinWidthToSuperview()
//    //        imageView.autoPinHeightToSuperview()
//    //    }
//    //
//    //    private func createVideoPreview(attachmentPreviewView: UIView) {
//    //        guard let dataUrl = attachment.dataUrl else {
//    //            createGenericPreview(attachmentPreviewView:attachmentPreviewView)
//    //            return
//    //        }
//    //        guard let videoPlayer = MPMoviePlayerController(contentURL:dataUrl) else {
//    //            createGenericPreview(attachmentPreviewView:attachmentPreviewView)
//    //            return
//    //        }
//    //        videoPlayer.prepareToPlay()
//    //
//    //        videoPlayer.controlStyle = .default
//    //        videoPlayer.shouldAutoplay = false
//    //
//    //        attachmentPreviewView.addSubview(videoPlayer.view)
//    //        self.videoPlayer = videoPlayer
//    //        videoPlayer.view.autoPinWidthToSuperview()
//    //        videoPlayer.view.autoPinHeightToSuperview()
//    //    }
//    //
//    //    private func createGenericPreview(attachmentPreviewView: UIView) {
//    //        var subviews = [UIView]()
//    //
//    //        let imageView = createHeroImageView(imageName: "file-thin-black-filled-large")
//    //        subviews.append(imageView)
//    //
//    //        let fileNameLabel = createFileNameLabel()
//    //        if let fileNameLabel = fileNameLabel {
//    //            subviews.append(fileNameLabel)
//    //        }
//    //
//    //        let fileSizeLabel = createFileSizeLabel()
//    //        subviews.append(fileSizeLabel)
//    //
//    //        let stackView = wrapViewsInVerticalStack(subviews:subviews)
//    //        attachmentPreviewView.addSubview(stackView)
//    //        fileNameLabel?.autoPinWidthToSuperview(withMargin: 32)
//    //        stackView.autoPinWidthToSuperview()
//    //        stackView.autoVCenterInSuperview()
//    //    }
//    //
//    //    private func createHeroViewSize() -> CGFloat {
//    //        return ScaleFromIPhone5To7Plus(175, 225)
//    //    }
//    //
//    //    private func createHeroImageView(imageName: String) -> UIView {
//    //        let imageSize = createHeroViewSize()
//    //        let image = UIImage(named:imageName)
//    //        assert(image != nil)
//    //        let imageView = UIImageView(image:image)
//    //        imageView.layer.minificationFilter = kCAFilterTrilinear
//    //        imageView.layer.magnificationFilter = kCAFilterTrilinear
//    //        imageView.layer.shadowColor = UIColor.black.cgColor
//    //        let shadowScaling = 5.0
//    //        imageView.layer.shadowRadius = CGFloat(2.0 * shadowScaling)
//    //        imageView.layer.shadowOpacity = 0.25
//    //        imageView.layer.shadowOffset = CGSize(width: 0.75 * shadowScaling, height: 0.75 * shadowScaling)
//    //        imageView.autoSetDimension(.width, toSize:imageSize)
//    //        imageView.autoSetDimension(.height, toSize:imageSize)
//    //
//    //        return imageView
//    //    }
//    //
//    //    private func labelFont() -> UIFont {
//    //        return UIFont.ows_regularFont(withSize:ScaleFromIPhone5To7Plus(18, 24))
//    //    }
//    //
//    //    private func formattedFileExtension() -> String? {
//    //        guard let fileExtension = attachment.fileExtension else {
//    //            return nil
//    //        }
//    //
//    //        return String(format:NSLocalizedString("ATTACHMENT_APPROVAL_FILE_EXTENSION_FORMAT",
//    //                                               comment: "Format string for file extension label in call interstitial view"),
//    //                      fileExtension.uppercased())
//    //    }
//    //
//    //    private func formattedFileName() -> String? {
//    //        guard let sourceFilename = attachment.sourceFilename else {
//    //            return nil
//    //        }
//    //        let filename = sourceFilename.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
//    //        guard filename.characters.count > 0 else {
//    //            return nil
//    //        }
//    //        return filename
//    //    }
//    //
//    //    private func createFileNameLabel() -> UIView? {
//    //        let filename = formattedFileName() ?? formattedFileExtension()
//    //
//    //        guard filename != nil else {
//    //            return nil
//    //        }
//    //
//    //        let label = UILabel()
//    //        label.text = filename
//    //        label.textColor = UIColor.ows_materialBlue()
//    //        label.font = labelFont()
//    //        label.textAlignment = .center
//    //        label.lineBreakMode = .byTruncatingMiddle
//    //        return label
//    //    }
//    //
//    //    private func createFileSizeLabel() -> UIView {
//    //        let label = UILabel()
//    //        let fileSize = attachment.dataLength
//    //        label.text = String(format:NSLocalizedString("ATTACHMENT_APPROVAL_FILE_SIZE_FORMAT",
//    //                                                     comment: "Format string for file size label in call interstitial view. Embeds: {{file size as 'N mb' or 'N kb'}}."),
//    //                            ViewControllerUtils.formatFileSize(UInt(fileSize)))
//    //
//    //        label.textColor = UIColor.ows_materialBlue()
//    //        label.font = labelFont()
//    //        label.textAlignment = .center
//    //
//    //        return label
//    //    }
//    //
//    //    private func createAudioStatusLabel() -> UILabel {
//    //        let label = UILabel()
//    //        label.textColor = UIColor.ows_materialBlue()
//    //        label.font = labelFont()
//    //        label.textAlignment = .center
//    //
//    //        return label
//    //    }
//    //
//    //    private func createButtonRow(attachmentPreviewView: UIView) {
//    //        let buttonTopMargin = ScaleFromIPhone5To7Plus(30, 40)
//    //        let buttonBottomMargin = ScaleFromIPhone5To7Plus(25, 40)
//    //        let buttonHSpacing = ScaleFromIPhone5To7Plus(20, 30)
//    //
//    //        let buttonRow = UIView()
//    //        self.view.addSubview(buttonRow)
//    //        buttonRow.autoPinWidthToSuperview()
//    //        buttonRow.autoPinEdge(toSuperviewEdge:.bottom, withInset:buttonBottomMargin)
//    //        buttonRow.autoPinEdge(.top, to:.bottom, of:attachmentPreviewView, withOffset:buttonTopMargin)
//    //
//    //        // We use this invisible subview to ensure that the buttons are centered
//    //        // horizontally.
//    //        let buttonSpacer = UIView()
//    //        buttonRow.addSubview(buttonSpacer)
//    //        // Vertical positioning of this view doesn't matter.
//    //        buttonSpacer.autoPinEdge(toSuperviewEdge:.top)
//    //        buttonSpacer.autoSetDimension(.width, toSize:buttonHSpacing)
//    //        buttonSpacer.autoHCenterInSuperview()
//    //
//    //        let cancelButton = createButton(title: CommonStrings.cancelButton,
//    //                                        color : UIColor.ows_destructiveRed(),
//    //                                        action: #selector(cancelPressed))
//    //        buttonRow.addSubview(cancelButton)
//    //        cancelButton.autoPinEdge(toSuperviewEdge:.top)
//    //        cancelButton.autoPinEdge(toSuperviewEdge:.bottom)
//    //        cancelButton.autoPinEdge(.right, to:.left, of:buttonSpacer)
//    //
//    //        let sendButton = createButton(title: NSLocalizedString("ATTACHMENT_APPROVAL_SEND_BUTTON",
//    //                                                               comment: "Label for 'send' button in the 'attachment approval' dialog."),
//    //                                      color : UIColor(rgbHex:0x2ecc71),
//    //                                      action: #selector(sendPressed))
//    //        buttonRow.addSubview(sendButton)
//    //        sendButton.autoPinEdge(toSuperviewEdge:.top)
//    //        sendButton.autoPinEdge(toSuperviewEdge:.bottom)
//    //        sendButton.autoPinEdge(.left, to:.right, of:buttonSpacer)
//    //    }
//    //
//    //    private func createButton(title: String, color: UIColor, action: Selector) -> UIView {
//    //        let buttonWidth = ScaleFromIPhone5To7Plus(110, 140)
//    //        let buttonHeight = ScaleFromIPhone5To7Plus(35, 45)
//    //
//    //        return OWSFlatButton.button(title:title,
//    //                                    titleColor:UIColor.white,
//    //                                    backgroundColor:color,
//    //                                    width:buttonWidth,
//    //                                    height:buttonHeight,
//    //                                    target:target,
//    //                                    selector:action)
//    //    }
//    //
//    //    // MARK: - Event Handlers
//    //
//    //    func donePressed(sender: UIButton) {
//    //        dismiss(animated: true, completion:nil)
//    //    }
//    //
//    //    func cancelPressed(sender: UIButton) {
//    //        dismiss(animated: true, completion:nil)
//    //    }
//    //
//    //    func sendPressed(sender: UIButton) {
//    //        let successCompletion = self.successCompletion
//    //        dismiss(animated: true, completion: {
//    //            successCompletion?()
//    //        })
//    //    }
//    //
//    //    func audioPlayButtonPressed(sender: UIButton) {
//    //        audioPlayer?.togglePlayState()
//    //    }
//    //
//    //    // MARK: - OWSAudioAttachmentPlayerDelegate
//    //
//    //    public func isAudioPlaying() -> Bool {
//    //        return isAudioPlayingFlag
//    //    }
//    //
//    //    public func setIsAudioPlaying(_ isAudioPlaying: Bool) {
//    //        isAudioPlayingFlag = isAudioPlaying
//    //
//    //        updateAudioStatusLabel()
//    //    }
//    //
//    //    public func isPaused() -> Bool {
//    //        return isAudioPaused
//    //    }
//    //
//    //    public func setIsPaused(_ isPaused: Bool) {
//    //        isAudioPaused = isPaused
//    //    }
//    //
//    //    public func setAudioProgress(_ progress: CGFloat, duration: CGFloat) {
//    //        audioProgressSeconds = progress
//    //        audioDurationSeconds = duration
//    //
//    //        updateAudioStatusLabel()
//    //    }
//    //
//    //    private func updateAudioStatusLabel() {
//    //        guard let audioStatusLabel = self.audioStatusLabel else {
//    //            owsFail("Missing audio status label")
//    //            return
//    //        }
//    //
//    //        if isAudioPlayingFlag && audioProgressSeconds > 0 && audioDurationSeconds > 0 {
//    //            audioStatusLabel.text = String(format:"%@ / %@",
//    //                ViewControllerUtils.formatDurationSeconds(Int(round(self.audioProgressSeconds))),
//    //                ViewControllerUtils.formatDurationSeconds(Int(round(self.audioDurationSeconds))))
//    //        } else {
//    //            audioStatusLabel.text = " "
//    //        }
//    //    }
//    //
//    //    public func setAudioIconToPlay() {
//    //        let image = UIImage(named:"audio_play_black_large")?.withRenderingMode(.alwaysTemplate)
//    //        assert(image != nil)
//    //        audioPlayButton?.setImage(image, for:.normal)
//    //        audioPlayButton?.imageView?.tintColor = UIColor.ows_materialBlue()
//    //    }
//    //
//    //    public func setAudioIconToPause() {
//    //        let image = UIImage(named:"audio_pause_black_large")?.withRenderingMode(.alwaysTemplate)
//    //        assert(image != nil)
//    //        audioPlayButton?.setImage(image, for:.normal)
//    //        audioPlayButton?.imageView?.tintColor = UIColor.ows_materialBlue()
//    //    }
//    
//    // MARK: - UICollectionViewDataSource
//    
//    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
//        return imageInfos.count
//    }
//
//    // The cell that is returned must be retrieved from a call to -dequeueReusableCellWithReuseIdentifier:forIndexPath:
//    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
//        let cell = self.dequeueReusableCell(withReuseIdentifier identifier: String, for indexPath: IndexPath) -> UICollectionViewCell
//    }
//
//    
//    // MARK: - UICollectionViewDelegate
//    
////    @available(iOS 6.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool
////    
////    @available(iOS 6.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath)
////    
////    @available(iOS 6.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath)
////    
////    @available(iOS 6.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool
////    
////    @available(iOS 6.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool // called when the user taps on an already-selected item in multi-select mode
////    
////    @available(iOS 6.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
////    
////    @available(iOS 6.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath)
////    
////    
////    @available(iOS 8.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath)
////    
////    @available(iOS 8.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, willDisplaySupplementaryView view: UICollectionReusableView, forElementKind elementKind: String, at indexPath: IndexPath)
////    
////    @available(iOS 6.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath)
////    
////    @available(iOS 6.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, didEndDisplayingSupplementaryView view: UICollectionReusableView, forElementOfKind elementKind: String, at indexPath: IndexPath)
////    
////    
////    // These methods provide support for copy/paste actions on cells.
////    // All three should be implemented if any are.
////    @available(iOS 6.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, shouldShowMenuForItemAt indexPath: IndexPath) -> Bool
////    
////    @available(iOS 6.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, canPerformAction action: Selector, forItemAt indexPath: IndexPath, withSender sender: Any?) -> Bool
////    
////    @available(iOS 6.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, performAction action: Selector, forItemAt indexPath: IndexPath, withSender sender: Any?)
////    
////    
////    // support for custom transition layout
////    @available(iOS 7.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, transitionLayoutForOldLayout fromLayout: UICollectionViewLayout, newLayout toLayout: UICollectionViewLayout) -> UICollectionViewTransitionLayout
////    
////    
////    // Focus
////    @available(iOS 9.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool
////    
////    @available(iOS 9.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, shouldUpdateFocusIn context: UICollectionViewFocusUpdateContext) -> Bool
////    
////    @available(iOS 9.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator)
////    
////    @available(iOS 9.0, *)
////    optional public func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath?
////    
////    
////    @available(iOS 9.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath, toProposedIndexPath proposedIndexPath: IndexPath) -> IndexPath
////    
////    
////    @available(iOS 9.0, *)
////    optional public func collectionView(_ collectionView: UICollectionView, targetContentOffsetForProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint // customize the content offset to be applied during transition or update animations
////}
//
//    // MARK: - Event Handlers
//
//    func donePressed(sender: UIButton) {
//        dismiss(animated: true, completion:nil)
//    }
}
