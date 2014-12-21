//
//  TSMessagesHandler.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessagesManager.h"

#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/SessionCipher.h>

#import "Cryptography.h"
#import "IncomingPushMessageSignal.pb.h"
#import "NSData+Base64.h"

#import "PushManager.h"

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
#import "TSMessagesManager+attachments.h"

#import "NSData+messagePadding.h"

#import "Environment.h"
#import "PreferencesUtil.h"

#import <CocoaLumberjack/DDLog.h>

#define ddLogLevel LOG_LEVEL_VERBOSE

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
        _dbConnection = [TSStorageManager sharedManager].newDatabaseConnection;
    }
    
    return self;
}

- (void)handleMessageSignal:(IncomingPushMessageSignal*)messageSignal{
    @try {
        switch (messageSignal.type) {
            case IncomingPushMessageSignalTypeCiphertext:
                [self handleSecureMessage:messageSignal];
                break;
                
            case IncomingPushMessageSignalTypePrekeyBundle:
                [self handlePreKeyBundle:messageSignal];
                break;
                
                // Other messages are just dismissed for now.
                
            case IncomingPushMessageSignalTypeKeyExchange:
                DDLogWarn(@"Received Key Exchange Message, not supported");
                break;
            case IncomingPushMessageSignalTypePlaintext:
                DDLogWarn(@"Received a plaintext message");
                break;
            case IncomingPushMessageSignalTypeReceipt:
                DDLogInfo(@"Received a delivery receipt");
                [self handleDeliveryReceipt:messageSignal];
                break;
            case IncomingPushMessageSignalTypeUnknown:
                DDLogWarn(@"Received an unknown message type");
                break;
            default:
                break;
        }
    }
    @catch (NSException *exception) {
        DDLogWarn(@"Received an incorrectly formatted protocol buffer: %@", exception.debugDescription);
    }
}

- (void)handleDeliveryReceipt:(IncomingPushMessageSignal*)signal{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSOutgoingMessage *message = [TSOutgoingMessage fetchObjectWithUniqueID:[TSInteraction stringFromTimeStamp:signal.timestamp] transaction:transaction];
        message.messageState = TSOutgoingMessageStateDelivered;
        [message saveWithTransaction:transaction];
    }];
}

- (void)handleSecureMessage:(IncomingPushMessageSignal*)secureMessage{
    @synchronized(self){
        TSStorageManager *storageManager = [TSStorageManager sharedManager];
        NSString *recipientId            = secureMessage.source;
        int  deviceId                    = (int) secureMessage.sourceDevice;
        
        if (![storageManager containsSession:recipientId deviceId:deviceId]) {
            [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                TSErrorMessage *errorMessage = [TSErrorMessage missingSessionWithSignal:secureMessage withTransaction:transaction];
                [errorMessage saveWithTransaction:transaction];
            }];
            return;
        }
        
        PushMessageContent *content;
        
        @try {
            
            WhisperMessage *message = [[WhisperMessage alloc] initWithData:secureMessage.message];
            
            SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:storageManager
                                                                    preKeyStore:storageManager
                                                              signedPreKeyStore:storageManager
                                                               identityKeyStore:storageManager
                                                                    recipientId:recipientId
                                                                       deviceId:deviceId];
            
            NSData *plaintext = [[cipher decrypt:message] removePadding];
            
            content = [PushMessageContent parseFromData:plaintext];
        }
        @catch (NSException *exception) {
            [self processException:exception pushSignal:secureMessage];
            return;
        }
        
        [self handleIncomingMessage:secureMessage withPushContent:content];
    }
}

- (void)handlePreKeyBundle:(IncomingPushMessageSignal*)preKeyMessage{
    @synchronized(self){
        TSStorageManager *storageManager = [TSStorageManager sharedManager];
        NSString *recipientId            = preKeyMessage.source;
        int  deviceId                    = (int)preKeyMessage.sourceDevice;
        
        PushMessageContent *content;
        
        @try {
            PreKeyWhisperMessage *message = [[PreKeyWhisperMessage alloc] initWithData:preKeyMessage.message];
            
            SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:storageManager
                                                                    preKeyStore:storageManager
                                                              signedPreKeyStore:storageManager
                                                               identityKeyStore:storageManager
                                                                    recipientId:recipientId
                                                                       deviceId:deviceId];
            
            NSData *plaintext = [[cipher decrypt:message] removePadding];
            
            content = [PushMessageContent parseFromData:plaintext];
        }
        @catch (NSException *exception) {
            [self processException:exception pushSignal:preKeyMessage];
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
        DDLogVerbose(@"Received push media message (attachment) ...");
        [self handleReceivedMediaMessage:incomingMessage withContent:content];
    } else {
        DDLogVerbose(@"Received push text message...");
        [self handleReceivedTextMessage:incomingMessage withContent:content];
    }
}

