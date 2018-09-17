//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBatchMessageProcessor.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "NSArray+OWS.h"
#import "NotificationsProtocol.h"
#import "OWSBackgroundTask.h"
#import "OWSMessageManager.h"
#import "OWSPrimaryStorage+SessionStore.h"
#import "OWSPrimaryStorage.h"
#import "OWSQueues.h"
#import "OWSStorage.h"
#import "SSKEnvironment.h"
#import "TSDatabaseView.h"
#import "TSErrorMessage.h"
#import "TSYapDatabaseObject.h"
#import "Threading.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabaseAutoView.h>
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseTransaction.h>
#import <YapDatabase/YapDatabaseViewTypes.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Persisted data model

@interface OWSMessageContentJob : TSYapDatabaseObject

@property (nonatomic, readonly) NSDate *createdAt;
@property (nonatomic, readonly) NSData *envelopeData;
@property (nonatomic, readonly, nullable) NSData *plaintextData;

- (instancetype)initWithEnvelopeData:(NSData *)envelopeData
                       plaintextData:(NSData *_Nullable)plaintextData NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithUniqueId:(NSString *_Nullable)uniqueId NS_UNAVAILABLE;

@property (nonatomic, readonly, nullable) SSKProtoEnvelope *envelope;

@end

#pragma mark -

@implementation OWSMessageContentJob

+ (NSString *)collection
{
    return @"OWSBatchMessageProcessingJob";
}

- (instancetype)initWithEnvelopeData:(NSData *)envelopeData plaintextData:(NSData *_Nullable)plaintextData
{
    OWSAssertDebug(envelopeData);

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

- (nullable SSKProtoEnvelope *)envelope
{
    NSError *error;
    SSKProtoEnvelope *_Nullable result = [SSKProtoEnvelope parseData:self.envelopeData error:&error];

    if (error) {
        OWSFailDebug(@"paring SSKProtoEnvelope failed with error: %@", error);
        return nil;
    }
    
    return result;
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
        OWSAssertDebug(viewTransaction != nil);
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

- (void)addJobWithEnvelopeData:(NSData *)envelopeData
                 plaintextData:(NSData *_Nullable)plaintextData
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(envelopeData);
    OWSAssertDebug(transaction);

    OWSMessageContentJob *job =
        [[OWSMessageContentJob alloc] initWithEnvelopeData:envelopeData plaintextData:plaintextData];
    [job saveWithTransaction:transaction];
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
        OWSFailDebug(@"%@ was already initialized.", OWSMessageContentJobFinderExtensionName);
        // already initialized
        return;
    }
    [storage asyncRegisterExtension:[self databaseExtension] withName:OWSMessageContentJobFinderExtensionName];
}

@end

#pragma mark - Queue Processing

@interface OWSMessageContentQueue : NSObject

@property (nonatomic, readonly) OWSMessageManager *messagesManager;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) OWSMessageContentJobFinder *finder;
@property (nonatomic) BOOL isDrainingQueue;
@property (atomic) BOOL isAppInBackground;

- (instancetype)initWithMessagesManager:(OWSMessageManager *)messagesManager
                         primaryStorage:(OWSPrimaryStorage *)primaryStorage
                                 finder:(OWSMessageContentJobFinder *)finder NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark -

@implementation OWSMessageContentQueue

- (instancetype)initWithMessagesManager:(OWSMessageManager *)messagesManager
                         primaryStorage:(OWSPrimaryStorage *)primaryStorage
                                 finder:(OWSMessageContentJobFinder *)finder
{
    OWSSingletonAssert();

    self = [super init];
    if (!self) {
        return self;
    }

    _messagesManager = messagesManager;
    _dbConnection = [primaryStorage newDatabaseConnection];
    _finder = finder;
    _isDrainingQueue = NO;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground:)
                                                 name:OWSApplicationWillEnterForegroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:OWSApplicationDidEnterBackgroundNotification
                                               object:nil];

    // Start processing.
    [AppReadiness runNowOrWhenAppIsReady:^{
        [self drainQueue];
    }];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    self.isAppInBackground = NO;
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    self.isAppInBackground = YES;
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

- (void)enqueueEnvelopeData:(NSData *)envelopeData
              plaintextData:(NSData *_Nullable)plaintextData
                transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(envelopeData);
    OWSAssertDebug(transaction);

    // We need to persist the decrypted envelope data ASAP to prevent data loss.
    [self.finder addJobWithEnvelopeData:envelopeData plaintextData:plaintextData transaction:transaction];
}

