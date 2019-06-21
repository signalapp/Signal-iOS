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
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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

@property (nonatomic, readonly) NSString *attachmentId;
@property (nonatomic, readonly, nullable) TSMessage *message;
@property (nonatomic, readonly) AttachmentDownloadSuccess success;
@property (nonatomic, readonly) AttachmentDownloadFailure failure;
@property (atomic) CGFloat progress;

@end

#pragma mark -

@implementation OWSAttachmentDownloadJob

- (instancetype)initWithAttachmentId:(NSString *)attachmentId
                             message:(nullable TSMessage *)message
                             success:(AttachmentDownloadSuccess)success
                             failure:(AttachmentDownloadFailure)failure
{
    self = [super init];
    if (!self) {
        return self;
    }

    _attachmentId = attachmentId;
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

- (SDSDatabaseStorage *)databaseStorage
{
    return SSKEnvironment.shared.databaseStorage;
}

- (TSNetworkManager *)networkManager
{
    return SSKEnvironment.shared.networkManager;
}

- (AFHTTPSessionManager *)cdnSessionManager
{
    return OWSSignalService.sharedInstance.CDNSessionManager;
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

- (void)downloadBodyAttachmentsForMessage:(TSMessage *)message
                              transaction:(SDSAnyReadTransaction *)transaction
                                  success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))success
                                  failure:(void (^)(NSError *error))failure
{
    [self downloadAttachmentsForMessage:message
                            attachments:[message bodyAttachmentsWithTransaction:transaction]
                            transaction:transaction
                                success:success
                                failure:failure];
}

- (void)downloadAllAttachmentsForMessage:(TSMessage *)message
                             transaction:(SDSAnyReadTransaction *)transaction
                                 success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))success
                                 failure:(void (^)(NSError *error))failure
{
    [self downloadAttachmentsForMessage:message
                            attachments:[message allAttachmentsWithTransaction:transaction]
                            transaction:transaction
                                success:success
                                failure:failure];
}

- (void)downloadAttachmentsForMessage:(TSMessage *)message
                          attachments:(NSArray<TSAttachment *> *)attachments
                          transaction:(SDSAnyReadTransaction *)transaction
                              success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))success
                              failure:(void (^)(NSError *error))failure
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(message);
    OWSAssertDebug(attachments.count > 0);

    NSMutableArray<TSAttachmentStream *> *attachmentStreams = [NSMutableArray array];
    NSMutableArray<TSAttachmentPointer *> *attachmentPointers = [NSMutableArray new];

    for (TSAttachment *attachment in attachments) {
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
                          message:(nullable TSMessage *)message
                          success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))success
                          failure:(void (^)(NSError *error))failure
{
    OWSAssertDebug(attachmentPointer);

    [self enqueueJobsForAttachmentStreams:@[]
                       attachmentPointers:@[
                           attachmentPointer,
                       ]
                                  message:message
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
                [self enqueueJobForAttachmentId:attachmentPointer.uniqueId
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

- (void)enqueueJobForAttachmentId:(NSString *)attachmentId
                          message:(nullable TSMessage *)message
                          success:(void (^)(TSAttachmentStream *attachmentStream))success
                          failure:(void (^)(NSError *error))failure
{
    OWSAssertDebug(attachmentId.length > 0);

    OWSAttachmentDownloadJob *job = [[OWSAttachmentDownloadJob alloc] initWithAttachmentId:attachmentId
                                                                                   message:message
                                                                                   success:success
                                                                                   failure:failure];

    @synchronized(self) {
        [self.attachmentDownloadJobQueue addObject:job];
    }

    [self tryToStartNextDownload];
}

- (void)tryToStartNextDownload
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
            if (self.downloadingJobMap[job.attachmentId] != nil) {
                // Ensure we only have one download in flight at a time for a given attachment.
                OWSLogWarn(@"Ignoring duplicate download.");
                return;
            }
            [self.attachmentDownloadJobQueue removeObjectAtIndex:0];
            self.downloadingJobMap[job.attachmentId] = job;
        }

        __block TSAttachmentPointer *_Nullable attachmentPointer;
        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            // Fetch latest to ensure we don't overwrite an attachment stream, resurrect an attachment, etc.
            TSAttachment *_Nullable attachment =
                [TSAttachmentPointer anyFetchWithUniqueId:job.attachmentId transaction:transaction];
            if (![attachment isKindOfClass:[TSAttachmentPointer class]]) {
                return;
            }

            attachmentPointer = (TSAttachmentPointer *)attachment;
            [attachmentPointer anyUpdateWithTransaction:transaction
                                                  block:^(TSAttachment *attachment) {
                                                      if (![attachment isKindOfClass:[TSAttachmentPointer class]]) {
                                                          OWSFailDebug(@"Unexpected object: %@", attachment.class);
                                                          return;
                                                      }
                                                      TSAttachmentPointer *pointer = (TSAttachmentPointer *)attachment;
                                                      pointer.state = TSAttachmentPointerStateDownloading;
                                                  }];

            if (job.message) {
                if (transaction.transitional_yapWriteTransaction) {
                    [job.message touchWithTransaction:transaction.transitional_yapWriteTransaction];
                }
            }
        }];

        if (!attachmentPointer) {
            // Abort.
            [self tryToStartNextDownload];
            return;
        }

        [self retrieveAttachmentForJob:job
            attachmentPointer:attachmentPointer
            success:^(TSAttachmentStream *attachmentStream) {
                OWSLogVerbose(@"Attachment download succeeded.");

                [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                    TSAttachment *_Nullable existingAttachment =
                        [TSAttachment anyFetchWithUniqueId:attachmentStream.uniqueId transaction:transaction];
                    if (!existingAttachment) {
                        OWSFailDebug(@"Attachment no longer exists.");
                        return;
                    }
                    if (![existingAttachment isKindOfClass:[TSAttachmentPointer class]]) {
                        OWSFailDebug(@"Attachment unexpectedly already saved.");
                        return;
                    }

                    [existingAttachment anyRemoveWithTransaction:transaction];
                    [attachmentStream anyInsertWithTransaction:transaction];

                    if (job.message) {
                        if (transaction.transitional_yapWriteTransaction) {
                            [job.message touchWithTransaction:transaction.transitional_yapWriteTransaction];
                        }
                    }
                }];

                job.success(attachmentStream);

                @synchronized(self) {
                    [self.downloadingJobMap removeObjectForKey:job.attachmentId];
                }

                [self tryToStartNextDownload];
            }
            failure:^(NSError *error) {
                OWSLogError(@"Attachment download failed with error: %@", error);

                [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                    // Fetch latest to ensure we don't overwrite an attachment stream, resurrect an attachment, etc.
                    TSAttachment *_Nullable attachment =
                        [TSAttachmentPointer anyFetchWithUniqueId:job.attachmentId transaction:transaction];
                    if (![attachment isKindOfClass:[TSAttachmentPointer class]]) {
                        return;
                    }
                    TSAttachmentPointer *attachmentPointer = (TSAttachmentPointer *)attachment;
                    [attachmentPointer
                        anyUpdateWithTransaction:transaction
                                           block:^(TSAttachment *attachment) {
                                               if (![attachment isKindOfClass:[TSAttachmentPointer class]]) {
                                                   OWSFailDebug(@"Unexpected object: %@", attachment.class);
                                                   return;
                                               }
                                               TSAttachmentPointer *pointer = (TSAttachmentPointer *)attachment;
                                               pointer.mostRecentFailureLocalizedText = error.localizedDescription;
                                               pointer.state = TSAttachmentPointerStateFailed;
                                           }];

                    if (job.message) {
                        if (transaction.transitional_yapWriteTransaction) {
                            [job.message touchWithTransaction:transaction.transitional_yapWriteTransaction];
                        }
                    }
                }];

                @synchronized(self) {
                    [self.downloadingJobMap removeObjectForKey:job.attachmentId];
                }

                job.failure(error);

                [self tryToStartNextDownload];
            }];
    });
}

