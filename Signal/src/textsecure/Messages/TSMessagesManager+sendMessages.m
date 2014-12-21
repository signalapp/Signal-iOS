//
//  TSMessagesManager+sendMessages.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 17/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessagesManager+sendMessages.h"

#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/SessionCipher.h>
#import <AxolotlKit/SessionBuilder.h>
#import <Mantle/Mantle.h>

#import "IncomingPushMessageSignal.pb.h"
#import "TSStorageManager.h"
#import "TSStorageManager+SessionStore.h"
#import "TSStorageManager+IdentityKeyStore.h"
#import "TSStorageManager+PreKeyStore.h"
#import "TSStorageManager+SignedPreKeyStore.h"

#import "PreKeyBundle+jsonDict.h"

#import "TSAttachmentStream.h"
#import "TSNetworkManager.h"
#import "TSServerMessage.h"
#import "TSSubmitMessageRequest.h"
#import "TSRecipientPrekeyRequest.h"

#import "TSErrorMessage.h"
#import "TSInfoMessage.h"

#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSRecipient.h"

@interface TSMessagesManager ()
dispatch_queue_t sendingQueue(void);
@end

typedef void (^messagesQueue)(NSArray *messages);

@implementation TSMessagesManager (sendMessages)

dispatch_queue_t sendingQueue() {
    static dispatch_once_t queueCreationGuard;
    static dispatch_queue_t queue;
    dispatch_once(&queueCreationGuard, ^{
        queue = dispatch_queue_create("org.whispersystems.signal.sendQueue", NULL);
    });
    return queue;
}

- (void)sendMessage:(TSOutgoingMessage*)message inThread:(TSThread*)thread{
    [self saveMessage:message withState:TSOutgoingMessageStateAttemptingOut];
    
    dispatch_async(sendingQueue(), ^{
        if ([thread isKindOfClass:[TSGroupThread class]]) {
            NSLog(@"Currently unsupported");
        } else if([thread isKindOfClass:[TSContactThread class]]){
            TSContactThread *contactThread = (TSContactThread*)thread;
            __block TSRecipient     *recipient;
            [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                recipient = [contactThread recipientWithTransaction:transaction];
            }];
            
            [self sendMessage:message
                  toRecipient:recipient
                     inThread:thread
                  withAttemps:3];
        }
    });
}

- (void)sendMessage:(TSOutgoingMessage*)message
        toRecipient:(TSRecipient*)recipient
           inThread:(TSThread*)thread
        withAttemps:(int)remainingAttempts{
    
    if (remainingAttempts > 0) {
        remainingAttempts -= 1;
        
        [self outgoingMessages:message toRecipient:recipient completion:^(NSArray *messages) {
            TSSubmitMessageRequest *request = [[TSSubmitMessageRequest alloc] initWithRecipient:recipient.uniqueId messages:messages relay:recipient.relay timeStamp:message.timeStamp];
            
            [[TSNetworkManager sharedManager] queueAuthenticatedRequest:request success:^(NSURLSessionDataTask *task, id responseObject) {
                [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    [recipient saveWithTransaction:transaction];
                }];
                [self handleMessageSent:message];
                
            } failure:^(NSURLSessionDataTask *task, NSError *error) {
                NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
                long statuscode = response.statusCode;
                
                switch (statuscode) {
                    case 404:{
                        DDLogError(@"Recipient not found");
                        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                            [recipient removeWithTransaction:transaction];
                            [message setMessageState:TSOutgoingMessageStateUnsent];
                            [[TSInfoMessage userNotRegisteredMessageInThread:thread transaction:transaction] saveWithTransaction:transaction];
                        }];
                        break;
                    }
                    case 409:
                        // Mismatched devices
                        DDLogError(@"Missing some devices");
                        break;
                    case 410:
                        // staledevices
                        DDLogWarn(@"Stale devices");
                        break;
                    default:
                        [self sendMessage:message toRecipient:recipient inThread:thread withAttemps:remainingAttempts];
                        break;
                }
            }];
        }];
    } else{
        [self saveMessage:message withState:TSOutgoingMessageStateUnsent];
    }
}

- (void)handleMessageSent:(TSOutgoingMessage*)message {
    [self saveMessage:message withState:TSOutgoingMessageStateSent];
}

