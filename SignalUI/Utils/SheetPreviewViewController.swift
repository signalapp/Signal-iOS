//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

#if DEBUG
final public class SheetPreviewViewController: UIViewController {
    private let animateFirstAppearance: Bool
    private let presentAction: PresentAction

    private enum PresentAction {
        case createSheet(() -> UIViewController)
        case presentSheet((_ viewController: SheetPreviewViewController, _ animated: Bool) -> Void)

        func present(from viewController: SheetPreviewViewController, animated: Bool) {
            switch self {
            case let .createSheet(createSheet):
                let sheet = createSheet()
                viewController.present(sheet, animated: animated)
            case let .presentSheet(presentSheet):
                presentSheet(viewController, animated)
            }
        }
    }

    public init(
        animateFirstAppearance: Bool = false,
        presentSheet: @escaping (
            _ viewController: SheetPreviewViewController,
            _ animated: Bool
        ) -> Void
    ) {
        self.animateFirstAppearance = animateFirstAppearance
        self.presentAction = .presentSheet(presentSheet)
        super.init(nibName: nil, bundle: nil)
    }

    public init(
        animateFirstAppearance: Bool = false,
        sheet: @escaping @autoclosure () -> UIViewController
    ) {
        self.animateFirstAppearance = animateFirstAppearance
        self.presentAction = .createSheet(sheet)
        super.init(nibName: nil, bundle: nil)
    }

    public init(
        animateFirstAppearance: Bool = false,
        createSheet: @escaping () -> UIViewController
    ) {
        self.animateFirstAppearance = animateFirstAppearance
        self.presentAction = .createSheet(createSheet)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        let button = OWSButton(title: "Present sheet") { [unowned self] in
            self.presentAction.present(from: self, animated: true)
        }
        view.addSubview(button)
        button.autoCenterInSuperview()
        button.setTitleColor(UIColor.Signal.accent, for: .normal)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.presentAction.present(from: self, animated: animateFirstAppearance)
    }
}
#endif
