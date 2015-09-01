//
//  TSMessagesHandler.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessagesManager.h"

#import <AudioToolbox/AudioToolbox.h>
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/SessionCipher.h>

#import "PushManager.h"

#import "TSInvalidIdentityKeyReceivingErrorMessage.h"
#import "TSInfoMessage.h"

#import "TSDatabaseView.h"
#import "TSStorageManager.h"
#import "TSMessagesManager+attachments.h"

#import "SignalKeyingStorage.h"

#import "NSData+messagePadding.h"

#import "Environment.h"
#import "PreferencesUtil.h"
#import "ContactsManager.h"
#import "TSCall.h"

@interface TSMessagesManager ()

@property SystemSoundID newMessageSound;

@end

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
        _dbConnection          = [TSStorageManager sharedManager].newDatabaseConnection;
        NSURL *newMessageSound = [NSURL URLWithString:[[NSBundle mainBundle] pathForResource:@"NewMessage" ofType:@"aifc"]];
        AudioServicesCreateSystemSoundID((__bridge CFURLRef)newMessageSound, &_newMessageSound);;
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
        TSInteraction *interaction = [TSInteraction interactionForTimestamp:signal.timestamp withTransaction:transaction];
        if ([interaction isKindOfClass:[TSOutgoingMessage class]]) {
            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage*)interaction;
            outgoingMessage.messageState       = TSOutgoingMessageStateDelivered;
            
            [outgoingMessage saveWithTransaction:transaction];
        }
    }];
}

- (void)handleSecureMessage:(IncomingPushMessageSignal*)secureMessage{
    @synchronized(self){
        TSStorageManager *storageManager = [TSStorageManager sharedManager];
        NSString *recipientId            = secureMessage.source;
        int  deviceId                    = (int) secureMessage.sourceDevice;
        
        if (![storageManager containsSession:recipientId deviceId:deviceId]) {
            [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                TSErrorMessage *errorMessage = [TSErrorMessage missingSessionWithSignal:secureMessage
                                                                        withTransaction:transaction];
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
    if(content.hasGroup)  {
        __block BOOL ignoreMessage = NO;
        [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            TSGroupModel *emptyModelToFillOutId = [[TSGroupModel alloc] initWithTitle:nil memberIds:nil image:nil groupId:content.group.id associatedAttachmentId:nil]; // TODO refactor the TSGroupThread to just take in an ID (as it is all that it uses). Should not take in more than it uses
            TSGroupThread *gThread = [TSGroupThread threadWithGroupModel:emptyModelToFillOutId transaction:transaction];
            if(gThread==nil && content.group.type != PushMessageContentGroupContextTypeUpdate) {
                ignoreMessage = YES;
            }
        }];
        if(ignoreMessage) {
            DDLogDebug(@"Received message from group that I left or don't know about, ignoring");
            return;
        }
        
    }
    if ((content.flags & PushMessageContentFlagsEndSession) != 0) {
        DDLogVerbose(@"Received end session message...");
        [self handleEndSessionMessage:incomingMessage withContent:content];
    }
    else if (content.attachments.count > 0 || (content.hasGroup && content.group.type == PushMessageContentGroupContextTypeUpdate && content.group.hasAvatar)) {
        DDLogVerbose(@"Received push media message (attachment) or group with an avatar...");
        [self handleReceivedMediaMessage:incomingMessage withContent:content];
    }
    else {
        DDLogVerbose(@"Received individual push text message...");
        [self handleReceivedTextMessage:incomingMessage withContent:content];
    }
}

- (void)handleEndSessionMessage:(IncomingPushMessageSignal*)message withContent:(PushMessageContent*)content{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSContactThread  *thread    = [TSContactThread getOrCreateThreadWithContactId:message.source transaction:transaction];
        uint64_t         timeStamp  = message.timestamp;
        
        if (thread){
            [[[TSInfoMessage alloc] initWithTimestamp:timeStamp inThread:thread messageType:TSInfoMessageTypeSessionDidEnd] saveWithTransaction:transaction];
        }
    }];
    
    [[TSStorageManager sharedManager] deleteAllSessionsForContact:message.source];
}

