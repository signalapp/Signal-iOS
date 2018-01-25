//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBatchMessageProcessor.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "NSArray+OWS.h"
#import "OWSBackgroundTask.h"
#import "OWSMessageManager.h"
#import "OWSQueues.h"
#import "OWSSignalServiceProtos.pb.h"
#import "OWSStorage.h"
#import "TSDatabaseView.h"
#import "TSStorageManager+SessionStore.h"
#import "TSStorageManager.h"
#import "TSYapDatabaseObject.h"
#import "Threading.h"
#import <YapDatabase/YapDatabaseAutoView.h>
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseTransaction.h>
#import <YapDatabase/YapDatabaseViewTypes.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Persisted data model

@class OWSSignalServiceProtosEnvelope;

@interface OWSMessageContentJob : TSYapDatabaseObject

@property (nonatomic, readonly) NSDate *createdAt;
@property (nonatomic, readonly) NSData *envelopeData;
@property (nonatomic, readonly, nullable) NSData *plaintextData;

- (instancetype)initWithEnvelopeData:(NSData *)envelopeData
                       plaintextData:(NSData *_Nullable)plaintextData NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithUniqueId:(NSString *_Nullable)uniqueId NS_UNAVAILABLE;
- (OWSSignalServiceProtosEnvelope *)envelopeProto;

@end

#pragma mark -

@implementation OWSMessageContentJob

+ (NSString *)collection
{
    return @"OWSBatchMessageProcessingJob";
}

- (instancetype)initWithEnvelopeData:(NSData *)envelopeData plaintextData:(NSData *_Nullable)plaintextData
{
    OWSAssert(envelopeData);

    self = [super initWithUniqueId:[NSUUID new].UUIDString];
    if (!self) {
        return self;
    }

    _envelopeData = envelopeData;
    _plaintextData = plaintextData;
    _createdAt = [NSDate new];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (OWSSignalServiceProtosEnvelope *)envelopeProto
{
    return [OWSSignalServiceProtosEnvelope parseFromData:self.envelopeData];
}

@end

#pragma mark - Finder

NSString *const OWSMessageContentJobFinderExtensionName = @"OWSMessageContentJobFinderExtensionName2";
NSString *const OWSMessageContentJobFinderExtensionGroup = @"OWSMessageContentJobFinderExtensionGroup2";

@interface OWSMessageContentJobFinder : NSObject

@end

#pragma mark -

@interface OWSMessageContentJobFinder ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

#pragma mark -

@implementation OWSMessageContentJobFinder

- (instancetype)initWithDBConnection:(YapDatabaseConnection *)dbConnection
{
    OWSSingletonAssert();

    self = [super init];
    if (!self) {
        return self;
    }

    _dbConnection = dbConnection;

    return self;
}

- (NSArray<OWSMessageContentJob *> *)nextJobsForBatchSize:(NSUInteger)maxBatchSize
{
    NSMutableArray<OWSMessageContentJob *> *jobs = [NSMutableArray new];
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        YapDatabaseViewTransaction *viewTransaction = [transaction ext:OWSMessageContentJobFinderExtensionName];
        OWSAssert(viewTransaction != nil);
        [viewTransaction enumerateKeysAndObjectsInGroup:OWSMessageContentJobFinderExtensionGroup
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
    }];

    return [jobs copy];
}

- (void)addJobWithEnvelopeData:(NSData *)envelopeData plaintextData:(NSData *_Nullable)plaintextData
{
    // We need to persist the decrypted envelope data ASAP to prevent data loss.
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        OWSMessageContentJob *job =
            [[OWSMessageContentJob alloc] initWithEnvelopeData:envelopeData plaintextData:plaintextData];
        [job saveWithTransaction:transaction];
    }];
}

