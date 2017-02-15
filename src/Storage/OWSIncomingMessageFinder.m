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
@property (nonatomic, readonly) BOOL isExtensionRegistered;

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

            [dict setObject:@(incomingMessage.timestamp) forKey:OWSIncomingMessageFinderColumnTimestamp];
            [dict setObject:incomingMessage.authorId forKey:OWSIncomingMessageFinderColumnSourceId];
            [dict setObject:@(incomingMessage.sourceDeviceId) forKey:OWSIncomingMessageFinderColumnSourceDeviceId];
        }
    };

    YapDatabaseSecondaryIndexHandler *handler = [YapDatabaseSecondaryIndexHandler withObjectBlock:block];

    return [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler];
}

- (void)asyncRegisterExtension
{
    DDLogInfo(@"%@ registering async.", self.tag);
    [self.database registerExtension:self.indexExtension withName:OWSIncomingMessageFinderExtensionName];
}

- (void)registerExtension
{
    OWSAssert(NO);
    DDLogError(@"%@ registering SYNC. We should prefer async when possible.", self.tag);
    [self.database registerExtension:self.indexExtension withName:OWSIncomingMessageFinderExtensionName];
}

#pragma mark - instance methods

- (BOOL)existsMessageWithTimestamp:(uint64_t)timestamp
                          sourceId:(NSString *)sourceId
                    sourceDeviceId:(uint32_t)sourceDeviceId
{
    if (![self.database registeredExtension:OWSIncomingMessageFinderExtensionName]) {
        DDLogError(@"%@ in %s but extension is not registered", self.tag, __PRETTY_FUNCTION__);
        OWSAssert(NO);

        // we should be initializing this at startup rather than have an unexpectedly slow lazy setup at random.
        [self registerExtension];
    }

    NSString *queryFormat = [NSString stringWithFormat:@"WHERE %@ = ? AND %@ = ? AND %@ = ?",
                                      OWSIncomingMessageFinderColumnTimestamp,
                                      OWSIncomingMessageFinderColumnSourceId,
                                      OWSIncomingMessageFinderColumnSourceDeviceId];
    // YapDatabaseQuery params must be objects
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:queryFormat, @(timestamp), sourceId, @(sourceDeviceId)];

    __block NSUInteger count;
    __block BOOL success;

    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        success = [[transaction ext:OWSIncomingMessageFinderExtensionName] getNumberOfRows:&count matchingQuery:query];
    }];

    if (!success) {
        OWSAssert(NO);
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
