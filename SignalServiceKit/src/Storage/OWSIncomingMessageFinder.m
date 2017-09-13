//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
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

@property (nonatomic, readonly) YapDatabase *database;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

@implementation OWSIncomingMessageFinder

@synthesize dbConnection = _dbConnection;

#pragma mark - init

- (instancetype)init
{
    OWSAssert([TSStorageManager sharedManager].database != nil);

    return [self initWithDatabase:[TSStorageManager sharedManager].database];
}

- (instancetype)initWithDatabase:(YapDatabase *)database
{
    self = [super init];
    if (!self) {
        return self;
    }

    _database = database;

    return self;
}

#pragma mark - properties

- (YapDatabaseConnection *)dbConnection
{
    @synchronized (self) {
        if (!_dbConnection) {
            _dbConnection = self.database.newConnection;
        }
    }
    return _dbConnection;
}

#pragma mark - YAP integration

- (YapDatabaseSecondaryIndex *)indexExtension
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

- (void)asyncRegisterExtension
{
    DDLogInfo(@"%@ registering async.", self.tag);
    [self.database asyncRegisterExtension:self.indexExtension
                                 withName:OWSIncomingMessageFinderExtensionName
                          completionBlock:^(BOOL ready) {
                              DDLogInfo(@"%@ finished registering async.", self.tag);
                          }];
}

// We should not normally hit this, as we should have prefer registering async, but it is useful for testing.
- (void)registerExtension
{
    DDLogError(@"%@ registering SYNC. We should prefer async when possible.", self.tag);
    [self.database registerExtension:self.indexExtension withName:OWSIncomingMessageFinderExtensionName];
}

#pragma mark - instance methods

- (BOOL)existsMessageWithTimestamp:(uint64_t)timestamp
                          sourceId:(NSString *)sourceId
                    sourceDeviceId:(uint32_t)sourceDeviceId
                       transaction:(YapDatabaseReadTransaction *)transaction
{
    if (![self.database registeredExtension:OWSIncomingMessageFinderExtensionName]) {
        OWSFail(@"%@ in %s but extension is not registered", self.tag, __PRETTY_FUNCTION__);

        // we should be initializing this at startup rather than have an unexpectedly slow lazy setup at random.
        [self registerExtension];
    }

    NSString *queryFormat = [NSString stringWithFormat:@"WHERE %@ = ? AND %@ = ? AND %@ = ?",
                                      OWSIncomingMessageFinderColumnTimestamp,
                                      OWSIncomingMessageFinderColumnSourceId,
                                      OWSIncomingMessageFinderColumnSourceDeviceId];
    // YapDatabaseQuery params must be objects
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:queryFormat, @(timestamp), sourceId, @(sourceDeviceId)];

    NSUInteger count;
    BOOL success = [[transaction ext:OWSIncomingMessageFinderExtensionName] getNumberOfRows:&count matchingQuery:query];
    if (!success) {
        OWSFail(@"%@ Could not execute query", self.tag);
        return NO;
    }

    return count > 0;
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
