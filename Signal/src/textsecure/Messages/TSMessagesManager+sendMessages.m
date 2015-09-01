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

#import "Environment.h"
#import "PreferencesUtil.h"
#import "NSData+messagePadding.h"
#import "TSStorageManager.h"

#import "PreKeyBundle+jsonDict.h"
#import "SignalKeyingStorage.h"

#import "TSNetworkManager.h"
#import "TSServerMessage.h"

#import "TSInfoMessage.h"
#import "CollapsingFutures.h"

#define RETRY_ATTEMPTS 3

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

- (void)sendMessage:(TSOutgoingMessage*)message inThread:(TSThread*)thread
            success:(successSendingCompletionBlock)successCompletionBlock
            failure:(failedSendingCompletionBlock)failedCompletionBlock
{
    [Environment.preferences setHasSentAMessage:YES];
    dispatch_async(sendingQueue(), ^{
        if ([thread isKindOfClass:[TSGroupThread class]]) {
            TSGroupThread* groupThread = (TSGroupThread*)thread;
            [self saveGroupMessage:message inThread:thread];
            __block NSArray* recipients;
            [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                recipients = [groupThread recipientsWithTransaction:transaction];
            }];
            
            [self groupSend:recipients Message:message inThread:thread success:successCompletionBlock failure:failedCompletionBlock];
        }
        else if([thread isKindOfClass:[TSContactThread class]]){
            TSContactThread *contactThread = (TSContactThread*)thread;
           
            [self saveMessage:message withState:TSOutgoingMessageStateAttemptingOut];
            
             if(![contactThread.contactIdentifier isEqualToString:[SignalKeyingStorage.localNumber toE164]]) {
                 __block TSRecipient     *recipient;
                 [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                     recipient = [contactThread recipientWithTransaction:transaction];
                 }];

                 [self sendMessage:message
                       toRecipient:recipient
                          inThread:thread
                       withAttemps:RETRY_ATTEMPTS
                           success:successCompletionBlock
                           failure:failedCompletionBlock];
             }
             else {
                 // Special situation: if we are sending to ourselves in a single thread, we treat this as an incoming message
                 [self handleMessageSent:message];
                 [[TSMessagesManager sharedManager] handleSendToMyself:message];
             }
        }
        
    });
}

/// For group sends, we're using chained futures to make the code more readable.

- (TOCFuture*)sendMessageFuture:(TSOutgoingMessage*)message
                      recipient:(TSRecipient*)recipient
                       inThread:(TSThread*)thread {
    TOCFutureSource *futureSource = [[TOCFutureSource alloc] init];
   
    [self sendMessage:message toRecipient:recipient inThread:thread withAttemps:RETRY_ATTEMPTS success:^{
        [futureSource trySetResult:@1];
    } failure:^{
        [futureSource trySetFailure:@0];
    }];
    
    return futureSource.future;
}

- (void)groupSend:(NSArray<TSRecipient*>*)recipients
          Message:(TSOutgoingMessage*)message
         inThread:(TSThread*)thread
          success:(successSendingCompletionBlock)successBlock
          failure:(failedSendingCompletionBlock)failureBlock {
    
    NSMutableArray<TOCFuture*> *futures = [NSMutableArray array];
    
    for(TSRecipient *rec in recipients){
        // we don't need to send the message to ourselves, but otherwise we send
        if( ![[rec uniqueId] isEqualToString:[SignalKeyingStorage.localNumber toE164]]){
            [futures addObject:[self sendMessageFuture:message recipient:rec inThread:thread]];
        }
    }
    
    TOCFuture *completionFuture = futures.toc_thenAll;
    
    [completionFuture thenDo:^(id value) {
        BLOCK_SAFE_RUN(successBlock);
    }];
    
    [completionFuture catchDo:^(id failure) {
        BLOCK_SAFE_RUN(failureBlock);
    }];
}

