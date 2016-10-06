//  Created by Frederic Jacobs on 17/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "ContactsUpdater.h"
#import "NSData+messagePadding.h"
#import "NSDate+millisecondTimeStamp.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSLegacyMessageServiceParams.h"
#import "OWSMessageServiceParams.h"
#import "OWSOutgoingSentMessageTranscript.h"
#import "PreKeyBundle+jsonDict.h"
#import "TSAccountManager.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSInfoMessage.h"
#import "TSMessagesManager+sendMessages.h"
#import "TSNetworkManager.h"
#import "TSStorageHeaders.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/SessionBuilder.h>
#import <AxolotlKit/SessionCipher.h>
#import <Mantle/Mantle.h>
#import <TwistedOakCollapsingFutures/CollapsingFutures.h>

#define RETRY_ATTEMPTS 3

#define InvalidDeviceException @"InvalidDeviceException"

@interface TSMessagesManager (sendMessagesPrivate)

dispatch_queue_t sendingQueue(void);
@property TSNetworkManager *networkManager;

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

- (void)getRecipients:(NSArray<NSString *> *)identifiers
              success:(void (^)(NSArray<SignalRecipient *> *))success
              failure:(void (^)(NSError *error))failure {
    NSMutableArray<SignalRecipient *> *recipients = [NSMutableArray array];

    __block NSError *latestError;
    for (NSString *recipientId in identifiers) {
        __block SignalRecipient *recipient;
        [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
          recipient = [SignalRecipient recipientWithTextSecureIdentifier:recipientId withTransaction:transaction];
        }];


        if (!recipient) {
            [self.contactsUpdater synchronousLookup:recipientId
                success:^(SignalRecipient *newRecipient) {
                  [recipients addObject:newRecipient];
                }
                failure:^(NSError *error) {
                    DDLogWarn(@"Not sending message to unknown recipient with error: %@", error);
                    latestError = error;
                }];
        } else {
            [recipients addObject:recipient];
        }
    }

    if (recipients > 0) {
        success(recipients);
    } else {
        failure(latestError);
    }

    return;
}

- (void)resendMessage:(TSOutgoingMessage *)message
          toRecipient:(SignalRecipient *)recipient
             inThread:(TSThread *)thread
              success:(successSendingCompletionBlock)successCompletionBlock
              failure:(failedSendingCompletionBlock)failedCompletionBlock
{
    if ([thread isKindOfClass:[TSGroupThread class]]) {
        dispatch_async(sendingQueue(), ^{
            [self groupSend:@[ recipient ] // Avoid spamming entire group when resending failed message.
                    Message:message
                   inThread:thread
                    success:successCompletionBlock
                    failure:failedCompletionBlock];
        });
    } else {
        [self sendMessage:message inThread:thread success:successCompletionBlock failure:failedCompletionBlock];
    }
}


- (void)sendMessage:(TSOutgoingMessage *)message
           inThread:(TSThread *)thread
            success:(successSendingCompletionBlock)successCompletionBlock
            failure:(failedSendingCompletionBlock)failedCompletionBlock {
    dispatch_async(sendingQueue(), ^{
      if ([thread isKindOfClass:[TSGroupThread class]]) {
          TSGroupThread *groupThread = (TSGroupThread *)thread;
          [self getRecipients:groupThread.groupModel.groupMemberIds
              success:^(NSArray<SignalRecipient *> *recipients) {
                [self groupSend:recipients
                        Message:message
                       inThread:thread
                        success:successCompletionBlock
                        failure:failedCompletionBlock];
              }
              failure:^(NSError *error) {
                DDLogError(@"Failure to retreive group recipient.");
                [self saveMessage:message withState:TSOutgoingMessageStateUnsent];
              }];

      } else if ([thread isKindOfClass:[TSContactThread class]] ||
          [message isKindOfClass:[OWSOutgoingSyncMessage class]]) {
          TSContactThread *contactThread = (TSContactThread *)thread;

          [self saveMessage:message withState:TSOutgoingMessageStateAttemptingOut];

          if (![contactThread.contactIdentifier isEqualToString:[TSAccountManager localNumber]] ||
              [message isKindOfClass:[OWSOutgoingSyncMessage class]]) {

              NSString *recipientContactId = [message isKindOfClass:[OWSOutgoingSyncMessage class]]
                  ? [TSAccountManager localNumber]
                  : contactThread.contactIdentifier;

              __block SignalRecipient *recipient;
              [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                  recipient = [SignalRecipient recipientWithTextSecureIdentifier:recipientContactId
                                                                 withTransaction:transaction];
              }];

              if (!recipient) {
                  [self.contactsUpdater synchronousLookup:contactThread.contactIdentifier
                      success:^(SignalRecipient *recip) {
                        recipient = recip;
                      }
                      failure:^(NSError *error) {
                        if (error.code == NOTFOUND_ERROR) {
                            DDLogWarn(@"recipient contact not found with error: %@", error);
                            [self unregisteredRecipient:recipient message:message inThread:thread];
                            return;
                        } else {
                            DDLogError(@"contact lookup failed with error: %@", error);
                            [self saveMessage:message withState:TSOutgoingMessageStateUnsent];
                            return;
                        }
                      }];
              }

              if (recipient) {
                  [self sendMessage:message
                        toRecipient:recipient
                           inThread:thread
                        withAttemps:RETRY_ATTEMPTS
                            success:successCompletionBlock
                            failure:failedCompletionBlock];
              }

          } else {
              // Special situation: if we are sending to ourselves in a single thread, we treat this as an incoming
              // message
              [self handleSendToMyself:message];
          }
      }
    });
}

