//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSAttachmentDownloads.h"
#import "AppContext.h"
#import "MIMETypeUtil.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSBackgroundTask.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSDispatch.h"
#import "OWSError.h"
#import "OWSFileSystem.h"
#import "OWSRequestFactory.h"
#import "ProfileManagerProtocol.h"
#import "SSKEnvironment.h"
#import "TSAttachmentPointer.h"
#import "TSAttachmentStream.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import "TSInfoMessage.h"
#import "TSMessage.h"
#import "TSNetworkManager.h"
#import "TSThread.h"
#import <AFNetworking/AFHTTPSessionManager.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

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

- (id<ProfileManagerProtocol>)profileManager
{
    return SSKEnvironment.shared.profileManager;
}

#pragma mark -

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    _downloadingJobMap = [NSMutableDictionary new];
    _attachmentDownloadJobQueue = [NSMutableArray new];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileWhitelistDidChange:)
                                                 name:kNSNotificationNameProfileWhitelistDidChange
                                               object:nil];

    return self;
}

#pragma mark -

- (void)profileWhitelistDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        SignalServiceAddress *_Nullable address = notification.userInfo[kNSNotificationKey_ProfileAddress];
        NSData *_Nullable groupId = notification.userInfo[kNSNotificationKey_ProfileGroupId];

        TSThread *_Nullable whitelistedThread;

        if (address.isValid) {
            if ([self.profileManager isUserInProfileWhitelist:address transaction:transaction]) {
                whitelistedThread = [TSContactThread getThreadWithContactAddress:address transaction:transaction];
            }
        } else if (groupId.length > 0) {
            if ([self.profileManager isGroupIdInProfileWhitelist:groupId transaction:transaction]) {
                whitelistedThread = [TSGroupThread fetchWithGroupId:groupId transaction:transaction];
            }
        }

        // If the thread was newly whitelisted, try and start any
        // downloads that were pending on a message request.
        if (whitelistedThread) {
            [self downloadAllAttachmentsForThread:whitelistedThread
                transaction:transaction
                success:^(NSArray<TSAttachmentStream *> *attachmentStreams) {
                    OWSLogDebug(
                        @"Successfully downloaded %ld attachments for whitelisted thread.", attachmentStreams.count);
                }
                failure:^(NSError *error) {
                    OWSFailDebug(@"Failed to download attachments for whitelisted thread: %@", error);
                }];
        }
    }];
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

- (void)downloadAllAttachmentsForThread:(TSThread *)thread
                            transaction:(SDSAnyReadTransaction *)transaction
                                success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))successHandler
                                failure:(void (^)(NSError *error))failureHandler
{
    NSMutableArray<TSAttachmentStream *> *attachmentStreams = [NSMutableArray new];
    NSMutableArray<AnyPromise *> *promises = [NSMutableArray array];

    GRDBInteractionFinder *finder = [[GRDBInteractionFinder alloc] initWithThreadUniqueId:thread.uniqueId];
    [finder
        enumerateMessagesWithAttachmentsWithTransaction:transaction.unwrapGrdbRead
                                                  error:nil
                                                  block:^(TSMessage *message, BOOL *stop) {
                                                      AnyPromise *promise = [AnyPromise promiseWithResolverBlock:^(
                                                          PMKResolver resolve) {
                                                          [self downloadAttachmentsForMessage:message
                                                              bypassPendingMessageRequest:NO
                                                              attachments:[message allAttachmentsWithTransaction:
                                                                                       transaction.unwrapGrdbRead]
                                                              success:^(NSArray<TSAttachmentStream *> *streams) {
                                                                  @synchronized(attachmentStreams) {
                                                                      [attachmentStreams addObjectsFromArray:streams];
                                                                  }

                                                                  resolve(@(1));
                                                              }
                                                              failure:^(NSError *error) {
                                                                  resolve(error);
                                                              }];
                                                      }];
                                                      [promises addObject:promise];
                                                  }];

    // We use PMKJoin(), not PMKWhen(), because we don't want the
    // completion promise to execute until _all_ promises
    // have either succeeded or failed. PMKWhen() executes as
    // soon as any of its input promises fail.
    PMKJoin(promises)
        .then(^(id value) {
            NSArray<TSAttachmentStream *> *attachmentStreamsCopy;
            @synchronized(attachmentStreams) {
                attachmentStreamsCopy = [attachmentStreams copy];
            }
            OWSLogInfo(@"Attachment downloads succeeded: %lu.", (unsigned long)attachmentStreamsCopy.count);

            dispatch_async(OWSAttachmentDownloads.serialQueue, ^{ successHandler(attachmentStreamsCopy); });
        })
        .catch(^(NSError *error) {
            OWSLogError(@"Attachment downloads failed.");

            dispatch_async(OWSAttachmentDownloads.serialQueue, ^{ failureHandler(error); });
        });
}