- (void)handleReceivedTextMessage:(IncomingPushMessageSignal*)message withContent:(PushMessageContent*)content{
    [self handleReceivedMessage:message withContent:content attachments:content.attachments];
}

-(void)handleSendToMyself:(TSOutgoingMessage*)outgoingMessage {
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSContactThread *cThread = [TSContactThread getOrCreateThreadWithContactId:[SignalKeyingStorage.localNumber toE164] transaction:transaction];
        [cThread saveWithTransaction:transaction];
        TSIncomingMessage *incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:(outgoingMessage.timestamp + 1) inThread:cThread messageBody:outgoingMessage.body attachments:outgoingMessage.attachments];
        [incomingMessage saveWithTransaction:transaction];
    }];
}

- (void)handleReceivedMessage:(IncomingPushMessageSignal *)message withContent:(PushMessageContent *)content attachments:(NSArray *)attachments{
    [self handleReceivedMessage:message withContent:content attachments:attachments completionBlock:nil];
}

- (void)handleReceivedMessage:(IncomingPushMessageSignal*)message withContent:(PushMessageContent*)content attachments:(NSArray*)attachments completionBlock:(void (^)(NSString* messageIdentifier))completionBlock {
    uint64_t timeStamp  = message.timestamp;
    NSString *body      = content.body;
    NSData   *groupId   = content.hasGroup?content.group.id:nil;
    
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSIncomingMessage *incomingMessage;
        TSThread          *thread;
        if (groupId) {
            TSGroupModel *model = [[TSGroupModel alloc] initWithTitle:content.group.name memberIds:[[[NSSet setWithArray:content.group.members] allObjects] mutableCopy] image:nil groupId:content.group.id associatedAttachmentId:nil];
            TSGroupThread *gThread = [TSGroupThread getOrCreateThreadWithGroupModel:model transaction:transaction];
            [gThread saveWithTransaction:transaction];
            if(content.group.type==PushMessageContentGroupContextTypeUpdate) {
                if([attachments count]==1) {
                    NSString* avatarId  = [attachments firstObject];
                    TSAttachment *avatar = [TSAttachment fetchObjectWithUniqueID:avatarId];
                    if ([avatar isKindOfClass:[TSAttachmentStream class]]) {
                        TSAttachmentStream *stream = (TSAttachmentStream*)avatar;
                        if ([stream isImage]) {
                            model.associatedAttachmentId = stream.uniqueId;
                            model.groupImage = [stream image];
                        }
                    }
                }
                
                NSString* updateGroupInfo = [gThread.groupModel getInfoStringAboutUpdateTo:model];
                gThread.groupModel = model;
                [gThread saveWithTransaction:transaction];
                [[[TSInfoMessage alloc] initWithTimestamp:timeStamp inThread:gThread messageType:TSInfoMessageTypeGroupUpdate customMessage:updateGroupInfo] saveWithTransaction:transaction];
            }
            else if(content.group.type==PushMessageContentGroupContextTypeQuit) {
                NSString *nameString = [[Environment.getCurrent contactsManager] nameStringForPhoneIdentifier:message.source];
                
                if (!nameString) {
                    nameString = message.source;
                }
                
                NSString* updateGroupInfo = [NSString stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_LEFT", @""),nameString];
                NSMutableArray *newGroupMembers = [NSMutableArray arrayWithArray:gThread.groupModel.groupMemberIds];
                [newGroupMembers removeObject:message.source];
                gThread.groupModel.groupMemberIds = newGroupMembers;
                
                [gThread saveWithTransaction:transaction];
                [[[TSInfoMessage alloc] initWithTimestamp:timeStamp inThread:gThread messageType:TSInfoMessageTypeGroupUpdate customMessage:updateGroupInfo] saveWithTransaction:transaction];
            } else {
                incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:timeStamp inThread:gThread authorId:message.source messageBody:body attachments:attachments];
                [incomingMessage saveWithTransaction:transaction];
            }
            
            thread = gThread;
            
        } else {
            TSContactThread *cThread = [TSContactThread getOrCreateThreadWithContactId:message.source
                                                                           transaction:transaction
                                                                            pushSignal:message];
            
            incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:timeStamp
                                                                  inThread:cThread
                                                               messageBody:body
                                                               attachments:attachments];
            thread = cThread;
            
        }
        
        if (thread && incomingMessage) {
            if ([attachments count] > 0 && body != nil && ![body isEqualToString:@""]) { // Android allows attachments to be sent with body.
                uint64_t textMessageTimestamp = timeStamp+1000; // We want the text to be displayed under the attachment
                
                if ([thread isGroupThread]) {
                    TSGroupThread *gThread = (TSGroupThread*)thread;
                    TSIncomingMessage *textMessage = [[TSIncomingMessage alloc] initWithTimestamp:textMessageTimestamp
                                                                                         inThread:gThread
                                                                                         authorId:message.source
                                                                                      messageBody:body
                                                                                      attachments:nil];
                    [textMessage saveWithTransaction:transaction];
                } else{
                    TSContactThread *cThread= (TSContactThread*)thread;
                    TSIncomingMessage *textMessage = [[TSIncomingMessage alloc] initWithTimestamp:textMessageTimestamp
                                                                                         inThread:cThread
                                                                                      messageBody:body
                                                                                      attachments:nil];
                    [textMessage saveWithTransaction:transaction];
                }
            }
            
            [incomingMessage saveWithTransaction:transaction];
        }
        
        if (completionBlock) {
            completionBlock(incomingMessage.uniqueId);
        }
        
        NSString *name = [thread name];
        
        if (incomingMessage && thread) {
            [self notifyUserForIncomingMessage:incomingMessage
                                          from:name
                                      inThread:thread];
        }
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
            errorMessage = [TSInvalidIdentityKeyReceivingErrorMessage untrustedKeyWithSignal:signal withTransaction:transaction];
        } else {
            errorMessage = [TSErrorMessage corruptedMessageWithSignal:signal withTransaction:transaction];
        }
        
        [errorMessage saveWithTransaction:transaction];
    }];
}

