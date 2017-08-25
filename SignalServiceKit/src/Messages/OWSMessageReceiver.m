//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageReceiver.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSDatabaseView.h"
#import "TSMessagesManager.h"
#import "TSStorageManager.h"
#import "TSYapDatabaseObject.h"
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseTransaction.h>
#import <YapDatabase/YapDatabaseView.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Persisted data model
@class OWSSignalServiceProtosEnvelope;

@interface OWSMessageProcessingJob : TSYapDatabaseObject

@property (nonatomic, readonly) NSDate *createdAt;

- (instancetype)initWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithUniqueId:(NSString *)uniqueId NS_UNAVAILABLE;
- (OWSSignalServiceProtosEnvelope *)envelopeProto;

@end

@interface OWSMessageProcessingJob ()

@property (nonatomic, readonly) NSData *envelopeData;

@end

@implementation OWSMessageProcessingJob

- (instancetype)initWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
{
    OWSAssert(envelope);

    self = [super initWithUniqueId:[NSUUID new].UUIDString];
    if (!self) {
        return self;
    }

    _envelopeData = envelope.data;
    _createdAt = [NSDate new];

    return self;
}

- (OWSSignalServiceProtosEnvelope *)envelopeProto
{
    return [OWSSignalServiceProtosEnvelope parseFromData:self.envelopeData];
}

@end

#pragma mark - Finder

NSString *const OWSMessageProcessingJobFinderExtensionName = @"OWSMessageProcessingJobFinderExtensionName";
NSString *const OWSMessageProcessingJobFinderExtensionGroup = @"OWSMessageProcessingJobFinderExtensionGroup";

@interface OWSMessageProcessingJobFinder : NSObject

- (nullable OWSMessageProcessingJob *)nextJob;
- (void)addJobForEnvelope:(OWSSignalServiceProtosEnvelope *)envelope;
- (void)removeJobWithId:(NSString *)uniqueId;

@end

@interface OWSMessageProcessingJobFinder ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

@implementation OWSMessageProcessingJobFinder

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

- (nullable OWSMessageProcessingJob *)nextJob
{
    __block OWSMessageProcessingJob *_Nullable job;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        YapDatabaseViewTransaction *viewTransaction = [transaction ext:OWSMessageProcessingJobFinderExtensionName];
        OWSAssert(viewTransaction != nil);
        job = [viewTransaction firstObjectInGroup:OWSMessageProcessingJobFinderExtensionGroup];
    }];

    return job;
}

- (void)addJobForEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [[[OWSMessageProcessingJob alloc] initWithEnvelope:envelope] saveWithTransaction:transaction];
    }];
}

- (void)removeJobWithId:(NSString *)uniqueId
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [transaction removeObjectForKey:uniqueId inCollection:[OWSMessageProcessingJob collection]];
    }];
}

+ (YapDatabaseView *)databaseExension
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

            if (![object1 isKindOfClass:[OWSMessageProcessingJob class]]) {
                OWSFail(@"Unexpected object: %@ in collection: %@", [object1 class], collection1);
                return NSOrderedSame;
            }
            OWSMessageProcessingJob *job1 = (OWSMessageProcessingJob *)object1;

            if (![object2 isKindOfClass:[OWSMessageProcessingJob class]]) {
                OWSFail(@"Unexpected object: %@ in collection: %@", [object2 class], collection2);
                return NSOrderedSame;
            }
            OWSMessageProcessingJob *job2 = (OWSMessageProcessingJob *)object2;

            return [job1.createdAt compare:job2.createdAt];
        }];

    YapDatabaseViewGrouping *grouping =
        [YapDatabaseViewGrouping withObjectBlock:^NSString *_Nullable(YapDatabaseReadTransaction *_Nonnull transaction,
            NSString *_Nonnull collection,
            NSString *_Nonnull key,
            id _Nonnull object) {
            if (![object isKindOfClass:[OWSMessageProcessingJob class]]) {
                OWSFail(@"Unexpected object: %@ in collection: %@", object, collection);
                return nil;
            }

            // Arbitrary string - all in the same group. We're only using the view for sorting.
            return OWSMessageProcessingJobFinderExtensionGroup;
        }];

    YapDatabaseViewOptions *options = [YapDatabaseViewOptions new];
    options.allowedCollections =
        [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:[OWSMessageProcessingJob collection]]];

    return [[YapDatabaseView alloc] initWithGrouping:grouping sorting:sorting versionTag:@"1" options:options];
}


+ (void)syncRegisterDatabaseExtension:(YapDatabase *)database
{
    YapDatabaseView *existingView = [database registeredExtension:OWSMessageProcessingJobFinderExtensionName];
    if (existingView) {
        OWSFail(@"%@ was already initialized.", OWSMessageProcessingJobFinderExtensionName);
        // already initialized
        return;
    }
    [database registerExtension:[self databaseExension] withName:OWSMessageProcessingJobFinderExtensionName];
}