- (void)sendMessage:(TSOutgoingMessage*)message
        toRecipient:(TSRecipient*)recipient
           inThread:(TSThread*)thread
        withAttemps:(int)remainingAttempts
            success:(successSendingCompletionBlock)successBlock
            failure:(failedSendingCompletionBlock)failureBlock
{
    
    if (remainingAttempts > 0) {
        remainingAttempts -= 1;
        
        [self outgoingMessages:message toRecipient:recipient inThread:thread completion:^(NSArray *messages) {
            TSSubmitMessageRequest *request = [[TSSubmitMessageRequest alloc] initWithRecipient:recipient.uniqueId messages:messages relay:recipient.relay timeStamp:message.timestamp];
            
            [[TSNetworkManager sharedManager] queueAuthenticatedRequest:request success:^(NSURLSessionDataTask *task, id responseObject) {
                [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    [recipient saveWithTransaction:transaction];
                }];
                [self handleMessageSent:message];
                BLOCK_SAFE_RUN(successBlock);
            } failure:^(NSURLSessionDataTask *task, NSError *error) {
                NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
                long statuscode = response.statusCode;
                NSData *responseData = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
                
                switch (statuscode) {
                    case 404:{
                        DDLogError(@"Recipient not found");
                        [self.dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                            [recipient removeWithTransaction:transaction];
                            [message setMessageState:TSOutgoingMessageStateUnsent];
                            [[TSInfoMessage userNotRegisteredMessageInThread:thread transaction:transaction] saveWithTransaction:transaction];
                        }];
                        BLOCK_SAFE_RUN(failureBlock);
                        break;
                    }
                    case 409:{
                        // Mismatched devices
                        DDLogWarn(@"Mismatch Devices.");
                        
                        NSError *e;
                        NSDictionary *serializedResponse = [NSJSONSerialization JSONObjectWithData:responseData
                                                                                           options:0
                                                                                             error:&e];
                        
                        if (e) {
                            DDLogError(@"Failed to serialize response of mismatched devices: %@", e.description);
                        } else {
                            [self handleMismatchedDevices:serializedResponse
                                                recipient:recipient];
                        }
                        
                        dispatch_async(sendingQueue(), ^{
                            [self sendMessage:message
                                  toRecipient:recipient
                                     inThread:thread
                                  withAttemps:remainingAttempts
                                      success:successBlock
                                      failure:failureBlock];
                        });
                        
                        break;
                    }
                    case 410:{
                        // staledevices
                        DDLogWarn(@"Stale devices");
                        
                        if (!responseData) {
                            DDLogWarn(@"Stale devices but server didn't specify devices in response.");
                            return;
                        }
                        
                        [self handleStaleDevicesWithResponse:responseData recipientId:recipient.uniqueId];
                        
                        dispatch_async(sendingQueue(), ^{
                            [self sendMessage:message
                                  toRecipient:recipient
                                     inThread:thread
                                  withAttemps:remainingAttempts
                                      success:successBlock
                                      failure:failureBlock];
                        });
                        
                        break;
                    }
                    default:
                        [self sendMessage:message
                              toRecipient:recipient
                                 inThread:thread
                              withAttemps:remainingAttempts
                                  success:successBlock
                                  failure:failureBlock];
                        break;
                }
            }];
        }];
    } else{
        [self saveMessage:message withState:TSOutgoingMessageStateUnsent];
        BLOCK_SAFE_RUN(failureBlock);
    }
}

- (void)handleMismatchedDevices:(NSDictionary*)dictionary recipient:(TSRecipient*)recipient {
    NSArray *extraDevices   = [dictionary objectForKey:@"extraDevices"];
    NSArray *missingDevices = [dictionary objectForKey:@"missingDevices"];
    
    if (extraDevices && [extraDevices count] > 0) {
        for (NSNumber *extraDeviceId in extraDevices) {
            [[TSStorageManager sharedManager] deleteSessionForContact:recipient.uniqueId deviceId:[extraDeviceId intValue]];
        }
        
        [recipient removeDevices:[NSSet setWithArray:extraDevices]];
    }
    
    if (missingDevices && [missingDevices count] > 0) {
        [recipient addDevices:[NSSet setWithArray:missingDevices]];
    }
    
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [recipient saveWithTransaction:transaction];
    }];
}

- (void)handleMessageSent:(TSOutgoingMessage*)message {
    [self saveMessage:message withState:TSOutgoingMessageStateSent];
}

- (void)outgoingMessages:(TSOutgoingMessage*)message toRecipient:(TSRecipient*)recipient inThread:(TSThread*)thread completion:(messagesQueue)sendMessages{
    NSMutableArray *messagesArray = [NSMutableArray arrayWithCapacity:recipient.devices.count];
    TSStorageManager *storage     = [TSStorageManager sharedManager];
    NSData *plainText             = [self plainTextForMessage:message inThread:thread];
    
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
            [self processException:exception outgoingMessage:message inThread:thread];
            return;
        }
    }
    
    sendMessages(messagesArray);
}

