//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMessaging

@objc
public class SplashViewController: OWSViewController, ExperienceUpgradeView {

    // MARK: -

    let experienceUpgrade: ExperienceUpgrade
    var canDismissWithGesture: Bool { return true }
    var isPresented: Bool { presentingViewController != nil }
    var isReadyToComplete: Bool { true }

    init(experienceUpgrade: ExperienceUpgrade) {
        self.experienceUpgrade = experienceUpgrade
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - View lifecycle

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.isDarkThemeEnabled ? .lightContent : .default
    }

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        // TODO Xcode 11: Delete this once we're compiling only in Xcode 11
        #if swift(>=5.1)

        // Don't allow interactive dismissal.
        if #available(iOS 13, *) {
            presentationController?.delegate = self
            isModalInPresentation = !canDismissWithGesture
        } else {
            addDismissGesture()
        }

        #else

        addDismissGesture()

        #endif
    }

    // MARK: -

    private func addDismissGesture() {
        let swipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(handleDismissGesture))
        swipeGesture.direction = .down
        view.addGestureRecognizer(swipeGesture)
        view.isUserInteractionEnabled = true
    }

    @objc
    public override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag) {
            self.didDismiss()
            completion?()
        }
    }

    @objc
    func didDismiss() {
        Logger.debug("")

        // Only complete on dismissal if we're ready to do so. This is by
        // default always true, but can be overriden on an individual basis.
        guard isReadyToComplete else { return }

        markAsComplete()
    }

    @objc
    func didTapDismissButton(sender: UIButton) {
        self.dismiss(animated: true)
    }

    @objc
    func handleDismissGesture(sender: AnyObject) {
        guard canDismissWithGesture else { return }

        Logger.debug("")
        self.dismiss(animated: true)
    }

    // MARK: Orientation

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }
}

extension SplashViewController: UIAdaptivePresentationControllerDelegate {
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        didDismiss()
    }
}
