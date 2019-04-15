//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSAttachmentDownloads.h"
#import "AppContext.h"
#import "MIMETypeUtil.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSBackgroundTask.h"
#import "OWSDispatch.h"
#import "OWSError.h"
#import "OWSFileSystem.h"
#import "OWSPrimaryStorage.h"
#import "OWSRequestFactory.h"
#import "SSKEnvironment.h"
#import "TSAttachmentPointer.h"
#import "TSAttachmentStream.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import "TSInfoMessage.h"
#import "TSMessage.h"
#import "TSNetworkManager.h"
#import "TSThread.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kAttachmentDownloadProgressNotification = @"kAttachmentDownloadProgressNotification";
NSString *const kAttachmentDownloadProgressKey = @"kAttachmentDownloadProgressKey";
NSString *const kAttachmentDownloadAttachmentIDKey = @"kAttachmentDownloadAttachmentIDKey";

// Use a slightly non-zero value to ensure that the progress
// indicator shows up as quickly as possible.
static const CGFloat kAttachmentDownloadProgressTheta = 0.001f;

typedef void (^AttachmentDownloadSuccess)(TSAttachmentStream *attachmentStream);
typedef void (^AttachmentDownloadFailure)(NSError *error);

@interface OWSAttachmentDownloadJob : NSObject

@property (nonatomic, readonly) TSAttachmentPointer *attachmentPointer;
@property (nonatomic, readonly, nullable) TSMessage *message;
@property (nonatomic, readonly) AttachmentDownloadSuccess success;
@property (nonatomic, readonly) AttachmentDownloadFailure failure;
@property (atomic) CGFloat progress;

@end

#pragma mark -

@implementation OWSAttachmentDownloadJob

- (instancetype)initWithAttachmentPointer:(TSAttachmentPointer *)attachmentPointer
                                  message:(nullable TSMessage *)message
                                  success:(AttachmentDownloadSuccess)success
                                  failure:(AttachmentDownloadFailure)failure
{
    self = [super init];
    if (!self) {
        return self;
    }

    _attachmentPointer = attachmentPointer;
    _message = message;
    _success = success;
    _failure = failure;

    return self;
}

@end

#pragma mark -

@interface OWSAttachmentDownloads ()

// This property should only be accessed while synchronized on this class.
@property (nonatomic, readonly) NSMutableDictionary<NSString *, OWSAttachmentDownloadJob *> *downloadingJobMap;
// This property should only be accessed while synchronized on this class.
@property (nonatomic, readonly) NSMutableArray<OWSAttachmentDownloadJob *> *attachmentDownloadJobQueue;

@end

#pragma mark -

@implementation OWSAttachmentDownloads

#pragma mark - Dependencies

- (OWSPrimaryStorage *)primaryStorage
{
    return SSKEnvironment.shared.primaryStorage;
}

- (TSNetworkManager *)networkManager
{
    return SSKEnvironment.shared.networkManager;
}


#pragma mark -

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _downloadingJobMap = [NSMutableDictionary new];
    _attachmentDownloadJobQueue = [NSMutableArray new];

    return self;
}

#pragma mark -

- (nullable NSNumber *)downloadProgressForAttachmentId:(NSString *)attachmentId
{

    @synchronized(self) {
        OWSAttachmentDownloadJob *_Nullable job = self.downloadingJobMap[attachmentId];
        if (!job) {
            return nil;
        }
        return @(job.progress);
    }
}

- (void)downloadAttachmentsForMessage:(TSMessage *)message
                          transaction:(YapDatabaseReadTransaction *)transaction
                              success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))success
                              failure:(void (^)(NSError *error))failure
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(message);

    NSMutableArray<TSAttachmentStream *> *attachmentStreams = [NSMutableArray array];
    NSMutableArray<TSAttachmentPointer *> *attachmentPointers = [NSMutableArray new];

    for (TSAttachment *attachment in [message attachmentsWithTransaction:transaction]) {
        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
            TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
            [attachmentStreams addObject:attachmentStream];
        } else if ([attachment isKindOfClass:[TSAttachmentPointer class]]) {
            TSAttachmentPointer *attachmentPointer = (TSAttachmentPointer *)attachment;
            if (attachmentPointer.pointerType != TSAttachmentPointerTypeIncoming) {
                OWSLogInfo(@"Ignoring restoring attachment.");
                continue;
            }
            [attachmentPointers addObject:attachmentPointer];
        } else {
            OWSFailDebug(@"Unexpected attachment type: %@", attachment.class);
        }
    }

    [self enqueueJobsForAttachmentStreams:attachmentStreams
                       attachmentPointers:attachmentPointers
                                  message:message
                                  success:success
                                  failure:failure];
}

