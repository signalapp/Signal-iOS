//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageReceiver.h"
#import "OWSBatchMessageProcessor.h"
#import "OWSMessageDecrypter.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSDatabaseView.h"
#import "TSStorageManager.h"
#import "TSYapDatabaseObject.h"
#import "Threading.h"
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

#pragma mark -

@interface OWSMessageProcessingJob ()

@property (nonatomic, readonly) NSData *envelopeData;

@end

#pragma mark -

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

- (NSArray<OWSMessageProcessingJob *> *)nextJobsForBatchSize:(NSUInteger)maxBatchSize;
- (void)addJobForEnvelope:(OWSSignalServiceProtosEnvelope *)envelope;
- (void)removeJobWithId:(NSString *)uniqueId;

@end

#pragma mark -

@interface OWSMessageProcessingJobFinder ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

#pragma mark -

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

- (NSArray<OWSMessageProcessingJob *> *)nextJobsForBatchSize:(NSUInteger)maxBatchSize
{
    NSMutableArray<OWSMessageProcessingJob *> *jobs = [NSMutableArray new];
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        YapDatabaseViewTransaction *viewTransaction = [transaction ext:OWSMessageProcessingJobFinderExtensionName];
        OWSAssert(viewTransaction != nil);
        NSMutableArray<NSString *> *jobIds = [NSMutableArray new];
        [viewTransaction enumerateKeysInGroup:OWSMessageProcessingJobFinderExtensionGroup
                                   usingBlock:^(NSString *_Nonnull collection,
                                       NSString *_Nonnull key,
                                       NSUInteger index,
                                       BOOL *_Nonnull stop) {
                                       [jobIds addObject:key];
                                       if (jobIds.count >= maxBatchSize) {
                                           *stop = YES;
                                       }
                                   }];

        for (NSString *jobId in jobIds) {
            OWSMessageProcessingJob *_Nullable job =
                [OWSMessageProcessingJob fetchObjectWithUniqueID:jobId transaction:transaction];
            if (job) {
                [jobs addObject:job];
            } else {
                OWSFail(@"Could not load job: %@", jobId);
            }
        }
    }];

    return jobs;
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
    [database registerExtension:[self databaseExtension] withName:OWSMessageProcessingJobFinderExtensionName];
}

@end

#pragma mark - Queue Processing

@interface OWSMessageProcessingQueue : NSObject

@property (nonatomic, readonly) OWSMessageDecrypter *messageDecrypter;
@property (nonatomic, readonly) OWSBatchMessageProcessor *batchMessageProcessor;
@property (nonatomic, readonly) OWSMessageProcessingJobFinder *finder;
@property (nonatomic) BOOL isDrainingQueue;

- (instancetype)initWithmessageDecrypter:(OWSMessageDecrypter *)messageDecrypter
                   batchMessageProcessor:(OWSBatchMessageProcessor *)batchMessageProcessor
                                  finder:(OWSMessageProcessingJobFinder *)finder NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark -

@implementation OWSMessageProcessingQueue

- (instancetype)initWithmessageDecrypter:(OWSMessageDecrypter *)messageDecrypter
                   batchMessageProcessor:(OWSBatchMessageProcessor *)batchMessageProcessor
                                  finder:(OWSMessageProcessingJobFinder *)finder
{
    OWSSingletonAssert();

    self = [super init];
    if (!self) {
        return self;
    }

    _messageDecrypter = messageDecrypter;
    _batchMessageProcessor = batchMessageProcessor;
    _finder = finder;
    _isDrainingQueue = NO;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(databaseViewRegistrationComplete)
                                                 name:kNSNotificationName_DatabaseViewRegistrationComplete
                                               object:nil];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)databaseViewRegistrationComplete
{
    [self drainQueue];
}

#pragma mark - instance methods

- (void)enqueueEnvelopeForProcessing:(OWSSignalServiceProtosEnvelope *)envelope
{
    [self.finder addJobForEnvelope:envelope];
}

