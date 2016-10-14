//  Created by Michael Kirk on 10/18/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSUploadingService.h"
#import "Cryptography.h"
#import "MIMETypeUtil.h"
#import "OWSDispatch.h"
#import "OWSError.h"
#import "TSAttachmentStream.h"
#import "TSNetworkManager.h"
#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

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
    outgoingMessage.messageState = TSOutgoingMessageStateAttemptingOut;
    [outgoingMessage save];

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
                NSData *encryptedAttachmentData =
                    [Cryptography encryptAttachmentData:attachmentData outKey:&encryptionKey];

                attachmentStream.encryptionKey = encryptionKey;

                [self uploadDataWithProgress:encryptedAttachmentData
                                    location:location
                                attachmentId:attachmentStream.uniqueId
                                     success:^{
                                         DDLogInfo(@"%@ Uploaded attachment.", self.tag);
                                         attachmentStream.serverId = serverId;
                                         attachmentStream.isDownloaded = YES;
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

    NSURLSessionUploadTask *uploadTask;
    uploadTask = [manager uploadTaskWithRequest:request
        fromData:cipherText
        progress:^(NSProgress *_Nonnull uploadProgress) {
            NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
            [notificationCenter postNotificationName:@"attachmentUploadProgress"
                                              object:nil
                                            userInfo:@{
                                                @"progress" : @(uploadProgress.fractionCompleted),
                                                @"attachmentId" : attachmentId
                                            }];
        }
        completionHandler:^(NSURLResponse *_Nonnull response, id _Nullable responseObject, NSError *_Nullable error) {
            if (error) {
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
        }];

    [uploadTask resume];
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
