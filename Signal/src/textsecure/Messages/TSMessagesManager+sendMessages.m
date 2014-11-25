//
//  TSMessagesManager+sendMessages.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 17/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessagesManager+sendMessages.h"

#import <AxolotlKit/SessionCipher.h>
#import <Mantle/Mantle.h>

#import "IncomingPushMessageSignal.pb.h"
#import "TSStorageManager.h"
#import "TSStorageManager+SessionStore.h"
#import "TSStorageManager+IdentityKeyStore.h"
#import "TSStorageManager+PreKeyStore.h"
#import "TSStorageManager+SignedPreKeyStore.h"

#import "TSNetworkManager.h"
#import "TSServerMessage.h"
#import "TSSubmitMessageRequest.h"

#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSRecipient.h"

@implementation TSMessagesManager (sendMessages)

- (void)sendMessage:(TSOutgoingMessage*)message inThread:(TSThread*)thread{
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
}


- (void)sendMessage:(TSOutgoingMessage*)message
        toRecipient:(TSRecipient*)recipient
           inThread:(TSThread*)thread
        withAttemps:(int)remainingAttempts{
    
    if (remainingAttempts > 0) {
        remainingAttempts -= 1;
        
        NSArray *outgoingMessages = [self outgoingMessages:message toRecipient:recipient];
        
        TSSubmitMessageRequest *request = [[TSSubmitMessageRequest alloc] initWithRecipient:recipient.uniqueId messages:outgoingMessages relay:recipient.relay timeStamp:message.timeStamp];
        
        [[TSNetworkManager sharedManager] queueAuthenticatedRequest:request success:^(NSURLSessionDataTask *task, id responseObject) {
            
            [self handleMessageSent:message inThread:thread];
            NSLog(@"Message sent");
            
            
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            long statuscode = response.statusCode;
            
            //TODO: Handle failures
            
            switch (statuscode) {
                case 404:
                    // Recipient not found
                    break;
                case 409:
                    // Mismatched devices
                    
                    break;
                case 410:
                    // staledevices
                    break;
                default:
                    break;
            }
            
            
        }];
    }
}

- (void)handleMessageSent:(TSOutgoingMessage*)message inThread:(TSThread*)thread{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [message setMessageState:TSOutgoingMessageStateSent];
        [message saveWithTransaction:transaction];
        TSThread *fetchedThread = [TSThread fetchObjectWithUniqueID:thread.uniqueId];
        fetchedThread.lastMessageId = [TSInteraction timeStampFromString:message.uniqueId];
        [thread saveWithTransaction:transaction];
    }];
}

- (NSArray*)outgoingMessages:(TSOutgoingMessage*)message  toRecipient:(TSRecipient*)recipient{

    NSMutableArray *messagesArray = [NSMutableArray arrayWithCapacity:recipient.devices.count];
    TSStorageManager *storage     = [TSStorageManager sharedManager];
    NSData *plainText             = [self plainTextForMessage:message];

    for (NSNumber *deviceNumber in recipient.devices) {
        if (![storage containsSession:recipient.uniqueId deviceId:[deviceNumber intValue]]) {
            // Needs to fetch prekey;
        }
        
        @try{
            SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:storage
                                                                    preKeyStore:storage
                                                              signedPreKeyStore:storage
                                                               identityKeyStore:storage
                                                                    recipientId:recipient.uniqueId
                                                                       deviceId:[deviceNumber intValue]];
            
            id<CipherMessage> encryptedMessage = [cipher encryptMessage:plainText];
            NSData *serializedMessage = encryptedMessage.serialized;
            TSWhisperMessageType messageType = [self messageTypeForCipherMessage:encryptedMessage];
            
    
            TSServerMessage *serverMessage = [[TSServerMessage alloc] initWithType:messageType
                                                                       destination:recipient.uniqueId
                                                                            device:[deviceNumber intValue]
                                                                              body:serializedMessage];
            
            
            [messagesArray addObject:[MTLJSONAdapter JSONDictionaryFromModel:serverMessage]];
            
        }@catch (NSException *exception) {
            [self processException:exception outgoingMessage:message];
        }
    }
    
    return messagesArray;
}

- (TSWhisperMessageType)messageTypeForCipherMessage:(id<CipherMessage>)cipherMessage{
    
    if ([cipherMessage isKindOfClass:[PreKeyWhisperMessage class]]) {
        return TSPreKeyWhisperMessageType;
    } else if ([cipherMessage isKindOfClass:[WhisperMessage class]]){
        return TSEncryptedWhisperMessageType;
    }
    return TSUnknownMessageType;
}

- (NSData*)plainTextForMessage:(TSOutgoingMessage*)message{
    
    PushMessageContentBuilder *builder = [PushMessageContentBuilder new];
    [builder setBody:message.body];
    
    return [builder.build data];
    
    //TO-DO: DEAL WITH ATTACHEMENTS AND GROUPS STUFF
}

@end
