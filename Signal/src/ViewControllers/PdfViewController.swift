//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import YYImage
import PDFKit

@objc
public class PdfViewController: OWSViewController {

    // MARK: Properties

    private let viewItem: ConversationViewItem
    private let attachmentStream: TSAttachmentStream
    private var pdfView: UIView?
    private var viewHasEverAppeared = false

    // MARK: Initializers

    @objc
    public required init(viewItem: ConversationViewItem,
                         attachmentStream: TSAttachmentStream) {
        self.viewItem = viewItem
        self.attachmentStream = attachmentStream

        super.init()
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.darkThemeBackgroundColor

        navigationItem.title = NSLocalizedString("PDF_VIEW_TITLE", comment: "Navbar title for for PDF view.")
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(didPressCloseButton))

        let contentView: UIView

        // Setup the PDFView as the contentView if supported
        if let url = attachmentStream.originalMediaURL,
            let pdfDocument = PDFDocument(url: url) {
            let pdfView = PDFView()
            self.pdfView = pdfView
            pdfView.displayMode = .singlePageContinuous
            pdfView.document = pdfDocument
            contentView = pdfView

            if let filename = attachmentStream.sourceFilename {
                navigationItem.title = filename.filterForDisplay
            }

        // Otherwise, render an error
        } else {
            let label = UILabel()
            contentView = label
            label.text = NSLocalizedString("PDF_VIEW_COULD_NOT_RENDER", comment: "Error indicating that a PDF could not be displayed.")
            label.font = UIFont.ows_dynamicTypeBody
            label.textColor = Theme.darkThemePrimaryColor
            label.textAlignment = .center
            label.numberOfLines = 0
        }

        view.addSubview(contentView)
        contentView.autoPinEdgesToSuperviewEdges()

        // Setup top + bottom bars

        guard let navigationBar = navigationController?.navigationBar as? OWSNavigationBar else {
            owsFailDebug("navigationBar was nil or unexpected class")
            return
        }

        navigationBar.switchToStyle(.alwaysDark)

        // Only setup the bottom bar if we have a PDF rendered
        guard let toolbar = navigationController?.toolbar, pdfView != nil else {
            return
        }

        navigationController?.isToolbarHidden = false

        toolbar.barStyle = .black
        toolbar.barTintColor = Theme.darkThemeBackgroundColor.withAlphaComponent(0.6)
        toolbar.tintColor = Theme.darkThemePrimaryColor

        setToolbarItems(
            [
                UIBarButtonItem(image: Theme.iconImage(.messageActionShare), style: .plain, target: self, action: #selector(shareButtonPressed)),
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                UIBarButtonItem(image: Theme.iconImage(.messageActionForward), style: .plain, target: self, action: #selector(forwardButtonPressed))
            ],
            animated: false
        )

        // tap to toggle the bar visibility
        let tapGestureRecognizer = UITapGestureRecognizer()
        contentView.addGestureRecognizer(tapGestureRecognizer)
        tapGestureRecognizer .addTarget(self, action: #selector(handleTap(_:)))
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if !viewHasEverAppeared,
            let pdfView = pdfView as? PDFView {
            pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
            pdfView.goToFirstPage(nil)
        }
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewHasEverAppeared = true
    }

    // MARK: - Actions

    @objc func shareButtonPressed(_ sender: UIBarButtonItem) {
        // TODO: Maybe we could add better share actions for PDFs?
        AttachmentSharing.showShareUI(forAttachment: attachmentStream, sender: sender)
    }

    @objc func forwardButtonPressed() {
        ForwardMessageNavigationController.present(for: viewItem, from: self, delegate: self)
    }

    @objc
    private func didPressCloseButton(sender: UIButton) {
        dismiss(animated: true)
    }

    // MARK: - Bar Management

    @objc
    func handleTap(_ sender: UITapGestureRecognizer) {
        shouldHideToolbars = !shouldHideToolbars
    }

    private var shouldHideToolbars: Bool = false {
        didSet {
            if oldValue == shouldHideToolbars {
                return
            }

            navigationController?.setNavigationBarHidden(shouldHideToolbars, animated: false)
            navigationController?.setToolbarHidden(shouldHideToolbars, animated: false)
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    public override var prefersStatusBarHidden: Bool {
        return shouldHideToolbars
    }

    public override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .none
    }
}

// MARK: -

extension PdfViewController: ForwardMessageDelegate {
    public func forwardMessageFlowDidComplete(viewItem: ConversationViewItem,
                                              threads: [TSThread]) {
        dismiss(animated: true) {
            self.didForwardMessage(threads: threads)
        }
    }

    public func forwardMessageFlowDidCancel() {
        dismiss(animated: true)
    }

    func didForwardMessage(threads: [TSThread]) {
        guard threads.count == 1 else {
            return
        }
        guard let thread = threads.first else {
            owsFailDebug("Missing thread.")
            return
        }
        guard thread.uniqueId != viewItem.interaction.uniqueThreadId else {
            return
        }
        SignalApp.shared().presentConversation(for: thread, animated: true)
    }
}
