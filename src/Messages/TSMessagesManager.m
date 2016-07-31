//  Created by Frederic Jacobs on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSMessagesManager.h"
#import "NSData+messagePadding.h"
#import "TSAccountManager.h"
#import "TSAttachmentStream.h"
#import "TSCall.h"
#import "TSContactThread.h"
#import "TSDatabaseView.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import "TSInfoMessage.h"
#import "TSInvalidIdentityKeyReceivingErrorMessage.h"
#import "TSMessagesManager+attachments.h"
#import "TSStorageHeaders.h"
#import "TextSecureKitEnv.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/SessionCipher.h>

@interface TSMessagesManager ()

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

- (instancetype)init {
    self = [super init];

    if (self) {
        _dbConnection = [TSStorageManager sharedManager].newDatabaseConnection;
    }

    return self;
}

- (void)handleMessageSignal:(IncomingPushMessageSignal *)messageSignal {
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
    } @catch (NSException *exception) {
        DDLogWarn(@"Received an incorrectly formatted protocol buffer: %@", exception.debugDescription);
    }
}

- (void)handleDeliveryReceipt:(IncomingPushMessageSignal *)signal {
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      TSInteraction *interaction = [TSInteraction interactionForTimestamp:signal.timestamp withTransaction:transaction];
      if ([interaction isKindOfClass:[TSOutgoingMessage class]]) {
          TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)interaction;
          outgoingMessage.messageState       = TSOutgoingMessageStateDelivered;

          [outgoingMessage saveWithTransaction:transaction];
      }
    }];
}

- (void)handleSecureMessage:(IncomingPushMessageSignal *)secureMessage {
    @synchronized(self) {
        TSStorageManager *storageManager = [TSStorageManager sharedManager];
        NSString *recipientId            = secureMessage.source;
        int deviceId                     = (int)secureMessage.sourceDevice;

        if (![storageManager containsSession:recipientId deviceId:deviceId]) {
            [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
              TSErrorMessage *errorMessage =
                  [TSErrorMessage missingSessionWithSignal:secureMessage withTransaction:transaction];
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
        } @catch (NSException *exception) {
            [self processException:exception pushSignal:secureMessage];
            return;
        }

        [self handleIncomingMessage:secureMessage withPushContent:content];
    }
}

- (void)handlePreKeyBundle:(IncomingPushMessageSignal *)preKeyMessage {
    @synchronized(self) {
        TSStorageManager *storageManager = [TSStorageManager sharedManager];
        NSString *recipientId            = preKeyMessage.source;
        int deviceId                     = (int)preKeyMessage.sourceDevice;

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
        } @catch (NSException *exception) {
            [self processException:exception pushSignal:preKeyMessage];
            return;
        }

        [self handleIncomingMessage:preKeyMessage withPushContent:content];
    }
}

- (void)handleIncomingMessage:(IncomingPushMessageSignal *)incomingMessage withPushContent:(PushMessageContent *)content
{
    if (content.hasGroup) {
        __block BOOL ignoreMessage = NO;
        [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            TSGroupModel *emptyModelToFillOutId =
                [[TSGroupModel alloc] initWithTitle:nil memberIds:nil image:nil groupId:content.group.id];
            TSGroupThread *gThread = [TSGroupThread threadWithGroupModel:emptyModelToFillOutId transaction:transaction];
            if (gThread == nil && content.group.type != PushMessageContentGroupContextTypeUpdate) {
                ignoreMessage = YES;
            }
        }];
        if (ignoreMessage) {
            DDLogDebug(@"Received message from group that I left or don't know "
                       @"about, ignoring");
            return;
        }
    }
    if ((content.flags & PushMessageContentFlagsEndSession) != 0) {
        DDLogVerbose(@"Received end session message...");
        [self handleEndSessionMessage:incomingMessage withContent:content];
    } else if (content.attachments.count > 0 ||
               (content.hasGroup && content.group.type == PushMessageContentGroupContextTypeUpdate &&
                content.group.hasAvatar)) {
        DDLogVerbose(@"Received push media message (attachment) or group with an avatar...");
        [self handleReceivedMediaMessage:incomingMessage withContent:content];
    } else {
        DDLogVerbose(@"Received individual push text message...");
        [self handleReceivedTextMessage:incomingMessage withContent:content];
    }
}

