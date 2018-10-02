//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSAttachmentsProcessor.h"
#import "AppContext.h"
#import "Cryptography.h"
#import "MIMETypeUtil.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSBackgroundTask.h"
#import "OWSDispatch.h"
#import "OWSError.h"
#import "OWSFileSystem.h"
#import "OWSPrimaryStorage.h"
#import "OWSRequestFactory.h"
#import "TSAttachmentPointer.h"
#import "TSAttachmentStream.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import "TSInfoMessage.h"
#import "TSMessage.h"
#import "TSNetworkManager.h"
#import "TSThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kAttachmentDownloadProgressNotification = @"kAttachmentDownloadProgressNotification";
NSString *const kAttachmentDownloadProgressKey = @"kAttachmentDownloadProgressKey";
NSString *const kAttachmentDownloadAttachmentIDKey = @"kAttachmentDownloadAttachmentIDKey";

// Use a slightly non-zero value to ensure that the progress
// indicator shows up as quickly as possible.
static const CGFloat kAttachmentDownloadProgressTheta = 0.001f;

@interface OWSAttachmentsProcessor ()

@property (nonatomic, readonly) TSNetworkManager *networkManager;

@end

@implementation OWSAttachmentsProcessor

- (instancetype)initWithAttachmentPointer:(TSAttachmentPointer *)attachmentPointer
                           networkManager:(TSNetworkManager *)networkManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _networkManager = networkManager;

    _attachmentPointers = @[ attachmentPointer ];
    _attachmentIds = @[ attachmentPointer.uniqueId ];

    return self;
}

- (instancetype)initWithAttachmentProtos:(NSArray<SSKProtoAttachmentPointer *> *)attachmentProtos
                          networkManager:(TSNetworkManager *)networkManager
                             transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    self = [super init];
    if (!self) {
        return self;
    }

    _networkManager = networkManager;

    NSMutableArray<NSString *> *attachmentIds = [NSMutableArray new];
    NSMutableArray<TSAttachmentPointer *> *attachmentPointers = [NSMutableArray new];

    for (SSKProtoAttachmentPointer *attachmentProto in attachmentProtos) {
        TSAttachmentPointer *_Nullable pointer = [TSAttachmentPointer attachmentPointerFromProto:attachmentProto];
        if (!pointer) {
            OWSFailDebug(@"Invalid attachment.");
            continue;
        }

        [attachmentIds addObject:pointer.uniqueId];
        [pointer saveWithTransaction:transaction];
        [attachmentPointers addObject:pointer];
    }

    _attachmentIds = [attachmentIds copy];
    _attachmentPointers = [attachmentPointers copy];

    return self;
}

// PERF: Remove this and use a pre-existing dbConnection
- (void)fetchAttachmentsForMessage:(nullable TSMessage *)message
                    primaryStorage:(OWSPrimaryStorage *)primaryStorage
                           success:(void (^)(TSAttachmentStream *attachmentStream))successHandler
                           failure:(void (^)(NSError *error))failureHandler
{
    [[primaryStorage newDatabaseConnection] readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self fetchAttachmentsForMessage:message
                             transaction:transaction
                                 success:successHandler
                                 failure:failureHandler];
    }];
}

- (void)fetchAttachmentsForMessage:(nullable TSMessage *)message
                       transaction:(YapDatabaseReadWriteTransaction *)transaction
                           success:(void (^)(TSAttachmentStream *attachmentStream))successHandler
                           failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertDebug(transaction);

    for (TSAttachmentPointer *attachmentPointer in self.attachmentPointers) {
        [self retrieveAttachment:attachmentPointer
                         message:message
                     transaction:transaction
                         success:successHandler
                         failure:failureHandler];
    }
}

