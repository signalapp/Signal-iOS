// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import DifferenceKit
import SessionUIKit

extension SessionCell {
    public struct Info<ID: Hashable & Differentiable>: Equatable, Hashable, Differentiable {
        let id: ID
        let leftAccessory: SessionCell.Accessory?
        let title: String
        let subtitle: String?
        let subtitleExtraViewGenerator: (() -> UIView)?
        let tintColor: ThemeValue
        let rightAccessory: SessionCell.Accessory?
        let extraAction: SessionCell.ExtraAction?
        let isEnabled: Bool
        let shouldHaveBackground: Bool
        let accessibilityIdentifier: String?
        let confirmationInfo: ConfirmationModal.Info?
        let onTap: ((UIView?) -> Void)?
        
        var currentBoolValue: Bool {
            return (
                (leftAccessory?.currentBoolValue ?? false) ||
                (rightAccessory?.currentBoolValue ?? false)
            )
        }
        
        // MARK: - Initialization
        
        init(
            id: ID,
            leftAccessory: SessionCell.Accessory? = nil,
            title: String,
            subtitle: String? = nil,
            subtitleExtraViewGenerator: (() -> UIView)? = nil,
            tintColor: ThemeValue = .textPrimary,
            rightAccessory: SessionCell.Accessory? = nil,
            extraAction: SessionCell.ExtraAction? = nil,
            isEnabled: Bool = true,
            shouldHaveBackground: Bool = true,
            accessibilityIdentifier: String? = nil,
            confirmationInfo: ConfirmationModal.Info? = nil,
            onTap: ((UIView?) -> Void)?
        ) {
            self.id = id
            self.leftAccessory = leftAccessory
            self.title = title
            self.subtitle = subtitle
            self.subtitleExtraViewGenerator = subtitleExtraViewGenerator
            self.tintColor = tintColor
            self.rightAccessory = rightAccessory
            self.extraAction = extraAction
            self.isEnabled = isEnabled
            self.shouldHaveBackground = shouldHaveBackground
            self.accessibilityIdentifier = accessibilityIdentifier
            self.confirmationInfo = confirmationInfo
            self.onTap = onTap
        }
        
        init(
            id: ID,
            leftAccessory: SessionCell.Accessory? = nil,
            title: String,
            subtitle: String? = nil,
            subtitleExtraViewGenerator: (() -> UIView)? = nil,
            tintColor: ThemeValue = .textPrimary,
            rightAccessory: SessionCell.Accessory? = nil,
            extraAction: SessionCell.ExtraAction? = nil,
            isEnabled: Bool = true,
            shouldHaveBackground: Bool = true,
            accessibilityIdentifier: String? = nil,
            confirmationInfo: ConfirmationModal.Info? = nil,
            onTap: (() -> Void)? = nil
        ) {
            self.id = id
            self.leftAccessory = leftAccessory
            self.title = title
            self.subtitle = subtitle
            self.subtitleExtraViewGenerator = subtitleExtraViewGenerator
            self.tintColor = tintColor
            self.rightAccessory = rightAccessory
            self.extraAction = extraAction
            self.isEnabled = isEnabled
            self.shouldHaveBackground = shouldHaveBackground
            self.accessibilityIdentifier = accessibilityIdentifier
            self.confirmationInfo = confirmationInfo
            self.onTap = (onTap != nil ? { _ in onTap?() } : nil)
        }
        
        // MARK: - Conformance
        
        public var differenceIdentifier: ID { id }
        
        public func hash(into hasher: inout Hasher) {
            id.hash(into: &hasher)
            leftAccessory.hash(into: &hasher)
            title.hash(into: &hasher)
            subtitle.hash(into: &hasher)
            tintColor.hash(into: &hasher)
            rightAccessory.hash(into: &hasher)
            extraAction.hash(into: &hasher)
            isEnabled.hash(into: &hasher)
            shouldHaveBackground.hash(into: &hasher)
            accessibilityIdentifier.hash(into: &hasher)
            confirmationInfo.hash(into: &hasher)
        }
        
        public static func == (lhs: Info<ID>, rhs: Info<ID>) -> Bool {
            return (
                lhs.id == rhs.id &&
                lhs.leftAccessory == rhs.leftAccessory &&
                lhs.title == rhs.title &&
                lhs.subtitle == rhs.subtitle &&
                lhs.tintColor == rhs.tintColor &&
                lhs.rightAccessory == rhs.rightAccessory &&
                lhs.extraAction == rhs.extraAction &&
                lhs.isEnabled == rhs.isEnabled &&
                lhs.shouldHaveBackground == rhs.shouldHaveBackground &&
                lhs.accessibilityIdentifier == rhs.accessibilityIdentifier
            )
        }
    }
}