- (NSDictionary*)encryptedMessageWithPlaintext:(NSData*)plainText toRecipient:(NSString*)identifier deviceId:(NSNumber*)deviceNumber keyingStorage:(TSStorageManager*)storage{

    if (![storage containsSession:identifier deviceId:[deviceNumber intValue]]) {
        __block dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        __block PreKeyBundle *bundle;
        
        [[TSNetworkManager sharedManager] queueAuthenticatedRequest:[[TSRecipientPrekeyRequest alloc] initWithRecipient:identifier deviceId:[deviceNumber stringValue]] success:^(NSURLSessionDataTask *task, id responseObject) {
            bundle = [PreKeyBundle preKeyBundleFromDictionary:responseObject forDeviceNumber:deviceNumber];
            dispatch_semaphore_signal(sema);
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            DDLogError(@"Server replied on PreKeyBundle request with error: %@", error);
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
            @try {
                [builder processPrekeyBundle:bundle];
            }
            @catch (NSException *exception) {
                if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
                    @throw [NSException exceptionWithName:UntrustedIdentityKeyException reason:nil userInfo:@{TSInvalidPreKeyBundleKey:bundle, TSInvalidRecipientKey:identifier}];
                }
                @throw exception;
            }
        }
    }
    
    SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:storage
                                                            preKeyStore:storage
                                                      signedPreKeyStore:storage
                                                       identityKeyStore:storage
                                                            recipientId:identifier
                                                               deviceId:[deviceNumber intValue]];
    
    id<CipherMessage> encryptedMessage = [cipher encryptMessage:[plainText paddedMessageBody]];
    NSData *serializedMessage = encryptedMessage.serialized;
    TSWhisperMessageType messageType = [self messageTypeForCipherMessage:encryptedMessage];
    
    
    TSServerMessage *serverMessage = [[TSServerMessage alloc] initWithType:messageType
                                                               destination:identifier
                                                                    device:[deviceNumber intValue]
                                                                      body:serializedMessage
                                                            registrationId:cipher.remoteRegistrationId];
    
    NSError *error;
    NSDictionary *jsonDict = [MTLJSONAdapter JSONDictionaryFromModel:serverMessage error:&error];
    
    if (error) {
        DDLogError(@"Error while making JSON dictionary of message: %@", error.debugDescription);
        return nil;
    }
    
    return jsonDict;
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
    if(message.groupMetaMessage == TSGroupMessageDeliver || message.groupMetaMessage == TSGroupMessageNone) {
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [message setMessageState:state];
            [message saveWithTransaction:transaction];
        }];
    }
}

- (void)saveGroupMessage:(TSOutgoingMessage*)message inThread:(TSThread*)thread{
    if(message.groupMetaMessage==TSGroupMessageDeliver) {
        [self saveMessage:message withState:message.messageState];
    }
    else if(message.groupMetaMessage==TSGroupMessageQuit) {
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            
            [[[TSInfoMessage alloc] initWithTimestamp:message.timestamp inThread:thread messageType:TSInfoMessageTypeGroupQuit] saveWithTransaction:transaction];
        }];
    }
    else {
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            
            [[[TSInfoMessage alloc] initWithTimestamp:message.timestamp inThread:thread messageType:TSInfoMessageTypeGroupUpdate] saveWithTransaction:transaction];
        }];
    }
}

- (NSData*)plainTextForMessage:(TSOutgoingMessage*)message inThread:(TSThread*)thread{
    PushMessageContentBuilder *builder = [PushMessageContentBuilder new];
    [builder setBody:message.body];
    BOOL processAttachments = YES;
    if([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *gThread = (TSGroupThread*)thread;
        PushMessageContentGroupContextBuilder *groupBuilder = [PushMessageContentGroupContextBuilder new];
       
        switch (message.groupMetaMessage) {
            case TSGroupMessageQuit:
                [groupBuilder setType:PushMessageContentGroupContextTypeQuit];
                break;
            case TSGroupMessageUpdate:
            case TSGroupMessageNew: {
                if(gThread.groupModel.groupImage!=nil && [message.attachments count] == 1) {
                    id dbObject = [TSAttachmentStream fetchObjectWithUniqueID:[message.attachments firstObject]];
                    if ([dbObject isKindOfClass:[TSAttachmentStream class]]) {
                        TSAttachmentStream *attachment = (TSAttachmentStream*)dbObject;
                        PushMessageContentAttachmentPointerBuilder *attachmentbuilder = [PushMessageContentAttachmentPointerBuilder new];
                        [attachmentbuilder setId:[attachment.identifier unsignedLongLongValue]];
                        [attachmentbuilder setContentType:attachment.contentType];
                        [attachmentbuilder setKey:attachment.encryptionKey];
                        [groupBuilder setAvatar:[attachmentbuilder build]];
                        processAttachments = NO;
                    }
                }
                [groupBuilder setMembersArray:gThread.groupModel.groupMemberIds];
                [groupBuilder setName:gThread.groupModel.groupName];
                [groupBuilder setType:PushMessageContentGroupContextTypeUpdate];
                break;
            }
            default:
                [groupBuilder setType:PushMessageContentGroupContextTypeDeliver];
                break;
        }
        [groupBuilder setId:gThread.groupModel.groupId];
        [builder setGroup:groupBuilder.build];
    }
    if(processAttachments) {
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
    }
    return [builder.build data];
}

- (void)handleStaleDevicesWithResponse:(NSData*)responseData recipientId:(NSString*)identifier {
    dispatch_async(sendingQueue(), ^{
        NSDictionary *serialization = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
        NSArray *devices            = serialization[@"staleDevices"];
        
        if (!([devices count] > 0)) {
            return;
        }
        
        for (NSUInteger i = 0; i < [devices count]; i++) {
            int deviceNumber = [devices[i] intValue];
            [[TSStorageManager sharedManager] deleteSessionForContact:identifier deviceId:deviceNumber];
        }
    });
}

@end
