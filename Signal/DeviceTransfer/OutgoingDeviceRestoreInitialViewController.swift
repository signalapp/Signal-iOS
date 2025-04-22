//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SwiftUI
import SignalUI
import SignalServiceKit

class OutgoingDeviceRestoreInitialViewModel: ObservableObject {

    var onTransferCallback: () -> Void = {}

    func startTransfer() {
        onTransferCallback()
    }
}

class OutgoingDeviceRestoreIntialViewController: HostingController<OutgoingDeviceRestoreInitialView> {
    private let viewModel = OutgoingDeviceRestoreInitialViewModel()

    init() {
        super.init(wrappedView: OutgoingDeviceRestoreInitialView(viewModel: viewModel))
        viewModel.onTransferCallback = { [weak self] in
            self?.onTransferButtonPressed()
        }

        self.modalPresentationStyle = .formSheet

        self.title = OWSLocalizedString(
            "OUTGOING_DEVICE_RESTORE_INITIAL_VIEW_TITLE",
            comment: "Title text describing the outgoing transfer."
        )
        self.navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)
        view.backgroundColor = UIColor.Signal.secondaryBackground
        OWSTableViewController2.removeBackButtonText(viewController: self)
    }

    func onTransferButtonPressed() {
        let sheet = HeroSheetViewController(
            hero: .image(UIImage(named: "transfer_account")!),
            title: LocalizationNotNeeded("Continue on your other device"),
            body: LocalizationNotNeeded("Continue transferring your account on your other device."),
            primary: .hero(.animation(named: "circular_indeterminate", height: 60))
        )
        sheet.modalPresentationStyle = .formSheet
        self.present(sheet, animated: true)
    }
}

struct OutgoingDeviceRestoreInitialView: View {
    @ObservedObject fileprivate var viewModel: OutgoingDeviceRestoreInitialViewModel

    var body: some View {
        SignalList {
            SignalSection {
                VStack(alignment: .center, spacing: 24) {
                    Image("transfer_account")

                    Text(OWSLocalizedString(
                        "OUTGOING_DEVICE_RESTORE_INITIAL_VIEW_BODY",
                        comment: "Body text describing the outgoing transfer."
                    ))
                    .appendLink(CommonStrings.learnMore) {
                        UIApplication.shared.open(URL(string: "TODO: link to documentation")!)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                    .tint(Color.Signal.label)

                    Button(OWSLocalizedString(
                        "OUTGOING_DEVICE_RESTORE_INITIAL_VIEW_CONFIRM_ACTION",
                        comment: "Action button to begin account transfer."
                    )) {
                        viewModel.startTransfer()
                    }
                    .buttonStyle(Registration.UI.FilledButtonStyle())
                }.padding([.top, .bottom], 12)
            }
            footer: {
                let footerString = OWSLocalizedString(
                    "OUTGOING_DEVICE_RESTORE_INITIAL_VIEW_FOOTER",
                    comment: "Body text describing the outgoing transfer."
                )
                Text("\(SignalSymbol.lock.text(dynamicTypeBaseSize: 14)) \(footerString)")
                    .font(.footnote)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                    .padding([.top, .bottom], 12)
            }
        }
        .scrollBounceBehaviorIfAvailable(.basedOnSize)
        .multilineTextAlignment(.center)
    }
}

// MARK: Previews

#if DEBUG
@available(iOS 17, *)
#Preview {
    OWSNavigationController(
        rootViewController: OutgoingDeviceRestoreIntialViewController()
    )
}
#endif