- (void)downloadAttachmentPointer:(TSAttachmentPointer *)attachmentPointer
                          success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))success
                          failure:(void (^)(NSError *error))failure
{
    OWSAssertDebug(attachmentPointer);

    [self enqueueJobsForAttachmentStreams:@[]
                       attachmentPointers:@[
                           attachmentPointer,
                       ]
                                  message:nil
                                  success:success
                                  failure:failure];
}

- (void)enqueueJobsForAttachmentStreams:(NSArray<TSAttachmentStream *> *)attachmentStreamsParam
                     attachmentPointers:(NSArray<TSAttachmentPointer *> *)attachmentPointers
                                message:(nullable TSMessage *)message
                                success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))successHandler
                                failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertDebug(attachmentStreamsParam);

    // To avoid deadlocks, synchronize on self outside of the transaction.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (attachmentPointers.count < 1) {
            OWSAssertDebug(attachmentStreamsParam.count > 0);
            successHandler(attachmentStreamsParam);
            return;
        }

        NSMutableArray<TSAttachmentStream *> *attachmentStreams = [attachmentStreamsParam mutableCopy];
        NSMutableArray<AnyPromise *> *promises = [NSMutableArray array];
        for (TSAttachmentPointer *attachmentPointer in attachmentPointers) {
            AnyPromise *promise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
                [self enqueueJobForAttachmentPointer:attachmentPointer
                    message:message
                    success:^(TSAttachmentStream *attachmentStream) {
                        @synchronized(attachmentStreams) {
                            [attachmentStreams addObject:attachmentStream];
                        }

                        resolve(@(1));
                    }
                    failure:^(NSError *error) {
                        resolve(error);
                    }];
            }];
            [promises addObject:promise];
        }

        // We use PMKJoin(), not PMKWhen(), because we don't want the
        // completion promise to execute until _all_ promises
        // have either succeeded or failed. PMKWhen() executes as
        // soon as any of its input promises fail.
        AnyPromise *completionPromise
            = PMKJoin(promises)
                  .then(^(id value) {
                      NSArray<TSAttachmentStream *> *attachmentStreamsCopy;
                      @synchronized(attachmentStreams) {
                          attachmentStreamsCopy = [attachmentStreams copy];
                      }
                      OWSLogInfo(@"Attachment downloads succeeded: %lu.", (unsigned long)attachmentStreamsCopy.count);

                      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                          successHandler(attachmentStreamsCopy);
                      });
                  })
                  .catch(^(NSError *error) {
                      OWSLogError(@"Attachment downloads failed.");

                      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                          failureHandler(error);
                      });
                  });
        [completionPromise retainUntilComplete];
    });
}

- (void)enqueueJobForAttachmentPointer:(TSAttachmentPointer *)attachmentPointer
                               message:(nullable TSMessage *)message
                               success:(void (^)(TSAttachmentStream *attachmentStream))success
                               failure:(void (^)(NSError *error))failure
{
    OWSAssertDebug(attachmentPointer);

    OWSAttachmentDownloadJob *job = [[OWSAttachmentDownloadJob alloc] initWithAttachmentPointer:attachmentPointer
                                                                                        message:message
                                                                                        success:success
                                                                                        failure:failure];

    @synchronized(self) {
        [self.attachmentDownloadJobQueue addObject:job];
    }

    [self startDownloadIfPossible];
}

