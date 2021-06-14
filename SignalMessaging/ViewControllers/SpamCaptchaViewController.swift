//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit
import WebKit

public protocol CaptchaViewDelegate: NSObjectProtocol {
    func captchaView(_: CaptchaView, didCompleteCaptchaWithToken: String)
    func captchaViewDidFailToCompleteCaptcha(_: CaptchaView)
}

public class CaptchaView: UIView {

    private let captchaURL = URL(string: "https://signalcaptchas.org/registration/generate.html")!

    private var webView: WKWebView = {
        // We want the CAPTCHA web content to "fill the screen (honoring margins)".
        // The way to do this with WKWebView is to inject a javascript snippet that
        // manipulates the viewport.
        //
        // TODO: There's a long outstanding where short devices will require vertical
        // scrolling to see the entire captcha. We should manipulate the viewport to mitigate
        // this.
        let viewportInjection = WKUserScript(
            source: """
                var meta = document.createElement('meta');
                meta.setAttribute('name', 'viewport');
                meta.setAttribute('content', 'width=device-width');
                document.getElementsByTagName('head')[0].appendChild(meta);
                """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true)

        let contentController = WKUserContentController()
        contentController.addUserScript(viewportInjection)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = false
        webView.customUserAgent = "Signal iOS (+https://signal.org/download)"
        webView.allowsLinkPreview = false
        webView.scrollView.contentInset = .zero
        webView.layoutMargins = .zero
        webView.accessibilityIdentifier = "onboarding.captcha." + "webView"
        return webView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(webView)
        webView.autoPinEdgesToSuperviewEdges()

        webView.navigationDelegate = self

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public weak var delegate: CaptchaViewDelegate?

    public func loadCaptcha() {
        webView.load(URLRequest(url: captchaURL))
    }

    @objc
    private func didBecomeActive() {
        loadCaptcha()
    }

    // Example URL:
    // signalcaptcha://03AF6jDqXgf1PocNNrWRJEENZ9l6RAMIsUoESi2dFKkxTgE2qjdZGVjE
    // W6SZNFQqeRRTgGqOii6zHGG--uLyC1HnhSmRt8wHeKxHcg1hsK4ucTusANIeFXVB8wPPiV7U
    // _0w2jUFVak5clMCvW9_JBfbfzj51_e9sou8DYfwc_R6THuTBTdpSV8Nh0yJalgget-nSukCx
    // h6FPA6hRVbw7lP3r-me1QCykHOfh-V29UVaQ4Fs5upHvwB5rtiViqT_HN8WuGmdIdGcaWxaq
    // y1lQTgFSs2Shdj593wZiXfhJnCWAw9rMn3jSgIZhkFxdXwKOmslQ2E_I8iWkm6
    private func parseCaptchaResult(url: URL) {
        if let token = url.host, token.count > 0 {
            delegate?.captchaView(self, didCompleteCaptchaWithToken: token)
        } else {
            owsFailDebug("Could not parse captcha token: \(url)")
            delegate?.captchaViewDidFailToCompleteCaptcha(self)
        }
    }
}

extension CaptchaView: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        Logger.verbose("navigationAction: \(String(describing: navigationAction.request.url))")

        guard let url: URL = navigationAction.request.url else {
            owsFailDebug("Missing URL.")
            decisionHandler(.cancel)
            return
        }
        if url.scheme == "signalcaptcha" {
            decisionHandler(.cancel)
            DispatchQueue.main.async {
                self.parseCaptchaResult(url: url)
            }
            return
        }

        // Loading the Captcha content involves a series of actions.
        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        Logger.verbose("navigationResponse: \(String(describing: navigationResponse))")

        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Logger.verbose("navigation: \(String(describing: navigation))")
    }

    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        Logger.verbose("navigation: \(String(describing: navigation))")
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Logger.verbose("navigation: \(String(describing: navigation)), error: \(error)")
        DispatchQueue.main.async {
            self.delegate?.captchaViewDidFailToCompleteCaptcha(self)
        }
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Logger.verbose("navigation: \(String(describing: navigation))")
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.verbose("navigation: \(String(describing: navigation))")
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.verbose("navigation: \(String(describing: navigation)), error: \(error)")
        DispatchQueue.main.async {
            self.delegate?.captchaViewDidFailToCompleteCaptcha(self)
        }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Logger.verbose("")
        DispatchQueue.main.async {
            self.delegate?.captchaViewDidFailToCompleteCaptcha(self)
        }
    }
}

@objc
public class SpamCaptchaViewController: UIViewController, CaptchaViewDelegate {
    private var captchaView: CaptchaView?
    var completionHandler: ((String?) -> Void)?

