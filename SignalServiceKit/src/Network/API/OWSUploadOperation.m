//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSUploadOperation.h"
#import "HTTPUtils.h"
#import "MIMETypeUtil.h"
#import "OWSError.h"
#import "OWSOperation.h"
#import "OWSUpload.h"
#import "SSKEnvironment.h"
#import "TSAttachmentStream.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kAttachmentUploadProgressNotification = @"kAttachmentUploadProgressNotification";
NSString *const kAttachmentUploadProgressKey = @"kAttachmentUploadProgressKey";
NSString *const kAttachmentUploadAttachmentIDKey = @"kAttachmentUploadAttachmentIDKey";

@interface OWSUploadOperation ()

@property (readonly, nonatomic) NSString *attachmentId;
@property (readonly, nonatomic) BOOL canUseV3;
@property (readonly, nonatomic) NSArray<NSString *> *messageIds;

@property (nonatomic, nullable) TSAttachmentStream *completedUpload;

@end

#pragma mark -

@implementation OWSUploadOperation

+ (NSOperationQueue *)uploadQueue
{
    static NSOperationQueue *operationQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        operationQueue = [NSOperationQueue new];
        operationQueue.name = @"OWSUpload";

        // TODO: Tune this limit.
        operationQueue.maxConcurrentOperationCount = CurrentAppContext().isNSE ? 2 : 8;
    });

    return operationQueue;
}

#pragma mark -

- (instancetype)initWithAttachmentId:(NSString *)attachmentId
                          messageIds:(NSArray<NSString *> *)messageIds
                            canUseV3:(BOOL)canUseV3
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.remainingRetries = 4;

    _attachmentId = attachmentId;
    _canUseV3 = canUseV3;
    _messageIds = messageIds;

    return self;
}

- (NetworkManager *)networkManager
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
        // Not finding local attachment is a terminal failure.
        NSError *error = [OWSUnretryableError asNSError];
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

    OWSAttachmentUploadV2 *upload = [[OWSAttachmentUploadV2 alloc] initWithAttachmentStream:attachmentStream
                                                                                   canUseV3:self.canUseV3];
    [BlurHash ensureBlurHashForAttachmentStream:attachmentStream]
        .catchInBackground(^(NSError *error) {
            // Swallow these errors; blurHashes are strictly optional.
            OWSLogWarn(@"Error generating blurHash.");
        })
        .thenInBackground(^(id value) {
            return [upload uploadWithProgressBlock:^(
                NSProgress *uploadProgress) { [self fireNotificationWithProgress:uploadProgress.fractionCompleted]; }];
        })
        .doneInBackground(^(id value) {
            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                [attachmentStream updateAsUploadedWithEncryptionKey:upload.encryptionKey
                                                             digest:upload.digest
                                                           serverId:upload.serverId
                                                             cdnKey:upload.cdnKey
                                                          cdnNumber:upload.cdnNumber
                                                    uploadTimestamp:upload.uploadTimestamp
                                                        transaction:transaction];

                for (NSString *messageId in self.messageIds) {
                    TSInteraction *_Nullable interaction = [TSInteraction anyFetchWithUniqueId:messageId
                                                                                   transaction:transaction];
                    if (interaction == nil) {
                        OWSLogWarn(@"Missing interaction.");
                        continue;
                    }
                    [self.databaseStorage touchInteraction:interaction shouldReindex:false transaction:transaction];
                }
            });
            self.completedUpload = attachmentStream;
            [self reportSuccess];
        })
        .catchInBackground(^(NSError *error) {
            OWSLogError(@"Failed: %@", error);

            if (error.httpStatusCode.intValue == 413) {
                OWSFailDebug(@"Request entity too large: %@.", @(attachmentStream.byteCount));
                [self reportError:[OWSUnretryableMessageSenderError asNSError]];
            } else if (error.isNetworkConnectivityFailure) {
                [self reportError:error];
            } else {
                OWSFailDebug(@"Unexpected error: %@", error);
                [self reportError:error];
            }
        });
}

- (void)fireNotificationWithProgress:(CGFloat)progress
{
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

    [notificationCenter postNotificationNameAsync:kAttachmentUploadProgressNotification
                                           object:nil
                                         userInfo:@{
                                             kAttachmentUploadProgressKey : @(progress),
                                             kAttachmentUploadAttachmentIDKey : self.attachmentId
                                         }];
}

@end

NS_ASSUME_NONNULL_END