- (void)removeJobsWithIds:(NSArray<NSString *> *)uniqueIds
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [transaction removeObjectsForKeys:uniqueIds inCollection:[OWSMessageContentJob collection]];
    }];
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
                OWSFail(@"Unexpected object: %@ in collection: %@", [object1 class], collection1);
                return NSOrderedSame;
            }
            OWSMessageContentJob *job1 = (OWSMessageContentJob *)object1;

            if (![object2 isKindOfClass:[OWSMessageContentJob class]]) {
                OWSFail(@"Unexpected object: %@ in collection: %@", [object2 class], collection2);
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
                OWSFail(@"Unexpected object: %@ in collection: %@", object, collection);
                return nil;
            }

            // Arbitrary string - all in the same group. We're only using the view for sorting.
            return OWSMessageContentJobFinderExtensionGroup;
        }];

    YapDatabaseViewOptions *options = [YapDatabaseViewOptions new];
    options.allowedCollections =
        [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:[OWSMessageContentJob collection]]];

    return [[YapDatabaseAutoView alloc] initWithGrouping:grouping sorting:sorting versionTag:@"1" options:options];
}


+ (void)asyncRegisterDatabaseExtension:(OWSStorage *)storage
{
    YapDatabaseView *existingView = [storage registeredExtension:OWSMessageContentJobFinderExtensionName];
    if (existingView) {
        OWSFail(@"%@ was already initialized.", OWSMessageContentJobFinderExtensionName);
        // already initialized
        return;
    }
    [storage asyncRegisterExtension:[self databaseExtension] withName:OWSMessageContentJobFinderExtensionName];
}

#pragma mark Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.logTag;
}

@end

#pragma mark - Queue Processing

@interface OWSMessageContentQueue : NSObject

@property (nonatomic, readonly) OWSMessageManager *messagesManager;
@property (nonatomic, readonly) YapDatabaseConnection *dbReadWriteConnection;
@property (nonatomic, readonly) OWSMessageContentJobFinder *finder;
@property (nonatomic) BOOL isDrainingQueue;

- (instancetype)initWithMessagesManager:(OWSMessageManager *)messagesManager
                         storageManager:(TSStorageManager *)storageManager
                                 finder:(OWSMessageContentJobFinder *)finder NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark -

@implementation OWSMessageContentQueue

- (instancetype)initWithMessagesManager:(OWSMessageManager *)messagesManager
                         storageManager:(TSStorageManager *)storageManager
                                 finder:(OWSMessageContentJobFinder *)finder
{
    OWSSingletonAssert();

    self = [super init];
    if (!self) {
        return self;
    }

    _messagesManager = messagesManager;
    _dbReadWriteConnection = [storageManager newDatabaseConnection];
    _finder = finder;
    _isDrainingQueue = NO;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appIsReady)
                                                 name:AppIsReadyNotification
                                               object:nil];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)appIsReady
{
    [self drainQueue];
}

#pragma mark - instance methods

- (dispatch_queue_t)serialQueue
{
    static dispatch_queue_t queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.whispersystems.message.process", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

- (void)enqueueEnvelopeData:(NSData *)envelopeData plaintextData:(NSData *_Nullable)plaintextData
{
    OWSAssert(envelopeData);

    // We need to persist the decrypted envelope data ASAP to prevent data loss.
    [self.finder addJobWithEnvelopeData:envelopeData plaintextData:plaintextData];
}

- (void)drainQueue
{
    // Don't process incoming messages in app extensions.
    if (!CurrentAppContext().isMainApp) {
        return;
    }

    dispatch_async(self.serialQueue, ^{
        if (!AppReadiness.isAppReady) {
            // We don't want to process incoming messages until storage is ready.
            return;
        }

        if (self.isDrainingQueue) {
            return;
        }
        self.isDrainingQueue = YES;

        [self drainQueueWorkStep];
    });
}

- (void)drainQueueWorkStep
{
    AssertOnDispatchQueue(self.serialQueue);

    // We want a value that is just high enough to yield perf benefits.
    const NSUInteger kIncomingMessageBatchSize = 32;

    NSArray<OWSMessageContentJob *> *jobs = [self.finder nextJobsForBatchSize:kIncomingMessageBatchSize];
    OWSAssert(jobs);
    if (jobs.count < 1) {
        self.isDrainingQueue = NO;
        DDLogVerbose(@"%@ Queue is drained", self.logTag);
        return;
    }

    OWSBackgroundTask *backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    [self processJobs:jobs];

    [self.finder removeJobsWithIds:jobs.uniqueIds];

    backgroundTask = nil;

    DDLogVerbose(@"%@ completed %zd jobs. %zd jobs left.",
        self.logTag,
        jobs.count,
        [OWSMessageContentJob numberOfKeysInCollection]);

    // Wait a bit in hopes of increasing the batch size.
    // This delay won't affect the first message to arrive when this queue is idle,
    // so by definition we're receiving more than one message and can benefit from
    // batching.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5f * NSEC_PER_SEC)), self.serialQueue, ^{
        [self drainQueueWorkStep];
    });
}

