//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageReceiver.h"
#import "NSArray+OWS.h"
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

@interface OWSMessageDecryptJob : TSYapDatabaseObject

@property (nonatomic, readonly) NSDate *createdAt;

- (instancetype)initWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithUniqueId:(NSString *)uniqueId NS_UNAVAILABLE;
- (OWSSignalServiceProtosEnvelope *)envelopeProto;

@end

#pragma mark -

@interface OWSMessageDecryptJob ()

@property (nonatomic, readonly) NSData *envelopeData;

@end

#pragma mark -

@implementation OWSMessageDecryptJob

+ (NSString *)collection
{
    return @"OWSMessageProcessingJob";
}

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

NSString *const OWSMessageDecryptJobFinderExtensionName = @"OWSMessageProcessingJobFinderExtensionName";
NSString *const OWSMessageDecryptJobFinderExtensionGroup = @"OWSMessageProcessingJobFinderExtensionGroup";

@interface OWSMessageDecryptJobFinder : NSObject

@end

#pragma mark -

@interface OWSMessageDecryptJobFinder ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

#pragma mark -

@implementation OWSMessageDecryptJobFinder

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

- (NSArray<OWSMessageDecryptJob *> *)nextJobsForBatchSize:(NSUInteger)maxBatchSize
{
    NSMutableArray<OWSMessageDecryptJob *> *jobs = [NSMutableArray new];
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        YapDatabaseViewTransaction *viewTransaction = [transaction ext:OWSMessageDecryptJobFinderExtensionName];
        OWSAssert(viewTransaction != nil);
        [viewTransaction enumerateKeysAndObjectsInGroup:OWSMessageDecryptJobFinderExtensionGroup
                                             usingBlock:^(NSString *_Nonnull collection,
                                                 NSString *_Nonnull key,
                                                 id _Nonnull object,
                                                 NSUInteger index,
                                                 BOOL *_Nonnull stop) {
                                                 OWSMessageDecryptJob *job = object;
                                                 [jobs addObject:job];
                                                 if (jobs.count >= maxBatchSize) {
                                                     *stop = YES;
                                                 }
                                             }];
    }];

    return [jobs copy];
}

- (void)addJobForEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [[[OWSMessageDecryptJob alloc] initWithEnvelope:envelope] saveWithTransaction:transaction];
    }];
}

- (void)removeJobsWithIds:(NSArray<NSString *> *)uniqueIds
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [transaction removeObjectsForKeys:uniqueIds inCollection:[OWSMessageDecryptJob collection]];
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

            if (![object1 isKindOfClass:[OWSMessageDecryptJob class]]) {
                OWSFail(@"Unexpected object: %@ in collection: %@", [object1 class], collection1);
                return NSOrderedSame;
            }
            OWSMessageDecryptJob *job1 = (OWSMessageDecryptJob *)object1;

            if (![object2 isKindOfClass:[OWSMessageDecryptJob class]]) {
                OWSFail(@"Unexpected object: %@ in collection: %@", [object2 class], collection2);
                return NSOrderedSame;
            }
            OWSMessageDecryptJob *job2 = (OWSMessageDecryptJob *)object2;

            return [job1.createdAt compare:job2.createdAt];
        }];

    YapDatabaseViewGrouping *grouping =
        [YapDatabaseViewGrouping withObjectBlock:^NSString *_Nullable(YapDatabaseReadTransaction *_Nonnull transaction,
            NSString *_Nonnull collection,
            NSString *_Nonnull key,
            id _Nonnull object) {
            if (![object isKindOfClass:[OWSMessageDecryptJob class]]) {
                OWSFail(@"Unexpected object: %@ in collection: %@", object, collection);
                return nil;
            }

            // Arbitrary string - all in the same group. We're only using the view for sorting.
            return OWSMessageDecryptJobFinderExtensionGroup;
        }];

    YapDatabaseViewOptions *options = [YapDatabaseViewOptions new];
    options.allowedCollections =
        [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:[OWSMessageDecryptJob collection]]];

    return [[YapDatabaseView alloc] initWithGrouping:grouping sorting:sorting versionTag:@"1" options:options];
}