- (void)drainQueue
{
    OWSAssertDebug(AppReadiness.isAppReady);

    // Don't process incoming messages in app extensions.
    if (!CurrentAppContext().isMainApp) {
        return;
    }

    dispatch_async(self.serialQueue, ^{
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

    NSArray<OWSMessageContentJob *> *batchJobs = [self.finder nextJobsForBatchSize:kIncomingMessageBatchSize];
    OWSAssertDebug(batchJobs);
    if (batchJobs.count < 1) {
        self.isDrainingQueue = NO;
        OWSLogVerbose(@"Queue is drained");
        return;
    }

    OWSBackgroundTask *_Nullable backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    NSArray<OWSMessageContentJob *> *processedJobs = [self processJobs:batchJobs];

    [self.finder removeJobsWithIds:processedJobs.uniqueIds];

    OWSAssertDebug(backgroundTask);
    backgroundTask = nil;

    OWSLogVerbose(@"completed %lu/%lu jobs. %lu jobs left.",
        (unsigned long)processedJobs.count,
        (unsigned long)batchJobs.count,
        (unsigned long)[OWSMessageContentJob numberOfKeysInCollection]);

    // Wait a bit in hopes of increasing the batch size.
    // This delay won't affect the first message to arrive when this queue is idle,
    // so by definition we're receiving more than one message and can benefit from
    // batching.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5f * NSEC_PER_SEC)), self.serialQueue, ^{
        [self drainQueueWorkStep];
    });
}

- (NSArray<OWSMessageContentJob *> *)processJobs:(NSArray<OWSMessageContentJob *> *)jobs
{
    AssertOnDispatchQueue(self.serialQueue);

    NSMutableArray<OWSMessageContentJob *> *processedJobs = [NSMutableArray new];
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (OWSMessageContentJob *job in jobs) {

            void (^reportFailure)(YapDatabaseReadWriteTransaction *transaction) = ^(
                YapDatabaseReadWriteTransaction *transaction) {
                // TODO: Add analytics.
                TSErrorMessage *errorMessage = [TSErrorMessage corruptedMessageInUnknownThread];
                [SSKEnvironment.shared.notificationsManager notifyUserForThreadlessErrorMessage:errorMessage
                                                                                    transaction:transaction];
            };

            @try {
                SSKProtoEnvelope *_Nullable envelope = job.envelope;
                if (!envelope) {
                    reportFailure(transaction);
                } else {
                    [self.messagesManager processEnvelope:envelope
                                            plaintextData:job.plaintextData
                                              transaction:transaction];
                }
            } @catch (NSException *exception) {
                OWSFailDebug(@"Received an invalid envelope: %@", exception.debugDescription);
                reportFailure(transaction);
            }
            [processedJobs addObject:job];

            if (self.isAppInBackground) {
                // If the app is in the background, stop processing this batch.
                //
                // Since this check is done after processing jobs, we'll continue
                // to process jobs in batches of 1.  This reduces the cost of
                // being interrupted and rolled back if app is suspended.
                break;
            }
        }
    }];
    return processedJobs;
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
                      primaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    OWSSingletonAssert();

    self = [super init];
    if (!self) {
        return self;
    }

    OWSMessageContentJobFinder *finder = [[OWSMessageContentJobFinder alloc] initWithDBConnection:dbConnection];
    OWSMessageContentQueue *processingQueue = [[OWSMessageContentQueue alloc] initWithMessagesManager:messagesManager
                                                                                       primaryStorage:primaryStorage
                                                                                               finder:finder];

    _processingQueue = processingQueue;

    return self;
}

- (instancetype)initDefault
{
    // For concurrency coherency we use the same dbConnection to persist and read the unprocessed envelopes
    YapDatabaseConnection *dbConnection = [[OWSPrimaryStorage sharedManager] newDatabaseConnection];
    OWSMessageManager *messagesManager = [OWSMessageManager sharedManager];
    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];

    return [self initWithDBConnection:dbConnection messagesManager:messagesManager primaryStorage:primaryStorage];
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

+ (NSString *)databaseExtensionName
{
    return OWSMessageContentJobFinderExtensionName;
}

+ (void)asyncRegisterDatabaseExtension:(OWSStorage *)storage
{
    [OWSMessageContentJobFinder asyncRegisterDatabaseExtension:storage];
}

#pragma mark - instance methods

- (void)handleAnyUnprocessedEnvelopesAsync
{
    [self.processingQueue drainQueue];
}

- (void)enqueueEnvelopeData:(NSData *)envelopeData
              plaintextData:(NSData *_Nullable)plaintextData
                transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (envelopeData.length < 1) {
        OWSFailDebug(@"Empty envelope.");
        return;
    }
    OWSAssert(transaction);

    // We need to persist the decrypted envelope data ASAP to prevent data loss.
    [self.processingQueue enqueueEnvelopeData:envelopeData plaintextData:plaintextData transaction:transaction];

    // The new envelope won't be visible to the finder until this transaction commits,
    // so drainQueue in the transaction completion.
    [transaction addCompletionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
                    completionBlock:^{
                        [self.processingQueue drainQueue];
                    }];
}

@end

NS_ASSUME_NONNULL_END