- (void)retrieveAttachment:(TSAttachmentPointer *)attachment
                   message:(nullable TSMessage *)message
               transaction:(YapDatabaseReadWriteTransaction *)transaction
                   success:(void (^)(TSAttachmentStream *attachmentStream))successHandler
                   failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertDebug(transaction);

    __block OWSBackgroundTask *_Nullable backgroundTask =
        [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    [self setAttachment:attachment isDownloadingInMessage:message transaction:transaction];

    void (^markAndHandleFailure)(NSError *) = ^(NSError *error) {
        // Ensure enclosing transaction is complete.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self setAttachment:attachment didFailInMessage:message error:error];
            failureHandler(error);

            OWSAssertDebug(backgroundTask);
            backgroundTask = nil;
        });
    };

    void (^markAndHandleSuccess)(TSAttachmentStream *attachmentStream) = ^(TSAttachmentStream *attachmentStream) {
        // Ensure enclosing transaction is complete.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            successHandler(attachmentStream);
            if (message) {
                [message touch];
            }

            OWSAssertDebug(backgroundTask);
            backgroundTask = nil;
        });
    };

    if (attachment.serverId < 100) {
        OWSLogError(@"Suspicious attachment id: %llu", (unsigned long long)attachment.serverId);
    }
    TSRequest *request = [OWSRequestFactory attachmentRequestWithAttachmentId:attachment.serverId];

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
                    pointer:attachment
                    success:^(NSString *encryptedDataFilePath) {
                        [self decryptAttachmentPath:encryptedDataFilePath
                                            pointer:attachment
                                            success:markAndHandleSuccess
                                            failure:markAndHandleFailure];
                    }
                    failure:^(NSURLSessionTask *_Nullable task, NSError *error) {
                        if (attachment.serverId < 100) {
                            // This looks like the symptom of the "frequent 404
                            // downloading attachments with low server ids".
                            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
                            NSInteger statusCode = [httpResponse statusCode];
                            OWSFailDebug(@"%d Failure with suspicious attachment id: %llu, %@",
                                (int)statusCode,
                                (unsigned long long)attachment.serverId,
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
            if (attachment.serverId < 100) {
                // This _shouldn't_ be the symptom of the "frequent 404
                // downloading attachments with low server ids".
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
                NSInteger statusCode = [httpResponse statusCode];
                OWSFailDebug(@"%d Failure with suspicious attachment id: %llu, %@",
                    (int)statusCode,
                    (unsigned long long)attachment.serverId,
                    error);
            }
            return markAndHandleFailure(error);
        }];
}

- (void)decryptAttachmentPath:(NSString *)encryptedDataFilePath
                      pointer:(TSAttachmentPointer *)attachment
                      success:(void (^)(TSAttachmentStream *attachmentStream))success
                      failure:(void (^)(NSError *error))failure
{
    OWSAssertDebug(encryptedDataFilePath.length > 0);
    OWSAssertDebug(attachment);

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

            [self decryptAttachmentData:encryptedData pointer:attachment success:success failure:failure];

            if (![OWSFileSystem deleteFile:encryptedDataFilePath]) {
                OWSLogError(@"Could not delete temporary file.");
            }
        }
    });
}

- (void)decryptAttachmentData:(NSData *)cipherText
                      pointer:(TSAttachmentPointer *)attachment
                      success:(void (^)(TSAttachmentStream *attachmentStream))successHandler
                      failure:(void (^)(NSError *error))failureHandler
{
    NSError *decryptError;
    NSData *_Nullable plaintext = [Cryptography decryptAttachment:cipherText
                                                          withKey:attachment.encryptionKey
                                                           digest:attachment.digest
                                                     unpaddedSize:attachment.byteCount
                                                            error:&decryptError];

    if (decryptError) {
        OWSLogError(@"failed to decrypt with error: %@", decryptError);
        failureHandler(decryptError);
        return;
    }

    if (!plaintext) {
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, NSLocalizedString(@"ERROR_MESSAGE_INVALID_MESSAGE", @""));
        failureHandler(error);
        return;
    }

    TSAttachmentStream *stream = [[TSAttachmentStream alloc] initWithPointer:attachment];

    NSError *writeError;
    [stream writeData:plaintext error:&writeError];
    if (writeError) {
        OWSLogError(@"Failed writing attachment stream with error: %@", writeError);
        failureHandler(writeError);
        return;
    }

    [stream save];
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
                     pointer:(TSAttachmentPointer *)pointer
                     success:(void (^)(NSString *encryptedDataPath))successHandler
                     failure:(void (^)(NSURLSessionTask *_Nullable task, NSError *error))failureHandlerParam
{
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.requestSerializer     = [AFHTTPRequestSerializer serializer];
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

            [self fireProgressNotification:MAX(kAttachmentDownloadProgressTheta, progress.fractionCompleted)
                              attachmentId:pointer.uniqueId];

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

- (void)setAttachment:(TSAttachmentPointer *)pointer
    isDownloadingInMessage:(nullable TSMessage *)message
               transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    pointer.state = TSAttachmentPointerStateDownloading;
    [pointer saveWithTransaction:transaction];
    if (message) {
        [message touchWithTransaction:transaction];
    }
}

- (void)setAttachment:(TSAttachmentPointer *)pointer
     didFailInMessage:(nullable TSMessage *)message
                error:(NSError *)error
{
    pointer.mostRecentFailureLocalizedText = error.localizedDescription;
    pointer.state = TSAttachmentPointerStateFailed;
    [pointer save];
    if (message) {
        [message touch];
    }
}

- (BOOL)hasSupportedAttachments
{
    return self.attachmentPointers.count > 0;
}

@end

NS_ASSUME_NONNULL_END