- (void)drainQueue
{
    DispatchMainThreadSafe(^{
        if ([TSDatabaseView hasPendingViewRegistrations]) {
            // We don't want to process incoming messages until database
            // view registration is complete.
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
    AssertIsOnMainThread();

    NSArray<OWSMessageProcessingJob *> *jobs = [self.finder nextJobsForBatchSize:kIncomingMessageBatchSize];
    OWSAssert(jobs);
    if (jobs.count < 1) {
        self.isDrainingQueue = NO;
        DDLogVerbose(@"%@ Queue is drained.", self.tag);
        return;
    }

    [self processJobs:jobs
           completion:^{
               dispatch_async(dispatch_get_main_queue(), ^{
                   for (OWSMessageProcessingJob *job in jobs) {
                       [self.finder removeJobWithId:job.uniqueId];
                   }
                   DDLogVerbose(@"%@ completed %zd jobs. %zd jobs left.",
                       self.tag,
                       jobs.count,
                       [OWSMessageProcessingJob numberOfKeysInCollection]);
                   [self drainQueueWorkStep];
               });
           }];
}

- (void)processJobs:(NSArray<OWSMessageProcessingJob *> *)jobs completion:(void (^)())completion
{
    [self processJobs:jobs
         unprocessedJobs:[jobs mutableCopy]
        plaintextDataMap:[NSMutableDictionary new]
              completion:completion];
}

- (void)processJobs:(NSArray<OWSMessageProcessingJob *> *)jobs
     unprocessedJobs:(NSMutableArray<OWSMessageProcessingJob *> *)unprocessedJobs
    plaintextDataMap:(NSMutableDictionary<NSString *, NSData *> *)plaintextDataMap
          completion:(void (^)())completion
{
    OWSAssert(jobs.count > 0);
    OWSAssert(unprocessedJobs.count <= jobs.count);

    if (unprocessedJobs.count < 1) {
        for (OWSMessageProcessingJob *job in jobs) {
            NSData *_Nullable plaintextData = plaintextDataMap[job.uniqueId];
            [self.batchMessageProcessor enqueueEnvelopeData:job.envelopeData plaintextData:plaintextData];
        }
        completion();
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OWSAssert(unprocessedJobs.count > 0);
        OWSMessageProcessingJob *job = unprocessedJobs.firstObject;
        [unprocessedJobs removeObjectAtIndex:0];
        [self.messageDecrypter decryptEnvelope:job.envelopeProto
            successBlock:^(NSData *_Nullable plaintextData) {
                if (plaintextData) {
                    plaintextDataMap[job.uniqueId] = plaintextData;
                }
                [self processJobs:jobs
                     unprocessedJobs:unprocessedJobs
                    plaintextDataMap:plaintextDataMap
                          completion:completion];
            }
            failureBlock:^{
                [self processJobs:jobs
                     unprocessedJobs:unprocessedJobs
                    plaintextDataMap:plaintextDataMap
                          completion:completion];
            }];
    });
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

#pragma mark -

@implementation OWSMessageReceiver

- (instancetype)initWithDBConnection:(YapDatabaseConnection *)dbConnection
                    messageDecrypter:(OWSMessageDecrypter *)messageDecrypter
               batchMessageProcessor:(OWSBatchMessageProcessor *)batchMessageProcessor
{
    OWSSingletonAssert();

    self = [super init];
    if (!self) {
        return self;
    }

    OWSMessageProcessingJobFinder *finder = [[OWSMessageProcessingJobFinder alloc] initWithDBConnection:dbConnection];
    OWSMessageProcessingQueue *processingQueue =
        [[OWSMessageProcessingQueue alloc] initWithmessageDecrypter:messageDecrypter
                                              batchMessageProcessor:batchMessageProcessor
                                                             finder:finder];

    _processingQueue = processingQueue;

    return self;
}

- (instancetype)initDefault
{
    // For concurrency coherency we use the same dbConnection to persist and read the unprocessed envelopes
    YapDatabaseConnection *dbConnection = [[TSStorageManager sharedManager].database newConnection];
    OWSMessageDecrypter *messageDecrypter = [OWSMessageDecrypter sharedManager];
    OWSBatchMessageProcessor *batchMessageProcessor = [OWSBatchMessageProcessor sharedInstance];

    return [self initWithDBConnection:dbConnection
                     messageDecrypter:messageDecrypter
                batchMessageProcessor:batchMessageProcessor];
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
    [self.processingQueue drainQueue];
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
