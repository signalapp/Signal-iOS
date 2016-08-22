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

- (void)handleReceivedEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
{
    @try {
        switch (envelope.type) {
            case OWSSignalServiceProtosEnvelopeTypeCiphertext:
                [self handleSecureMessage:envelope];
                break;
            case OWSSignalServiceProtosEnvelopeTypePrekeyBundle:
                [self handlePreKeyBundle:envelope];
                break;
            case OWSSignalServiceProtosEnvelopeTypeReceipt:
                DDLogInfo(@"Received a delivery receipt");
                [self handleDeliveryReceipt:envelope];
                break;

            // Other messages are just dismissed for now.

            case OWSSignalServiceProtosEnvelopeTypeKeyExchange:
                DDLogWarn(@"Received Key Exchange Message, not supported");
                break;
            case OWSSignalServiceProtosEnvelopeTypeUnknown:
                DDLogWarn(@"Received an unknown message type");
                break;
            default:
                DDLogWarn(@"Received unhandled envelope type: %d", envelope.type);
                break;
        }
    } @catch (NSException *exception) {
        DDLogWarn(@"Received an incorrectly formatted protocol buffer: %@", exception.debugDescription);
    }
}

- (void)handleDeliveryReceipt:(OWSSignalServiceProtosEnvelope *)envelope
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSInteraction *interaction =
            [TSInteraction interactionForTimestamp:envelope.timestamp withTransaction:transaction];
        if ([interaction isKindOfClass:[TSOutgoingMessage class]]) {
            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)interaction;
            outgoingMessage.messageState = TSOutgoingMessageStateDelivered;

            [outgoingMessage saveWithTransaction:transaction];
        }
    }];
}

- (void)handleSecureMessage:(OWSSignalServiceProtosEnvelope *)messageEnvelope
{
    @synchronized(self) {
        TSStorageManager *storageManager = [TSStorageManager sharedManager];
        NSString *recipientId = messageEnvelope.source;
        int deviceId = messageEnvelope.sourceDevice;

        if (![storageManager containsSession:recipientId deviceId:deviceId]) {
            [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                TSErrorMessage *errorMessage =
                    [TSErrorMessage missingSessionWithEnvelope:messageEnvelope withTransaction:transaction];
                [errorMessage saveWithTransaction:transaction];
            }];
            return;
        }

        // DEPRECATED - Remove after all clients have been upgraded.
        NSData *encryptedData = messageEnvelope.hasContent ? messageEnvelope.content : messageEnvelope.legacyMessage;
        if (!encryptedData) {
            DDLogError(@"Skipping message envelope which had no encrypted data");
            return;
        }

        NSData *plaintextData;
        @try {
            WhisperMessage *message = [[WhisperMessage alloc] initWithData:encryptedData];
            SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:storageManager
                                                                    preKeyStore:storageManager
                                                              signedPreKeyStore:storageManager
                                                               identityKeyStore:storageManager
                                                                    recipientId:recipientId
                                                                       deviceId:deviceId];

            plaintextData = [[cipher decrypt:message] removePadding];
        } @catch (NSException *exception) {
            [self processException:exception envelope:messageEnvelope];
            return;
        }

        OWSSignalServiceProtosDataMessage *dataMessage;
        if (messageEnvelope.hasContent) { // New style content payload
            OWSSignalServiceProtosContent *content = [OWSSignalServiceProtosContent parseFromData:plaintextData];
            dataMessage = content.dataMessage;
        } else if (messageEnvelope.hasLegacyMessage) { // DEPRECATED - Remove after all clients have been upgraded.
            dataMessage = [OWSSignalServiceProtosDataMessage parseFromData:plaintextData];
        }

        if (!dataMessage) {
            DDLogWarn(@"Ignoring content that has no dataMessage.");
            return;
        }

        [self handleIncomingEnvelope:messageEnvelope withDataMessage:dataMessage];
    }
}