- (void)downloadAttachmentsForMessage:(TSMessage *)message
          bypassPendingMessageRequest:(BOOL)bypassPendingMessageRequest
                          attachments:(NSArray<TSAttachment *> *)attachments
                              success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))success
                              failure:(void (^)(NSError *error))failure
{
    OWSAssertDebug(message);
    OWSAssertDebug(attachments.count > 0);

    if (CurrentAppContext().isRunningTests) {
        dispatch_async(OWSAttachmentDownloads.serialQueue, ^{
            NSError *error = [OWSAttachmentDownloads buildError];
            failure(error);
        });
        return;
    }

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
              bypassPendingMessageRequest:bypassPendingMessageRequest
                                  success:success
                                  failure:failure];
}

- (void)downloadAttachmentPointer:(TSAttachmentPointer *)attachmentPointer
      bypassPendingMessageRequest:(BOOL)bypassPendingMessageRequest
                          success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))success
                          failure:(void (^)(NSError *error))failure
{
    [self downloadAttachmentPointer:attachmentPointer
                    nullableMessage:nil
        bypassPendingMessageRequest:bypassPendingMessageRequest
                            success:success
                            failure:failure];
}

- (void)downloadAttachmentPointer:(TSAttachmentPointer *)attachmentPointer
                          message:(TSMessage *)message
      bypassPendingMessageRequest:(BOOL)bypassPendingMessageRequest
                          success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))success
                          failure:(void (^)(NSError *error))failure
{
    OWSAssertDebug(message);

    [self downloadAttachmentPointer:attachmentPointer
                    nullableMessage:message
        bypassPendingMessageRequest:bypassPendingMessageRequest
                            success:success
                            failure:failure];
}

