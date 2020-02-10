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
        markAsComplete()
        super.dismiss(animated: flag, completion: completion)
    }

    @objc
    func didTapDismissButton(sender: UIButton) {
        Logger.debug("")
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
        markAsComplete()
    }
}