- (void)handlePreKeyBundle:(OWSSignalServiceProtosEnvelope *)preKeyEnvelope
{
    @synchronized(self) {
        TSStorageManager *storageManager = [TSStorageManager sharedManager];
        NSString *recipientId = preKeyEnvelope.source;
        int deviceId = preKeyEnvelope.sourceDevice;

        // DEPRECATED - Remove after all clients have been upgraded.
        NSData *encryptedData = preKeyEnvelope.hasContent ? preKeyEnvelope.content : preKeyEnvelope.legacyMessage;
        if (!encryptedData) {
            DDLogError(@"Skipping message envelope which had no encrypted data");
            return;
        }

        NSData *plaintextData;
        @try {
            PreKeyWhisperMessage *message = [[PreKeyWhisperMessage alloc] initWithData:encryptedData];
            SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:storageManager
                                                                    preKeyStore:storageManager
                                                              signedPreKeyStore:storageManager
                                                               identityKeyStore:storageManager
                                                                    recipientId:recipientId
                                                                       deviceId:deviceId];

            plaintextData = [[cipher decrypt:message] removePadding];
        } @catch (NSException *exception) {
            [self processException:exception envelope:preKeyEnvelope];
            return;
        }

        OWSSignalServiceProtosDataMessage *dataMessage;
        if (preKeyEnvelope.hasContent) {
            OWSSignalServiceProtosContent *content = [OWSSignalServiceProtosContent parseFromData:plaintextData];
            if (content.hasDataMessage) {
                dataMessage = content.dataMessage;
            }
        } else if (preKeyEnvelope.hasLegacyMessage) {
            // DEPRECATED - Remove after all clients have been upgraded.
            dataMessage = [OWSSignalServiceProtosDataMessage parseFromData:plaintextData];
        }

        if (!dataMessage) {
            DDLogError(@"unable to ascertain decrypted dataMessage from preKeyEnvelope");
            return;
        }

        [self handleIncomingEnvelope:preKeyEnvelope withDataMessage:dataMessage];
    }
}

- (void)handleIncomingEnvelope:(OWSSignalServiceProtosEnvelope *)incomingEnvelope
               withDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    if (dataMessage.hasGroup) {
        __block BOOL ignoreMessage = NO;
        [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            TSGroupModel *emptyModelToFillOutId =
                [[TSGroupModel alloc] initWithTitle:nil memberIds:nil image:nil groupId:dataMessage.group.id];
            TSGroupThread *gThread = [TSGroupThread threadWithGroupModel:emptyModelToFillOutId transaction:transaction];
            if (gThread == nil && dataMessage.group.type != OWSSignalServiceProtosGroupContextTypeUpdate) {
                ignoreMessage = YES;
            }
        }];
        if (ignoreMessage) {
            DDLogDebug(@"Received message from group that I left or don't know "
                       @"about, ignoring");
            return;
        }
    }
    if ((dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsEndSession) != 0) {
        DDLogVerbose(@"Received end session message...");
        [self handleEndSessionMessageWithEnvelope:incomingEnvelope dataMessage:dataMessage];
    } else if (dataMessage.attachments.count > 0
        || (dataMessage.hasGroup && dataMessage.group.type == OWSSignalServiceProtosGroupContextTypeUpdate
               && dataMessage.group.avatar)) {

        DDLogVerbose(@"Received push media message (attachment) or group with an avatar...");
        [self handleReceivedMediaWithEnvelope:incomingEnvelope dataMessage:dataMessage];
    } else {
        DDLogVerbose(@"Received individual push text message...");
        [self handleReceivedTextMessageWithEnvelope:incomingEnvelope dataMessage:dataMessage];
    }
}

- (void)handleEndSessionMessageWithEnvelope:(OWSSignalServiceProtosEnvelope *)endSessionEnvelope
                                dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSContactThread *thread =
            [TSContactThread getOrCreateThreadWithContactId:endSessionEnvelope.source transaction:transaction];
        uint64_t timeStamp = endSessionEnvelope.timestamp;

        if (thread) {
            [[[TSInfoMessage alloc] initWithTimestamp:timeStamp
                                             inThread:thread
                                          messageType:TSInfoMessageTypeSessionDidEnd] saveWithTransaction:transaction];
        }
    }];

    [[TSStorageManager sharedManager] deleteAllSessionsForContact:endSessionEnvelope.source];
}

