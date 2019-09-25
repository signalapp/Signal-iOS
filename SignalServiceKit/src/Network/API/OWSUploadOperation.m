//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSUploadOperation.h"
#import "MIMETypeUtil.h"
#import "NSError+OWSOperation.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSDispatch.h"
#import "OWSError.h"
#import "OWSOperation.h"
#import "OWSRequestFactory.h"
#import "OWSUploadV2.h"
#import "SSKEnvironment.h"
#import "TSAttachmentStream.h"
#import "TSNetworkManager.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kAttachmentUploadProgressNotification = @"kAttachmentUploadProgressNotification";
NSString *const kAttachmentUploadProgressKey = @"kAttachmentUploadProgressKey";
NSString *const kAttachmentUploadAttachmentIDKey = @"kAttachmentUploadAttachmentIDKey";

// Use a slightly non-zero value to ensure that the progress
// indicator shows up as quickly as possible.
static const CGFloat kAttachmentUploadProgressTheta = 0.001f;

@interface OWSUploadOperation ()

@property (readonly, nonatomic) NSString *attachmentId;
@property (nonatomic, nullable) TSAttachmentStream *completedUpload;

@end

#pragma mark -

@implementation OWSUploadOperation

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

+ (NSOperationQueue *)uploadQueue
{
    static NSOperationQueue *operationQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        operationQueue = [NSOperationQueue new];
        operationQueue.name = @"Uploads";

        // TODO - stream uploads from file and raise this limit.
        operationQueue.maxConcurrentOperationCount = 1;
    });

    return operationQueue;
}

#pragma mark -

- (instancetype)initWithAttachmentId:(NSString *)attachmentId
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.remainingRetries = 4;

    _attachmentId = attachmentId;

    return self;
}

- (TSNetworkManager *)networkManager
{
    return SSKEnvironment.shared.networkManager;
}

- (void)run
{
    __block TSAttachmentStream *_Nullable attachmentStream;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        attachmentStream =
            [TSAttachmentStream anyFetchAttachmentStreamWithUniqueId:self.attachmentId transaction:transaction];
        if (attachmentStream == nil) {
            // Message may have been removed.
            OWSLogWarn(@"Missing attachment.");
            return;
        }
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
        self.completedUpload = attachmentStream;
        [self reportSuccess];
        return;
    }
    
    [self fireNotificationWithProgress:0];

    OWSAttachmentUploadV2 *upload = [OWSAttachmentUploadV2 new];
    [[upload uploadAttachmentToService:attachmentStream
                         progressBlock:^(NSProgress *uploadProgress) {
                             [self fireNotificationWithProgress:uploadProgress.fractionCompleted];
                         }]
            .thenInBackground(^{
                [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                    [attachmentStream updateAsUploadedWithEncryptionKey:upload.encryptionKey
                                                                 digest:upload.digest
                                                               serverId:upload.serverId
                                                            transaction:transaction];
                }];
                self.completedUpload = attachmentStream;
                [self reportSuccess];
            })
            .catchInBackground(^(NSError *error) {
                OWSLogError(@"Failed: %@", error);

                if (error.code == kCFURLErrorSecureConnectionFailed) {
                    error.isRetryable = NO;
                } else {
                    error.isRetryable = YES;
                }

                [self reportError:error];
            }) retainUntilComplete];
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
