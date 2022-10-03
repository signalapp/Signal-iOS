// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUtilitiesKit

public enum NoNav: Equatable {}

extension SessionTableViewModel {
    public struct NavItem: Equatable {
        let id: NavItemId
        let image: UIImage?
        let style: UIBarButtonItem.Style
        let systemItem: UIBarButtonItem.SystemItem?
        let accessibilityIdentifier: String
        let action: (() -> Void)?
        
        // MARK: - Initialization
        
        public init(
            id: NavItemId,
            systemItem: UIBarButtonItem.SystemItem?,
            accessibilityIdentifier: String,
            action: (() -> Void)? = nil
        ) {
            self.id = id
            self.image = nil
            self.style = .plain
            self.systemItem = systemItem
            self.accessibilityIdentifier = accessibilityIdentifier
            self.action = action
        }
        
        public init(
            id: NavItemId,
            image: UIImage?,
            style: UIBarButtonItem.Style,
            accessibilityIdentifier: String,
            action: (() -> Void)? = nil
        ) {
            self.id = id
            self.image = image
            self.style = style
            self.systemItem = nil
            self.accessibilityIdentifier = accessibilityIdentifier
            self.action = action
        }
        
        // MARK: - Functions
        
        public func createBarButtonItem() -> DisposableBarButtonItem {
            guard let systemItem: UIBarButtonItem.SystemItem = systemItem else {
                return DisposableBarButtonItem(
                    image: image,
                    style: style,
                    target: nil,
                    action: nil,
                    accessibilityIdentifier: accessibilityIdentifier
                )
            }

            return DisposableBarButtonItem(
                barButtonSystemItem: systemItem,
                target: nil,
                action: nil,
                accessibilityIdentifier: accessibilityIdentifier
            )
        }
        
        // MARK: - Conformance
        
        public static func == (
            lhs: SessionTableViewModel<NavItemId, Section, SettingItem>.NavItem,
            rhs: SessionTableViewModel<NavItemId, Section, SettingItem>.NavItem
        ) -> Bool {
            return (
                lhs.id == rhs.id &&
                lhs.image == rhs.image &&
                lhs.style == rhs.style &&
                lhs.systemItem == rhs.systemItem &&
                lhs.accessibilityIdentifier == rhs.accessibilityIdentifier
            )
        }
    }
}
