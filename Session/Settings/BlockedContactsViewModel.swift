// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SignalUtilitiesKit

public class BlockedContactsViewModel {
    public typealias SectionModel = ArraySection<Section, SessionCell.Info<Profile>>
    
    // MARK: - Section
    
    public enum Section: Differentiable {
        case contacts
        case loadMore
    }
    
    // MARK: - Variables
    
    public static let pageSize: Int = 30
    
    // MARK: - Initialization
    
    init() {
        self.pagedDataObserver = nil
        
        // Note: Since this references self we need to finish initializing before setting it, we
        // also want to skip the initial query and trigger it async so that the push animation
        // doesn't stutter (it should load basically immediately but without this there is a
        // distinct stutter)
        self.pagedDataObserver = PagedDatabaseObserver(
            pagedTable: Profile.self,
            pageSize: BlockedContactsViewModel.pageSize,
            idColumn: .id,
            observedChanges: [
                PagedData.ObservedChanges(
                    table: Profile.self,
                    columns: [
                        .id,
                        .name,
                        .nickname,
                        .profilePictureFileName
                    ]
                ),
                PagedData.ObservedChanges(
                    table: Contact.self,
                    columns: [.isBlocked],
                    joinToPagedType: {
                        let profile: TypedTableAlias<Profile> = TypedTableAlias()
                        let contact: TypedTableAlias<Contact> = TypedTableAlias()
                        
                        return SQL("JOIN \(Contact.self) ON \(contact[.id]) = \(profile[.id])")
                    }()
                )
            ],
            /// **Note:** This `optimisedJoinSQL` value includes the required minimum joins needed for the query
            joinSQL: DataModel.optimisedJoinSQL,
            filterSQL: DataModel.filterSQL,
            orderSQL: DataModel.orderSQL,
            dataQuery: DataModel.query(
                filterSQL: DataModel.filterSQL,
                orderSQL: DataModel.orderSQL
            ),
            onChangeUnsorted: { [weak self] updatedData, updatedPageInfo in
                guard
                    let currentData: [SectionModel] = self?.contactData,
                    let updatedContactData: [SectionModel] = self?.process(data: updatedData, for: updatedPageInfo)
                else { return }
                
                let changeset: StagedChangeset<[SectionModel]> = StagedChangeset(
                    source: currentData,
                    target: updatedContactData
                )
                
                // No need to do anything if there were no changes
                guard !changeset.isEmpty else { return }
                
                // Run any changes on the main thread (as they will generally trigger UI updates)
                DispatchQueue.main.async {
                    // If we have the callback then trigger it, otherwise just store the changes to be sent
                    // to the callback if we ever start observing again (when we have the callback it needs
                    // to do the data updating as it's tied to UI updates and can cause crashes if not updated
                    // in the correct order)
                    guard let onContactChange: (([SectionModel], StagedChangeset<[SectionModel]>) -> ()) = self?.onContactChange else {
                        self?.unobservedContactDataChanges = (updatedContactData, changeset)
                        return
                    }
                    
                    onContactChange(updatedContactData, changeset)
                }
            }
        )
        
        // Run the initial query on a background thread so we don't block the push transition
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // The `.pageBefore` will query from a `0` offset loading the first page
            self?.pagedDataObserver?.load(.pageBefore)
        }
    }
    
    // MARK: - Contact Data
    
    public private(set) var selectedContactIds: Set<String> = []
    public private(set) var unobservedContactDataChanges: ([SectionModel], StagedChangeset<[SectionModel]>)?
    public private(set) var contactData: [SectionModel] = []
    public private(set) var pagedDataObserver: PagedDatabaseObserver<Profile, DataModel>?
    
    public var onContactChange: (([SectionModel], StagedChangeset<[SectionModel]>) -> ())? {
        didSet {
            // When starting to observe interaction changes we want to trigger a UI update just in case the
            // data was changed while we weren't observing
            if let unobservedContactDataChanges: ([SectionModel], StagedChangeset<[SectionModel]>) = self.unobservedContactDataChanges {
                onContactChange?(unobservedContactDataChanges.0 , unobservedContactDataChanges.1)
                self.unobservedContactDataChanges = nil
            }
        }
    }
    
    private func process(data: [DataModel], for pageInfo: PagedData.PageInfo) -> [SectionModel] {
        // Update the 'selectedContactIds' to only include selected contacts which are within the
        // data (ie. handle profile deletions)
        let profileIds: Set<String> = data.map { $0.id }.asSet()
        selectedContactIds = selectedContactIds.intersection(profileIds)
        
        return [
            [
                SectionModel(
                    section: .contacts,
                    elements: data
                        .sorted { lhs, rhs -> Bool in
                            lhs.profile.displayName() > rhs.profile.displayName()
                        }
                        .map { model -> SessionCell.Info<Profile> in
                            SessionCell.Info(
                                id: model.profile,
                                leftAccessory: .profile(model.profile.id, model.profile),
                                title: model.profile.displayName(),
                                rightAccessory: .radio(
                                    isSelected: { [weak self] in
                                        self?.selectedContactIds.contains(model.profile.id) == true
                                    }
                                ),
                                onTap: { [weak self] in
                                    guard self?.selectedContactIds.contains(model.profile.id) == true else {
                                        self?.selectedContactIds.insert(model.profile.id)
                                        return
                                    }
                                    
                                    self?.selectedContactIds.remove(model.profile.id)
                                }
                            )
                        }
                )
            ],
            (!data.isEmpty && (pageInfo.pageOffset + pageInfo.currentCount) < pageInfo.totalCount ?
                [SectionModel(section: .loadMore)] :
                []
            )
        ].flatMap { $0 }
    }
    
    public func updateContactData(_ updatedData: [SectionModel]) {
        self.contactData = updatedData
    }
    
    // MARK: - DataModel

    public struct DataModel: FetchableRecordWithRowId, Decodable, Equatable, Hashable, Identifiable, Differentiable {
        public static let rowIdKey: SQL = SQL(stringLiteral: CodingKeys.rowId.stringValue)
        public static let profileKey: SQL = SQL(stringLiteral: CodingKeys.profile.stringValue)
        
        public static let profileString: String = CodingKeys.profile.stringValue
        
        public var differenceIdentifier: String { profile.id }
        public var id: String { profile.id }
        
        public let rowId: Int64
        public let profile: Profile
    
        static func query(
            filterSQL: SQL,
            orderSQL: SQL
        ) -> (([Int64]) -> AdaptedFetchRequest<SQLRequest<DataModel>>) {
            return { rowIds -> AdaptedFetchRequest<SQLRequest<DataModel>> in
                let profile: TypedTableAlias<Profile> = TypedTableAlias()
                
                /// **Note:** The `numColumnsBeforeProfile` value **MUST** match the number of fields before
                /// the `DataModel.profileKey` entry below otherwise the query will fail to
                /// parse and might throw
                ///
                /// Explicitly set default values for the fields ignored for search results
                let numColumnsBeforeProfile: Int = 1
                
                let request: SQLRequest<DataModel> = """
                    SELECT
                        \(profile.alias[Column.rowID]) AS \(DataModel.rowIdKey),
                        \(DataModel.profileKey).*
                    
                    FROM \(Profile.self)
                    WHERE \(profile.alias[Column.rowID]) IN \(rowIds)
                    ORDER BY \(orderSQL)
                """
                
                return request.adapted { db in
                    let adapters = try splittingRowAdapters(columnCounts: [
                        numColumnsBeforeProfile,
                        Profile.numberOfSelectedColumns(db)
                    ])
                    
                    return ScopeAdapter([
                        DataModel.profileString: adapters[1]
                    ])
                }
            }
        }
        
        static var optimisedJoinSQL: SQL = {
            let profile: TypedTableAlias<Profile> = TypedTableAlias()
            let contact: TypedTableAlias<Contact> = TypedTableAlias()
            
            return SQL("JOIN \(Contact.self) ON \(contact[.id]) = \(profile[.id])")
        }()
        
        static var filterSQL: SQL = {
            let contact: TypedTableAlias<Contact> = TypedTableAlias()
            
            return SQL("\(contact[.isBlocked]) = true")
        }()
        
        static let orderSQL: SQL = {
            let profile: TypedTableAlias<Profile> = TypedTableAlias()
            
            return SQL("IFNULL(IFNULL(\(profile[.nickname]), \(profile[.name])), \(profile[.id])) ASC")
        }()
    }

}
