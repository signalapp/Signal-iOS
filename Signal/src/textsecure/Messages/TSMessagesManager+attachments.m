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

#import "TSConstants.h"
#import "TSMessagesManager+attachments.h"
#import "TSAttachmentRequest.h"
#import "TSUploadAttachment.h"
#import "TSInfoMessage.h"
#import "TSattachmentPointer.h"
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
    NSMutableArray *attachments = [NSMutableArray array];
    
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (PushMessageContentAttachmentPointer *pointer in content.attachments) {
            TSAttachmentPointer *attachmentPointer = [[TSAttachmentPointer alloc] initWithIdentifier:pointer.id key:pointer.key contentType:pointer.contentType relay:message.relay];
            [attachmentPointer saveWithTransaction:transaction];
            dispatch_async(attachmentsQueue(), ^{
                [self retrieveAttachment:attachmentPointer];
            });
            [attachments addObject:attachmentPointer.uniqueId];
        }
    }];
    
    [self handleReceivedMessage:message withContent:content attachments:attachments];
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
        }];
        NSLog(@"We got %@ of type %@", plaintext, attachment.contentType);
    }
    
}

@end
