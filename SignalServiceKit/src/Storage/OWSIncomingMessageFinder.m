//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSIncomingMessageFinder.h"
#import "TSIncomingMessage.h"
#import "TSStorageManager.h"
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSIncomingMessageFinderExtensionName = @"OWSIncomingMessageFinderExtensionName";

NSString *const OWSIncomingMessageFinderColumnTimestamp = @"OWSIncomingMessageFinderColumnTimestamp";
NSString *const OWSIncomingMessageFinderColumnSourceId = @"OWSIncomingMessageFinderColumnSourceId";
NSString *const OWSIncomingMessageFinderColumnSourceDeviceId = @"OWSIncomingMessageFinderColumnSourceDeviceId";

@interface OWSIncomingMessageFinder ()

@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

@implementation OWSIncomingMessageFinder

@synthesize dbConnection = _dbConnection;

#pragma mark - init

- (instancetype)init
{
    OWSAssert([TSStorageManager sharedManager]);

    return [self initWithStorageManager:[TSStorageManager sharedManager]];
}

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _storageManager = storageManager;

    return self;
}

#pragma mark - properties

- (YapDatabaseConnection *)dbConnection
{
    @synchronized (self) {
        if (!_dbConnection) {
            _dbConnection = [self.storageManager newDatabaseConnection];
        }
    }
    return _dbConnection;
}

#pragma mark - YAP integration

+ (YapDatabaseSecondaryIndex *)indexExtension
{
    YapDatabaseSecondaryIndexSetup *setup = [YapDatabaseSecondaryIndexSetup new];

    [setup addColumn:OWSIncomingMessageFinderColumnTimestamp withType:YapDatabaseSecondaryIndexTypeInteger];
    [setup addColumn:OWSIncomingMessageFinderColumnSourceId withType:YapDatabaseSecondaryIndexTypeText];
    [setup addColumn:OWSIncomingMessageFinderColumnSourceDeviceId withType:YapDatabaseSecondaryIndexTypeInteger];

    YapDatabaseSecondaryIndexWithObjectBlock block = ^(YapDatabaseReadTransaction *transaction,
        NSMutableDictionary *dict,
        NSString *collection,
        NSString *key,
        id object) {
        if ([object isKindOfClass:[TSIncomingMessage class]]) {
            TSIncomingMessage *incomingMessage = (TSIncomingMessage *)object;

            // On new messages authorId should be set on all incoming messages, but there was a time when authorId was
            // only set on incoming group messages.
            NSObject *authorIdOrNull = incomingMessage.authorId ? incomingMessage.authorId : [NSNull null];
            [dict setObject:@(incomingMessage.timestamp) forKey:OWSIncomingMessageFinderColumnTimestamp];
            [dict setObject:authorIdOrNull forKey:OWSIncomingMessageFinderColumnSourceId];
            [dict setObject:@(incomingMessage.sourceDeviceId) forKey:OWSIncomingMessageFinderColumnSourceDeviceId];
        }
    };

    YapDatabaseSecondaryIndexHandler *handler = [YapDatabaseSecondaryIndexHandler withObjectBlock:block];

    return [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler];
}

+ (void)asyncRegisterExtensionWithStorageManager:(OWSStorage *)storage
{
    DDLogInfo(@"%@ registering async.", self.logTag);
    [storage asyncRegisterExtension:self.indexExtension withName:OWSIncomingMessageFinderExtensionName];
}

#ifdef DEBUG
// We should not normally hit this, as we should have prefer registering async, but it is useful for testing.
- (void)registerExtension
{
    DDLogError(@"%@ registering SYNC. We should prefer async when possible.", self.logTag);
    [self.storageManager registerExtension:self.class.indexExtension withName:OWSIncomingMessageFinderExtensionName];
}
#endif

#pragma mark - instance methods

- (BOOL)existsMessageWithTimestamp:(uint64_t)timestamp
                          sourceId:(NSString *)sourceId
                    sourceDeviceId:(uint32_t)sourceDeviceId
                       transaction:(YapDatabaseReadTransaction *)transaction
{
#ifdef DEBUG
    if (![self.storageManager registeredExtension:OWSIncomingMessageFinderExtensionName]) {
        OWSFail(@"%@ in %s but extension is not registered", self.logTag, __PRETTY_FUNCTION__);

        // we should be initializing this at startup rather than have an unexpectedly slow lazy setup at random.
        [self registerExtension];
    }
#endif

    NSString *queryFormat = [NSString stringWithFormat:@"WHERE %@ = ? AND %@ = ? AND %@ = ?",
                                      OWSIncomingMessageFinderColumnTimestamp,
                                      OWSIncomingMessageFinderColumnSourceId,
                                      OWSIncomingMessageFinderColumnSourceDeviceId];
    // YapDatabaseQuery params must be objects
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:queryFormat, @(timestamp), sourceId, @(sourceDeviceId)];

    NSUInteger count;
    BOOL success = [[transaction ext:OWSIncomingMessageFinderExtensionName] getNumberOfRows:&count matchingQuery:query];
    if (!success) {
        OWSFail(@"%@ Could not execute query", self.logTag);
        return NO;
    }

    return count > 0;
}

@end

NS_ASSUME_NONNULL_END
