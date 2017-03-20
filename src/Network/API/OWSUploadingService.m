//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSUploadingService.h"
#import "Cryptography.h"
#import "MIMETypeUtil.h"
#import "OWSError.h"
#import "TSAttachmentStream.h"
#import "TSNetworkManager.h"
#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const kAttachmentUploadProgressNotification = @"kAttachmentUploadProgressNotification";
NSString *const kAttachmentUploadProgressKey = @"kAttachmentUploadProgressKey";
NSString *const kAttachmentUploadAttachmentIDKey = @"kAttachmentUploadAttachmentIDKey";

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
                       failure:(void (^)(NSError *_Nonnull))failureHandler
{
    if (attachmentStream.serverId) {
        DDLogDebug(@"%@ Attachment previously uploaded.", self.tag);
        successHandler(outgoingMessage);
        return;
    }

    TSRequest *allocateAttachment = [[TSAllocAttachmentRequest alloc] init];
    [self.networkManager makeRequest:allocateAttachment
        success:^(NSURLSessionDataTask *task, id responseObject) {
            dispatch_async([OWSDispatch attachmentsQueue], ^{ // TODO can we move this queue specification up a level?
                if (![responseObject isKindOfClass:[NSDictionary class]]) {
                    DDLogError(@"%@ unexpected response from server: %@", self.tag, responseObject);
                    NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                    return failureHandler(error);
                }

                NSDictionary *responseDict = (NSDictionary *)responseObject;
                UInt64 serverId = ((NSDecimalNumber *)[responseDict objectForKey:@"id"]).unsignedLongLongValue;
                NSString *location = [responseDict objectForKey:@"location"];

                NSError *error;
                NSData *attachmentData = [attachmentStream readDataFromFileWithError:&error];
                if (error) {
                    DDLogError(@"%@ Failed to read attachment data with error:%@", self.tag, error);
                    return failureHandler(error);
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

                                         successHandler();
                                     }
                                     failure:failureHandler];

            });
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            DDLogError(@"%@ Failed to allocate attachment with error: %@", self.tag, error);
            failureHandler(error);
        }];
}


- (void)uploadDataWithProgress:(NSData *)cipherText
                      location:(NSString *)location
                  attachmentId:(NSString *)attachmentId
                       success:(void (^)())successHandler
                       failure:(void (^)(NSError *error))failureHandler
{
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:location]];
    request.HTTPMethod = @"PUT";
    request.HTTPBody = cipherText;
    [request setValue:OWSMimeTypeApplicationOctetStream forHTTPHeaderField:@"Content-Type"];

    AFURLSessionManager *manager = [[AFURLSessionManager alloc]
        initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];

    [self fireProgressNotification:0 attachmentId:attachmentId];

    NSURLSessionUploadTask *uploadTask;
    uploadTask = [manager uploadTaskWithRequest:request
        fromData:cipherText
        progress:^(NSProgress *_Nonnull uploadProgress) {
            [self fireProgressNotification:uploadProgress.fractionCompleted attachmentId:attachmentId];
        }
        completionHandler:^(NSURLResponse *_Nonnull response, id _Nullable responseObject, NSError *_Nullable error) {
            OWSAssert([NSThread isMainThread]);
            if (error) {
                [self fireProgressNotification:0 attachmentId:attachmentId];
                return failureHandler(error);
            }

            NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
            BOOL isValidResponse = (statusCode >= 200) && (statusCode < 400);
            if (!isValidResponse) {
                DDLogError(@"%@ Unexpected server response: %d", self.tag, (int)statusCode);
                NSError *invalidResponseError = OWSErrorMakeUnableToProcessServerResponseError();
                return failureHandler(invalidResponseError);
            }

            successHandler();

            [self fireProgressNotification:1 attachmentId:attachmentId];
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
