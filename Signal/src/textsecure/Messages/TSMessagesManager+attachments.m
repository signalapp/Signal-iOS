//
//  TSMessagesManager+attachments.m
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "NSDate+millisecondTimeStamp.h"
#import <YapDatabase/YapDatabaseConnection.h>

#import "Cryptography.h"

#import "TSAllocAttachmentRequest.h"
#import "TSAttachmentEncryptionResult.h"
#import "TSAttachmentPointer.h"
#import "TSAttachmentStream.h"
#import "TSAttachmentRequest.h"
#import "TSConstants.h"
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

- (void)handleReceivedMediaMessage:(IncomingPushMessageSignal*)message withContent:(PushMessageContent*)content {
    NSArray *attachmentsToRetrieve = content.group ?  [NSArray arrayWithObject:content.group.avatar] : content.attachments;

    NSMutableArray *retrievedAttachments = [NSMutableArray array];
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (PushMessageContentAttachmentPointer *pointer in attachmentsToRetrieve) {
            TSAttachmentPointer *attachmentPointer = content.group ? [[TSAttachmentPointer alloc] initWithIdentifier:pointer.id key:pointer.key contentType:pointer.contentType relay:message.relay avatarOfGroupId:content.group.id] : [[TSAttachmentPointer alloc] initWithIdentifier:pointer.id key:pointer.key contentType:pointer.contentType relay:message.relay];
            [attachmentPointer saveWithTransaction:transaction];
            dispatch_async(attachmentsQueue(), ^{
                [self retrieveAttachment:attachmentPointer];
            });
            [retrievedAttachments addObject:attachmentPointer.uniqueId];
        }
    }];
    
    [self handleReceivedMessage:message withContent:content attachments:retrievedAttachments];
}








- (void)sendAttachment:(NSData*)attachmentData contentType:(NSString*)contentType inMessage:(TSOutgoingMessage*)outgoingMessage thread:(TSThread*)thread {
    
    TSRequest *allocateAttachment = [[TSAllocAttachmentRequest alloc] init];
    [[TSNetworkManager sharedManager] queueAuthenticatedRequest:allocateAttachment success:^(NSURLSessionDataTask *task, id responseObject) {
        dispatch_async(attachmentsQueue(), ^{
            if ([responseObject isKindOfClass:[NSDictionary class]]){
                NSDictionary *responseDict = (NSDictionary*)responseObject;
                NSString *attachementId    = [[responseDict objectForKey:@"id"] stringValue];
                NSString *location         = [responseDict objectForKey:@"location"];
                
                TSAttachmentEncryptionResult *result =
                [Cryptography encryptAttachment:attachmentData contentType:contentType identifier:attachementId];
                
                BOOL success = [self uploadData:result.body location:location];
                
                if (success) {
                    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                        [result.pointer saveWithTransaction:transaction];
                    }];
                    [outgoingMessage.attachments addObject:attachementId];
                    [self sendMessage:outgoingMessage inThread:thread];
                } else{
                    DDLogWarn(@"Failed to upload attachment");
                }
            } else{
                DDLogError(@"The server didn't returned an empty responseObject");
            }
        });
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        DDLogError(@"Failed to get attachment allocated: %@", error);
    }];

    
    
}

- (void)sendAttachment:(NSData*)attachmentData contentType:(NSString*)contentType thread:(TSThread*)thread {
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:thread messageBody:nil attachments:[[NSMutableArray alloc] init]];
    [self sendAttachment:attachmentData contentType:contentType inMessage:message thread:thread];
}

- (void)retrieveAttachment:(TSAttachmentPointer*)attachment {
    
    TSAttachmentRequest *attachmentRequest = [[TSAttachmentRequest alloc] initWithId:[attachment identifier]
                                                                                  relay:attachment.relay];
    
    [[TSNetworkManager sharedManager] queueAuthenticatedRequest:attachmentRequest success:^(NSURLSessionDataTask *task, id responseObject) {
        if ([responseObject isKindOfClass:[NSDictionary class]]) {
            NSString *location = [(NSDictionary*)responseObject objectForKey:@"location"];
            NSData *data = [self downloadFromLocation:location];
            if (data) {
                dispatch_async(attachmentsQueue(), ^{
                    [self decryptedAndSaveAttachment:attachment data:data];
                });
            }
            
        }
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        DDLogError(@"Failed task %@ error: %@", task.description, error.description);
    }];
}

- (void)decryptedAndSaveAttachment:(TSAttachmentPointer*)attachment data:(NSData*)cipherText {
    NSData *plaintext = [Cryptography decryptAttachment:cipherText withKey:attachment.encryptionKey];
    
    if (!plaintext) {
        DDLogError(@"Failed to get attachment decrypted ...");
    } else {
        TSAttachmentStream *stream = [[TSAttachmentStream alloc] initWithIdentifier:attachment.uniqueId
                                                                                 data:plaintext key:attachment.encryptionKey
                                                                          contentType:attachment.contentType];
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [stream saveWithTransaction:transaction];
            if(attachment.avatarOfGroupId!=nil) {
                GroupModel *emptyModelToFillOutId = [[GroupModel alloc] initWithTitle:nil memberIds:nil image:nil groupId:attachment.avatarOfGroupId]; // TODO refactor the TSGroupThread to just take in an ID (as it is all that it uses). Should not take in more than it uses
                TSGroupThread* gThread = [TSGroupThread getOrCreateThreadWithGroupModel:emptyModelToFillOutId transaction:transaction];
                gThread.groupModel.groupImage=[stream image];
                [gThread saveWithTransaction:transaction];
            
            }
        }];
    }
}

- (NSData*)downloadFromLocation:(NSString*)location {
    __block NSData *data;
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    manager.completionQueue    = attachmentsQueue();
    manager.requestSerializer  = [AFHTTPRequestSerializer serializer];
    [manager.requestSerializer setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [manager GET:location parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        data = responseObject;
        dispatch_semaphore_signal(sema);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        DDLogError(@"Failed to retreive attachment with error: %@", error.description);
        dispatch_semaphore_signal(sema);
    }];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    
    return data;
}

- (BOOL)uploadData:(NSData*)cipherText location:(NSString*)location {
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block BOOL success = NO;
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:location]];
    request.HTTPMethod = @"PUT";
    request.HTTPBody   = cipherText;
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    
    AFHTTPRequestOperation *httpOperation = [manager HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
        success = YES;
        dispatch_semaphore_signal(sema);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        DDLogError(@"Failed uploading attachment with error: %@", error.description);
        success = NO;
        dispatch_semaphore_signal(sema);
    }];
    
    [httpOperation start];
    
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    
    return success;
}

@end
