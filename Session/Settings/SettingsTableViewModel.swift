// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit.UIImage
import Combine
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

class SettingsTableViewModel<NavItemId: Equatable, Section: SettingSection, SettingItem: Hashable & Differentiable> {
    typealias SectionModel = ArraySection<Section, SettingInfo<SettingItem>>
    typealias ObservableData = AnyPublisher<[SectionModel], Error>
    
    var closeNavItemId: NavItemId?
    
    // MARK: - Initialization
    
    /// Provide a `closeNavItemId` in order to show a close button
    init(closeNavItemId: NavItemId? = nil) {
        self.closeNavItemId = closeNavItemId
    }
    
    // MARK: - Input
    
    let navItemTapped: PassthroughSubject<NavItemId, Never> = PassthroughSubject()
    private let _isEditing: CurrentValueSubject<Bool, Never> = CurrentValueSubject(false)
    lazy var isEditing: AnyPublisher<Bool, Never> = _isEditing
        .removeDuplicates()
        .shareReplay(1)
    
    private let _transitionToScreen: PassthroughSubject<(UIViewController, TransitionType), Never> = PassthroughSubject()
    lazy var transitionToScreen: AnyPublisher<(UIViewController, TransitionType), Never> = _transitionToScreen
        .shareReplay(0)
    
    // MARK: - Navigation
    
    open var leftNavItems: AnyPublisher<[NavItem]?, Never> {
        guard let closeNavItemId: NavItemId = self.closeNavItemId else {
            return Just(nil).eraseToAnyPublisher()
        }
        
        return Just([
            NavItem(
                id: closeNavItemId,
                image: UIImage(named: "X")?
                    .withRenderingMode(.alwaysTemplate),
                style: .plain,
                accessibilityIdentifier: "Close Button"
            )
        ]).eraseToAnyPublisher()
    }
    
    open var rightNavItems: AnyPublisher<[NavItem]?, Never> { Just(nil).eraseToAnyPublisher() }
    
    open var closeScreen: AnyPublisher<Bool, Never> {
        navItemTapped
            .filter { [weak self] itemId in itemId == self?.closeNavItemId }
            .map { _ in true }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Content
    
    open var title: String { preconditionFailure("abstract class - override in subclass") }
    open var settingsData: [SectionModel] { preconditionFailure("abstract class - override in subclass") }
    open var observableSettingsData: ObservableData {
        preconditionFailure("abstract class - override in subclass")
    }
    
    func updateSettings(_ updatedSettings: [SectionModel]) {
        preconditionFailure("abstract class - override in subclass")
    }
    
    func setIsEditing(_ isEditing: Bool) {
        _isEditing.send(isEditing)
    }
    
    func transitionToScreen(_ viewController: UIViewController, transitionType: TransitionType = .push) {
        _transitionToScreen.send((viewController, transitionType))
    }
}

// MARK: - NavItem

public enum NoNav: Equatable {}

extension SettingsTableViewModel {
    public struct NavItem {
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
    }
}

// MARK: - SettingSectionHeaderStyle

public enum SettingSectionHeaderStyle: Differentiable {
    case none
    case title
    case padding
}

// MARK: - SettingSection

protocol SettingSection: Differentiable {
    var title: String? { get }
    var style: SettingSectionHeaderStyle { get }
}

extension SettingSection {
    var title: String? { nil }
    var style: SettingSectionHeaderStyle { .none }
}

// MARK: - IconSize

public enum IconSize: Differentiable {
    case small
    case medium
    case large
    
    var size: CGFloat {
        switch self {
            case .small: return 24
            case .medium: return 32
            case .large: return 80
        }
    }
}

// MARK: - TransitionType

public enum TransitionType {
    case push
    case present
}

// MARK: - SettingInfo

struct SettingInfo<ID: Hashable & Differentiable>: Equatable, Hashable, Differentiable {
    let id: ID
    let icon: UIImage?
    let iconSize: IconSize
    let iconSetter: ((UIImageView) -> Void)?
    let title: String
    let subtitle: String?
    let alignment: NSTextAlignment
    let accessibilityIdentifier: String?
    let action: SettingsAction
    let subtitleExtraViewGenerator: (() -> UIView)?
    let extraActionTitle: String?
    let onExtraAction: (() -> Void)?
    
    // MARK: - Initialization
    
    init(
        id: ID,
        icon: UIImage? = nil,
        iconSize: IconSize = .small,
        iconSetter: ((UIImageView) -> Void)? = nil,
        title: String,
        subtitle: String? = nil,
        alignment: NSTextAlignment = .left,
        accessibilityIdentifier: String? = nil,
        subtitleExtraViewGenerator: (() -> UIView)? = nil,
        action: SettingsAction,
        extraActionTitle: String? = nil,
        onExtraAction: (() -> Void)? = nil
    ) {
        self.id = id
        self.icon = icon
        self.iconSize = iconSize
        self.iconSetter = iconSetter
        self.title = title
        self.subtitle = subtitle
        self.alignment = alignment
        self.accessibilityIdentifier = accessibilityIdentifier
        self.subtitleExtraViewGenerator = subtitleExtraViewGenerator
        self.action = action
        self.extraActionTitle = extraActionTitle
        self.onExtraAction = onExtraAction
    }
    
