//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "YAPDBMessageContentJobFinder.h"
#import "OWSBatchMessageProcessor.h"
#import "OWSStorage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabaseAutoView.h>
#import <YapDatabase/YapDatabaseTransaction.h>
#import <YapDatabase/YapDatabaseViewTypes.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const YAPDBMessageContentJobFinderExtensionName = @"OWSMessageContentJobFinderExtensionName2";
NSString *const YAPDBMessageContentJobFinderExtensionGroup = @"OWSMessageContentJobFinderExtensionGroup2";

@implementation YAPDBMessageContentJobFinder

- (NSArray<OWSMessageContentJob *> *)nextJobsForBatchSize:(NSUInteger)maxBatchSize
                                              transaction:(YapDatabaseReadTransaction *)transaction
{
    NSMutableArray<OWSMessageContentJob *> *jobs = [NSMutableArray new];
    YapDatabaseViewTransaction *viewTransaction = [transaction ext:YAPDBMessageContentJobFinderExtensionName];
    OWSAssertDebug(viewTransaction != nil);
    [viewTransaction enumerateKeysAndObjectsInGroup:YAPDBMessageContentJobFinderExtensionGroup
                                         usingBlock:^(NSString *_Nonnull collection,
                                             NSString *_Nonnull key,
                                             id _Nonnull object,
                                             NSUInteger index,
                                             BOOL *_Nonnull stop) {
                                             OWSMessageContentJob *job = object;
                                             [jobs addObject:job];
                                             if (jobs.count >= maxBatchSize) {
                                                 *stop = YES;
                                             }
                                         }];

    return [jobs copy];
}

- (void)addJobWithEnvelopeData:(NSData *)envelopeData
                 plaintextData:(NSData *_Nullable)plaintextData
               wasReceivedByUD:(BOOL)wasReceivedByUD
       serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(envelopeData);
    OWSAssertDebug(transaction);

    OWSMessageContentJob *job = [[OWSMessageContentJob alloc] initWithEnvelopeData:envelopeData
                                                                     plaintextData:plaintextData
                                                                   wasReceivedByUD:wasReceivedByUD
                                                           serverDeliveryTimestamp:serverDeliveryTimestamp];
    [job anyInsertWithTransaction:transaction.asAnyWrite];
}

- (void)removeJobsWithIds:(NSArray<NSString *> *)uniqueIds transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [transaction removeObjectsForKeys:uniqueIds inCollection:[OWSMessageContentJob collection]];
}

+ (YapDatabaseView *)databaseExtension
{
    YapDatabaseViewSorting *sorting =
        [YapDatabaseViewSorting withObjectBlock:^NSComparisonResult(YapDatabaseReadTransaction *transaction,
            NSString *group,
            NSString *collection1,
            NSString *key1,
            id object1,
            NSString *collection2,
            NSString *key2,
            id object2) {
            if (![object1 isKindOfClass:[OWSMessageContentJob class]]) {
                OWSFailDebug(@"Unexpected object: %@ in collection: %@", [object1 class], collection1);
                return NSOrderedSame;
            }
            OWSMessageContentJob *job1 = (OWSMessageContentJob *)object1;

            if (![object2 isKindOfClass:[OWSMessageContentJob class]]) {
                OWSFailDebug(@"Unexpected object: %@ in collection: %@", [object2 class], collection2);
                return NSOrderedSame;
            }
            OWSMessageContentJob *job2 = (OWSMessageContentJob *)object2;

            return [job1.createdAt compare:job2.createdAt];
        }];

    YapDatabaseViewGrouping *grouping =
        [YapDatabaseViewGrouping withObjectBlock:^NSString *_Nullable(YapDatabaseReadTransaction *_Nonnull transaction,
            NSString *_Nonnull collection,
            NSString *_Nonnull key,
            id _Nonnull object) {
            if (![object isKindOfClass:[OWSMessageContentJob class]]) {
                OWSFailDebug(@"Unexpected object: %@ in collection: %@", object, collection);
                return nil;
            }

            // Arbitrary string - all in the same group. We're only using the view for sorting.
            return YAPDBMessageContentJobFinderExtensionGroup;
        }];

    YapDatabaseViewOptions *options = [YapDatabaseViewOptions new];
    options.allowedCollections =
        [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:[OWSMessageContentJob collection]]];

    return [[YapDatabaseAutoView alloc] initWithGrouping:grouping sorting:sorting versionTag:@"1" options:options];
}

+ (void)asyncRegisterDatabaseExtension:(OWSStorage *)storage
{
    YapDatabaseView *existingView = [storage registeredExtension:YAPDBMessageContentJobFinderExtensionName];
    if (existingView) {
        OWSFailDebug(@"%@ was already initialized.", YAPDBMessageContentJobFinderExtensionName);
        // already initialized
        return;
    }
    [storage asyncRegisterExtension:[self databaseExtension] withName:YAPDBMessageContentJobFinderExtensionName];
}

@end

NS_ASSUME_NONNULL_END
