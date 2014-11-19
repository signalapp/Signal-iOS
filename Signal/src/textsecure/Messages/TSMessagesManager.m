//
//  TSMessagesHandler.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessagesManager.h"

#import <AxolotlKit/SessionCipher.h>

#import "Cryptography.h"
#import "IncomingPushMessageSignal.pb.h"
#import "NSData+Base64.h"

#import "TSContact.h"

#import "TSIncomingMessage.h"
#import "TSErrorMessage.h"
#import "TSInfoMessage.h"

#import "TSStorageManager+keyingMaterial.h"
#import "TSStorageManager+IdentityKeyStore.h"
#import "TSStorageManager+SessionStore.h"
#import "TSStorageManager+SignedPreKeyStore.h"
#import "TSStorageManager+PreKeyStore.h"
#import "TSNetworkManager.h"
#import "TSSubmitMessageRequest.h"

#import "NSData+messagePadding.h"

#import <CocoaLumberjack/DDLog.h>

#define ddLogLevel LOG_LEVEL_DEBUG

@implementation TSMessagesManager

+ (instancetype)sharedManager {
    static TSMessagesManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] init];
    });
    return sharedMyManager;
}

- (instancetype)init{
    self = [super init];
    
    if (self) {
        _dbConnection = [TSStorageManager sharedManager].databaseConnection;
    }
    
    return self;
}

- (void)handleBase64MessageSignal:(NSString*)base64EncodedMessage{
    NSData *decryptedPayload = [Cryptography decryptAppleMessagePayload:[NSData dataFromBase64String:base64EncodedMessage] withSignalingKey:TSStorageManager.signalingKey];
    
    if (!decryptedPayload) {
        return;
    }
    
    IncomingPushMessageSignal *messageSignal = [IncomingPushMessageSignal parseFromData:decryptedPayload];
    
    switch (messageSignal.type) {
        case IncomingPushMessageSignalTypeCiphertext:
            [self handleSecureMessage:messageSignal];
            break;
            
        case IncomingPushMessageSignalTypePrekeyBundle:
            [self handlePreKeyBundle:messageSignal];
            break;
            
            // Other messages are just dismissed for now.
            
        case IncomingPushMessageSignalTypeKeyExchange:
            NSLog(@"Key exchange!");
            break;
        case IncomingPushMessageSignalTypePlaintext:
            NSLog(@"Plaintext");
            break;
        case IncomingPushMessageSignalTypeReceipt:
            NSLog(@"Receipt");
            break;
        case IncomingPushMessageSignalTypeUnknown:
            NSLog(@"Unknown");
            break;
        default:
            break;
    }
}

- (void)handleSecureMessage:(IncomingPushMessageSignal*)secureMessage{
    @synchronized(self){
        TSStorageManager *storageManager = [TSStorageManager sharedManager];
        NSString *recipientId            = secureMessage.source;
        int  deviceId                    = secureMessage.sourceDevice;
        
        if (![storageManager containsSession:recipientId deviceId:deviceId]) {
            // Deal with failure
        }
        
        WhisperMessage *message = [[WhisperMessage alloc] initWithData:secureMessage.message];
        
        if (!message) {
            [self failedProtocolBufferDeserialization:secureMessage];
            return;
        }
        
        NSData *plaintext;
        
        @try {
            SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:storageManager
                                                                    preKeyStore:storageManager
                                                              signedPreKeyStore:storageManager
                                                               identityKeyStore:storageManager
                                                                    recipientId:recipientId
                                                                       deviceId:deviceId];
            
            plaintext = [[cipher decrypt:message] removePadding];
        }
        @catch (NSException *exception) {
            [self processException:exception pushSignal:secureMessage];
            return;
        }
        
        PushMessageContent *content = [PushMessageContent parseFromData:plaintext];
        
        if (!content) {
            [self failedProtocolBufferDeserialization:secureMessage];
            return;
        }
        
        [self handleIncomingMessage:secureMessage withPushContent:content];
    }
}