- (void)startDownloadIfPossible
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OWSAttachmentDownloadJob *_Nullable job;

        @synchronized(self) {
            const NSUInteger kMaxSimultaneousDownloads = 4;
            if (self.downloadingJobMap.count >= kMaxSimultaneousDownloads) {
                return;
            }
            job = self.attachmentDownloadJobQueue.firstObject;
            if (!job) {
                return;
            }
            if (self.downloadingJobMap[job.attachmentPointer.uniqueId] != nil) {
                // Ensure we only have one download in flight at a time for a given attachment.
                OWSLogWarn(@"Ignoring duplicate download.");
                return;
            }
            [self.attachmentDownloadJobQueue removeObjectAtIndex:0];
            self.downloadingJobMap[job.attachmentPointer.uniqueId] = job;
        }

        [self.primaryStorage.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            job.attachmentPointer.state = TSAttachmentPointerStateDownloading;
            [job.attachmentPointer saveWithTransaction:transaction];

            if (job.message) {
                [job.message touchWithTransaction:transaction];
            }
        }];

        [self retrieveAttachmentForJob:job
            success:^(TSAttachmentStream *attachmentStream) {
                OWSLogVerbose(@"Attachment download succeeded.");

                [self.primaryStorage.dbReadWriteConnection
                    readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                        [attachmentStream saveWithTransaction:transaction];

                        if (job.message) {
                            [job.message touchWithTransaction:transaction];
                        }
                    }];

                job.success(attachmentStream);

                @synchronized(self) {
                    [self.downloadingJobMap removeObjectForKey:job.attachmentPointer.uniqueId];
                }

                [self startDownloadIfPossible];
            }
            failure:^(NSError *error) {
                OWSLogError(@"Attachment download failed with error: %@", error);

                [self.primaryStorage.dbReadWriteConnection
                    readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                        job.attachmentPointer.mostRecentFailureLocalizedText = error.localizedDescription;
                        job.attachmentPointer.state = TSAttachmentPointerStateFailed;
                        [job.attachmentPointer saveWithTransaction:transaction];

                        if (job.message) {
                            [job.message touchWithTransaction:transaction];
                        }
                    }];

                @synchronized(self) {
                    [self.downloadingJobMap removeObjectForKey:job.attachmentPointer.uniqueId];
                }

                job.failure(error);

                [self startDownloadIfPossible];
            }];
    });
}

#pragma mark -

- (void)retrieveAttachmentForJob:(OWSAttachmentDownloadJob *)job
                         success:(void (^)(TSAttachmentStream *attachmentStream))successHandler
                         failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertDebug(job);
    TSAttachmentPointer *attachmentPointer = job.attachmentPointer;

    __block OWSBackgroundTask *_Nullable backgroundTask =
        [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    void (^markAndHandleFailure)(NSError *) = ^(NSError *error) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            failureHandler(error);

            OWSAssertDebug(backgroundTask);
            backgroundTask = nil;
        });
    };

    void (^markAndHandleSuccess)(TSAttachmentStream *attachmentStream) = ^(TSAttachmentStream *attachmentStream) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            successHandler(attachmentStream);

            OWSAssertDebug(backgroundTask);
            backgroundTask = nil;
        });
    };

    if (attachmentPointer.serverId < 100) {
        OWSLogError(@"Suspicious attachment id: %llu", (unsigned long long)attachmentPointer.serverId);
    }
    TSRequest *request = [OWSRequestFactory attachmentRequestWithAttachmentId:attachmentPointer.serverId];

    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            if (![responseObject isKindOfClass:[NSDictionary class]]) {
                OWSLogError(@"Failed retrieval of attachment. Response had unexpected format.");
                NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                return markAndHandleFailure(error);
            }
            NSString *location = [(NSDictionary *)responseObject objectForKey:@"location"];
            if (!location) {
                OWSLogError(@"Failed retrieval of attachment. Response had no location.");
                NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                return markAndHandleFailure(error);
            }

            dispatch_async([OWSDispatch attachmentsQueue], ^{
                [self downloadFromLocation:location
                    job:job
                    success:^(NSString *encryptedDataFilePath) {
                        [self decryptAttachmentPath:encryptedDataFilePath
                                  attachmentPointer:attachmentPointer
                                            success:markAndHandleSuccess
                                            failure:markAndHandleFailure];
                    }
                    failure:^(NSURLSessionTask *_Nullable task, NSError *error) {
                        if (attachmentPointer.serverId < 100) {
                            // This looks like the symptom of the "frequent 404
                            // downloading attachments with low server ids".
                            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
                            NSInteger statusCode = [httpResponse statusCode];
                            OWSFailDebug(@"%d Failure with suspicious attachment id: %llu, %@",
                                (int)statusCode,
                                (unsigned long long)attachmentPointer.serverId,
                                error);
                        }
                        markAndHandleFailure(error);
                    }];
            });
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (!IsNSErrorNetworkFailure(error)) {
                OWSProdError([OWSAnalyticsEvents errorAttachmentRequestFailed]);
            }
            OWSLogError(@"Failed retrieval of attachment with error: %@", error);
            if (attachmentPointer.serverId < 100) {
                // This _shouldn't_ be the symptom of the "frequent 404
                // downloading attachments with low server ids".
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
                NSInteger statusCode = [httpResponse statusCode];
                OWSFailDebug(@"%d Failure with suspicious attachment id: %llu, %@",
                    (int)statusCode,
                    (unsigned long long)attachmentPointer.serverId,
                    error);
            }
            return markAndHandleFailure(error);
        }];
}

