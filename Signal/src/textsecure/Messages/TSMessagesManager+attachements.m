//
//  TSMessagesManager+attachements.m
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "NSDate+millisecondTimeStamp.h"
#import <YapDatabase/YapDatabaseConnection.h>

#import "Cryptography.h"

#import "TSConstants.h"
#import "TSMessagesManager+attachements.h"
#import "TSAttachementRequest.h"
#import "TSUploadAttachment.h"
#import "TSInfoMessage.h"
#import "TSAttachementPointer.h"
#import "TSNetworkManager.h"

@interface TSMessagesManager ()

dispatch_queue_t attachementsQueue(void);

@end

dispatch_queue_t attachementsQueue() {
    static dispatch_once_t queueCreationGuard;
    static dispatch_queue_t queue;
    dispatch_once(&queueCreationGuard, ^{
        queue = dispatch_queue_create("org.whispersystems.signal.attachements", NULL);
    });
    return queue;
}

@implementation TSMessagesManager (attachements)

- (void)handleReceivedMediaMessage:(IncomingPushMessageSignal*)message withContent:(PushMessageContent*)content {
    NSMutableArray *attachements = [NSMutableArray array];
    
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (PushMessageContentAttachmentPointer *pointer in content.attachments) {
            TSAttachementPointer *attachementPointer = [[TSAttachementPointer alloc] initWithIdentifier:pointer.id key:pointer.key contentType:pointer.contentType relay:message.relay];
            [attachementPointer saveWithTransaction:transaction];
            dispatch_async(attachementsQueue(), ^{
                [self retrieveAttachment:attachementPointer];
            });
            [attachements addObject:attachementPointer.uniqueId];
        }
    }];
    
    [self handleReceivedMessage:message withContent:content attachements:attachements];
}

- (void)retrieveAttachment:(TSAttachementPointer*)attachement {
    
    TSAttachementRequest *attachementRequest = [[TSAttachementRequest alloc] initWithId:[attachement identifier]
                                                                                  relay:attachement.relay];
    
    [[TSNetworkManager sharedManager] queueAuthenticatedRequest:attachementRequest success:^(NSURLSessionDataTask *task, id responseObject) {
        if ([responseObject isKindOfClass:[NSDictionary class]]) {
            NSString *location = [(NSDictionary*)responseObject objectForKey:@"location"];
            NSData *data = [self downloadFromLocation:location];
            if (data) {
                dispatch_async(attachementsQueue(), ^{
                    [self decryptedAndSaveAttachement:attachement data:data];
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
    manager.completionQueue    = attachementsQueue();
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

- (void)decryptedAndSaveAttachement:(TSAttachementPointer*)attachement data:(NSData*)cipherText {
    NSData *plaintext = [Cryptography decryptAttachment:cipherText withKey:attachement.encryptionKey];
    
    if (!plaintext) {
        DDLogError(@"Failed to get attachement decrypted ...");
    } else {
        TSAttachementStream *stream = [[TSAttachementStream alloc] initWithIdentifier:attachement.uniqueId
                                                                                 data:plaintext key:attachement.encryptionKey
                                                                          contentType:attachement.contentType];
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [stream saveWithTransaction:transaction];
        }];
        NSLog(@"We got %@ of type %@", plaintext, attachement.contentType);
    }
    
}

@end
