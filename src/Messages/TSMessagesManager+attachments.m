//
//  TSMessagesManager+attachments.m
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <YapDatabase/YapDatabaseConnection.h>
#import "Cryptography.h"
#import "MIMETypeUtil.h"
#import "NSDate+millisecondTimeStamp.h"
#import "TSAttachmentPointer.h"
#import "TSInfoMessage.h"
#import "TSMessagesManager+attachments.h"
#import "TSMessagesManager+sendMessages.h"
#import "TSNetworkManager.h"

@interface TSMessagesManager ()

dispatch_queue_t attachmentsQueue(void);

@end

dispatch_queue_t attachmentsQueue() {
    static dispatch_once_t queueCreationGuard;
    static dispatch_queue_t queue;
    dispatch_once(&queueCreationGuard, ^{
      queue = dispatch_queue_create("org.whispersystems.signal.attachments", NULL);
    });
    return queue;
}

@implementation TSMessagesManager (attachments)

- (void)handleReceivedMediaMessage:(IncomingPushMessageSignal *)message withContent:(PushMessageContent *)content {
    NSArray *attachmentsToRetrieve =
        (content.group != nil && (content.group.type == PushMessageContentGroupContextTypeUpdate))
            ? [NSArray arrayWithObject:content.group.avatar]
            : content.attachments;

    NSMutableArray *retrievedAttachments = [NSMutableArray array];
    __block BOOL shouldProcessMessage    = YES;
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      for (PushMessageContentAttachmentPointer *pointer in attachmentsToRetrieve) {
          TSAttachmentPointer *attachmentPointer =
              (content.group != nil && (content.group.type == PushMessageContentGroupContextTypeUpdate))
                  ? [[TSAttachmentPointer alloc] initWithIdentifier:pointer.id
                                                                key:pointer.key
                                                        contentType:pointer.contentType
                                                              relay:message.relay
                                                    avatarOfGroupId:content.group.id]
                  : [[TSAttachmentPointer alloc] initWithIdentifier:pointer.id
                                                                key:pointer.key
                                                        contentType:pointer.contentType
                                                              relay:message.relay];

          if ([MIMETypeUtil isSupportedMIMEType:attachmentPointer.contentType]) {
              [attachmentPointer saveWithTransaction:transaction];
              [retrievedAttachments addObject:attachmentPointer.uniqueId];
              shouldProcessMessage = YES;
          } else {
              TSThread *thread =
                  [TSContactThread getOrCreateThreadWithContactId:message.source transaction:transaction];
              TSInfoMessage *infoMessage =
                  [[TSInfoMessage alloc] initWithTimestamp:message.timestamp
                                                  inThread:thread
                                               messageType:TSInfoMessageTypeUnsupportedMessage];
              [infoMessage saveWithTransaction:transaction];
              shouldProcessMessage = NO;
          }
      }
    }];

    if (shouldProcessMessage) {
        [self handleReceivedMessage:message
                        withContent:content
                        attachments:retrievedAttachments
                    completionBlock:^(NSString *messageIdentifier) {
                      for (NSString *pointerId in retrievedAttachments) {
                          dispatch_async(attachmentsQueue(), ^{
                            __block TSAttachmentPointer *pointer;

                            [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                              pointer = [TSAttachmentPointer fetchObjectWithUniqueID:pointerId transaction:transaction];
                            }];

                            [self retrieveAttachment:pointer messageId:messageIdentifier];
                          });
                      }
                    }];
    }
}

- (void)sendAttachment:(NSData *)attachmentData
           contentType:(NSString *)contentType
             inMessage:(TSOutgoingMessage *)outgoingMessage
                thread:(TSThread *)thread {
    TSRequest *allocateAttachment = [[TSAllocAttachmentRequest alloc] init];
    [[TSNetworkManager sharedManager] makeRequest:allocateAttachment
        success:^(NSURLSessionDataTask *task, id responseObject) {
          dispatch_async(attachmentsQueue(), ^{
            if ([responseObject isKindOfClass:[NSDictionary class]]) {
                NSDictionary *responseDict = (NSDictionary *)responseObject;
                NSString *attachementId    = [(NSNumber *)[responseDict objectForKey:@"id"] stringValue];
                NSString *location         = [responseDict objectForKey:@"location"];

                TSAttachmentEncryptionResult *result =
                    [Cryptography encryptAttachment:attachmentData contentType:contentType identifier:attachementId];
                [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                  result.pointer.isDownloaded = NO;
                  [result.pointer saveWithTransaction:transaction];
                }];
                outgoingMessage.body = nil;
                [outgoingMessage.attachments addObject:attachementId];
                if (outgoingMessage.groupMetaMessage != TSGroupMessageNew &&
                    outgoingMessage.groupMetaMessage != TSGroupMessageUpdate) {
                    [outgoingMessage setMessageState:TSOutgoingMessageStateAttemptingOut];
                    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                      [outgoingMessage saveWithTransaction:transaction];
                    }];
                }
                BOOL success = [self uploadDataWithProgress:result.body location:location attachmentID:attachementId];
                if (success) {
                    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                      result.pointer.isDownloaded = YES;
                      [result.pointer saveWithTransaction:transaction];
                    }];
                    [self sendMessage:outgoingMessage inThread:thread success:nil failure:nil];
                } else {
                    DDLogWarn(@"Failed to upload attachment");
                }
            } else {
                DDLogError(@"The server didn't returned an empty responseObject");
            }
          });
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
          DDLogError(@"Failed to get attachment allocated: %@", error);
        }];
}

