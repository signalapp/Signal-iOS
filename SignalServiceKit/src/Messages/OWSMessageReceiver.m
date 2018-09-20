//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageReceiver.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "NSArray+OWS.h"
#import "NotificationsProtocol.h"
#import "OWSBackgroundTask.h"
#import "OWSBatchMessageProcessor.h"
#import "OWSMessageDecrypter.h"
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

@interface OWSMessageDecryptJob : TSYapDatabaseObject

@property (nonatomic, readonly) NSDate *createdAt;
@property (nonatomic, readonly) NSData *envelopeData;
@property (nonatomic, readonly, nullable) SSKProtoEnvelope *envelopeProto;

- (instancetype)initWithEnvelopeData:(NSData *)envelopeData NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithUniqueId:(NSString *_Nullable)uniqueId NS_UNAVAILABLE;

@end

#pragma mark -

@implementation OWSMessageDecryptJob

+ (NSString *)collection
{
    return @"OWSMessageProcessingJob";
}

- (instancetype)initWithEnvelopeData:(NSData *)envelopeData
{
    OWSAssertDebug(envelopeData);

    self = [super initWithUniqueId:[NSUUID new].UUIDString];
    if (!self) {
        return self;
    }

    _envelopeData = envelopeData;
    _createdAt = [NSDate new];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoEnvelope *)envelopeProto
{
    NSError *error;
    SSKProtoEnvelope *_Nullable envelope = [SSKProtoEnvelope parseData:self.envelopeData error:&error];
    if (error || envelope == nil) {
        OWSFailDebug(@"failed to parase envelope with error: %@", error);
        return nil;
    }

    return envelope;
}

@end

#pragma mark - Finder

NSString *const OWSMessageDecryptJobFinderExtensionName = @"OWSMessageProcessingJobFinderExtensionName2";
NSString *const OWSMessageDecryptJobFinderExtensionGroup = @"OWSMessageProcessingJobFinderExtensionGroup2";

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

    [OWSMessageDecryptJobFinder registerLegacyClasses];

    return self;
}

- (OWSMessageDecryptJob *_Nullable)nextJob
{
    __block OWSMessageDecryptJob *_Nullable job = nil;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        YapDatabaseViewTransaction *viewTransaction = [transaction ext:OWSMessageDecryptJobFinderExtensionName];
        OWSAssertDebug(viewTransaction != nil);
        job = [viewTransaction firstObjectInGroup:OWSMessageDecryptJobFinderExtensionGroup];
    }];

    return job;
}

- (void)addJobForEnvelopeData:(NSData *)envelopeData
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        OWSMessageDecryptJob *job = [[OWSMessageDecryptJob alloc] initWithEnvelopeData:envelopeData];
        [job saveWithTransaction:transaction];
    }];
}

- (void)removeJobWithId:(NSString *)uniqueId
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [transaction removeObjectForKey:uniqueId inCollection:[OWSMessageDecryptJob collection]];
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
                OWSFailDebug(@"Unexpected object: %@ in collection: %@", [object1 class], collection1);
                return NSOrderedSame;
            }
            OWSMessageDecryptJob *job1 = (OWSMessageDecryptJob *)object1;

            if (![object2 isKindOfClass:[OWSMessageDecryptJob class]]) {
                OWSFailDebug(@"Unexpected object: %@ in collection: %@", [object2 class], collection2);
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
                OWSFailDebug(@"Unexpected object: %@ in collection: %@", object, collection);
                return nil;
            }

            // Arbitrary string - all in the same group. We're only using the view for sorting.
            return OWSMessageDecryptJobFinderExtensionGroup;
        }];

    YapDatabaseViewOptions *options = [YapDatabaseViewOptions new];
    options.allowedCollections =
        [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:[OWSMessageDecryptJob collection]]];

    return [[YapDatabaseAutoView alloc] initWithGrouping:grouping sorting:sorting versionTag:@"1" options:options];
}

+ (void)registerLegacyClasses
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // We've renamed OWSMessageProcessingJob to OWSMessageDecryptJob.
        [NSKeyedUnarchiver setClass:[OWSMessageDecryptJob class] forClassName:[OWSMessageDecryptJob collection]];
    });
}

+ (void)asyncRegisterDatabaseExtension:(OWSStorage *)storage
{
    [self registerLegacyClasses];

    YapDatabaseView *existingView = [storage registeredExtension:OWSMessageDecryptJobFinderExtensionName];
    if (existingView) {
        OWSFailDebug(@"%@ was already initialized.", OWSMessageDecryptJobFinderExtensionName);
        // already initialized
        return;
    }
    [storage asyncRegisterExtension:[self databaseExtension] withName:OWSMessageDecryptJobFinderExtensionName];
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

    [AppReadiness runNowOrWhenAppIsReady:^{
        [self drainQueue];
    }];

    return self;
}