- (void)handlePreKeyBundle:(IncomingPushMessageSignal*)preKeyMessage{
    @synchronized(self){
        TSStorageManager *storageManager = [TSStorageManager sharedManager];
        NSString *recipientId            = preKeyMessage.source;
        int  deviceId                    = preKeyMessage.sourceDevice;
        
        PreKeyWhisperMessage *message = [[PreKeyWhisperMessage alloc] initWithData:preKeyMessage.message];
        
        if (!message) {
            [self failedProtocolBufferDeserialization:preKeyMessage];
            return;
        }
        
        
        NSData *plaintext;
        @try {
            SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:storageManager
                                                                    preKeyStore:storageManager
                                                              signedPreKeyStore:storageManager
                                                               identityKeyStore:storageManager
                                                                    recipientId:recipientId
                                                                       deviceId:deviceId];
            
            plaintext = [[cipher decrypt:message] removePadding];
        }
        @catch (NSException *exception) {
            [self processException:exception pushSignal:preKeyMessage];
            return;
        }
        
        PushMessageContent *content = [PushMessageContent parseFromData:plaintext];
        
        if (!content) {
            [self failedProtocolBufferDeserialization:preKeyMessage];
            return;
        }
        
        [self handleIncomingMessage:preKeyMessage withPushContent:content];
    }
    
}

- (void)handleIncomingMessage:(IncomingPushMessageSignal*)incomingMessage withPushContent:(PushMessageContent*)content{
    if ((content.flags & PushMessageContentFlagsEndSession) != 0) {
        DDLogVerbose(@"Received end session message...");
        [self handleEndSessionMessage:incomingMessage withContent:content];
    } else if (content.hasGroup && (content.group.type != PushMessageContentGroupContextTypeDeliver)) {
        DDLogVerbose(@"Received push group update message...");
        [self handleGroupMessage:incomingMessage withContent:content];
    } else if (content.attachments.count > 0) {
        DDLogVerbose(@"Received push media message (attachement) ...");
        [self handleReceivedMediaMessage:incomingMessage withContent:content];
    } else {
        DDLogVerbose(@"Received push text message...");
        [self handleReceivedTextMessage:incomingMessage withContent:content];
    }
}

- (void)handleEndSessionMessage:(IncomingPushMessageSignal*)message withContent:(PushMessageContent*)content{
    TSContactThread  *thread    = [TSContactThread threadWithContactId:message.source];
    uint64_t         timeStamp  = message.timestamp;

    if (thread){
        [[[TSInfoMessage alloc] initWithTimestamp:timeStamp inThread:thread messageType:TSInfoMessageTypeSessionDidEnd] save];
    }
    
    [[TSStorageManager sharedManager] deleteAllSessionsForContact:message.source];
}

- (void)handleGroupMessage:(IncomingPushMessageSignal*)message withContent:(PushMessageContent*)content{
    // TO DO
}

- (void)handleReceivedMediaMessage:(IncomingPushMessageSignal*)message withContent:(PushMessageContent*)content{
    // TO DO
}

- (void)handleReceivedTextMessage:(IncomingPushMessageSignal*)message withContent:(PushMessageContent*)content{
    uint64_t timeStamp  = message.timestamp;
    NSString *body      = content.body;
    NSData   *groupId   = content.hasGroup?content.group.id:nil;
    
    TSIncomingMessage *incomingMessage;
    
    if (groupId) {
        TSGroupThread *thread = [TSGroupThread threadWithGroupId:groupId];
        incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:timeStamp inThread:thread authorId:message.source messageBody:body attachements:nil];
    } else{
        TSContactThread *thread = [TSContactThread threadWithContactId:message.source];
        incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:timeStamp inThread:thread messageBody:body attachements:nil];
    }
    
    NSLog(@"Incoming message: %@", incomingMessage.body);
    [incomingMessage save];
}

- (void)failedProtocolBufferDeserialization:(IncomingPushMessageSignal*)signal{
    NSLog(@"Failed Protocol buffer deserialization");
    TSErrorMessage *errorMessage = [TSErrorMessage invalidProtocolBufferWithSignal:signal];
    [errorMessage save];
    return;
}

- (void)processException:(NSException*)exception pushSignal:(IncomingPushMessageSignal*)signal{
    NSLog(@"Got exception: %@", exception.description);
}


- (void)processException:(NSException*)exception outgoingMessage:(TSOutgoingMessage*)message{
    NSLog(@"Got exception: %@", exception.description);
}

@end
