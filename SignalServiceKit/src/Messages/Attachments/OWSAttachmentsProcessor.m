//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSAttachmentsProcessor.h"
#import "AppContext.h"
#import "Cryptography.h"
#import "MIMETypeUtil.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSBackgroundTask.h"
#import "OWSError.h"
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
        TSAttachmentPointer *pointer = [TSAttachmentPointer attachmentPointerFromProto:attachmentProto];

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
    OWSAssert(transaction);

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
    OWSAssert(transaction);

    __block OWSBackgroundTask *backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    [self setAttachment:attachment isDownloadingInMessage:message transaction:transaction];

    void (^markAndHandleFailure)(NSError *) = ^(NSError *error) {
        // Ensure enclosing transaction is complete.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self setAttachment:attachment didFailInMessage:message error:error];
            failureHandler(error);

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

            backgroundTask = nil;
        });
    };

    if (attachment.serverId < 100) {
        DDLogError(@"%@ Suspicious attachment id: %llu", self.logTag, (unsigned long long)attachment.serverId);
    }
    TSRequest *request = [OWSRequestFactory attachmentRequestWithAttachmentId:attachment.serverId];

    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            if (![responseObject isKindOfClass:[NSDictionary class]]) {
                DDLogError(@"%@ Failed retrieval of attachment. Response had unexpected format.", self.logTag);
                NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                return markAndHandleFailure(error);
            }
            NSString *location = [(NSDictionary *)responseObject objectForKey:@"location"];
            if (!location) {
                DDLogError(@"%@ Failed retrieval of attachment. Response had no location.", self.logTag);
                NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                return markAndHandleFailure(error);
            }

            dispatch_async([OWSDispatch attachmentsQueue], ^{
                [self downloadFromLocation:location
                    pointer:attachment
                    success:^(NSData *encryptedData) {
                        [self decryptAttachmentData:encryptedData
                                            pointer:attachment
                                            success:markAndHandleSuccess
                                            failure:markAndHandleFailure];
                    }
                    failure:^(NSURLSessionDataTask *_Nullable task, NSError *error) {
                        if (attachment.serverId < 100) {
                            // This looks like the symptom of the "frequent 404
                            // downloading attachments with low server ids".
                            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
                            NSInteger statusCode = [httpResponse statusCode];
                            OWSFail(@"%@ %d Failure with suspicious attachment id: %llu, %@",
                                self.logTag,
                                (int)statusCode,
                                (unsigned long long)attachment.serverId,
                                error);
                        }
                        if (markAndHandleFailure) {
                            markAndHandleFailure(error);
                        }
                    }];
            });
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (!IsNSErrorNetworkFailure(error)) {
                OWSProdError([OWSAnalyticsEvents errorAttachmentRequestFailed]);
            }
            DDLogError(@"Failed retrieval of attachment with error: %@", error);
            if (attachment.serverId < 100) {
                // This _shouldn't_ be the symptom of the "frequent 404
                // downloading attachments with low server ids".
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
                NSInteger statusCode = [httpResponse statusCode];
                OWSFail(@"%@ %d Failure with suspicious attachment id: %llu, %@",
                    self.logTag,
                    (int)statusCode,
                    (unsigned long long)attachment.serverId,
                    error);
            }
            return markAndHandleFailure(error);
        }];
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
        DDLogError(@"%@ failed to decrypt with error: %@", self.logTag, decryptError);
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
        DDLogError(@"%@ Failed writing attachment stream with error: %@", self.logTag, writeError);
        failureHandler(writeError);
        return;
    }

    [stream save];
    successHandler(stream);
}

- (void)downloadFromLocation:(NSString *)location
                     pointer:(TSAttachmentPointer *)pointer
                     success:(void (^)(NSData *encryptedData))successHandler
                     failure:(void (^)(NSURLSessionDataTask *_Nullable task, NSError *error))failureHandler
{
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.requestSerializer     = [AFHTTPRequestSerializer serializer];
    [manager.requestSerializer setValue:OWSMimeTypeApplicationOctetStream forHTTPHeaderField:@"Content-Type"];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    manager.completionQueue    = dispatch_get_main_queue();

    // We want to avoid large downloads from a compromised or buggy service.
    const long kMaxDownloadSize = 150 * 1024 * 1024;
    // TODO stream this download rather than storing the entire blob.
    __block NSURLSessionDataTask *task = nil;
    __block BOOL hasCheckedContentLength = NO;
    task = [manager GET:location
        parameters:nil
        progress:^(NSProgress *progress) {
            OWSAssert(progress != nil);
            
            // Don't do anything until we've received at least one byte of data.
            if (progress.completedUnitCount < 1) {
                return;
            }

            void (^abortDownload)(void) = ^{
                OWSFail(@"%@ Download aborted.", self.logTag);
                [task cancel];
            };

            if (progress.totalUnitCount > kMaxDownloadSize || progress.completedUnitCount > kMaxDownloadSize) {
                // A malicious service might send a misleading content length header,
                // so....
                //
                // If the current downloaded bytes or the expected total byes
                // exceed the max download size, abort the download.
                DDLogError(@"%@ Attachment download exceed expected content length: %lld, %lld.",
                    self.logTag,
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
                DDLogError(@"%@ Attachment download has missing or invalid response.", self.logTag);
                abortDownload();
                return;
            }
            
            NSDictionary *headers = [httpResponse allHeaderFields];
            if (![headers isKindOfClass:[NSDictionary class]]) {
                DDLogError(@"%@ Attachment download invalid headers.", self.logTag);
                abortDownload();
                return;
            }
            
            
            NSString *contentLength = headers[@"Content-Length"];
            if (![contentLength isKindOfClass:[NSString class]]) {
                DDLogError(@"%@ Attachment download missing or invalid content length.", self.logTag);
                abortDownload();
                return;
            }
            
            
            if (contentLength.longLongValue > kMaxDownloadSize) {
                DDLogError(@"%@ Attachment download content length exceeds max download size.", self.logTag);
                abortDownload();
                return;
            }
            
            // This response has a valid content length that is less
            // than our max download size.  Proceed with the download.
            hasCheckedContentLength = YES;
        }
        success:^(NSURLSessionDataTask *task, id _Nullable responseObject) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                if (![responseObject isKindOfClass:[NSData class]]) {
                    DDLogError(@"%@ Failed retrieval of attachment. Response had unexpected format.", self.logTag);
                    NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                    return failureHandler(task, error);
                }
                NSData *responseData = (NSData *)responseObject;
                if (responseData.length > kMaxDownloadSize) {
                    DDLogError(@"%@ Attachment download content length exceeds max download size.", self.logTag);
                    NSError *error = OWSErrorWithCodeDescription(
                        OWSErrorCodeInvalidMessage, NSLocalizedString(@"ERROR_MESSAGE_INVALID_MESSAGE", @""));
                    failureHandler(task, error);
                } else {
                    successHandler(responseData);
                }
            });
        }
        failure:^(NSURLSessionDataTask *_Nullable task, NSError *error) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                DDLogError(@"Failed to retrieve attachment with error: %@", error.description);
                return failureHandler(task, error);
            });
        }];
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
    OWSAssert(transaction);

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
