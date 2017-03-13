//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSAttachmentsProcessor.h"
#import "Cryptography.h"
#import "MIMETypeUtil.h"
#import "OWSError.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSAttachmentPointer.h"
#import "TSAttachmentRequest.h"
#import "TSAttachmentStream.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import "TSInfoMessage.h"
#import "TSMessage.h"
#import "TSNetworkManager.h"
#import "TSThread.h"
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSAttachmentsProcessor ()

@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) NSArray<TSAttachmentPointer *> *supportedAttachmentPointers;

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

    _supportedAttachmentPointers = @[ attachmentPointer ];
    _supportedAttachmentIds = @[ attachmentPointer.uniqueId ];

    return self;
}

- (instancetype)initWithAttachmentProtos:(NSArray<OWSSignalServiceProtosAttachmentPointer *> *)attachmentProtos
                               timestamp:(uint64_t)timestamp
                                   relay:(nullable NSString *)relay
                                  thread:(TSThread *)thread
                          networkManager:(TSNetworkManager *)networkManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _networkManager = networkManager;

    NSMutableArray<NSString *> *attachmentIds = [NSMutableArray new];
    NSMutableArray<TSAttachmentPointer *> *supportedAttachmentPointers = [NSMutableArray new];
    NSMutableArray<NSString *> *supportedAttachmentIds = [NSMutableArray new];

    for (OWSSignalServiceProtosAttachmentPointer *attachmentProto in attachmentProtos) {
        TSAttachmentPointer *pointer = [[TSAttachmentPointer alloc] initWithServerId:attachmentProto.id
                                                                                 key:attachmentProto.key
                                                                              digest:attachmentProto.digest
                                                                         contentType:attachmentProto.contentType
                                                                               relay:relay];

        [attachmentIds addObject:pointer.uniqueId];

        if ([MIMETypeUtil isSupportedMIMEType:pointer.contentType]) {
            [pointer save];
            [supportedAttachmentPointers addObject:pointer];
            [supportedAttachmentIds addObject:pointer.uniqueId];
        } else {
            DDLogError(@"%@ Received unsupported attachment of type: %@", self.tag, pointer.contentType);
            TSInfoMessage *infoMessage = [[TSInfoMessage alloc] initWithTimestamp:timestamp
                                                                         inThread:thread
                                                                      messageType:TSInfoMessageTypeUnsupportedMessage];
            [infoMessage save];
        }
    }

    _attachmentIds = [attachmentIds copy];
    _supportedAttachmentPointers = [supportedAttachmentPointers copy];
    _supportedAttachmentIds = [supportedAttachmentIds copy];

    return self;
}

- (void)fetchAttachmentsForMessage:(nullable TSMessage *)message
                           success:(void (^)(TSAttachmentStream *attachmentStream))successHandler
                           failure:(void (^)(NSError *error))failureHandler
{
    for (TSAttachmentPointer *attachmentPointer in self.supportedAttachmentPointers) {
        [self retrieveAttachment:attachmentPointer message:message success:successHandler failure:failureHandler];
    }
}