- (void)handleReceivedTextMessageWithEnvelope:(OWSSignalServiceProtosEnvelope *)textMessageEnvelope
                                  dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    [self handleReceivedEnvelope:textMessageEnvelope withDataMessage:dataMessage attachmentIds:@[] completionBlock:nil];
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

- (void)handleReceivedEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
               withDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
                 attachmentIds:(NSArray<NSString *> *)attachmentIds
               completionBlock:(void (^)(NSString *messageIdentifier))completionBlock
{
    uint64_t timeStamp = envelope.timestamp;
    NSString *body = dataMessage.body;
    NSData *groupId = dataMessage.hasGroup ? dataMessage.group.id : nil;

    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      TSIncomingMessage *incomingMessage;
      TSThread *thread;
      if (groupId) {
          NSMutableArray *uniqueMemberIds = [[[NSSet setWithArray:dataMessage.group.members] allObjects] mutableCopy];
          TSGroupModel *model = [[TSGroupModel alloc] initWithTitle:dataMessage.group.name
                                                          memberIds:uniqueMemberIds
                                                              image:nil
                                                            groupId:dataMessage.group.id];
          TSGroupThread *gThread = [TSGroupThread getOrCreateThreadWithGroupModel:model transaction:transaction];
          [gThread saveWithTransaction:transaction];

          if (dataMessage.group.type == OWSSignalServiceProtosGroupContextTypeUpdate) {
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
          } else if (dataMessage.group.type == OWSSignalServiceProtosGroupContextTypeQuit) {
              NSString *nameString =
                  [[TextSecureKitEnv sharedEnv].contactsManager nameStringForPhoneIdentifier:envelope.source];

              if (!nameString) {
                  nameString = envelope.source;
              }

              NSString *updateGroupInfo =
                  [NSString stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_LEFT", @""), nameString];
              NSMutableArray *newGroupMembers = [NSMutableArray arrayWithArray:gThread.groupModel.groupMemberIds];
              [newGroupMembers removeObject:envelope.source];
              gThread.groupModel.groupMemberIds = newGroupMembers;

              [gThread saveWithTransaction:transaction];
              [[[TSInfoMessage alloc] initWithTimestamp:timeStamp
                                               inThread:gThread
                                            messageType:TSInfoMessageTypeGroupUpdate
                                          customMessage:updateGroupInfo] saveWithTransaction:transaction];
          } else {
              incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:timeStamp
                                                                    inThread:gThread
                                                                    authorId:envelope.source
                                                                 messageBody:body
                                                               attachmentIds:attachmentIds];
              [incomingMessage saveWithTransaction:transaction];
          }

          thread = gThread;
      } else {
          TSContactThread *cThread = [TSContactThread getOrCreateThreadWithContactId:envelope.source
                                                                         transaction:transaction
                                                                            envelope:envelope];

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
                                                                                       authorId:envelope.source
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

- (void)processException:(NSException *)exception envelope:(OWSSignalServiceProtosEnvelope *)envelope
{
    DDLogError(@"Got exception: %@ of type: %@", exception.description, exception.name);
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      TSErrorMessage *errorMessage;

      if ([exception.name isEqualToString:NoSessionException]) {
          errorMessage = [TSErrorMessage missingSessionWithEnvelope:envelope withTransaction:transaction];
      } else if ([exception.name isEqualToString:InvalidKeyException]) {
          errorMessage = [TSErrorMessage invalidKeyExceptionWithEnvelope:envelope withTransaction:transaction];
      } else if ([exception.name isEqualToString:InvalidKeyIdException]) {
          errorMessage = [TSErrorMessage invalidKeyExceptionWithEnvelope:envelope withTransaction:transaction];
      } else if ([exception.name isEqualToString:DuplicateMessageException]) {
          // Duplicate messages are dismissed
          return;
      } else if ([exception.name isEqualToString:InvalidVersionException]) {
          errorMessage = [TSErrorMessage invalidVersionWithEnvelope:envelope withTransaction:transaction];
      } else if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
          errorMessage =
              [TSInvalidIdentityKeyReceivingErrorMessage untrustedKeyWithEnvelope:envelope withTransaction:transaction];
      } else {
          errorMessage = [TSErrorMessage corruptedMessageWithEnvelope:envelope withTransaction:transaction];
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