- (void)downloadAttachmentPointer:(TSAttachmentPointer *)attachmentPointer
                  nullableMessage:(nullable TSMessage *)message
      bypassPendingMessageRequest:(BOOL)bypassPendingMessageRequest
                          success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))success
                          failure:(void (^)(NSError *error))failure
{
    OWSAssertDebug(attachmentPointer);

    if (CurrentAppContext().isRunningTests) {
        dispatch_async(OWSAttachmentDownloads.serialQueue, ^{
            NSError *error = [OWSAttachmentDownloads buildError];
            failure(error);
        });
        return;
    }

    [self enqueueJobsForAttachmentStreams:@[]
                       attachmentPointers:@[
                           attachmentPointer,
                       ]
                                  message:message
              bypassPendingMessageRequest:bypassPendingMessageRequest
                                  success:success
                                  failure:failure];
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
    dispatch_async(OWSAttachmentDownloads.serialQueue, ^{
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
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            // Fetch latest to ensure we don't overwrite an attachment stream, resurrect an attachment, etc.
            TSAttachment *_Nullable attachment = [TSAttachment anyFetchWithUniqueId:job.attachmentId
                                                                        transaction:transaction];
            if (attachment == nil) {
                // This isn't necessarily a bug.  For example:
                //
                // * Receive an incoming message with an attachment.
                // * Kick off download of that attachment.
                // * Receive read receipt for that message, causing it to be disappeared immediately.
                // * Try to download that attachment - but it's missing.
                OWSFailDebug(@"Missing attachment.");
                return;
            }
            if (![attachment isKindOfClass:[TSAttachmentPointer class]]) {
                // This isn't necessarily a bug.
                //
                // * An attachment may have been enqueued for download multiple times by the user in some cases.
                OWSFailDebug(@"Unexpected attachment.");
                return;
            }
            attachmentPointer = (TSAttachmentPointer *)attachment;
            [attachmentPointer updateWithAttachmentPointerState:TSAttachmentPointerStateDownloading
                                                    transaction:transaction];

            if (job.message != nil) {
                [self reloadAndTouchLatestVersionOfMessage:job.message transaction:transaction];
            }
        });

        if (!attachmentPointer) {
            // Abort.
            [self tryToStartNextDownload];
            return;
        }

        [self retrieveAttachmentWithJob:job
            attachmentPointer:attachmentPointer
            success:^(TSAttachmentStream *attachmentStream) {
                OWSLogVerbose(@"Attachment download succeeded.");

                DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                    TSAttachmentPointer *_Nullable existingAttachment =
                        [TSAttachmentPointer anyFetchAttachmentPointerWithUniqueId:attachmentStream.uniqueId
                                                                       transaction:transaction];
                    if (existingAttachment == nil) {
                        OWSLogWarn(@"Attachment no longer exists.");
                        return;
                    }
                    if (![existingAttachment isKindOfClass:[TSAttachmentPointer class]]) {
                        OWSFailDebug(@"Unexpected attachment pointer class: %@", existingAttachment.class);
                    }
                    [attachmentPointer anyRemoveWithTransaction:transaction];
                    [attachmentStream anyInsertWithTransaction:transaction];

                    if (job.message != nil) {
                        [self reloadAndTouchLatestVersionOfMessage:job.message transaction:transaction];
                    }
                });

                job.success(attachmentStream);

                @synchronized(self) {
                    [self.downloadingJobMap removeObjectForKey:job.attachmentId];
                }

                [self tryToStartNextDownload];
            }
            failure:^(NSError *error) {
                OWSLogError(@"Attachment download failed with error: %@", error);

                DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                    // Fetch latest to ensure we don't overwrite an attachment stream, resurrect an attachment, etc.
                    TSAttachmentPointer *_Nullable attachmentPointer =
                        [TSAttachmentPointer anyFetchAttachmentPointerWithUniqueId:job.attachmentId
                                                                       transaction:transaction];
                    if (attachmentPointer == nil) {
                        OWSLogWarn(@"Attachment no longer exists.");
                        return;
                    }
                    [attachmentPointer updateWithAttachmentPointerState:TSAttachmentPointerStateFailed
                                                            transaction:transaction];

                    if (job.message != nil) {
                        [self reloadAndTouchLatestVersionOfMessage:job.message transaction:transaction];
                    }
                });

                @synchronized(self) {
                    [self.downloadingJobMap removeObjectForKey:job.attachmentId];
                }

                job.failure(error);

                [self tryToStartNextDownload];
            }];
    });
}

- (void)reloadAndTouchLatestVersionOfMessage:(TSMessage *)message transaction:(SDSAnyWriteTransaction *)transaction
{
    TSMessage *messageToNotify;
    if (message.sortId > 0) {
        messageToNotify = message;
    } else {
        // Ensure relevant sortId is loaded for touch to succeed.
        TSMessage *_Nullable latestMessage = [TSMessage anyFetchMessageWithUniqueId:message.uniqueId
                                                                        transaction:transaction];
        if (latestMessage == nil) {
            // This could be valid but should be very rare.
            OWSFailDebug(@"Message has been deleted.");
            return;
        }
        messageToNotify = latestMessage;
    }
    [self.databaseStorage touchInteraction:messageToNotify shouldReindex:YES transaction:transaction];
}

#pragma mark -

+ (NSError *)buildError
{
    return OWSErrorWithCodeDescription(OWSErrorCodeAttachmentDownloadFailed,
        NSLocalizedString(@"ERROR_MESSAGE_ATTACHMENT_DOWNLOAD_FAILED",
            @"Error message indicating that attachment download(s) failed."));
}

@end

NS_ASSUME_NONNULL_END