    // MARK: - Conformance
    
    var differenceIdentifier: ID { id }
    
    func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
        icon.hash(into: &hasher)
        iconSize.hash(into: &hasher)
        title.hash(into: &hasher)
        subtitle.hash(into: &hasher)
        alignment.hash(into: &hasher)
        accessibilityIdentifier.hash(into: &hasher)
        action.hash(into: &hasher)
        extraActionTitle.hash(into: &hasher)
    }
    
    static func == (lhs: SettingInfo<ID>, rhs: SettingInfo<ID>) -> Bool {
        return (
            lhs.id == rhs.id &&
            lhs.icon == rhs.icon &&
            lhs.iconSize == rhs.iconSize &&
            lhs.title == rhs.title &&
            lhs.subtitle == rhs.subtitle &&
            lhs.alignment == rhs.alignment &&
            lhs.accessibilityIdentifier == rhs.accessibilityIdentifier &&
            lhs.action == rhs.action &&
            lhs.extraActionTitle == rhs.extraActionTitle
        )
    }
    
    // MARK: - Mutation
    
    func with(action: SettingsAction) -> SettingInfo {
        return SettingInfo(
            id: self.id,
            icon: self.icon,
            title: self.title,
            subtitle: self.subtitle,
            alignment: self.alignment,
            accessibilityIdentifier: self.accessibilityIdentifier,
            subtitleExtraViewGenerator: self.subtitleExtraViewGenerator,
            action: action,
            extraActionTitle: self.extraActionTitle,
            onExtraAction: self.onExtraAction
        )
    }
}

// MARK: - SettingsAction

public enum SettingsAction: Hashable, Equatable {
    case threadInfo(
        threadViewModel: SessionThreadViewModel,
        style: ThreadInfoStyle = ThreadInfoStyle(),
        avatarTapped: (() -> Void)? = nil,
        titleTapped: (() -> Void)? = nil,
        titleChanged: ((String) -> Void)? = nil
    )
    case userDefaultsBool(
        defaults: UserDefaults,
        key: String,
        isEnabled: Bool = true,
        onChange: (() -> Void)?
    )
    case settingBool(
        key: Setting.BoolKey,
        confirmationInfo: ConfirmationModal.Info?,
        isEnabled: Bool = true
    )
    case customToggle(
        value: Bool,
        isEnabled: Bool = true,
        confirmationInfo: ConfirmationModal.Info? = nil,
        onChange: ((Bool) -> Void)? = nil
    )
    case settingEnum(
        key: String,
        title: String?,
        createUpdateScreen: () -> UIViewController
    )
    case generalEnum(
        title: String?,
        createUpdateScreen: () -> UIViewController
    )
    
    case trigger(
        showChevron: Bool = true,
        action: () -> Void
    )
    case push(
        showChevron: Bool = true,
        tintColor: ThemeValue = .textPrimary,
        shouldHaveBackground: Bool = true,
        createDestination: () -> UIViewController
    )
    case present(
        tintColor: ThemeValue = .textPrimary,
        createDestination: () -> UIViewController
    )
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
            case .threadInfo: return "threadInfo"
            case .userDefaultsBool: return "userDefaultsBool"
            case .settingBool: return "settingBool"
            case .customToggle: return "customToggle"
            case .settingEnum: return "settingEnum"
            case .generalEnum: return "generalEnum"
            