- (void)handleEndSessionMessage:(IncomingPushMessageSignal *)message withContent:(PushMessageContent *)content {
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactId:message.source transaction:transaction];
      uint64_t timeStamp      = message.timestamp;

      if (thread) {
          [[[TSInfoMessage alloc] initWithTimestamp:timeStamp
                                           inThread:thread
                                        messageType:TSInfoMessageTypeSessionDidEnd] saveWithTransaction:transaction];
      }
    }];

    [[TSStorageManager sharedManager] deleteAllSessionsForContact:message.source];
}

- (void)handleReceivedTextMessage:(IncomingPushMessageSignal *)message withContent:(PushMessageContent *)content
{
    [self handleReceivedMessage:message withContent:content attachmentIds:content.attachments];
}

- (void)handleSendToMyself:(TSOutgoingMessage *)outgoingMessage
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      TSContactThread *cThread =
          [TSContactThread getOrCreateThreadWithContactId:[TSAccountManager localNumber] transaction:transaction];
      [cThread saveWithTransaction:transaction];
      TSIncomingMessage *incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:(outgoingMessage.timestamp + 1)
                                                                               inThread:cThread
                                                                            messageBody:outgoingMessage.body
                                                                          attachmentIds:outgoingMessage.attachmentIds];
      [incomingMessage saveWithTransaction:transaction];
    }];
}

- (void)handleReceivedMessage:(IncomingPushMessageSignal *)message
                  withContent:(PushMessageContent *)content
                attachmentIds:(NSArray<NSString *> *)attachmentIds
{
    [self handleReceivedMessage:message withContent:content attachmentIds:attachmentIds completionBlock:nil];
}

- (void)handleReceivedMessage:(IncomingPushMessageSignal *)message
                  withContent:(PushMessageContent *)content
                attachmentIds:(NSArray<NSString *> *)attachmentIds
              completionBlock:(void (^)(NSString *messageIdentifier))completionBlock
{
    uint64_t timeStamp = message.timestamp;
    NSString *body     = content.body;
    NSData *groupId    = content.hasGroup ? content.group.id : nil;

    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      TSIncomingMessage *incomingMessage;
      TSThread *thread;
      if (groupId) {
          TSGroupModel *model =
              [[TSGroupModel alloc] initWithTitle:content.group.name
                                        memberIds:[[[NSSet setWithArray:content.group.members] allObjects] mutableCopy]
                                            image:nil
                                          groupId:content.group.id];
          TSGroupThread *gThread = [TSGroupThread getOrCreateThreadWithGroupModel:model transaction:transaction];
          [gThread saveWithTransaction:transaction];

          if (content.group.type == PushMessageContentGroupContextTypeUpdate) {
              if ([attachmentIds count] == 1) {
                  NSString *avatarId = attachmentIds[0];
                  TSAttachment *avatar = [TSAttachment fetchObjectWithUniqueID:avatarId];
                  if ([avatar isKindOfClass:[TSAttachmentStream class]]) {
                      TSAttachmentStream *stream = (TSAttachmentStream *)avatar;
                      if ([stream isImage]) {
                          model.groupImage = [stream image];
                          // No need to keep the attachment around after assigning the image.
                          [stream removeWithTransaction:transaction];
                      }
                  }
              }

              NSString *updateGroupInfo = [gThread.groupModel getInfoStringAboutUpdateTo:model];
              gThread.groupModel        = model;
              [gThread saveWithTransaction:transaction];
              [[[TSInfoMessage alloc] initWithTimestamp:timeStamp
                                               inThread:gThread
                                            messageType:TSInfoMessageTypeGroupUpdate
                                          customMessage:updateGroupInfo] saveWithTransaction:transaction];
          } else if (content.group.type == PushMessageContentGroupContextTypeQuit) {
              NSString *nameString =
                  [[TextSecureKitEnv sharedEnv].contactsManager nameStringForPhoneIdentifier:message.source];

              if (!nameString) {
                  nameString = message.source;
              }

              NSString *updateGroupInfo =
                  [NSString stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_LEFT", @""), nameString];
              NSMutableArray *newGroupMembers = [NSMutableArray arrayWithArray:gThread.groupModel.groupMemberIds];
              [newGroupMembers removeObject:message.source];
              gThread.groupModel.groupMemberIds = newGroupMembers;

              [gThread saveWithTransaction:transaction];
              [[[TSInfoMessage alloc] initWithTimestamp:timeStamp
                                               inThread:gThread
                                            messageType:TSInfoMessageTypeGroupUpdate
                                          customMessage:updateGroupInfo] saveWithTransaction:transaction];
          } else {
              incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:timeStamp
                                                                    inThread:gThread
                                                                    authorId:message.source
                                                                 messageBody:body
                                                               attachmentIds:attachmentIds];
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
                                                           attachmentIds:attachmentIds];
          thread = cThread;
      }

      if (thread && incomingMessage) {
          // Android allows attachments to be sent with body.
          // We want the text to be displayed under the attachment
          if ([attachmentIds count] > 0 && body != nil && ![body isEqualToString:@""]) {
              uint64_t textMessageTimestamp = timeStamp + 1000;

              if ([thread isGroupThread]) {
                  TSGroupThread *gThread = (TSGroupThread *)thread;
                  TSIncomingMessage *textMessage = [[TSIncomingMessage alloc] initWithTimestamp:textMessageTimestamp
                                                                                       inThread:gThread
                                                                                       authorId:message.source
                                                                                    messageBody:body
                                                                                  attachmentIds:nil];
                  [textMessage saveWithTransaction:transaction];
              } else {
                  TSContactThread *cThread = (TSContactThread *)thread;
                  TSIncomingMessage *textMessage = [[TSIncomingMessage alloc] initWithTimestamp:textMessageTimestamp
                                                                                       inThread:cThread
                                                                                    messageBody:body
                                                                                  attachmentIds:nil];
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
          [[TextSecureKitEnv sharedEnv]
                  .notificationsManager notifyUserForIncomingMessage:incomingMessage
                                                                from:name
                                                            inThread:thread];
      }
    }];
}