- (void)outgoingMessages:(TSOutgoingMessage*)message toRecipient:(TSRecipient*)recipient completion:(messagesQueue)sendMessages{
    NSMutableArray *messagesArray = [NSMutableArray arrayWithCapacity:recipient.devices.count];
    TSStorageManager *storage     = [TSStorageManager sharedManager];
    NSData *plainText             = [self plainTextForMessage:message];
    
    for (NSNumber *deviceNumber in recipient.devices) {
        @try {
            NSDictionary *messageDict = [self encryptedMessageWithPlaintext:plainText toRecipient:recipient.uniqueId deviceId:deviceNumber keyingStorage:storage];
            if (messageDict) {
                [messagesArray addObject:messageDict];
            } else{
                @throw [NSException exceptionWithName:InvalidMessageException reason:@"Failed to encrypt message" userInfo:nil];
            }
        }
        @catch (NSException *exception) {
            [self processException:exception outgoingMessage:message];
            return;
        }
    }
    
    sendMessages(messagesArray);
}

- (NSDictionary*)encryptedMessageWithPlaintext:(NSData*)plainText toRecipient:(NSString*)identifier deviceId:(NSNumber*)deviceNumber keyingStorage:(TSStorageManager*)storage{

    if (![storage containsSession:identifier deviceId:[deviceNumber intValue]]) {
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        __block PreKeyBundle *bundle;
        
        [[TSNetworkManager sharedManager] queueAuthenticatedRequest:[[TSRecipientPrekeyRequest alloc] initWithRecipient:identifier deviceId:[deviceNumber stringValue]] success:^(NSURLSessionDataTask *task, id responseObject) {
            bundle = [PreKeyBundle preKeyBundleFromDictionary:responseObject forDeviceNumber:deviceNumber];
            dispatch_semaphore_signal(sema);
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            dispatch_semaphore_signal(sema);
        }];
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        
        if (!bundle) {
            @throw [NSException exceptionWithName:InvalidVersionException reason:@"Can't get a prekey bundle from the server with required information" userInfo:nil];
        } else{
            SessionBuilder *builder = [[SessionBuilder alloc] initWithSessionStore:storage
                                                                       preKeyStore:storage
                                                                 signedPreKeyStore:storage
                                                                  identityKeyStore:storage
                                                                       recipientId:identifier
                                                                          deviceId:[deviceNumber intValue]];
            [builder processPrekeyBundle:bundle];
        }
    }
    
    SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:storage
                                                            preKeyStore:storage
                                                      signedPreKeyStore:storage
                                                       identityKeyStore:storage
                                                            recipientId:identifier
                                                               deviceId:[deviceNumber intValue]];
    
    id<CipherMessage> encryptedMessage = [cipher encryptMessage:plainText];
    NSData *serializedMessage = encryptedMessage.serialized;
    TSWhisperMessageType messageType = [self messageTypeForCipherMessage:encryptedMessage];
    
    
    TSServerMessage *serverMessage = [[TSServerMessage alloc] initWithType:messageType
                                                               destination:identifier
                                                                    device:[deviceNumber intValue]
                                                                      body:serializedMessage];
    
    
    return [MTLJSONAdapter JSONDictionaryFromModel:serverMessage];
}

- (TSWhisperMessageType)messageTypeForCipherMessage:(id<CipherMessage>)cipherMessage{
    
    if ([cipherMessage isKindOfClass:[PreKeyWhisperMessage class]]) {
        return TSPreKeyWhisperMessageType;
    } else if ([cipherMessage isKindOfClass:[WhisperMessage class]]){
        return TSEncryptedWhisperMessageType;
    }
    return TSUnknownMessageType;
}

- (void)saveMessage:(TSOutgoingMessage*)message withState:(TSOutgoingMessageState)state{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [message setMessageState:state];
        [message saveWithTransaction:transaction];
    }];
}

- (NSData*)plainTextForMessage:(TSOutgoingMessage*)message{
    
    PushMessageContentBuilder *builder = [PushMessageContentBuilder new];
    [builder setBody:message.body];
    
    NSMutableArray *attachmentsArray = [NSMutableArray array];
    
    for (NSString *attachmentId in message.attachments){
        id dbObject = [TSAttachmentStream fetchObjectWithUniqueID:attachmentId];
        
        if ([dbObject isKindOfClass:[TSAttachmentStream class]]) {
            TSAttachmentStream *attachment = (TSAttachmentStream*)dbObject;
            
            PushMessageContentAttachmentPointerBuilder *attachmentbuilder = [PushMessageContentAttachmentPointerBuilder new];
            [attachmentbuilder setId:[attachment.identifier unsignedLongLongValue]];
            [attachmentbuilder setContentType:attachment.contentType];
            [attachmentbuilder setKey:attachment.encryptionKey];
    
            [attachmentsArray addObject:[attachmentbuilder build]];
        }
    }
    
    [builder setAttachmentsArray:attachmentsArray];
    
    return [builder.build data];
}

@end