#pragma mark -

- (void)retrieveAttachmentForJob:(OWSAttachmentDownloadJob *)job
               attachmentPointer:(TSAttachmentPointer *)attachmentPointer
                         success:(void (^)(TSAttachmentStream *attachmentStream))successHandler
                         failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertDebug(job);
    OWSAssertDebug(attachmentPointer);

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
    dispatch_async([OWSDispatch attachmentsQueue], ^{
        [self downloadJob:job
            attachmentPointer:(TSAttachmentPointer *)attachmentPointer
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
                NSError *error = [OWSAttachmentDownloads buildError];
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
        NSError *error = [OWSAttachmentDownloads buildError];
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

- (void)downloadJob:(OWSAttachmentDownloadJob *)job
    attachmentPointer:(TSAttachmentPointer *)attachmentPointer
              success:(void (^)(NSString *encryptedDataPath))successHandler
              failure:(void (^)(NSURLSessionTask *_Nullable task, NSError *error))failureHandlerParam
{
    OWSAssertDebug(job);
    OWSAssertDebug(attachmentPointer);

    AFHTTPSessionManager *manager = self.cdnSessionManager;
    manager.completionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    NSString *urlPath = [NSString stringWithFormat:@"attachments/%llu", attachmentPointer.serverId];
    NSURL *url = [[NSURL alloc] initWithString:urlPath relativeToURL:manager.baseURL];

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
                                                                      URLString:url.absoluteString
                                                                     parameters:nil
                                                                          error:&serializationError];
    [request setValue:OWSMimeTypeApplicationOctetStream forHTTPHeaderField:@"Content-Type"];
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
        completionHandler:^(NSURLResponse *response, NSURL *_Nullable completionUrl, NSError *_Nullable error) {
            if (error) {
                failureHandler(error);
                return;
            }
            if (![tempFileURL isEqual:completionUrl]) {
                OWSLogError(@"Unexpected temp file path.");
                NSError *error = [OWSAttachmentDownloads buildError];
                return failureHandler(error);
            }

            NSNumber *_Nullable fileSize = [OWSFileSystem fileSizeOfPath:tempFilePath];
            if (!fileSize) {
                OWSLogError(@"Could not determine attachment file size.");
                NSError *error = [OWSAttachmentDownloads buildError];
                return failureHandler(error);
            }
            if (fileSize.unsignedIntegerValue > kMaxDownloadSize) {
                OWSLogError(@"Attachment download length exceeds max size.");
                NSError *error = [OWSAttachmentDownloads buildError];
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

+ (NSError *)buildError
{
    return OWSErrorWithCodeDescription(OWSErrorCodeAttachmentDownloadFailed,
        NSLocalizedString(@"ERROR_MESSAGE_ATTACHMENT_DOWNLOAD_FAILED",
            @"Error message indicating that attachment download(s) failed."));
}


@end

NS_ASSUME_NONNULL_END