/// For group sends, we're using chained futures to make the code more readable.

- (TOCFuture *)sendMessageFuture:(TSOutgoingMessage *)message
                       recipient:(SignalRecipient *)recipient
                        inThread:(TSThread *)thread {
    TOCFutureSource *futureSource = [[TOCFutureSource alloc] init];

    [self sendMessage:message
        toRecipient:recipient
        inThread:thread
        withAttemps:RETRY_ATTEMPTS
        success:^{
          [futureSource trySetResult:@1];
        }
        failure:^{
          [futureSource trySetFailure:@0];
        }];

    return futureSource.future;
}

- (void)groupSend:(NSArray<SignalRecipient *> *)recipients
          Message:(TSOutgoingMessage *)message
         inThread:(TSThread *)thread
          success:(successSendingCompletionBlock)successBlock
          failure:(failedSendingCompletionBlock)failureBlock
{
    [self saveGroupMessage:message inThread:thread];
    NSMutableArray<TOCFuture *> *futures = [NSMutableArray array];

    for (SignalRecipient *rec in recipients) {
        // we don't need to send the message to ourselves, but otherwise we send
        if (![[rec uniqueId] isEqualToString:[TSStorageManager localNumber]]) {
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

- (void)unregisteredRecipient:(SignalRecipient *)recipient
                      message:(TSOutgoingMessage *)message
                     inThread:(TSThread *)thread {
    [self.dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      [recipient removeWithTransaction:transaction];
      [[TSInfoMessage userNotRegisteredMessageInThread:thread transaction:transaction] saveWithTransaction:transaction];
    }];

    [self saveMessage:message withState:TSOutgoingMessageStateUnsent];
}

- (void)sendMessage:(TSOutgoingMessage *)message
        toRecipient:(SignalRecipient *)recipient
           inThread:(TSThread *)thread
        withAttemps:(int)remainingAttempts
            success:(successSendingCompletionBlock)successBlock
            failure:(failedSendingCompletionBlock)failureBlock
{
    if (remainingAttempts > 0) {
        remainingAttempts -= 1;

        NSArray<NSDictionary *> *deviceMessages;
        @try {
            deviceMessages = [self deviceMessages:message forRecipient:recipient inThread:thread];
        } @catch (NSException *exception) {
            deviceMessages = @[];
            if (remainingAttempts == 0) {
                DDLogWarn(@"%@ Terminal failure to build any device messages. Giving up with exception:%@",
                    self.logTag,
                    exception);
                [self processException:exception outgoingMessage:message inThread:thread];
                return;
            }
        }

        TSSubmitMessageRequest *request = [[TSSubmitMessageRequest alloc] initWithRecipient:recipient.uniqueId
                                                                                   messages:deviceMessages
                                                                                      relay:recipient.relay
                                                                                  timeStamp:message.timestamp];

        [self.networkManager makeRequest:request
            success:^(NSURLSessionDataTask *task, id responseObject) {
                dispatch_async(sendingQueue(), ^{
                    [recipient save];
                    [self handleMessageSentLocally:message];
                    BLOCK_SAFE_RUN(successBlock);
                });
            }
            failure:^(NSURLSessionDataTask *task, NSError *error) {
                NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
                long statuscode = response.statusCode;
                NSData *responseData = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];

                switch (statuscode) {
                    case 404: {
                        [self unregisteredRecipient:recipient message:message inThread:thread];
                        BLOCK_SAFE_RUN(failureBlock);
                        break;
                    }
                    case 409: {
                        // Mismatched devices
                        DDLogWarn(@"%@ Mismatch Devices.", self.logTag);

                        NSError *e;
                        NSDictionary *serializedResponse =
                            [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&e];

                        if (e) {
                            DDLogError(@"%@ Failed to serialize response of mismatched devices: %@", self.logTag, e);
                        } else {
                            [self handleMismatchedDevices:serializedResponse recipient:recipient];
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
                    case 410: {
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
    } else {
        [self saveMessage:message withState:TSOutgoingMessageStateUnsent];
        BLOCK_SAFE_RUN(failureBlock);
    }
}

- (void)handleMismatchedDevices:(NSDictionary *)dictionary recipient:(SignalRecipient *)recipient {
    NSArray *extraDevices   = [dictionary objectForKey:@"extraDevices"];
    NSArray *missingDevices = [dictionary objectForKey:@"missingDevices"];

    if (extraDevices && [extraDevices count] > 0) {
        for (NSNumber *extraDeviceId in extraDevices) {
            [[TSStorageManager sharedManager] deleteSessionForContact:recipient.uniqueId
                                                             deviceId:[extraDeviceId intValue]];
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

- (void)handleMessageSentLocally:(TSOutgoingMessage *)message
{
    [self saveMessage:message withState:TSOutgoingMessageStateSent];
    if (message.shouldSyncTranscript) {
        message.hasSyncedTranscript = YES;
        [self sendSyncTranscriptForMessage:message];
    }

    [self.disappearingMessagesJob setExpirationForMessage:message];
}

- (void)handleMessageSentRemotely:(TSOutgoingMessage *)message sentAt:(uint64_t)sentAt
{
    [self saveMessage:message withState:TSOutgoingMessageStateDelivered];

    [self becomeConsistentWithDisappearingConfigurationForMessage:message];
    [self.disappearingMessagesJob setExpirationForMessage:message expirationStartedAt:sentAt];
}

- (void)handleSendToMyself:(TSOutgoingMessage *)outgoingMessage
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSContactThread *cThread =
            [TSContactThread getOrCreateThreadWithContactId:[TSAccountManager localNumber] transaction:transaction];
        [cThread saveWithTransaction:transaction];
        TSIncomingMessage *incomingMessage =
            [[TSIncomingMessage alloc] initWithTimestamp:(outgoingMessage.timestamp + 1)
                                                inThread:cThread
                                                authorId:[cThread contactIdentifier]
                                             messageBody:outgoingMessage.body
                                           attachmentIds:outgoingMessage.attachmentIds
                                        expiresInSeconds:outgoingMessage.expiresInSeconds];
        [incomingMessage saveWithTransaction:transaction];
    }];
    [self handleMessageSentLocally:outgoingMessage];
}

- (void)sendSyncTranscriptForMessage:(TSOutgoingMessage *)message
{
    OWSOutgoingSentMessageTranscript *sentMessageTranscript =
        [[OWSOutgoingSentMessageTranscript alloc] initWithOutgoingMessage:message];

    [self sendMessage:sentMessageTranscript
        toRecipient:[SignalRecipient selfRecipient]
        inThread:message.thread
        withAttemps:RETRY_ATTEMPTS
        success:^{
            DDLogInfo(@"Succesfully sent sync transcript.");
        }
        failure:^{
            DDLogInfo(@"Failed to send sync transcript.");
        }];
}

- (NSArray<NSDictionary *> *)deviceMessages:(TSOutgoingMessage *)message
                               forRecipient:(SignalRecipient *)recipient
                                   inThread:(TSThread *)thread
{
    NSMutableArray *messagesArray = [NSMutableArray arrayWithCapacity:recipient.devices.count];
    NSData *plainText = [message buildPlainTextData];

    for (NSNumber *deviceNumber in recipient.devices) {
        @try {
            // DEPRECATED - Remove after all clients have been upgraded.
            BOOL isLegacyMessage = ![message isKindOfClass:[OWSOutgoingSyncMessage class]];

            NSDictionary *messageDict = [self encryptedMessageWithPlaintext:plainText
                                                                toRecipient:recipient.uniqueId
                                                                   deviceId:deviceNumber
                                                              keyingStorage:[TSStorageManager sharedManager]
                                                                     legacy:isLegacyMessage];
            if (messageDict) {
                [messagesArray addObject:messageDict];
            } else {
                @throw [NSException exceptionWithName:InvalidMessageException
                                               reason:@"Failed to encrypt message"
                                             userInfo:nil];
            }
        } @catch (NSException *exception) {
            if ([exception.name isEqualToString:InvalidDeviceException]) {
                [recipient removeDevices:[NSSet setWithObject:deviceNumber]];
            } else {
                @throw exception;
            }
        }
    }

    return [messagesArray copy];
}

- (NSDictionary *)encryptedMessageWithPlaintext:(NSData *)plainText
                                    toRecipient:(NSString *)identifier
                                       deviceId:(NSNumber *)deviceNumber
                                  keyingStorage:(TSStorageManager *)storage
                                         legacy:(BOOL)isLegacymessage
{
    if (![storage containsSession:identifier deviceId:[deviceNumber intValue]]) {
        __block dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        __block PreKeyBundle *bundle;

        [self.networkManager
            makeRequest:[[TSRecipientPrekeyRequest alloc] initWithRecipient:identifier
                                                                   deviceId:[deviceNumber stringValue]]
            success:^(NSURLSessionDataTask *task, id responseObject) {
              bundle = [PreKeyBundle preKeyBundleFromDictionary:responseObject forDeviceNumber:deviceNumber];
              dispatch_semaphore_signal(sema);
            }
            failure:^(NSURLSessionDataTask *task, NSError *error) {
              DDLogError(@"Server replied on PreKeyBundle request with error: %@", error);
              NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
              if (response.statusCode == 404) {
                  @throw [NSException exceptionWithName:InvalidDeviceException
                                                 reason:@"Device not registered"
                                               userInfo:nil];
              }
              dispatch_semaphore_signal(sema);
            }];
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

        if (!bundle) {
            @throw [NSException exceptionWithName:InvalidVersionException
                                           reason:@"Can't get a prekey bundle from the server with required information"
                                         userInfo:nil];
        } else {
            SessionBuilder *builder = [[SessionBuilder alloc] initWithSessionStore:storage
                                                                       preKeyStore:storage
                                                                 signedPreKeyStore:storage
                                                                  identityKeyStore:storage
                                                                       recipientId:identifier
                                                                          deviceId:[deviceNumber intValue]];
            @try {
                [builder processPrekeyBundle:bundle];
            } @catch (NSException *exception) {
                if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
                    @throw [NSException
                        exceptionWithName:UntrustedIdentityKeyException
                                   reason:nil
                                 userInfo:@{TSInvalidPreKeyBundleKey : bundle, TSInvalidRecipientKey : identifier}];
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
    NSData *serializedMessage          = encryptedMessage.serialized;
    TSWhisperMessageType messageType   = [self messageTypeForCipherMessage:encryptedMessage];

    OWSMessageServiceParams *messageParams;
    // DEPRECATED - Remove after all clients have been upgraded.
    if (isLegacymessage) {
        messageParams = [[OWSLegacyMessageServiceParams alloc] initWithType:messageType
                                                                recipientId:identifier
                                                                     device:[deviceNumber intValue]
                                                                       body:serializedMessage
                                                             registrationId:cipher.remoteRegistrationId];
    } else {
        messageParams = [[OWSMessageServiceParams alloc] initWithType:messageType
                                                          recipientId:identifier
                                                               device:[deviceNumber intValue]
                                                              content:serializedMessage
                                                       registrationId:cipher.remoteRegistrationId];
    }

    NSError *error;
    NSDictionary *jsonDict = [MTLJSONAdapter JSONDictionaryFromModel:messageParams error:&error];

    if (error) {
        DDLogError(@"Error while making JSON dictionary of message: %@", error.debugDescription);
        return nil;
    }

    return jsonDict;
}

- (TSWhisperMessageType)messageTypeForCipherMessage:(id<CipherMessage>)cipherMessage {
    if ([cipherMessage isKindOfClass:[PreKeyWhisperMessage class]]) {
        return TSPreKeyWhisperMessageType;
    } else if ([cipherMessage isKindOfClass:[WhisperMessage class]]) {
        return TSEncryptedWhisperMessageType;
    }
    return TSUnknownMessageType;
}

- (void)saveMessage:(TSOutgoingMessage *)message withState:(TSOutgoingMessageState)state {
    if (message.groupMetaMessage == TSGroupMessageDeliver || message.groupMetaMessage == TSGroupMessageNone) {
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
          [message setMessageState:state];
          [message saveWithTransaction:transaction];
        }];
    }
}

- (void)saveGroupMessage:(TSOutgoingMessage *)message inThread:(TSThread *)thread {
    if (message.groupMetaMessage == TSGroupMessageDeliver) {
        [self saveMessage:message withState:message.messageState];
    } else if (message.groupMetaMessage == TSGroupMessageQuit) {
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

          [[[TSInfoMessage alloc] initWithTimestamp:message.timestamp
                                           inThread:thread
                                        messageType:TSInfoMessageTypeGroupQuit] saveWithTransaction:transaction];
        }];
    } else {
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

          [[[TSInfoMessage alloc] initWithTimestamp:message.timestamp
                                           inThread:thread
                                        messageType:TSInfoMessageTypeGroupUpdate] saveWithTransaction:transaction];
        }];
    }
}

- (void)handleStaleDevicesWithResponse:(NSData *)responseData recipientId:(NSString *)identifier {
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

+ (NSString *)logTag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)logTag
{
    return self.class.logTag;
}

@end