- (void)handleEndSessionMessage:(IncomingPushMessageSignal*)message withContent:(PushMessageContent*)content{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSContactThread  *thread    = [TSContactThread threadWithContactId:message.source transaction:transaction];
        uint64_t         timeStamp  = message.timestamp;
        
        if (thread){
            [[[TSInfoMessage alloc] initWithTimestamp:timeStamp inThread:thread messageType:TSInfoMessageTypeSessionDidEnd] saveWithTransaction:transaction];
        }
    }];
    
    [[TSStorageManager sharedManager] deleteAllSessionsForContact:message.source];
}

- (void)handleGroupMessage:(IncomingPushMessageSignal*)message withContent:(PushMessageContent*)content{
    // TO DO
}

- (void)handleReceivedTextMessage:(IncomingPushMessageSignal*)message withContent:(PushMessageContent*)content{
    [self handleReceivedMessage:message withContent:content attachments:nil];
}

- (void)handleReceivedMessage:(IncomingPushMessageSignal*)message withContent:(PushMessageContent*)content attachments:(NSArray*)attachments {
    uint64_t timeStamp  = message.timestamp;
    NSString *body      = content.body;
    NSData   *groupId   = content.hasGroup?content.group.id:nil;
    
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSIncomingMessage *incomingMessage;
        TSThread          *thread;
        if (groupId) {
            TSGroupThread *gThread = [TSGroupThread threadWithGroupId:groupId];
            [gThread saveWithTransaction:transaction];
            incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:timeStamp inThread:gThread authorId:message.source messageBody:body attachments:attachments];
            thread = gThread;
        } else{
            TSContactThread *cThread = [TSContactThread threadWithContactId:message.source transaction:transaction];
            [cThread saveWithTransaction:transaction];
            incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:timeStamp inThread:cThread messageBody:body attachments:attachments];
            thread = cThread;
        }
        [incomingMessage saveWithTransaction:transaction];
        NSString *name = [thread name];
        [self notifyUserForIncomingMessage:incomingMessage from:name];
    }];
}

- (void)processException:(NSException*)exception pushSignal:(IncomingPushMessageSignal*)signal{
    DDLogError(@"Got exception: %@ of type: %@", exception.description, exception.name);
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSErrorMessage *errorMessage;
        
        if ([exception.name isEqualToString:NoSessionException]) {
            errorMessage = [TSErrorMessage missingSessionWithSignal:signal withTransaction:transaction];
        } else if ([exception.name isEqualToString:InvalidKeyException]){
            errorMessage = [TSErrorMessage invalidKeyExceptionWithSignal:signal withTransaction:transaction];
        } else if ([exception.name isEqualToString:InvalidKeyIdException]){
            errorMessage = [TSErrorMessage invalidKeyExceptionWithSignal:signal withTransaction:transaction];
        } else if ([exception.name isEqualToString:DuplicateMessageException]){
            // Duplicate messages are dismissed
            return ;
        } else if ([exception.name isEqualToString:InvalidVersionException]){
            errorMessage = [TSErrorMessage invalidVersionWithSignal:signal withTransaction:transaction];
        } else if ([exception.name isEqualToString:UntrustedIdentityKeyException]){
            errorMessage = [TSErrorMessage untrustedKeyWithSignal:signal withTransaction:transaction];
        } else {
            errorMessage = [TSErrorMessage corruptedMessageWithSignal:signal withTransaction:transaction];
        }
        
        [errorMessage saveWithTransaction:transaction];
    }];
    
}

- (void)processException:(NSException*)exception outgoingMessage:(TSOutgoingMessage*)message{
    DDLogWarn(@"Got exception: %@", exception.description);
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [message setMessageState:TSOutgoingMessageStateUnsent];
        [message saveWithTransaction:transaction];
    }];
}

- (void)notifyUserForIncomingMessage:(TSIncomingMessage*)message from:(NSString*)name{
    
    UILocalNotification *notification = [[UILocalNotification alloc] init];
    notification.alertBody = [self alertBodyForNotificationSetting:[Environment.preferences notificationPreviewType] withMessage:message from:name];
    notification.soundName = @"default";
    notification.category  = Signal_Message_Category;
    [[UIApplication sharedApplication] presentLocalNotificationNow:notification];
}

-(NSString*)alertBodyForNotificationSetting:(NotificationType)setting withMessage:(TSIncomingMessage*)message from:(NSString*)name
{
    switch (setting) {
        case NotificationNoNameNoPreview:
            return @"New message";
            break;
        case NotificationNameNoPreview:
            return [NSString stringWithFormat:@"New message from %@", name];
            break;
        case NotificationNamePreview:
            return [NSString stringWithFormat:@"%@ : %@", name, message.body];
            break;
        default:
            DDLogWarn(@"Unexpected notification type %lu", setting);
            break;
    }
}

@end