#pragma mark - instance methods

- (dispatch_queue_t)serialQueue
{
    static dispatch_queue_t queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.whispersystems.message.decrypt", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

- (void)enqueueEnvelopeData:(NSData *)envelopeData
{
    [self.finder addJobForEnvelopeData:envelopeData];
}

- (void)drainQueue
{
    OWSAssertDebug(AppReadiness.isAppReady);

    // Don't decrypt messages in app extensions.
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

    OWSMessageDecryptJob *_Nullable job = [self.finder nextJob];
    if (!job) {
        self.isDrainingQueue = NO;
        OWSLogVerbose(@"Queue is drained.");
        return;
    }

    __block OWSBackgroundTask *_Nullable backgroundTask =
        [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    [self processJob:job
          completion:^(BOOL success) {
              [self.finder removeJobWithId:job.uniqueId];
              OWSLogVerbose(@"%@ job. %lu jobs left.",
                  success ? @"decrypted" : @"failed to decrypt",
                  (unsigned long)[OWSMessageDecryptJob numberOfKeysInCollection]);
              [self drainQueueWorkStep];
              OWSAssertDebug(backgroundTask);
              backgroundTask = nil;
          }];
}

- (void)processJob:(OWSMessageDecryptJob *)job completion:(void (^)(BOOL))completion
{
    AssertOnDispatchQueue(self.serialQueue);
    OWSAssertDebug(job);

    SSKProtoEnvelope *_Nullable envelope = job.envelopeProto;
    if (!envelope) {
        OWSFailDebug(@"Could not parse proto.");
        // TODO: Add analytics.

        [[OWSPrimaryStorage.sharedManager newDatabaseConnection]
            readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                TSErrorMessage *errorMessage = [TSErrorMessage corruptedMessageInUnknownThread];
                [SSKEnvironment.shared.notificationsManager notifyUserForThreadlessErrorMessage:errorMessage
                                                                                    transaction:transaction];
            }];

        dispatch_async(self.serialQueue, ^{
            completion(NO);
        });
        return;
    }

    [self.messageDecrypter decryptEnvelope:envelope
        successBlock:^(NSData *_Nullable plaintextData, YapDatabaseReadWriteTransaction *transaction) {
            OWSAssertDebug(transaction);

            // We persist the decrypted envelope data in the same transaction within which
            // it was decrypted to prevent data loss.  If the new job isn't persisted,
            // the session state side effects of its decryption are also rolled back.
            [self.batchMessageProcessor enqueueEnvelopeData:job.envelopeData
                                              plaintextData:plaintextData
                                                transaction:transaction];

            dispatch_async(self.serialQueue, ^{
                completion(YES);
            });
        }
        failureBlock:^{
            dispatch_async(self.serialQueue, ^{
                completion(NO);
            });
        }];
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
    YapDatabaseConnection *dbConnection = [[OWSPrimaryStorage sharedManager] newDatabaseConnection];
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

+ (NSString *)databaseExtensionName
{
    return OWSMessageDecryptJobFinderExtensionName;
}

+ (void)asyncRegisterDatabaseExtension:(OWSStorage *)storage
{
    [OWSMessageDecryptJobFinder asyncRegisterDatabaseExtension:storage];
}

#pragma mark - instance methods

- (void)handleAnyUnprocessedEnvelopesAsync
{
    [self.processingQueue drainQueue];
}

- (void)handleReceivedEnvelopeData:(NSData *)envelopeData
{
    if (envelopeData.length < 1) {
        OWSFailDebug(@"Empty envelope.");
        return;
    }

    // Drop any too-large messages on the floor. Well behaving clients should never send them.
    NSUInteger kMaxEnvelopeByteCount = 250 * 1024;
    if (envelopeData.length > kMaxEnvelopeByteCount) {
        OWSProdError([OWSAnalyticsEvents messageReceiverErrorOversizeMessage]);
        OWSFailDebug(@"Oversize message.");
        return;
    }

    // Take note of any messages larger than we expect, but still process them.
    // This likely indicates a misbehaving sending client.
    NSUInteger kLargeEnvelopeWarningByteCount = 25 * 1024;
    if (envelopeData.length > kLargeEnvelopeWarningByteCount) {
        OWSProdError([OWSAnalyticsEvents messageReceiverErrorLargeMessage]);
        OWSFailDebug(@"Unexpectedly large message.");
    }

    [self.processingQueue enqueueEnvelopeData:envelopeData];
    [self.processingQueue drainQueue];
}

@end

NS_ASSUME_NONNULL_END