+ (void)syncRegisterDatabaseExtension:(YapDatabase *)database
{
    YapDatabaseView *existingView = [database registeredExtension:OWSMessageDecryptJobFinderExtensionName];
    if (existingView) {
        OWSFail(@"%@ was already initialized.", OWSMessageDecryptJobFinderExtensionName);
        // already initialized
        return;
    }
    [database registerExtension:[self databaseExtension] withName:OWSMessageDecryptJobFinderExtensionName];
}

@end

#pragma mark - Queue Processing

@interface OWSMessageDecryptQueue : NSObject

@property (nonatomic, readonly) OWSMessageDecrypter *messageDecrypter;
@property (nonatomic, readonly) OWSBatchMessageProcessor *batchMessageProcessor;
@property (nonatomic, readonly) OWSMessageDecryptJobFinder *finder;
@property (nonatomic) BOOL isDrainingQueue;

- (instancetype)initWithMessageDecrypter:(OWSMessageDecrypter *)messageDecrypter
                   batchMessageProcessor:(OWSBatchMessageProcessor *)batchMessageProcessor
                                  finder:(OWSMessageDecryptJobFinder *)finder NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark -

@implementation OWSMessageDecryptQueue

- (instancetype)initWithMessageDecrypter:(OWSMessageDecrypter *)messageDecrypter
                   batchMessageProcessor:(OWSBatchMessageProcessor *)batchMessageProcessor
                                  finder:(OWSMessageDecryptJobFinder *)finder
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

    NSArray<OWSMessageDecryptJob *> *jobs = [self.finder nextJobsForBatchSize:kIncomingMessageBatchSize];
    OWSAssert(jobs);
    if (jobs.count < 1) {
        self.isDrainingQueue = NO;
        DDLogVerbose(@"%@ Queue is drained.", self.tag);
        return;
    }

    [self processJobs:jobs
           completion:^{
               dispatch_async(dispatch_get_main_queue(), ^{
                   [self.finder removeJobsWithIds:jobs.uniqueIds];
                   DDLogVerbose(@"%@ completed %zd jobs. %zd jobs left.",
                       self.tag,
                       jobs.count,
                       [OWSMessageDecryptJob numberOfKeysInCollection]);
                   [self drainQueueWorkStep];
               });
           }];
}

- (void)processJobs:(NSArray<OWSMessageDecryptJob *> *)jobs completion:(void (^)())completion
{
    [self processJobs:jobs
         unprocessedJobs:[jobs mutableCopy]
        plaintextDataMap:[NSMutableDictionary new]
              completion:completion];
}

- (void)processJobs:(NSArray<OWSMessageDecryptJob *> *)jobs
     unprocessedJobs:(NSMutableArray<OWSMessageDecryptJob *> *)unprocessedJobs
    plaintextDataMap:(NSMutableDictionary<NSString *, NSData *> *)plaintextDataMap
          completion:(void (^)())completion
{
    OWSAssert(jobs.count > 0);
    OWSAssert(unprocessedJobs.count <= jobs.count);

    if (unprocessedJobs.count < 1) {
        for (OWSMessageDecryptJob *job in jobs) {
            NSData *_Nullable plaintextData = plaintextDataMap[job.uniqueId];
            [self.batchMessageProcessor enqueueEnvelopeData:job.envelopeData plaintextData:plaintextData];
        }
        completion();
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OWSAssert(unprocessedJobs.count > 0);
        OWSMessageDecryptJob *job = unprocessedJobs.firstObject;
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

@property (nonatomic, readonly) OWSMessageDecryptQueue *processingQueue;
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

    OWSMessageDecryptJobFinder *finder = [[OWSMessageDecryptJobFinder alloc] initWithDBConnection:dbConnection];
    OWSMessageDecryptQueue *processingQueue =
        [[OWSMessageDecryptQueue alloc] initWithMessageDecrypter:messageDecrypter
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
    [OWSMessageDecryptJobFinder syncRegisterDatabaseExtension:database];
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