- (void)processException:(NSException *)exception pushSignal:(IncomingPushMessageSignal *)signal {
    DDLogError(@"Got exception: %@ of type: %@", exception.description, exception.name);
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      TSErrorMessage *errorMessage;

      if ([exception.name isEqualToString:NoSessionException]) {
          errorMessage = [TSErrorMessage missingSessionWithSignal:signal withTransaction:transaction];
      } else if ([exception.name isEqualToString:InvalidKeyException]) {
          errorMessage = [TSErrorMessage invalidKeyExceptionWithSignal:signal withTransaction:transaction];
      } else if ([exception.name isEqualToString:InvalidKeyIdException]) {
          errorMessage = [TSErrorMessage invalidKeyExceptionWithSignal:signal withTransaction:transaction];
      } else if ([exception.name isEqualToString:DuplicateMessageException]) {
          // Duplicate messages are dismissed
          return;
      } else if ([exception.name isEqualToString:InvalidVersionException]) {
          errorMessage = [TSErrorMessage invalidVersionWithSignal:signal withTransaction:transaction];
      } else if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
          errorMessage =
              [TSInvalidIdentityKeyReceivingErrorMessage untrustedKeyWithSignal:signal withTransaction:transaction];
      } else {
          errorMessage = [TSErrorMessage corruptedMessageWithSignal:signal withTransaction:transaction];
      }

      [errorMessage saveWithTransaction:transaction];
    }];
}

- (void)processException:(NSException *)exception
         outgoingMessage:(TSOutgoingMessage *)message
                inThread:(TSThread *)thread {
    DDLogWarn(@"Got exception: %@", exception.description);

    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      TSErrorMessage *errorMessage;

      if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
          errorMessage = [TSInvalidIdentityKeySendingErrorMessage
              untrustedKeyWithOutgoingMessage:message
                                     inThread:thread
                                 forRecipient:exception.userInfo[TSInvalidRecipientKey]
                                 preKeyBundle:exception.userInfo[TSInvalidPreKeyBundleKey]
                              withTransaction:transaction];
          message.messageState = TSOutgoingMessageStateUnsent;
          [message saveWithTransaction:transaction];
      } else if (message.groupMetaMessage == TSGroupMessageNone) {
          // Only update this with exception if it is not a group message as group
          // messages may except for one group
          // send but not another and the UI doesn't know how to handle that
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

- (NSUInteger)unreadMessagesCountExcept:(TSThread *)thread {
    __block NSUInteger numberOfItems;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      numberOfItems = [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInAllGroups];
      numberOfItems =
          numberOfItems - [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInGroup:thread.uniqueId];
    }];

    return numberOfItems;
}

- (NSUInteger)unreadMessagesInThread:(TSThread *)thread {
    __block NSUInteger numberOfItems;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      numberOfItems = [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInGroup:thread.uniqueId];
    }];
    return numberOfItems;
}

@end
