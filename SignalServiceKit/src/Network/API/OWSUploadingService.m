//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSUploadingService.h"
#import "Cryptography.h"
#import "MIMETypeUtil.h"
#import "OWSError.h"
#import "OWSMessageSender.h"
#import "TSAttachmentStream.h"
#import "TSNetworkManager.h"
#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const kAttachmentUploadProgressNotification = @"kAttachmentUploadProgressNotification";
NSString *const kAttachmentUploadProgressKey = @"kAttachmentUploadProgressKey";
NSString *const kAttachmentUploadAttachmentIDKey = @"kAttachmentUploadAttachmentIDKey";

// Use a slightly non-zero value to ensure that the progress
// indicator shows up as quickly as possible.
static const CGFloat kAttachmentUploadProgressTheta = 0.001f;

@interface OWSUploadingService ()

@property (nonatomic, readonly) TSNetworkManager *networkManager;

@end

@implementation OWSUploadingService

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _networkManager = networkManager;

    return self;
}

- (void)uploadAttachmentStream:(TSAttachmentStream *)attachmentStream
                       message:(TSOutgoingMessage *)outgoingMessage
                       success:(void (^)())successHandler
                       failure:(RetryableFailureHandler)failureHandler
{
    void (^successHandlerWrapper)() = ^{
        [self fireProgressNotification:1 attachmentId:attachmentStream.uniqueId];

        successHandler();
    };

    RetryableFailureHandler failureHandlerWrapper = ^(NSError *_Nonnull error) {
        [self fireProgressNotification:0 attachmentId:attachmentStream.uniqueId];

        failureHandler(error);
    };

    if (attachmentStream.serverId) {
        DDLogDebug(@"%@ Attachment previously uploaded.", self.tag);
        successHandlerWrapper(outgoingMessage);
        return;
    }

    [self fireProgressNotification:kAttachmentUploadProgressTheta attachmentId:attachmentStream.uniqueId];

    TSRequest *allocateAttachment = [[TSAllocAttachmentRequest alloc] init];
    [self.networkManager makeRequest:allocateAttachment
        success:^(NSURLSessionDataTask *task, id responseObject) {
            dispatch_async([OWSDispatch attachmentsQueue], ^{ // TODO can we move this queue specification up a level?
                if (![responseObject isKindOfClass:[NSDictionary class]]) {
                    DDLogError(@"%@ unexpected response from server: %@", self.tag, responseObject);
                    NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                    [error setIsRetryable:YES];
                    return failureHandlerWrapper(error);
                }

                NSDictionary *responseDict = (NSDictionary *)responseObject;
                UInt64 serverId = ((NSDecimalNumber *)[responseDict objectForKey:@"id"]).unsignedLongLongValue;
                NSString *location = [responseDict objectForKey:@"location"];

                NSError *error;
                NSData *attachmentData = [attachmentStream readDataFromFileWithError:&error];
                if (error) {
                    DDLogError(@"%@ Failed to read attachment data with error:%@", self.tag, error);
                    [error setIsRetryable:YES];
                    return failureHandlerWrapper(error);
                }

                NSData *encryptionKey;
                NSData *digest;
                NSData *encryptedAttachmentData =
                    [Cryptography encryptAttachmentData:attachmentData outKey:&encryptionKey outDigest:&digest];

                attachmentStream.encryptionKey = encryptionKey;
                attachmentStream.digest = digest;

                [self uploadDataWithProgress:encryptedAttachmentData
                                    location:location
                                attachmentId:attachmentStream.uniqueId
                                     success:^{
                                         OWSAssert([NSThread isMainThread]);

                                         DDLogInfo(@"%@ Uploaded attachment: %p.", self.tag, attachmentStream);
                                         attachmentStream.serverId = serverId;
                                         attachmentStream.isUploaded = YES;
                                         [attachmentStream save];

                                         successHandlerWrapper();
                                     }
                                     failure:failureHandlerWrapper];

            });
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            DDLogError(@"%@ Failed to allocate attachment with error: %@", self.tag, error);
            [error setIsRetryable:YES];
            failureHandlerWrapper(error);
        }];
}


- (void)uploadDataWithProgress:(NSData *)cipherText
                      location:(NSString *)location
                  attachmentId:(NSString *)attachmentId
                       success:(void (^)())successHandler
                       failure:(RetryableFailureHandler)failureHandler
{
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:location]];
    request.HTTPMethod = @"PUT";
    request.HTTPBody = cipherText;
    [request setValue:OWSMimeTypeApplicationOctetStream forHTTPHeaderField:@"Content-Type"];

    AFURLSessionManager *manager = [[AFURLSessionManager alloc]
        initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];

    NSURLSessionUploadTask *uploadTask;
    uploadTask = [manager uploadTaskWithRequest:request
        fromData:cipherText
        progress:^(NSProgress *_Nonnull uploadProgress) {
            [self fireProgressNotification:MAX(kAttachmentUploadProgressTheta, uploadProgress.fractionCompleted)
                              attachmentId:attachmentId];
        }
        completionHandler:^(NSURLResponse *_Nonnull response, id _Nullable responseObject, NSError *_Nullable error) {
            OWSAssert([NSThread isMainThread]);
            if (error) {
                [error setIsRetryable:YES];
                return failureHandler(error);
            }

            NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
            BOOL isValidResponse = (statusCode >= 200) && (statusCode < 400);
            if (!isValidResponse) {
                DDLogError(@"%@ Unexpected server response: %d", self.tag, (int)statusCode);
                NSError *invalidResponseError = OWSErrorMakeUnableToProcessServerResponseError();
                [invalidResponseError setIsRetryable:YES];
                return failureHandler(invalidResponseError);
            }

            successHandler();
        }];

    [uploadTask resume];
}

- (void)fireProgressNotification:(CGFloat)progress attachmentId:(NSString *)attachmentId
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter postNotificationName:kAttachmentUploadProgressNotification
                                          object:nil
                                        userInfo:@{
                                            kAttachmentUploadProgressKey : @(progress),
                                            kAttachmentUploadAttachmentIDKey : attachmentId
                                        }];
    });
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
