//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSUploadOperation.h"
#import "Cryptography.h"
#import "MIMETypeUtil.h"
#import "NSError+MessageSending.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSDispatch.h"
#import "OWSError.h"
#import "OWSOperation.h"
#import "OWSRequestFactory.h"
#import "SSKEnvironment.h"
#import "TSAttachmentStream.h"
#import "TSNetworkManager.h"
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kAttachmentUploadProgressNotification = @"kAttachmentUploadProgressNotification";
NSString *const kAttachmentUploadProgressKey = @"kAttachmentUploadProgressKey";
NSString *const kAttachmentUploadAttachmentIDKey = @"kAttachmentUploadAttachmentIDKey";

// Use a slightly non-zero value to ensure that the progress
// indicator shows up as quickly as possible.
static const CGFloat kAttachmentUploadProgressTheta = 0.001f;

@interface OWSUploadOperation ()

@property (readonly, nonatomic) NSString *attachmentId;
@property (readonly, nonatomic) YapDatabaseConnection *dbConnection;

@end

#pragma mark -

@implementation OWSUploadOperation

- (instancetype)initWithAttachmentId:(NSString *)attachmentId
                        dbConnection:(YapDatabaseConnection *)dbConnection
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.remainingRetries = 4;

    _attachmentId = attachmentId;
    _dbConnection = dbConnection;

    return self;
}

- (TSNetworkManager *)networkManager
{
    return SSKEnvironment.shared.networkManager;
}

- (void)run
{
    __block TSAttachmentStream *attachmentStream;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        attachmentStream = [TSAttachmentStream fetchObjectWithUniqueID:self.attachmentId transaction:transaction];
    }];

    if (!attachmentStream) {
        OWSProdError([OWSAnalyticsEvents messageSenderErrorCouldNotLoadAttachment]);
        NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
        // Not finding local attachment is a terminal failure.
        error.isRetryable = NO;
        [self reportError:error];
        return;
    }

    if (attachmentStream.isUploaded) {
        OWSLogDebug(@"Attachment previously uploaded.");
        [self reportSuccess];
        return;
    }
    
    [self fireNotificationWithProgress:0];

    OWSLogDebug(@"alloc attachment: %@", self.attachmentId);
    TSRequest *request = [OWSRequestFactory allocAttachmentRequest];
    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            if (![responseObject isKindOfClass:[NSDictionary class]]) {
                OWSLogError(@"unexpected response from server: %@", responseObject);
                NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                error.isRetryable = YES;
                [self reportError:error];
                return;
            }

            NSDictionary *responseDict = (NSDictionary *)responseObject;
            UInt64 serverId = ((NSDecimalNumber *)[responseDict objectForKey:@"id"]).unsignedLongLongValue;
            NSString *location = [responseDict objectForKey:@"location"];

            dispatch_async([OWSDispatch attachmentsQueue], ^{
                [self uploadWithServerId:serverId location:location attachmentStream:attachmentStream];
            });
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            OWSLogError(@"Failed to allocate attachment with error: %@", error);
            error.isRetryable = YES;
            [self reportError:error];
        }];
}

- (void)uploadWithServerId:(UInt64)serverId
                  location:(NSString *)location
          attachmentStream:(TSAttachmentStream *)attachmentStream
{
    OWSLogDebug(@"started uploading data for attachment: %@", self.attachmentId);
    NSError *error;
    NSData *attachmentData = [attachmentStream readDataFromFileWithError:&error];
    if (error) {
        OWSLogError(@"Failed to read attachment data with error: %@", error);
        error.isRetryable = YES;
        [self reportError:error];
        return;
    }

    NSData *encryptionKey;
    NSData *digest;
    NSData *_Nullable encryptedAttachmentData =
        [Cryptography encryptAttachmentData:attachmentData outKey:&encryptionKey outDigest:&digest];
    if (!encryptedAttachmentData) {
        OWSFailDebug(@"could not encrypt attachment data.");
        error = OWSErrorMakeFailedToSendOutgoingMessageError();
        error.isRetryable = YES;
        [self reportError:error];
        return;
    }
    attachmentStream.encryptionKey = encryptionKey;
    attachmentStream.digest = digest;

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:location]];
    request.HTTPMethod = @"PUT";
    [request setValue:OWSMimeTypeApplicationOctetStream forHTTPHeaderField:@"Content-Type"];

    AFURLSessionManager *manager = [[AFURLSessionManager alloc]
        initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];

    NSURLSessionUploadTask *uploadTask;
    uploadTask = [manager uploadTaskWithRequest:request
        fromData:encryptedAttachmentData
        progress:^(NSProgress *_Nonnull uploadProgress) {
            [self fireNotificationWithProgress:uploadProgress.fractionCompleted];
        }
        completionHandler:^(NSURLResponse *_Nonnull response, id _Nullable responseObject, NSError *_Nullable error) {
            OWSAssertIsOnMainThread();
            if (error) {
                error.isRetryable = YES;
                [self reportError:error];
                return;
            }

            NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
            BOOL isValidResponse = (statusCode >= 200) && (statusCode < 400);
            if (!isValidResponse) {
                OWSLogError(@"Unexpected server response: %d", (int)statusCode);
                NSError *invalidResponseError = OWSErrorMakeUnableToProcessServerResponseError();
                invalidResponseError.isRetryable = YES;
                [self reportError:invalidResponseError];
                return;
            }

            OWSLogInfo(@"Uploaded attachment: %p.", attachmentStream.uniqueId);
            attachmentStream.serverId = serverId;
            attachmentStream.isUploaded = YES;
            [attachmentStream saveAsyncWithCompletionBlock:^{
                [self reportSuccess];
            }];
        }];

    [uploadTask resume];
}

- (void)fireNotificationWithProgress:(CGFloat)aProgress
{
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

    CGFloat progress = MAX(kAttachmentUploadProgressTheta, aProgress);
    [notificationCenter postNotificationNameAsync:kAttachmentUploadProgressNotification
                                           object:nil
                                         userInfo:@{
                                             kAttachmentUploadProgressKey : @(progress),
                                             kAttachmentUploadAttachmentIDKey : self.attachmentId
                                         }];
}

@end

NS_ASSUME_NONNULL_END
