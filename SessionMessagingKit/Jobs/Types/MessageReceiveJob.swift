// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SessionUtilitiesKit

public enum MessageReceiveJob: JobExecutor {
    public static var maxFailureCount: Int = 10
    public static var requiresThreadId: Bool = true
    public static let requiresInteractionId: Bool = false
    
    public static func run(
        _ job: Job,
        queue: DispatchQueue,
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    ) {
        guard
            let detailsData: Data = job.details,
            let details: Details = try? JSONDecoder().decode(Details.self, from: detailsData)
        else {
            failure(job, JobRunnerError.missingRequiredDetails, false)
            return
        }
        
        var updatedJob: Job = job
        var leastSevereError: Error?
        
        Storage.shared.write { db in
            var remainingMessagesToProcess: [Details.MessageInfo] = []
            
            for messageInfo in details.messages {
                do {
                    try MessageReceiver.handle(
                        db,
                        message: messageInfo.message,
                        associatedWithProto: try SNProtoContent.parseData(messageInfo.serializedProtoData),
                        openGroupId: nil
                    )
                }
                catch {
                    // If the current message is a permanent failure then override it with the
                    // new error (we want to retry if there is a single non-permanent error)
                    switch error {
                        // Ignore duplicate and self-send errors (these will usually be caught during
                        // parsing but sometimes can get past and conflict at database insertion - eg.
                        // for open group messages) we also don't bother logging as it results in
                        // excessive logging which isn't useful)
                        case DatabaseError.SQLITE_CONSTRAINT_UNIQUE,
                            MessageReceiverError.duplicateMessage,
                            MessageReceiverError.duplicateControlMessage,
                            MessageReceiverError.selfSend:
                            break
                        
                        case let receiverError as MessageReceiverError where !receiverError.isRetryable:
                            SNLog("MessageReceiveJob permanently failed message due to error: \(error)")
                            continue
                        
                        default:
                            SNLog("Couldn't receive message due to error: \(error)")
                            leastSevereError = error
                            
                            // We failed to process this message but it is a retryable error
                            // so add it to the list to re-process
                            remainingMessagesToProcess.append(messageInfo)
                    }
                }
            }
            
            // If any messages failed to process then we want to update the job to only include
            // those failed messages
            updatedJob = try job
                .with(
                    details: Details(
                        messages: remainingMessagesToProcess,
                        calledFromBackgroundPoller: details.calledFromBackgroundPoller
                    )
                )
                .defaulting(to: job)
                .saved(db)
        }
        
        // Handle the result
        switch leastSevereError {
            case let error as MessageReceiverError where !error.isRetryable:
                failure(updatedJob, error, true)
                
            case .some(let error):
                failure(updatedJob, error, false) // TODO: Confirm the 'noKeyPair' errors here aren't an issue
                
            case .none:
                success(updatedJob, false)
        }
    }
}

// MARK: - MessageReceiveJob.Details

extension MessageReceiveJob {
    public struct Details: Codable {
        public struct MessageInfo: Codable {
            private enum CodingKeys: String, CodingKey {
                case message
                case variant
                case serializedProtoData
            }
            
            public let message: Message
            public let variant: Message.Variant
            public let serializedProtoData: Data
            
            public init(
                message: Message,
                variant: Message.Variant,
                proto: SNProtoContent
            ) throws {
                self.message = message
                self.variant = variant
                self.serializedProtoData = try proto.serializedData()
            }
            
            private init(
                message: Message,
                variant: Message.Variant,
                serializedProtoData: Data
            ) {
                self.message = message
                self.variant = variant
                self.serializedProtoData = serializedProtoData
            }
            
            // MARK: - Codable
            
            public init(from decoder: Decoder) throws {
                let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
                
                guard let variant: Message.Variant = try? container.decode(Message.Variant.self, forKey: .variant) else {
                    SNLog("Unable to decode messageReceive job due to missing variant")
                    throw StorageError.decodingFailed
                }
                
                self = MessageInfo(
                    message: try variant.decode(from: container, forKey: .message),
                    variant: variant,
                    serializedProtoData: try container.decode(Data.self, forKey: .serializedProtoData)
                )
            }
            
            public func encode(to encoder: Encoder) throws {
                var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
                
                guard let variant: Message.Variant = Message.Variant(from: message) else {
                    SNLog("Unable to encode messageReceive job due to unsupported variant")
                    throw StorageError.objectNotFound
                }

                try container.encode(message, forKey: .message)
                try container.encode(variant, forKey: .variant)
                try container.encode(serializedProtoData, forKey: .serializedProtoData)
            }
        }
        
        public let messages: [MessageInfo]
        private let isBackgroundPoll: Bool
        
        // Renamed variable for clarity (and didn't want to migrate old MessageReceiveJob
        // values so didn't rename the original)
        public var calledFromBackgroundPoller: Bool { isBackgroundPoll }
        
        public init(
            messages: [MessageInfo],
            calledFromBackgroundPoller: Bool
        ) {
            self.messages = messages
            self.isBackgroundPoll = calledFromBackgroundPoller
        }
    }
}
