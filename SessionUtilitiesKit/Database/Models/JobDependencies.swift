// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public struct JobDependencies: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "jobDependencies" }
    internal static let jobForeignKey = ForeignKey([Columns.jobId], to: [Job.Columns.id])
    internal static let job = belongsTo(Job.self, using: jobForeignKey)
    internal static let dependant = hasOne(Job.self, using: Job.dependencyForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case jobId
        case dependantId
    }
    
    public let jobId: Int64
    public let dependantId: Int64
    
    // MARK: - Initialization
    
    public init(
        jobId: Int64,
        dependantId: Int64
    ) {
        self.jobId = jobId
        self.dependantId = dependantId
    }
    
    // MARK: - Relationships
         
    public var job: QueryInterfaceRequest<Job> {
        request(for: JobDependencies.job)
    }
    
    public var dependant: QueryInterfaceRequest<Job> {
        request(for: JobDependencies.dependant)
    }
}
