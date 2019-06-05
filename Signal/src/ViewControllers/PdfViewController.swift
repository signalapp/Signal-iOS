//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import YYImage
import PDFKit

@objc
public class PdfViewController: OWSViewController {

    // MARK: Properties

    private let attachmentStream: TSAttachmentStream

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    public required init(attachmentStream: TSAttachmentStream) {
        self.attachmentStream = attachmentStream

        super.init(nibName: nil, bundle: nil)

        self.modalPresentationStyle = .overFullScreen
    }

    @objc
    public class var canRenderPdf: Bool {
        if #available(iOS 11.0, *) {
            return true
        } else {
            return false
        }
    }

    // MARK: - View Lifecycle

    override public func loadView() {
        super.loadView()

        view.backgroundColor = Theme.backgroundColor

        self.navigationItem.title = NSLocalizedString("PDF_VIEW_TITLE", comment: "Navbar title for for PDF view.")

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(didPressCloseButton))

        var contentView = UIView()
        if #available(iOS 11.0, *),
            let url = attachmentStream.originalMediaURL,
            let pdfDocument = PDFDocument(url: url) {
            let pdfView = PDFView()
            self.pdfView = pdfView
            pdfView.displayMode = .singlePageContinuous
            pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
            pdfView.document = pdfDocument
            contentView = pdfView

            if let filename = attachmentStream.sourceFilename {
                self.navigationItem.title = filename.filterForDisplay
            }
        } else {
            let label = UILabel()
            label.text = NSLocalizedString("PDF_VIEW_COULD_NOT_RENDER", comment: "Error indicating that a PDF could not be displayed.")
            label.font = UIFont.ows_dynamicTypeBody
            label.textColor = Theme.primaryColor
            label.numberOfLines = 0
            contentView.addSubview(label)
            label.autoPinEdge(toSuperviewMargin: .leading)
            label.autoPinEdge(toSuperviewMargin: .trailing)
            label.autoVCenterInSuperview()
        }
        contentView.setCompressionResistanceLow()
        contentView.setContentHuggingLow()

        var arrangedSubviews: [UIView] = [
            contentView
        ]

        if pdfView != nil {
            let footer = UIToolbar()
            footer.items = [
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareButtonPressed)),
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            ]
            arrangedSubviews.append(footer)
        }

        let stackView = UIStackView(arrangedSubviews: arrangedSubviews)
        stackView.axis = .vertical
        stackView.alignment = .fill
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperview()
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        stackView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
    }

    private var pdfView: UIView?
    private var viewHasAppeared = false

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard #available(iOS 11.0, *),
            let pdfView = pdfView as? PDFView else {
            return
        }
        if !viewHasAppeared {
            pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
            pdfView.goToFirstPage(self)
        }
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.becomeFirstResponder()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.becomeFirstResponder()

        viewHasAppeared = true
    }

    override public var canBecomeFirstResponder: Bool {
        return true
    }

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    // MARK: - Actions

    @objc func shareButtonPressed() {
        AttachmentSharing.showShareUI(forAttachment: attachmentStream)
    }

    @objc
    private func didPressCloseButton(sender: UIButton) {
        Logger.info("")
        // We'll ask again next time they launch
        self.dismiss(animated: true)
    }
}