- (void)processException:(NSException*)exception outgoingMessage:(TSOutgoingMessage*)message inThread:(TSThread*)thread {
    DDLogWarn(@"Got exception: %@", exception.description);
    
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSErrorMessage *errorMessage;
        
        if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
            errorMessage = [TSInvalidIdentityKeySendingErrorMessage untrustedKeyWithOutgoingMessage:message inThread:thread forRecipient:exception.userInfo[TSInvalidRecipientKey] preKeyBundle:exception.userInfo[TSInvalidPreKeyBundleKey] withTransaction:transaction];
            message.messageState = TSOutgoingMessageStateUnsent;
            [message saveWithTransaction:transaction];
        } else if (message.groupMetaMessage==TSGroupMessageNone) {
            // Only update this with exception if it is not a group message as group messages may except for one group send but not another and the UI doesn't know how to handle that
            [message setMessageState:TSOutgoingMessageStateUnsent];
            [message saveWithTransaction:transaction];
        }
        
        [errorMessage saveWithTransaction:transaction];
    }];
}

- (NSUInteger)unreadMessagesCount {
    __block NSUInteger numberOfItems;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        numberOfItems = [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInAllGroups];
    }];
    
    return numberOfItems;
}

- (NSUInteger)unreadMessagesCountExcept:(TSThread*)thread {
    __block NSUInteger numberOfItems;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        numberOfItems = [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInAllGroups];
        numberOfItems = numberOfItems - [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInGroup:thread.uniqueId];
    }];
    
    return numberOfItems;
}

