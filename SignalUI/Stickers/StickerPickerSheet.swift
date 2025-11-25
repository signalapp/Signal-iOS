//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public protocol StickerPickerSheetDelegate: AnyObject {
    func makeManageStickersViewController(for: StickerPickerSheet) -> UIViewController
}

public class StickerPickerSheet: InteractiveSheetViewController {

    public override var interactiveScrollViews: [UIScrollView] { stickerPickerView.stickerPackCollectionViewPages }

    public override var sheetBackgroundColor: UIColor { .clear }

    /// Used for presenting the sticker manager from the toolbar.
    ///
    /// This delegate is optional. If it is not set, the picker sheet will
    /// still function, but the manage stickers button will not appear
    /// on the toolbar.
    public weak var sheetDelegate: StickerPickerSheetDelegate? {
        didSet {
            // The picker view only shows the manage button if it has a delegate
            // If the sheet doesn't have a delegate, it can't present the
            // manage stickers view controller, so only set the picker view
            // delegate if there is a sheet delegate.
            stickerPickerView.delegate = sheetDelegate == nil ? nil : self
        }
    }
    /// Used for handling sticker selection.
    private weak var pickerDelegate: (StickerPickerDelegate&StoryStickerPickerDelegate)?

    private lazy var stickerPickerView = StickerPickerView(
        delegate: self,
        storyStickerConfiguration: .showWithDelegate(pickerDelegate!)
    )

    public init(pickerDelegate: StickerPickerDelegate&StoryStickerPickerDelegate) {
        self.pickerDelegate = pickerDelegate

        let useBlurEffect = !UIAccessibility.isReduceTransparencyEnabled
        super.init(visualEffect: useBlurEffect ? UIBlurEffect(style: .dark) : nil)

        if !useBlurEffect {
            stickerPickerView.backgroundColor = .Signal.background
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        overrideUserInterfaceStyle = .dark

        stickerPickerView.directionalLayoutMargins = .init(
            hMargin: OWSTableViewController2.cellHInnerMargin,
            vMargin: 8
        )
        contentView.addSubview(stickerPickerView)
        stickerPickerView.autoPinEdgesToSuperviewEdges()
        stickerPickerView.stickerPackCollectionViewPages.forEach { $0.alwaysBounceVertical = true }
    }

    private var viewHasAppeared = false

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        stickerPickerView.willBePresented()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        viewHasAppeared = true
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if !viewHasAppeared {
            stickerPickerView.wasPresented()
        }
    }
}

// MARK: StickerPickerViewDelegate

extension StickerPickerSheet: StickerPickerViewDelegate {

    func presentManageStickersView(for stickerPickerView: StickerPickerView) {
        guard let sheetDelegate else { return }
        let manageStickersViewController = sheetDelegate.makeManageStickersViewController(for: self)
        presentFormSheet(manageStickersViewController, animated: true)
    }

    public func didSelectSticker(_ stickerInfo: StickerInfo) {
        pickerDelegate?.didSelectSticker(stickerInfo)
    }
}