- (void)decryptAttachmentPath:(NSString *)encryptedDataFilePath
            attachmentPointer:(TSAttachmentPointer *)attachmentPointer
                      success:(void (^)(TSAttachmentStream *attachmentStream))success
                      failure:(void (^)(NSError *error))failure
{
    OWSAssertDebug(encryptedDataFilePath.length > 0);
    OWSAssertDebug(attachmentPointer);

    // Use attachmentDecryptSerialQueue to ensure that we only load into memory
    // & decrypt a single attachment at a time.
    dispatch_async(self.attachmentDecryptSerialQueue, ^{
        @autoreleasepool {
            NSData *_Nullable encryptedData = [NSData dataWithContentsOfFile:encryptedDataFilePath];
            if (!encryptedData) {
                OWSLogError(@"Could not load encrypted data.");
                NSError *error = OWSErrorWithCodeDescription(
                    OWSErrorCodeInvalidMessage, NSLocalizedString(@"ERROR_MESSAGE_INVALID_MESSAGE", @""));
                return failure(error);
            }

            [self decryptAttachmentData:encryptedData
                      attachmentPointer:attachmentPointer
                                success:success
                                failure:failure];

            if (![OWSFileSystem deleteFile:encryptedDataFilePath]) {
                OWSLogError(@"Could not delete temporary file.");
            }
        }
    });
}

- (void)decryptAttachmentData:(NSData *)cipherText
            attachmentPointer:(TSAttachmentPointer *)attachmentPointer
                      success:(void (^)(TSAttachmentStream *attachmentStream))successHandler
                      failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertDebug(attachmentPointer);

    NSError *decryptError;
    NSData *_Nullable plaintext = [Cryptography decryptAttachment:cipherText
                                                          withKey:attachmentPointer.encryptionKey
                                                           digest:attachmentPointer.digest
                                                     unpaddedSize:attachmentPointer.byteCount
                                                            error:&decryptError];

    if (decryptError) {
        OWSLogError(@"failed to decrypt with error: %@", decryptError);
        failureHandler(decryptError);
        return;
    }

    if (!plaintext) {
        NSError *error = OWSErrorWithCodeDescription(
            OWSErrorCodeFailedToDecryptMessage, NSLocalizedString(@"ERROR_MESSAGE_INVALID_MESSAGE", @""));
        failureHandler(error);
        return;
    }

    TSAttachmentStream *stream = [[TSAttachmentStream alloc] initWithPointer:attachmentPointer];

    NSError *writeError;
    [stream writeData:plaintext error:&writeError];
    if (writeError) {
        OWSLogError(@"Failed writing attachment stream with error: %@", writeError);
        failureHandler(writeError);
        return;
    }

    successHandler(stream);
}

- (dispatch_queue_t)attachmentDecryptSerialQueue
{
    static dispatch_queue_t _serialQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _serialQueue = dispatch_queue_create("org.whispersystems.attachment.decrypt", DISPATCH_QUEUE_SERIAL);
    });

    return _serialQueue;
}