- (void)notifyUserForCall:(TSCall*)call inThread:(TSThread*)thread {
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive){
        // Remove previous notification of call and show missed notification.
        UILocalNotification *notif = [[PushManager sharedManager] closeVOIPBackgroundTask];
        TSContactThread *cThread = (TSContactThread*)thread;
        
        if (call.callType == RPRecentCallTypeMissed) {
            if (notif) {
                [[UIApplication sharedApplication] cancelLocalNotification:notif];
            }
            
            UILocalNotification *notification = [[UILocalNotification alloc] init];
            notification.category   = Signal_CallBack_Category;
            notification.userInfo   = @{Signal_Call_UserInfo_Key:cThread.contactIdentifier};
            notification.soundName  = @"NewMessage.aifc";
            notification.alertBody  = [NSString stringWithFormat:NSLocalizedString(@"MSGVIEW_MISSED_CALL", nil), [thread name]];
            
            [[PushManager sharedManager] presentNotification:notification];
        }
    }
}

- (void)notifyUserForError:(TSErrorMessage*)message inThread:(TSThread*)thread {
    NSString *messageDescription = message.description;
    
    if (([UIApplication sharedApplication].applicationState != UIApplicationStateActive) && messageDescription) {
        UILocalNotification *notification = [[UILocalNotification alloc] init];
        notification.userInfo  = @{Signal_Thread_UserInfo_Key:thread.uniqueId};
        notification.soundName = @"NewMessage.aifc";
        
        NSString *alertBodyString = @"";
        
        NSString *authorName = [thread name];
        switch ([[Environment preferences] notificationPreviewType]) {
            case NotificationNamePreview:
            case NotificationNameNoPreview:
                alertBodyString = [NSString stringWithFormat:@"%@: %@", authorName,messageDescription];
                break;
            case NotificationNoNameNoPreview:
                alertBodyString = messageDescription;
                break;
        }
        notification.alertBody = alertBodyString;
        
        [[PushManager sharedManager]presentNotification:notification];
    } else {
        if ([Environment.preferences soundInForeground]) {
            AudioServicesPlayAlertSound(_newMessageSound);
        }
    }
}

- (void)notifyUserForIncomingMessage:(TSIncomingMessage*)message from:(NSString*)name inThread:(TSThread*)thread {
    NSString *messageDescription = message.description;
    
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive && messageDescription) {
        UILocalNotification *notification = [[UILocalNotification alloc] init];
        notification.soundName = @"NewMessage.aifc";
        
        switch ([[Environment preferences] notificationPreviewType]) {
            case NotificationNamePreview:
                notification.category  = Signal_Full_New_Message_Category;
                notification.userInfo  = @{Signal_Thread_UserInfo_Key:thread.uniqueId,
                                           Signal_Message_UserInfo_Key:message.uniqueId};
                
                if ([thread isGroupThread]) {
                    NSString *sender = [[Environment getCurrent].contactsManager nameStringForPhoneIdentifier:message.authorId];
                    if (!sender) {
                        sender = message.authorId;
                    }
                    
                    NSString *threadName   = [NSString stringWithFormat:@"\"%@\"", name];
                    notification.alertBody = [NSString stringWithFormat:NSLocalizedString(@"APN_MESSAGE_IN_GROUP_DETAILED", nil), sender, threadName, messageDescription];
                } else {
                    notification.alertBody = [NSString stringWithFormat:@"%@: %@", name, messageDescription];
                }
                break;
            case NotificationNameNoPreview:{
                notification.userInfo  = @{Signal_Thread_UserInfo_Key:thread.uniqueId};
                if ([thread isGroupThread]) {
                    notification.alertBody = [NSString stringWithFormat:@"%@ \"%@\"", NSLocalizedString(@"APN_MESSAGE_IN_GROUP",nil), name];
                } else {
                    notification.alertBody = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"APN_MESSAGE_FROM", nil), name];
                }
                break;
            }
            case NotificationNoNameNoPreview:
                notification.alertBody = NSLocalizedString(@"APN_Message", nil);
                break;
            default:
                notification.alertBody = NSLocalizedString(@"APN_Message", nil);
                break;
        }
        
        [[PushManager sharedManager] presentNotification:notification];
    } else {
        if ([Environment.preferences soundInForeground]) {
            AudioServicesPlayAlertSound(_newMessageSound);
        }
    }
}

- (void)dealloc {
    AudioServicesDisposeSystemSoundID(_newMessageSound);
}

@end