@end

#pragma mark - Queue Processing

@interface OWSMessageProcessingQueue : NSObject

@property (nonatomic, readonly) TSMessagesManager *messagesManager;
@property (nonatomic, readonly) OWSMessageProcessingJobFinder *finder;
@property (nonatomic) BOOL isDrainingQueue;

- (instancetype)initWithMessagesManager:(TSMessagesManager *)messagesManager
                                 finder:(OWSMessageProcessingJobFinder *)finder NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@implementation OWSMessageProcessingQueue

- (instancetype)initWithMessagesManager:(TSMessagesManager *)messagesManager
                                 finder:(OWSMessageProcessingJobFinder *)finder
{
    OWSSingletonAssert();

    self = [super init];
    if (!self) {
        return self;
    }

    _messagesManager = messagesManager;
    _finder = finder;
    _isDrainingQueue = NO;

    return self;
}

#pragma mark - instance methods

- (void)enqueueEnvelopeForProcessing:(OWSSignalServiceProtosEnvelope *)envelope
{
    [self.finder addJobForEnvelope:envelope];
}

- (void)drainQueue
{
    AssertIsOnMainThread();

    if (self.isDrainingQueue) {
        return;
    }
    self.isDrainingQueue = YES;

    [self drainQueueWorkStep];
}

- (void)drainQueueWorkStep
{
    AssertIsOnMainThread();

    OWSMessageProcessingJob *_Nullable job = [self.finder nextJob];
    if (job == nil) {
        self.isDrainingQueue = NO;
        DDLogVerbose(@"%@ Queue is drained", self.tag);
        return;
    }

    [self processJob:job
          completion:^{
              DDLogVerbose(@"%@ completed job. %lu jobs left.",
                  self.tag,
                  (unsigned long)[OWSMessageProcessingJob numberOfKeysInCollection]);
              [self drainQueueWorkStep];
          }];
}

- (void)processJob:(OWSMessageProcessingJob *)job completion:(void (^)())completion
{
    [self.messagesManager processEnvelope:job.envelopeProto
                               completion:^{
                                   [self.finder removeJobWithId:job.uniqueId];
                                   completion();
                               }];
}

#pragma mark Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

#pragma mark - OWSMessageReceiver

@interface OWSMessageReceiver ()

@property (nonatomic, readonly) OWSMessageProcessingQueue *processingQueue;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

@implementation OWSMessageReceiver

- (instancetype)initWithDBConnection:(YapDatabaseConnection *)dbConnection
                     messagesManager:(TSMessagesManager *)messagesManager
{
    OWSSingletonAssert();

    self = [super init];
    if (!self) {
        return self;
    }

    OWSMessageProcessingJobFinder *finder = [[OWSMessageProcessingJobFinder alloc] initWithDBConnection:dbConnection];
    OWSMessageProcessingQueue *processingQueue =
        [[OWSMessageProcessingQueue alloc] initWithMessagesManager:messagesManager finder:finder];

    _processingQueue = processingQueue;

    return self;
}

- (instancetype)initDefault
{
    // For concurrency coherency we use the same dbConnection to persist and read the unprocessed envelopes
    YapDatabaseConnection *dbConnection = [[TSStorageManager sharedManager].database newConnection];
    TSMessagesManager *messagesManager = [TSMessagesManager sharedManager];

    return [self initWithDBConnection:dbConnection messagesManager:messagesManager];
}

+ (instancetype)sharedInstance
{
    static OWSMessageReceiver *sharedInstance;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] initDefault];
    });

    return sharedInstance;
}

#pragma mark - class methods

+ (void)syncRegisterDatabaseExtension:(YapDatabase *)database
{
    [OWSMessageProcessingJobFinder syncRegisterDatabaseExtension:database];
}

#pragma mark - instance methods

- (void)handleAnyUnprocessedEnvelopesAsync
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.processingQueue drainQueue];
    });
}

- (void)handleReceivedEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
{
    // Drop any too-large messages on the floor. Well behaving clients should never send them.
    NSUInteger kMaxEnvelopeByteCount = 250 * 1024;
    if (envelope.serializedSize > kMaxEnvelopeByteCount) {
        OWSProdError([OWSAnalyticsEvents messageReceiverErrorOversizeMessage]);
        return;
    }

    // Take note of any messages larger than we expect, but still process them.
    // This likely indicates a misbehaving sending client.
    NSUInteger kLargeEnvelopeWarningByteCount = 25 * 1024;
    if (envelope.serializedSize > kLargeEnvelopeWarningByteCount) {
        OWSProdError([OWSAnalyticsEvents messageReceiverErrorLargeMessage]);
    }

    [self.processingQueue enqueueEnvelopeForProcessing:envelope];
    [self.processingQueue drainQueue];
}

@end

NS_ASSUME_NONNULL_END