            case .trigger: return "trigger"
            case .push: return "push"
            case .present: return "present"
            case .listSelection: return "listSelection"
            case .rightButtonAction: return "rightButtonAction"
        }
    }
    
    var shouldHaveBackground: Bool {
        switch self {
            case .threadInfo: return false
            case .push(_, _, let shouldHaveBackground, _): return shouldHaveBackground
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
            case .threadInfo(let threadViewModel, let style, _, _, _):
                threadViewModel.hash(into: &hasher)
                style.hash(into: &hasher)
                
            case .userDefaultsBool(_, let key, let isEnabled, _):
                key.hash(into: &hasher)
                isEnabled.hash(into: &hasher)
                
            case .settingBool(let key, let confirmationInfo, let isEnabled):
                key.hash(into: &hasher)
                confirmationInfo.hash(into: &hasher)
                isEnabled.hash(into: &hasher)
                
            case .customToggle(let value, let isEnabled, let confirmationInfo, _):
                value.hash(into: &hasher)
                isEnabled.hash(into: &hasher)
                confirmationInfo.hash(into: &hasher)
                
            case .settingEnum(let key, let title, _):
                key.hash(into: &hasher)
                title.hash(into: &hasher)
                
            case .generalEnum(let title, _):
                title.hash(into: &hasher)
                
            case .trigger(let showChevron, _):
                showChevron.hash(into: &hasher)
                
            case .push(let showChevron, let tintColor, let shouldHaveBackground, _):
                showChevron.hash(into: &hasher)
                tintColor.hash(into: &hasher)
                shouldHaveBackground.hash(into: &hasher)
                
            case .present(let tintColor, _):
                tintColor.hash(into: &hasher)
                
            case .listSelection(let isSelected, let storedSelection, let shouldAutoSave, _):
                isSelected().hash(into: &hasher)
                storedSelection.hash(into: &hasher)
                shouldAutoSave.hash(into: &hasher)
                
            case .rightButtonAction(let title, _):
                title.hash(into: &hasher)
        }
    }
    
    public static func == (lhs: SettingsAction, rhs: SettingsAction) -> Bool {
        switch (lhs, rhs) {
            case (.threadInfo(let lhsThreadViewModel, let lhsStyle, _, _, _), .threadInfo(let rhsThreadViewModel, let rhsStyle, _, _, _)):
                return (
                    lhsThreadViewModel == rhsThreadViewModel &&
                    lhsStyle == rhsStyle
                )
                
            case (.userDefaultsBool(_, let lhsKey, let lhsIsEnabled, _), .userDefaultsBool(_, let rhsKey, let rhsIsEnabled, _)):
                return (
                    lhsKey == rhsKey &&
                    lhsIsEnabled == rhsIsEnabled
                )
            
            case (.settingBool(let lhsKey, let lhsConfirmationInfo, let lhsIsEnabled), .settingBool(let rhsKey, let rhsConfirmationInfo, let rhsIsEnabled)):
                return (
                    lhsKey == rhsKey &&
                    lhsConfirmationInfo == rhsConfirmationInfo &&
                    lhsIsEnabled == rhsIsEnabled
                )
            
            case (.customToggle(let lhsValue, let lhsIsEnabled, let lhsConfirmationInfo, _), .customToggle(let rhsValue, let rhsIsEnabled, let rhsConfirmationInfo, _)):
                return (
                    lhsValue == rhsValue &&
                    lhsIsEnabled == rhsIsEnabled &&
                    lhsConfirmationInfo == rhsConfirmationInfo
                )
                
            case (.settingEnum(let lhsKey, let lhsTitle, _), .settingEnum(let rhsKey, let rhsTitle, _)):
                return (
                    lhsKey == rhsKey &&
                    lhsTitle == rhsTitle
                )
                
            case (.generalEnum(let lhsTitle, _), .generalEnum(let rhsTitle, _)):
                return (lhsTitle == rhsTitle)
                
            case (.trigger(let lhsShowChevron, _), .trigger(let rhsShowChevron, _)):
                return (lhsShowChevron == rhsShowChevron)
                
            case (.push(let lhsShowChevron, let lhsTintColor, let lhsHasBackground, _), .push(let rhsShowChevron, let rhsTintColor, let rhsHasBackground, _)):
                return (
                    lhsShowChevron == rhsShowChevron &&
                    lhsTintColor == rhsTintColor &&
                    lhsHasBackground == rhsHasBackground
                )
                
            case (.present(let lhsTintColor, _), .present(let rhsTintColor, _)):
                return (lhsTintColor == rhsTintColor)
                
            case (.listSelection(let lhsIsSelected, let lhsStoredSelection, let lhsShouldAutoSave, _), .listSelection(let rhsIsSelected, let rhsStoredSelection, let rhsShouldAutoSave, _)):
                return (
                    lhsIsSelected() == rhsIsSelected() &&
                    lhsStoredSelection == rhsStoredSelection &&
                    lhsShouldAutoSave == rhsShouldAutoSave
                )
                
            case (.rightButtonAction(let lhsTitle, _), .rightButtonAction(let rhsTitle, _)):
                return (lhsTitle == rhsTitle)
                
            default: return false
        }
    }
}

// MARK: - ThreadInfoStyle

public struct ThreadInfoStyle: Hashable, Equatable {
    public enum Style: Hashable, Equatable {
        case small
        case monoSmall
        case monoLarge
    }
    
    public struct Action: Hashable, Equatable {
        let title: String
        let run: (OutlineButton?) -> ()
        
        public func hash(into hasher: inout Hasher) {
            title.hash(into: &hasher)
        }
        
        public static func == (lhs: Action, rhs: Action) -> Bool {
            return (lhs.title == rhs.title)
        }
    }
    
    public let separatorTitle: String?
    public let descriptionStyle: Style
    public let descriptionActions: [Action]
    
    public init(
        separatorTitle: String? = nil,
        descriptionStyle: Style = .monoSmall,
        descriptionActions: [Action] = []
    ) {
        self.separatorTitle = separatorTitle
        self.descriptionStyle = descriptionStyle
        self.descriptionActions = descriptionActions
    }
}