    private init() {
        super.init(nibName: nil, bundle: nil)
    }

    override public func loadView() {
        let captchaView = CaptchaView()
        captchaView.delegate = self

        let view = UIView()
        view.addSubview(captchaView)
        captchaView.autoPinEdgesToSuperviewEdges()

        self.captchaView = captchaView
        self.view = view
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        captchaView?.loadCaptcha()

        if #available(iOS 13.0, *) {
            isModalInPresentation = true
        }
        navigationItem.title = NSLocalizedString("SPAM_CAPTCHA_VIEW_CONTROLLER", comment: "Title for the captcha view controller")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .stop,
            target: self,
            action: #selector(didTapCancel)
        )
    }

    @objc
    func didTapCancel() {
        completionHandler?(nil)
        completionHandler = nil
    }

    public func captchaView(_: CaptchaView, didCompleteCaptchaWithToken token: String) {
        completionHandler?(token)
        completionHandler = nil
    }

    public func captchaViewDidFailToCompleteCaptcha(_: CaptchaView) {
        captchaView?.loadCaptcha()
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }
}

extension SpamCaptchaViewController {
    @objc
    public static func presentActionSheet(from fromVC: UIViewController) {

        let titleLabel = UILabel()
        titleLabel.font = UIFont.ows_dynamicTypeTitle2Clamped.ows_semibold
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        titleLabel.text = NSLocalizedString("SPAM_CAPTCHA_SHEET_TITLE", comment: "Title for action sheet explaining captcha requirement.")

        let bodyLabel = UILabel()
        bodyLabel.font = .ows_dynamicTypeBody2Clamped
        bodyLabel.textColor = Theme.primaryTextColor
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.text = NSLocalizedString("SPAM_CAPTCHA_SHEET_BODY", comment: "Body for action sheet explaining captcha requirement.")

        let continueButton = OWSFlatButton()
        continueButton.setTitle(
            title: CommonStrings.continueButton,
            font: UIFont.ows_dynamicTypeBodyClamped.ows_semibold,
            titleColor: .white)
        continueButton.setBackgroundColors(upColor: Theme.accentBlueColor)
        continueButton.layer.cornerRadius = 8
        continueButton.layer.masksToBounds = true
        continueButton.contentEdgeInsets = UIEdgeInsets(hMargin: 4, vMargin: 14)

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            bodyLabel,
            UIView.spacer(withHeight: 72),
            continueButton
        ])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = 16

        let sheet = SheetViewController()
        sheet.isHandleHidden = true
        sheet.contentView.addSubview(stackView)
        sheet.dismissHandler = { sheet in
            sheet.dismiss(animated: true)

            let confirmationSheet = ActionSheetController(
                title: NSLocalizedString(
                    "SPAM_CAPTCHA_DISMISS_CONFIRMATION_TITLE",
                    comment: "Title for confirmation dialog confirming to ignore verification."),
                message: NSLocalizedString(
                    "SPAM_CAPTCHA_DISMISS_CONFIRMATION_MESSAGE",
                    comment: "Message for confirmation dialog confirming to ignore verification.")
                )

            confirmationSheet.addAction(
                ActionSheetAction(
                    title: NSLocalizedString("SPAM_CAPTCHA_SKIP_VERIFICATION_ACTION", comment: "Action to skip verification"),
                    style: .destructive
                ))
            confirmationSheet.addAction(
                ActionSheetAction(
                    title: CommonStrings.cancelButton,
                    style: .cancel,
                    handler: { _ in
                        presentActionSheet(from: fromVC)
                    }
                ))
            fromVC.present(confirmationSheet, animated: true, completion: nil)
        }

        continueButton.setPressedBlock {
            sheet.dismiss(animated: true)
            presentCaptchaVC(from: fromVC)
        }

        stackView.autoPinEdgesToSuperviewMargins(
            with: UIEdgeInsets(hMargin: 24, vMargin: 16))
        continueButton.autoPinWidthToSuperviewMargins()

        fromVC.present(sheet, animated: true, completion: nil)
    }

    @objc
    static func presentCaptchaVC(from fromVC: UIViewController) {
        let vc = SpamCaptchaViewController()
        vc.completionHandler = { token in
            if let token = token {
                fromVC.presentToast(
                    text: NSLocalizedString(
                        "SPAM_CAPTCHA_COMPLETED_TOAST",
                        comment: "Text for toast presented after spam verification has been completed"))
                spamChallengeResolver.handleIncomingCaptchaChallengeToken(token)
            }
            vc.dismiss(animated: true)
        }
        let navVC = OWSNavigationController(rootViewController: vc)
        fromVC.present(navVC, animated: true, completion: nil)
    }
}
