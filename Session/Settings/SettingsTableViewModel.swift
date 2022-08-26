// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SessionUIKit
import SessionUtilitiesKit

class SettingsTableViewModel<Section: SettingSection, SettingItem: Hashable & Differentiable> {
    typealias SectionModel = ArraySection<Section, SettingInfo<SettingItem>>
    typealias ObservableData = ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Fetch<[SectionModel]>>>
    
    open var title: String { preconditionFailure("abstract class - override in subclass") }
    open var settingsData: [SectionModel] { preconditionFailure("abstract class - override in subclass") }
    open var observableSettingsData: ObservableData {
        preconditionFailure("abstract class - override in subclass")
    }
    
    func updateSettings(_ updatedSettings: [SectionModel]) {
        preconditionFailure("abstract class - override in subclass")
    }
    
    func saveChanges() {
        preconditionFailure("abstract class - override in subclass")
    }
}

// MARK: - SettingSection

protocol SettingSection: Differentiable {
    var title: String { get }
}

// MARK: - SettingInfo

struct SettingInfo<ID: Hashable & Differentiable>: Equatable, Hashable, Differentiable {
    let id: ID
    let title: String
    let subtitle: String?
    let action: SettingsAction
    let subtitleExtraViewGenerator: (() -> UIView)?
    let extraActionTitle: ((Theme, Theme.PrimaryColor) -> NSAttributedString)?
    let onExtraAction: (() -> Void)?
    
    // MARK: - Initialization
    
    init(
        id: ID,
        title: String,
        subtitle: String? = nil,
        subtitleExtraViewGenerator: (() -> UIView)? = nil,
        action: SettingsAction,
        extraActionTitle: ((Theme, Theme.PrimaryColor) -> NSAttributedString)? = nil,
        onExtraAction: (() -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.subtitleExtraViewGenerator = subtitleExtraViewGenerator
        self.action = action
        self.extraActionTitle = extraActionTitle
        self.onExtraAction = onExtraAction
    }
    
    // MARK: - Conformance
    
    var differenceIdentifier: ID { id }
    
    func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
        title.hash(into: &hasher)
        subtitle.hash(into: &hasher)
        action.hash(into: &hasher)
    }
    
    static func == (lhs: SettingInfo<ID>, rhs: SettingInfo<ID>) -> Bool {
        return (
            lhs.id == rhs.id &&
            lhs.title == rhs.title &&
            lhs.subtitle == rhs.subtitle &&
            lhs.action == rhs.action
        )
    }
}

// MARK: - SettingsAction

public enum SettingsAction: Hashable, Equatable {
    case userDefaultsBool(
        defaults: UserDefaults,
        key: String,
        onChange: (() -> Void)?
    )
    case settingBool(
        key: Setting.BoolKey,
        confirmationInfo: ConfirmationModal.Info?
    )
    case settingEnum(
        key: String,
        title: String?,
        createUpdateScreen: () -> UIViewController
    )
    
    case trigger(action: () -> Void)
    case push(createDestination: () -> UIViewController)
    case dangerPush(createDestination: () -> UIViewController)
    case listSelection(
        isSelected: () -> Bool,
        storedSelection: Bool,
        shouldAutoSave: Bool,
        selectValue: () -> Void
    )
    case rightButtonAction(
        title: String,
        action: (UIView) -> ()
    )
    
    private var actionName: String {
        switch self {
            case .userDefaultsBool: return "userDefaultsBool"
            case .settingBool: return "settingBool"
            case .settingEnum: return "settingEnum"
            
            case .trigger: return "trigger"
            case .push: return "push"
            case .dangerPush: return "dangerPush"
            case .listSelection: return "listSelection"
            case .rightButtonAction: return "rightButtonAction"
        }
    }
    
    var shouldHaveBackground: Bool {
        switch self {
            case .dangerPush: return false
            default: return true
        }
    }
    
    // MARK: - Convenience
    
    public static func settingEnum<ET: EnumIntSetting>(
        _ db: Database,
        type: ET.Type,
        key: Setting.EnumKey,
        titleGenerator: @escaping ((ET?) -> String?),
        createUpdateScreen: @escaping () -> UIViewController
    ) -> SettingsAction {
        return SettingsAction.settingEnum(
            key: key.rawValue,
            title: titleGenerator(db[key]),
            createUpdateScreen: createUpdateScreen
        )
    }
    
    public static func settingEnum<ET: EnumStringSetting>(
        _ db: Database,
        type: ET.Type,
        key: Setting.EnumKey,
        titleGenerator: @escaping ((ET?) -> String?),
        createUpdateScreen: @escaping () -> UIViewController
    ) -> SettingsAction {
        return SettingsAction.settingEnum(
            key: key.rawValue,
            title: titleGenerator(db[key]),
            createUpdateScreen: createUpdateScreen
        )
    }
    
    public static func settingBool(key: Setting.BoolKey) -> SettingsAction {
        return .settingBool(key: key, confirmationInfo: nil)
    }
        
    // MARK: - Conformance
    
    public func hash(into hasher: inout Hasher) {
        actionName.hash(into: &hasher)
        
        switch self {
            case .userDefaultsBool(_, let key, _): key.hash(into: &hasher)
            case .settingBool(let key, let confirmationInfo):
                key.hash(into: &hasher)
                confirmationInfo.hash(into: &hasher)
                
            case .settingEnum(let key, let title, _):
                key.hash(into: &hasher)
                title.hash(into: &hasher)
                
            case .listSelection(let isSelected, let storedSelection, let shouldAutoSave, _):
                isSelected().hash(into: &hasher)
                storedSelection.hash(into: &hasher)
                shouldAutoSave.hash(into: &hasher)
            
            default: break
        }
    }
    
    public static func == (lhs: SettingsAction, rhs: SettingsAction) -> Bool {
        switch (lhs, rhs) {
            case (.userDefaultsBool(_, let lhsKey, _), .userDefaultsBool(_, let rhsKey, _)):
                return (lhsKey == rhsKey)
            
            case (.settingBool(let lhsKey, let lhsConfirmationInfo), .settingBool(let rhsKey, let rhsConfirmationInfo)):
                return (
                    lhsKey == rhsKey &&
                    lhsConfirmationInfo == rhsConfirmationInfo
                )
                
            case (.settingEnum(let lhsKey, let lhsTitle, _), .settingEnum(let rhsKey, let rhsTitle, _)):
                return (
                    lhsKey == rhsKey &&
                    lhsTitle == rhsTitle
                )
                
            case (.listSelection(let lhsIsSelected, let lhsStoredSelection, let lhsShouldAutoSave, _), .listSelection(let rhsIsSelected, let rhsStoredSelection, let rhsShouldAutoSave, _)):
                return (
                    lhsIsSelected() == rhsIsSelected() &&
                    lhsStoredSelection == rhsStoredSelection &&
                    lhsShouldAutoSave == rhsShouldAutoSave
                )
                
            default: return false
        }
    }
}
