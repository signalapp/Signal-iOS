//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSBatchMessageProcessor.h"
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

@interface OWSBatchMessageProcessingJob : TSYapDatabaseObject

@property (nonatomic, readonly) NSDate *createdAt;

- (instancetype)initWithEnvelopeData:(NSData *)envelopeData
                       plaintextData:(NSData *_Nullable)plaintextData NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithUniqueId:(NSString *)uniqueId NS_UNAVAILABLE;
- (OWSSignalServiceProtosEnvelope *)envelopeProto;

@end

#pragma mark -

@interface OWSBatchMessageProcessingJob ()

@property (nonatomic, readonly) NSData *envelopeData;
@property (nonatomic, readonly, nullable) NSData *plaintextData;

@end

#pragma mark -

@implementation OWSBatchMessageProcessingJob

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

- (OWSSignalServiceProtosEnvelope *)envelopeProto
{
    return [OWSSignalServiceProtosEnvelope parseFromData:self.envelopeData];
}

@end

#pragma mark - Finder

NSString *const OWSBatchMessageProcessingJobFinderExtensionName = @"OWSBatchMessageProcessingJobFinderExtensionName";
NSString *const OWSBatchMessageProcessingJobFinderExtensionGroup = @"OWSBatchMessageProcessingJobFinderExtensionGroup";

@interface OWSBatchMessageProcessingJobFinder : NSObject

- (nullable OWSBatchMessageProcessingJob *)nextJob;
- (void)addJobWithEnvelopeData:(NSData *)envelopeData plaintextData:(NSData *_Nullable)plaintextData;
- (void)removeJobWithId:(NSString *)uniqueId;

@end

#pragma mark -

@interface OWSBatchMessageProcessingJobFinder ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

#pragma mark -

@implementation OWSBatchMessageProcessingJobFinder

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

- (nullable OWSBatchMessageProcessingJob *)nextJob
{
    __block OWSBatchMessageProcessingJob *_Nullable job;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        YapDatabaseViewTransaction *viewTransaction = [transaction ext:OWSBatchMessageProcessingJobFinderExtensionName];
        OWSAssert(viewTransaction != nil);
        job = [viewTransaction firstObjectInGroup:OWSBatchMessageProcessingJobFinderExtensionGroup];
    }];

    return job;
}

- (void)addJobWithEnvelopeData:(NSData *)envelopeData plaintextData:(NSData *_Nullable)plaintextData
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [[[OWSBatchMessageProcessingJob alloc] initWithEnvelopeData:envelopeData plaintextData:plaintextData]
            saveWithTransaction:transaction];
    }];
}

- (void)removeJobWithId:(NSString *)uniqueId
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [transaction removeObjectForKey:uniqueId inCollection:[OWSBatchMessageProcessingJob collection]];
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

            if (![object1 isKindOfClass:[OWSBatchMessageProcessingJob class]]) {
                OWSFail(@"Unexpected object: %@ in collection: %@", [object1 class], collection1);
                return NSOrderedSame;
            }
            OWSBatchMessageProcessingJob *job1 = (OWSBatchMessageProcessingJob *)object1;

            if (![object2 isKindOfClass:[OWSBatchMessageProcessingJob class]]) {
                OWSFail(@"Unexpected object: %@ in collection: %@", [object2 class], collection2);
                return NSOrderedSame;
            }
            OWSBatchMessageProcessingJob *job2 = (OWSBatchMessageProcessingJob *)object2;

            return [job1.createdAt compare:job2.createdAt];
        }];

    YapDatabaseViewGrouping *grouping =
        [YapDatabaseViewGrouping withObjectBlock:^NSString *_Nullable(YapDatabaseReadTransaction *_Nonnull transaction,
            NSString *_Nonnull collection,
            NSString *_Nonnull key,
            id _Nonnull object) {
            if (![object isKindOfClass:[OWSBatchMessageProcessingJob class]]) {
                OWSFail(@"Unexpected object: %@ in collection: %@", object, collection);
                return nil;
            }

            // Arbitrary string - all in the same group. We're only using the view for sorting.
            return OWSBatchMessageProcessingJobFinderExtensionGroup;
        }];

    YapDatabaseViewOptions *options = [YapDatabaseViewOptions new];
    options.allowedCollections = [[YapWhitelistBlacklist alloc]
        initWithWhitelist:[NSSet setWithObject:[OWSBatchMessageProcessingJob collection]]];

    return [[YapDatabaseView alloc] initWithGrouping:grouping sorting:sorting versionTag:@"1" options:options];
}