- (void)downloadFromLocation:(NSString *)location
                         job:(OWSAttachmentDownloadJob *)job
                     success:(void (^)(NSString *encryptedDataPath))successHandler
                     failure:(void (^)(NSURLSessionTask *_Nullable task, NSError *error))failureHandlerParam
{
    OWSAssertDebug(job);
    TSAttachmentPointer *attachmentPointer = job.attachmentPointer;

    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.requestSerializer = [AFHTTPRequestSerializer serializer];
    [manager.requestSerializer setValue:OWSMimeTypeApplicationOctetStream forHTTPHeaderField:@"Content-Type"];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    manager.completionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    // We want to avoid large downloads from a compromised or buggy service.
    const long kMaxDownloadSize = 150 * 1024 * 1024;
    __block BOOL hasCheckedContentLength = NO;

    NSString *tempFilePath =
        [OWSTemporaryDirectoryAccessibleAfterFirstAuth() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSURL *tempFileURL = [NSURL fileURLWithPath:tempFilePath];

    __block NSURLSessionDownloadTask *task;
    void (^failureHandler)(NSError *) = ^(NSError *error) {
        OWSLogError(@"Failed to download attachment with error: %@", error.description);

        if (![OWSFileSystem deleteFileIfExists:tempFilePath]) {
            OWSLogError(@"Could not delete temporary file #1.");
        }

        failureHandlerParam(task, error);
    };

    NSString *method = @"GET";
    NSError *serializationError = nil;
    NSMutableURLRequest *request = [manager.requestSerializer requestWithMethod:method
                                                                      URLString:location
                                                                     parameters:nil
                                                                          error:&serializationError];
    if (serializationError) {
        return failureHandler(serializationError);
    }

    task = [manager downloadTaskWithRequest:request
        progress:^(NSProgress *progress) {
            OWSAssertDebug(progress != nil);

            // Don't do anything until we've received at least one byte of data.
            if (progress.completedUnitCount < 1) {
                return;
            }

            void (^abortDownload)(void) = ^{
                OWSFailDebug(@"Download aborted.");
                [task cancel];
            };

            if (progress.totalUnitCount > kMaxDownloadSize || progress.completedUnitCount > kMaxDownloadSize) {
                // A malicious service might send a misleading content length header,
                // so....
                //
                // If the current downloaded bytes or the expected total byes
                // exceed the max download size, abort the download.
                OWSLogError(@"Attachment download exceed expected content length: %lld, %lld.",
                    (long long)progress.totalUnitCount,
                    (long long)progress.completedUnitCount);
                abortDownload();
                return;
            }

            job.progress = progress.fractionCompleted;

            [self fireProgressNotification:MAX(kAttachmentDownloadProgressTheta, progress.fractionCompleted)
                              attachmentId:attachmentPointer.uniqueId];

            // We only need to check the content length header once.
            if (hasCheckedContentLength) {
                return;
            }

            // Once we've received some bytes of the download, check the content length
            // header for the download.
            //
            // If the task doesn't exist, or doesn't have a response, or is missing
            // the expected headers, or has an invalid or oversize content length, etc.,
            // abort the download.
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
            if (![httpResponse isKindOfClass:[NSHTTPURLResponse class]]) {
                OWSLogError(@"Attachment download has missing or invalid response.");
                abortDownload();
                return;
            }

            NSDictionary *headers = [httpResponse allHeaderFields];
            if (![headers isKindOfClass:[NSDictionary class]]) {
                OWSLogError(@"Attachment download invalid headers.");
                abortDownload();
                return;
            }


            NSString *contentLength = headers[@"Content-Length"];
            if (![contentLength isKindOfClass:[NSString class]]) {
                OWSLogError(@"Attachment download missing or invalid content length.");
                abortDownload();
                return;
            }


            if (contentLength.longLongValue > kMaxDownloadSize) {
                OWSLogError(@"Attachment download content length exceeds max download size.");
                abortDownload();
                return;
            }

            // This response has a valid content length that is less
            // than our max download size.  Proceed with the download.
            hasCheckedContentLength = YES;
        }
        destination:^(NSURL *targetPath, NSURLResponse *response) {
            return tempFileURL;
        }
        completionHandler:^(NSURLResponse *response, NSURL *_Nullable filePath, NSError *_Nullable error) {
            if (error) {
                failureHandler(error);
                return;
            }
            if (![tempFileURL isEqual:filePath]) {
                OWSLogError(@"Unexpected temp file path.");
                NSError *error = OWSErrorWithCodeDescription(
                    OWSErrorCodeInvalidMessage, NSLocalizedString(@"ERROR_MESSAGE_INVALID_MESSAGE", @""));
                return failureHandler(error);
            }

            NSNumber *_Nullable fileSize = [OWSFileSystem fileSizeOfPath:tempFilePath];
            if (!fileSize) {
                OWSLogError(@"Could not determine attachment file size.");
                NSError *error = OWSErrorWithCodeDescription(
                    OWSErrorCodeInvalidMessage, NSLocalizedString(@"ERROR_MESSAGE_INVALID_MESSAGE", @""));
                return failureHandler(error);
            }
            if (fileSize.unsignedIntegerValue > kMaxDownloadSize) {
                OWSLogError(@"Attachment download length exceeds max size.");
                NSError *error = OWSErrorWithCodeDescription(
                    OWSErrorCodeInvalidMessage, NSLocalizedString(@"ERROR_MESSAGE_INVALID_MESSAGE", @""));
                return failureHandler(error);
            }
            successHandler(tempFilePath);
        }];
    [task resume];
}

- (void)fireProgressNotification:(CGFloat)progress attachmentId:(NSString *)attachmentId
{
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter postNotificationNameAsync:kAttachmentDownloadProgressNotification
                                           object:nil
                                         userInfo:@{
                                             kAttachmentDownloadProgressKey : @(progress),
                                             kAttachmentDownloadAttachmentIDKey : attachmentId
                                         }];
}

@end

NS_ASSUME_NONNULL_END