- (void)retrieveAttachment:(TSAttachmentPointer *)attachment
                   message:(nullable TSMessage *)message
                   success:(void (^)(TSAttachmentStream *attachmentStream))successHandler
                   failure:(void (^)(NSError *error))failureHandler
{
    [self setAttachment:attachment isDownloadingInMessage:message];

    void (^markAndHandleFailure)(NSError *) = ^(NSError *error) {
        [self setAttachment:attachment didFailInMessage:message];
        return failureHandler(error);
    };

    void (^markAndHandleSuccess)(TSAttachmentStream *attachmentStream) = ^(TSAttachmentStream *attachmentStream) {
        successHandler(attachmentStream);
        if (message) {
            [message touch];
        }
    };

    if (attachment.serverId < 100) {
        DDLogError(@"%@ Suspicious attachment id: %llu", self.tag, (unsigned long long)attachment.serverId);
    }
    TSAttachmentRequest *attachmentRequest = [[TSAttachmentRequest alloc] initWithId:attachment.serverId relay:attachment.relay];

    [self.networkManager makeRequest:attachmentRequest
                             success:^(NSURLSessionDataTask *task, id responseObject) {
                                 if (![responseObject isKindOfClass:[NSDictionary class]]) {
                                     DDLogError(@"%@ Failed retrieval of attachment. Response had unexpected format.",
                                         self.tag);
                                     NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                                     return markAndHandleFailure(error);
                                 }
                                 NSString *location = [(NSDictionary *)responseObject objectForKey:@"location"];
                                 if (!location) {
                                     DDLogError(
                                         @"%@ Failed retrieval of attachment. Response had no location.", self.tag);
                                     NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                                     return markAndHandleFailure(error);
                                 }

                                 dispatch_async([OWSDispatch attachmentsQueue], ^{
                                     [self downloadFromLocation:location
                                         pointer:attachment
                                         success:^(NSData *_Nonnull encryptedData) {
                                             [self decryptAttachmentData:encryptedData
                                                                 pointer:attachment
                                                                 success:markAndHandleSuccess
                                                                 failure:markAndHandleFailure];
                                         }
                                         failure:^(NSURLSessionDataTask *_Nullable task, NSError *_Nonnull error) {
                                             if (attachment.serverId < 100) {
                                                 // This looks like the symptom of the "frequent 404
                                                 // downloading attachments with low server ids".
                                                 NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
                                                 NSInteger statusCode = [httpResponse statusCode];
                                                 DDLogError(@"%@ %d Failure with suspicious attachment id: %llu, %@",
                                                     self.tag,
                                                     (int)statusCode,
                                                     (unsigned long long)attachment.serverId,
                                                     error);
                                                 [DDLog flushLog];
                                                 OWSAssert(0);
                                             }
                                             if (markAndHandleFailure) {
                                                 markAndHandleFailure(error);
                                             }
                                         }];
                                 });
                             }
                             failure:^(NSURLSessionDataTask *task, NSError *error) {
                                 DDLogError(@"Failed retrieval of attachment with error: %@", error);
                                 if (attachment.serverId < 100) {
                                     // This _shouldn't_ be the symptom of the "frequent 404
                                     // downloading attachments with low server ids".
                                     NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
                                     NSInteger statusCode = [httpResponse statusCode];
                                     DDLogError(@"%@ %d Failure with suspicious attachment id: %llu, %@",
                                         self.tag,
                                         (int)statusCode,
                                         (unsigned long long)attachment.serverId,
                                         error);
                                     [DDLog flushLog];
                                     OWSAssert(0);
                                 }
                                 return markAndHandleFailure(error);
                             }];
}

- (void)decryptAttachmentData:(NSData *)cipherText
                      pointer:(TSAttachmentPointer *)attachment
                      success:(void (^)(TSAttachmentStream *attachmentStream))successHandler
                      failure:(void (^)(NSError *error))failureHandler
{
    NSData *plaintext =
        [Cryptography decryptAttachment:cipherText withKey:attachment.encryptionKey digest:attachment.digest];

    if (!plaintext) {
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, NSLocalizedString(@"ERROR_MESSAGE_INVALID_MESSAGE", @""));
        return failureHandler(error);
    }

    TSAttachmentStream *stream = [[TSAttachmentStream alloc] initWithPointer:attachment];

    NSError *error;
    [stream writeData:plaintext error:&error];
    if (error) {
        DDLogError(@"%@ Failed writing attachment stream with error: %@", self.tag, error);
        return failureHandler(error);
    }

    [stream save];
    successHandler(stream);
}

- (void)downloadFromLocation:(NSString *)location
                     pointer:(TSAttachmentPointer *)pointer
                     success:(void (^)(NSData *encryptedData))successHandler
                     failure:(void (^)(NSURLSessionDataTask *_Nullable task, NSError *_Nonnull error))failureHandler
{
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.requestSerializer     = [AFHTTPRequestSerializer serializer];
    [manager.requestSerializer setValue:OWSMimeTypeApplicationOctetStream forHTTPHeaderField:@"Content-Type"];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    manager.completionQueue    = dispatch_get_main_queue();

    // TODO stream this download rather than storing the entire blob.
    [manager GET:location
      parameters:nil
        progress:nil // TODO show some progress!
         success:^(NSURLSessionDataTask *_Nonnull task, id _Nullable responseObject) {
             if (![responseObject isKindOfClass:[NSData class]]) {
                 DDLogError(@"%@ Failed retrieval of attachment. Response had unexpected format.", self.tag);
                 NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                 return failureHandler(task, error);
             }
             successHandler((NSData *)responseObject);
         }
         failure:^(NSURLSessionDataTask *_Nullable task, NSError *_Nonnull error) {
             DDLogError(@"Failed to retrieve attachment with error: %@", error.description);
             return failureHandler(task, error);
         }];
}

- (void)setAttachment:(TSAttachmentPointer *)pointer isDownloadingInMessage:(nullable TSMessage *)message
{
    pointer.downloading = YES;
    [pointer save];
    if (message) {
        [message touch];
    }
}

- (void)setAttachment:(TSAttachmentPointer *)pointer didFailInMessage:(nullable TSMessage *)message
{
    pointer.downloading = NO;
    pointer.failed = YES;
    [pointer save];
    if (message) {
        [message touch];
    }
}

- (BOOL)hasSupportedAttachments
{
    return self.supportedAttachmentPointers.count > 0;
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