+ (void)syncRegisterDatabaseExtension:(YapDatabase *)database
{
    YapDatabaseView *existingView = [database registeredExtension:OWSBatchMessageProcessingJobFinderExtensionName];
    if (existingView) {
        OWSFail(@"%@ was already initialized.", OWSBatchMessageProcessingJobFinderExtensionName);
        // already initialized
        return;
    }
    [database registerExtension:[self databaseExtension] withName:OWSBatchMessageProcessingJobFinderExtensionName];
}

@end

#pragma mark - Queue Processing

@interface OWSBatchMessageProcessingQueue : NSObject

@property (nonatomic, readonly) TSMessagesManager *messagesManager;
@property (nonatomic, readonly) OWSBatchMessageProcessingJobFinder *finder;
@property (nonatomic) BOOL isDrainingQueue;

- (instancetype)initWithMessagesManager:(TSMessagesManager *)messagesManager
                                 finder:(OWSBatchMessageProcessingJobFinder *)finder NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark -

@implementation OWSBatchMessageProcessingQueue

- (instancetype)initWithMessagesManager:(TSMessagesManager *)messagesManager
                                 finder:(OWSBatchMessageProcessingJobFinder *)finder
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

- (void)enqueueEnvelopeData:(NSData *)envelopeData plaintextData:(NSData *_Nullable)plaintextData
{
    OWSAssert(envelopeData);

    [self.finder addJobWithEnvelopeData:envelopeData plaintextData:plaintextData];
}

- (void)drainQueue
{
    dispatch_async(dispatch_get_main_queue(), ^{
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

    OWSBatchMessageProcessingJob *_Nullable job = [self.finder nextJob];
    if (job == nil) {
        self.isDrainingQueue = NO;
        DDLogVerbose(@"%@ Queue is drained", self.tag);
        return;
    }

    [self processJob:job
          completion:^{
              dispatch_async(dispatch_get_main_queue(), ^{
                  DDLogVerbose(@"%@ completed job. %lu jobs left.",
                      self.tag,
                      (unsigned long)[OWSBatchMessageProcessingJob numberOfKeysInCollection]);
                  [self.finder removeJobWithId:job.uniqueId];
                  [self drainQueueWorkStep];
              });
          }];
}

- (void)processJob:(OWSBatchMessageProcessingJob *)job completion:(void (^)())completion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.messagesManager processEnvelope:job.envelopeProto plaintextData:job.plaintextData];
        completion();
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

#pragma mark - OWSBatchMessageProcessor

@interface OWSBatchMessageProcessor ()

@property (nonatomic, readonly) OWSBatchMessageProcessingQueue *processingQueue;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

#pragma mark -

@implementation OWSBatchMessageProcessor

- (instancetype)initWithDBConnection:(YapDatabaseConnection *)dbConnection
                     messagesManager:(TSMessagesManager *)messagesManager
{
    OWSSingletonAssert();

    self = [super init];
    if (!self) {
        return self;
    }

    OWSBatchMessageProcessingJobFinder *finder =
        [[OWSBatchMessageProcessingJobFinder alloc] initWithDBConnection:dbConnection];
    OWSBatchMessageProcessingQueue *processingQueue =
        [[OWSBatchMessageProcessingQueue alloc] initWithMessagesManager:messagesManager finder:finder];

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
    static OWSBatchMessageProcessor *sharedInstance;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] initDefault];
    });

    return sharedInstance;
}

#pragma mark - class methods

+ (void)syncRegisterDatabaseExtension:(YapDatabase *)database
{
    [OWSBatchMessageProcessingJobFinder syncRegisterDatabaseExtension:database];
}

#pragma mark - instance methods

- (void)handleAnyUnprocessedEnvelopesAsync
{
    [self.processingQueue drainQueue];
}

- (void)enqueueEnvelopeData:(NSData *)envelopeData plaintextData:(NSData *_Nullable)plaintextData
{
    OWSAssert(envelopeData);

    [self.processingQueue enqueueEnvelopeData:envelopeData plaintextData:plaintextData];
    [self.processingQueue drainQueue];
}

@end

NS_ASSUME_NONNULL_END
