//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSMessageContentJob;
@class OWSStorage;
@class YapDatabaseReadTransaction;
@class YapDatabaseReadWriteTransaction;

@interface YAPDBMessageContentJobFinder : NSObject

- (NSArray<OWSMessageContentJob *> *)nextJobsForBatchSize:(NSUInteger)maxBatchSize
                                              transaction:(YapDatabaseReadTransaction *)transaction;

- (void)addJobWithEnvelopeData:(NSData *)envelopeData
                 plaintextData:(NSData *_Nullable)plaintextData
               wasReceivedByUD:(BOOL)wasReceivedByUD
       serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
                   transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (void)removeJobsWithIds:(NSArray<NSString *> *)uniqueIds transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (void)asyncRegisterDatabaseExtension:(OWSStorage *)storage;

@end

NS_ASSUME_NONNULL_END
