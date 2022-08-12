// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public struct TargetMigrations: Comparable {
    /// This identifier is used to determine the order each set of migrations should run in.
    ///
    /// All migrations within a specific set will run first, followed by all migrations for the same set index in
    /// the next `Identifier` before moving on to the next `MigrationSet`. So given the migrations:
    ///
    /// `{a: [1], [2, 3]}, {b: [4, 5], [6]}`
    ///
    /// the migrations will run in the following order:
    ///
    /// `a1, b4, b5, a2, a3, b6`
    public enum Identifier: String, CaseIterable, Comparable {
        // WARNING: The string version of these cases are used as migration identifiers so
        // changing them will result in the migrations running again
        case utilitiesKit
        case snodeKit
        case messagingKit
        case uiKit
        
        public static func < (lhs: Self, rhs: Self) -> Bool {
            let lhsIndex: Int = (Identifier.allCases.firstIndex(of: lhs) ?? Identifier.allCases.count)
            let rhsIndex: Int = (Identifier.allCases.firstIndex(of: rhs) ?? Identifier.allCases.count)
            
            return (lhsIndex < rhsIndex)
        }
        
        public func key(with migration: Migration.Type) -> String {
            return "\(self.rawValue).\(migration.identifier)"
        }
    }
    
    public typealias MigrationSet = [Migration.Type]
    
    let identifier: Identifier
    let migrations: [MigrationSet]
    
    // MARK: - Initialization
    
    public init(
        identifier: Identifier,
        migrations: [MigrationSet]
    ) {
        guard !migrations.contains(where: { migration in migration.contains(where: { $0.target != identifier }) }) else {
            preconditionFailure("Attempted to register a migration with the wrong target")
        }
        
        self.identifier = identifier
        self.migrations = migrations
    }
    
    // MARK: - Equatable
    
    public static func == (lhs: TargetMigrations, rhs: TargetMigrations) -> Bool {
        return (
            lhs.identifier == rhs.identifier &&
            lhs.migrations.count == rhs.migrations.count
        )
    }
    
    // MARK: - Comparable
    
    public static func < (lhs: Self, rhs: Self) -> Bool {
        return (lhs.identifier < rhs.identifier)
    }
}
