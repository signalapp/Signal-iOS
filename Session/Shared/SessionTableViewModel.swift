// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit.UIImage
import Combine
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

class SessionTableViewModel<NavItemId: Equatable, Section: SessionTableSection, SettingItem: Hashable & Differentiable> {
    typealias SectionModel = ArraySection<Section, SessionCell.Info<SettingItem>>
    typealias ObservableData = AnyPublisher<[SectionModel], Error>
    
    // MARK: - Input
    
    let navItemTapped: PassthroughSubject<NavItemId, Never> = PassthroughSubject()
    private let _isEditing: CurrentValueSubject<Bool, Never> = CurrentValueSubject(false)
    lazy var isEditing: AnyPublisher<Bool, Never> = _isEditing
        .removeDuplicates()
        .shareReplay(1)
    
    // MARK: - Navigation
    
    open var leftNavItems: AnyPublisher<[NavItem]?, Never> { Just(nil).eraseToAnyPublisher() }
    open var rightNavItems: AnyPublisher<[NavItem]?, Never> { Just(nil).eraseToAnyPublisher() }
    
    private let _showToast: PassthroughSubject<(String, ThemeValue), Never> = PassthroughSubject()
    lazy var showToast: AnyPublisher<(String, ThemeValue), Never> = _showToast
        .shareReplay(0)
    private let _transitionToScreen: PassthroughSubject<(UIViewController, TransitionType), Never> = PassthroughSubject()
    lazy var transitionToScreen: AnyPublisher<(UIViewController, TransitionType), Never> = _transitionToScreen
        .shareReplay(0)
    private let _dismissScreen: PassthroughSubject<DismissType, Never> = PassthroughSubject()
    lazy var dismissScreen: AnyPublisher<DismissType, Never> = _dismissScreen
        .shareReplay(0)
    
    // MARK: - Content
    
    open var title: String { preconditionFailure("abstract class - override in subclass") }
    open var settingsData: [SectionModel] { preconditionFailure("abstract class - override in subclass") }
    open var observableSettingsData: ObservableData {
        preconditionFailure("abstract class - override in subclass")
    }
    
    func updateSettings(_ updatedSettings: [SectionModel]) {
        preconditionFailure("abstract class - override in subclass")
    }
    
    // MARK: - Functions
    
    func setIsEditing(_ isEditing: Bool) {
        _isEditing.send(isEditing)
    }
    
    func showToast(text: String, backgroundColor: ThemeValue = .backgroundPrimary) {
        _showToast.send((text, backgroundColor))
    }
    
    func dismissScreen(type: DismissType = .auto) {
        _dismissScreen.send(type)
    }
    
    func transitionToScreen(_ viewController: UIViewController, transitionType: TransitionType = .push) {
        _transitionToScreen.send((viewController, transitionType))
    }
}