- (void)processJobs:(NSArray<OWSMessageContentJob *> *)jobs
{
    AssertOnDispatchQueue(self.serialQueue);

    // Note that we use the protocolStoreDBConnection to process incoming messages,
    // to ensure session & identity store consistency.
    [TSStorageManager.protocolStoreDBConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (OWSMessageContentJob *job in jobs) {
            [self.messagesManager processEnvelope:job.envelopeProto
                                    plaintextData:job.plaintextData
                                      transaction:transaction];
        }
    }];
}

#pragma mark Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.logTag;
}

@end

#pragma mark - OWSBatchMessageProcessor

@interface OWSBatchMessageProcessor ()

@property (nonatomic, readonly) OWSMessageContentQueue *processingQueue;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

#pragma mark -

@implementation OWSBatchMessageProcessor

- (instancetype)initWithDBConnection:(YapDatabaseConnection *)dbConnection
                     messagesManager:(OWSMessageManager *)messagesManager
                      storageManager:(TSStorageManager *)storageManager
{
    OWSSingletonAssert();

    self = [super init];
    if (!self) {
        return self;
    }

    OWSMessageContentJobFinder *finder = [[OWSMessageContentJobFinder alloc] initWithDBConnection:dbConnection];
    OWSMessageContentQueue *processingQueue = [[OWSMessageContentQueue alloc] initWithMessagesManager:messagesManager
                                                                                       storageManager:storageManager
                                                                                               finder:finder];

    _processingQueue = processingQueue;

    return self;
}

- (instancetype)initDefault
{
    // For concurrency coherency we use the same dbConnection to persist and read the unprocessed envelopes
    YapDatabaseConnection *dbConnection = [[TSStorageManager sharedManager] newDatabaseConnection];
    OWSMessageManager *messagesManager = [OWSMessageManager sharedManager];
    TSStorageManager *storageManager = [TSStorageManager sharedManager];

    return [self initWithDBConnection:dbConnection messagesManager:messagesManager storageManager:storageManager];
}

+ (instancetype)sharedInstance
{
    static OWSBatchMessageProcessor *sharedInstance;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] initDefault];
    });

    return sharedInstance;
}

#pragma mark - class methods

+ (void)asyncRegisterDatabaseExtension:(OWSStorage *)storage
{
    [OWSMessageContentJobFinder asyncRegisterDatabaseExtension:storage];
}

#pragma mark - instance methods

- (void)handleAnyUnprocessedEnvelopesAsync
{
    [self.processingQueue drainQueue];
}

- (void)enqueueEnvelopeData:(NSData *)envelopeData plaintextData:(NSData *_Nullable)plaintextData
{
    OWSAssert(envelopeData);

    // We need to persist the decrypted envelope data ASAP to prevent data loss.
    [self.processingQueue enqueueEnvelopeData:envelopeData plaintextData:plaintextData];
    [self.processingQueue drainQueue];
}

@end

NS_ASSUME_NONNULL_END
