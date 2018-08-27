//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol ToastViewDelegate: class {
    func didTapToastView(_ toastView: ToastView)
    func didSwipeToastView(_ toastView: ToastView)
}

class ToastView: UIView {

    var text: String? {
        get {
            return label.text
        }
        set {
            label.text = newValue
        }
    }
    weak var delegate: ToastViewDelegate?

    private let label: UILabel

    // MARK: Initializers

    override init(frame: CGRect) {
        label = UILabel()
        super.init(frame: frame)

        self.layer.cornerRadius = 4
        self.backgroundColor = Theme.toastBackgroundColor
        self.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        label.textAlignment = .center
        label.textColor = Theme.toastForegroundColor
        label.font = UIFont.ows_dynamicTypeBody
        label.numberOfLines = 0
        self.addSubview(label)
        label.autoPinEdgesToSuperviewMargins()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap(gesture:)))
        self.addGestureRecognizer(tapGesture)

        let swipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(didSwipe(gesture:)))
        self.addGestureRecognizer(swipeGesture)
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: Gestures

    @objc
    func didTap(gesture: UITapGestureRecognizer) {
        self.delegate?.didTapToastView(self)
    }

    @objc
    func didSwipe(gesture: UISwipeGestureRecognizer) {
        self.delegate?.didSwipeToastView(self)
    }
}

@objc
class ToastController: NSObject, ToastViewDelegate {

    static var currentToastController: ToastController?

    private let toastView: ToastView
    private var isDismissing: Bool

    // MARK: Initializers

    @objc
    required init(text: String) {
        toastView = ToastView()
        toastView.text = text
        isDismissing = false

        super.init()

        toastView.delegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: Public

    @objc
    func presentToastView(fromBottomOfView view: UIView, inset: CGFloat) {
        Logger.debug("")
        toastView.alpha = 0
        view.addSubview(toastView)
        toastView.setCompressionResistanceHigh()
        toastView.autoPinEdge(.bottom, to: .bottom, of: view, withOffset: -inset)
        toastView.autoPinWidthToSuperview(withMargin: 24)

        if let currentToastController = type(of: self).currentToastController {
            currentToastController.dismissToastView()
            type(of: self).currentToastController = nil
        }
        type(of: self).currentToastController = self

        UIView.animate(withDuration: 0.1) {
            self.toastView.alpha = 1
        }

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1.5) {
            // intentional strong reference to self.
            // As with an AlertController, the caller likely expects toast to
            // be presented and dismissed without maintaining a strong reference to ToastController
            self.dismissToastView()
        }
    }

    // MARK: ToastViewDelegate

    func didTapToastView(_ toastView: ToastView) {
        Logger.debug("")
        self.dismissToastView()
    }

    func didSwipeToastView(_ toastView: ToastView) {
        Logger.debug("")
        self.dismissToastView()
    }

    // MARK: Internal

    func dismissToastView() {
        Logger.debug("")

        guard !isDismissing else {
            return
        }
        isDismissing = true

        if type(of: self).currentToastController == self {
            type(of: self).currentToastController = nil
        }

        UIView.animate(withDuration: 0.1,
                       animations: {
            self.toastView.alpha = 0
        },
                       completion: { (_) in
            self.toastView.removeFromSuperview()
        })
    }
}