- (void)sendAttachment:(NSData *)attachmentData contentType:(NSString *)contentType thread:(TSThread *)thread {
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                     inThread:thread
                                                                  messageBody:nil
                                                                  attachments:[[NSMutableArray alloc] init]];
    [self sendAttachment:attachmentData contentType:contentType inMessage:message thread:thread];
}

- (void)retrieveAttachment:(TSAttachmentPointer *)attachment messageId:(NSString *)messageId {
    [self setAttachment:attachment isDownloadingInMessage:messageId];

    TSAttachmentRequest *attachmentRequest =
        [[TSAttachmentRequest alloc] initWithId:[attachment identifier] relay:attachment.relay];

    [[TSNetworkManager sharedManager] makeRequest:attachmentRequest
        success:^(NSURLSessionDataTask *task, id responseObject) {
          if ([responseObject isKindOfClass:[NSDictionary class]]) {
              dispatch_async(attachmentsQueue(), ^{
                NSString *location = [(NSDictionary *)responseObject objectForKey:@"location"];

                NSData *data = [self downloadFromLocation:location pointer:attachment messageId:messageId];
                if (data) {
                    [self decryptedAndSaveAttachment:attachment data:data messageId:messageId];
                }
              });
          }
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
          DDLogError(@"Failed retrieval of attachment with error: %@", error.description);
          [self setFailedAttachment:attachment inMessage:messageId];
        }];
}

- (void)setAttachment:(TSAttachmentPointer *)pointer isDownloadingInMessage:(NSString *)messageId {
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      [pointer setDownloading:YES];
      [pointer saveWithTransaction:transaction];
      TSMessage *message = [TSMessage fetchObjectWithUniqueID:messageId transaction:transaction];
      [message saveWithTransaction:transaction];
    }];
}

- (void)setFailedAttachment:(TSAttachmentPointer *)pointer inMessage:(NSString *)messageId {
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      [pointer setDownloading:NO];
      [pointer setFailed:YES];
      [pointer saveWithTransaction:transaction];
      TSMessage *message = [TSMessage fetchObjectWithUniqueID:messageId transaction:transaction];
      [message saveWithTransaction:transaction];
    }];
}

- (void)decryptedAndSaveAttachment:(TSAttachmentPointer *)attachment
                              data:(NSData *)cipherText
                         messageId:(NSString *)messageId {
    NSData *plaintext = [Cryptography decryptAttachment:cipherText withKey:attachment.encryptionKey];

    if (!plaintext) {
        DDLogError(@"Failed to get attachment decrypted ...");
    } else {
        TSAttachmentStream *stream = [[TSAttachmentStream alloc] initWithIdentifier:attachment.uniqueId
                                                                               data:plaintext
                                                                                key:attachment.encryptionKey
                                                                        contentType:attachment.contentType];

        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
          [stream saveWithTransaction:transaction];
          if ([attachment.avatarOfGroupId length] != 0) {
              TSGroupModel *emptyModelToFillOutId = [[TSGroupModel alloc]
                           initWithTitle:nil
                               memberIds:nil
                                   image:nil
                                 groupId:attachment.avatarOfGroupId
                  associatedAttachmentId:attachment.uniqueId]; // TODO refactor the TSGroupThread to just take in an ID
                                                               // (as it is all that it uses). Should not take in more
                                                               // than it uses
              TSGroupThread *gThread =
                  [TSGroupThread getOrCreateThreadWithGroupModel:emptyModelToFillOutId transaction:transaction];
              gThread.groupModel.groupImage = [stream image];
              [gThread saveWithTransaction:transaction];
          } else {
              // Causing message to be reloaded in view.
              TSMessage *message = [TSMessage fetchObjectWithUniqueID:messageId transaction:transaction];
              [message saveWithTransaction:transaction];
          }
        }];
    }
}

- (NSData *)downloadFromLocation:(NSString *)location
                         pointer:(TSAttachmentPointer *)pointer
                       messageId:(NSString *)messageId {
    __block NSData *data;

    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.requestSerializer     = [AFHTTPRequestSerializer serializer];
    [manager.requestSerializer setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    manager.completionQueue    = dispatch_get_main_queue();

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    [manager GET:location
        parameters:nil
        progress:nil
        success:^(NSURLSessionDataTask *_Nonnull task, id _Nullable responseObject) {
          data = responseObject;
          dispatch_semaphore_signal(sema);
        }
        failure:^(NSURLSessionDataTask *_Nullable task, NSError *_Nonnull error) {
          DDLogError(@"Failed to retrieve attachment with error: %@", error.description);
          if (pointer && messageId) {
              [self setFailedAttachment:pointer inMessage:messageId];
          }
          dispatch_semaphore_signal(sema);
        }];

    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

    return data;
}

- (BOOL)uploadDataWithProgress:(NSData *)cipherText
                      location:(NSString *)location
                  attachmentID:(NSString *)attachmentID {
    // AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    // manager.responseSerializer    = [AFHTTPResponseSerializer serializer];
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block BOOL success      = NO;

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:location]];
    request.HTTPMethod           = @"PUT";
    request.HTTPBody             = cipherText;
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];

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
                                              @"attachmentID" : attachmentID
                                          }];
        }
        completionHandler:^(NSURLResponse *_Nonnull response, id _Nullable responseObject, NSError *_Nullable error) {
          NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
          BOOL isValidResponse = (statusCode >= 200) && (statusCode < 400);
          if (!error && isValidResponse) {
              success = YES;
              dispatch_semaphore_signal(sema);
          } else {
              DDLogError(@"Failed uploading attachment with error: %@", error.description);
              success = NO;
              dispatch_semaphore_signal(sema);
          }
        }];

    [uploadTask resume];

    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

    return success;
}

@end
