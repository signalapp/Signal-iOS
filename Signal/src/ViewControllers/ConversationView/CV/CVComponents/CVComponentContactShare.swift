//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class CVComponentContactShare: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .contactShare }

    private let contactShareState: CVComponentState.ContactShare

    private var contactShare: ContactShareViewModel {
        contactShareState.state.contactShare
    }

    init(itemModel: CVItemModel, contactShareState: CVComponentState.ContactShare) {
        self.contactShareState = contactShareState

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewContactShare()
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewContactShare else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let contactShareView = componentView.contactShareView
        contactShareView.configureForRendering(state: contactShareState.state,
                                               cellMeasurement: cellMeasurement)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        return CVContactShareView.measure(maxWidth: maxWidth,
                                          measurementBuilder: measurementBuilder,
                                          state: contactShareState.state)
    }

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        componentDelegate.didTapContactShare(contactShare)
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewContactShare: NSObject, CVComponentView {

        fileprivate let contactShareView = CVContactShareView(name: "CVContactShareView")

        public var isDedicatedCellView = false

        public var rootView: UIView {
            contactShareView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            contactShareView.reset()
        }

    }
}

// MARK: -

extension CVComponentContactShare: CVAccessibilityComponent {
    public var accessibilityDescription: String {
        if let contactName = contactShare.displayName.filterForDisplay,
           !contactName.isEmpty {
            let format = NSLocalizedString("ACCESSIBILITY_LABEL_CONTACT_FORMAT",
                                           comment: "Accessibility label for contact. Embeds: {{ the contact name }}.")
            return String(format: format, contactName)
        } else {
            return NSLocalizedString("ACCESSIBILITY_LABEL_CONTACT",
                                     comment: "Accessibility label for contact.")
        }
    }
}
