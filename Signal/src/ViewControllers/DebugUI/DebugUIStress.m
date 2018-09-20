//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DebugUIStress.h"
#import "OWSMessageSender.h"
#import "OWSTableViewController.h"
#import "SignalApp.h"
#import "ThreadUtil.h"
#import <Curve25519Kit/Randomness.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/Cryptography.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/OWSDynamicOutgoingMessage.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIStress

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Stress";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    OWSAssertDebug(thread);
    
    NSMutableArray<OWSTableItem *> *items = [NSMutableArray new];

#ifdef DEBUG

    [items addObject:[OWSTableItem itemWithTitle:@"Send empty message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread block:^(SignalRecipient *recipient) {
                                             return [NSData new];
                                         }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send random noise message"
                                     actionBlock:^{
                                         [DebugUIStress
                                             sendStressMessage:thread
                                                         block:^(SignalRecipient *recipient) {
                                                             NSUInteger contentLength = arc4random_uniform(32);
                                                             return [Cryptography generateRandomBytes:contentLength];
                                                         }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send no payload message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread
                                                                    block:^(SignalRecipient *recipient) {
                                                                        SSKProtoContentBuilder *contentBuilder =
                                                                            [SSKProtoContentBuilder new];
                                                                        return [[contentBuilder buildIgnoringErrors]
                                                                            serializedDataIgnoringErrors];
                                                                    }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send empty null message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread
                                                                    block:^(SignalRecipient *recipient) {
                                                                        SSKProtoContentBuilder *contentBuilder =
                                                                            [SSKProtoContentBuilder new];
                                                                        SSKProtoNullMessageBuilder *nullMessageBuilder =
                                                                            [SSKProtoNullMessageBuilder new];
                                                                        contentBuilder.nullMessage =
                                                                            [nullMessageBuilder buildIgnoringErrors];
                                                                        return [[contentBuilder buildIgnoringErrors]
                                                                            serializedDataIgnoringErrors];
                                                                    }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send random null message"
                                     actionBlock:^{
                                         [DebugUIStress
                                             sendStressMessage:thread
                                                         block:^(SignalRecipient *recipient) {
                                                             SSKProtoContentBuilder *contentBuilder =
                                                                 [SSKProtoContentBuilder new];
                                                             SSKProtoNullMessageBuilder *nullMessageBuilder =
                                                                 [SSKProtoNullMessageBuilder new];
                                                             NSUInteger contentLength = arc4random_uniform(32);
                                                             nullMessageBuilder.padding =
                                                                 [Cryptography generateRandomBytes:contentLength];
                                                             contentBuilder.nullMessage =
                                                                 [nullMessageBuilder buildIgnoringErrors];
                                                             return [[contentBuilder buildIgnoringErrors]
                                                                 serializedDataIgnoringErrors];
                                                         }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send empty sync message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread
                                                                    block:^(SignalRecipient *recipient) {
                                                                        SSKProtoContentBuilder *contentBuilder =
                                                                            [SSKProtoContentBuilder new];
                                                                        SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                                            [SSKProtoSyncMessageBuilder new];
                                                                        contentBuilder.syncMessage =
                                                                            [syncMessageBuilder buildIgnoringErrors];
                                                                        return [[contentBuilder buildIgnoringErrors]
                                                                            serializedDataIgnoringErrors];
                                                                    }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send empty sync sent message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread
                                                                    block:^(SignalRecipient *recipient) {
                                                                        SSKProtoContentBuilder *contentBuilder =
                                                                            [SSKProtoContentBuilder new];
                                                                        SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                                            [SSKProtoSyncMessageBuilder new];
                                                                        SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                                            [SSKProtoSyncMessageSentBuilder new];
                                                                        syncMessageBuilder.sent =
                                                                            [sentBuilder buildIgnoringErrors];
                                                                        contentBuilder.syncMessage =
                                                                            [syncMessageBuilder buildIgnoringErrors];
                                                                        return [[contentBuilder buildIgnoringErrors]
                                                                            serializedDataIgnoringErrors];
                                                                    }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send whitespace text data message"
                                     actionBlock:^{
                                         [DebugUIStress
                                             sendStressMessage:thread
                                                         block:^(SignalRecipient *recipient) {
                                                             SSKProtoContentBuilder *contentBuilder =
                                                                 [SSKProtoContentBuilder new];
                                                             SSKProtoDataMessageBuilder *dataBuilder =
                                                                 [SSKProtoDataMessageBuilder new];
                                                             dataBuilder.body = @" ";
                                                             [DebugUIStress ensureGroupOfDataBuilder:dataBuilder
                                                                                              thread:thread];
                                                             contentBuilder.dataMessage =
                                                                 [dataBuilder buildIgnoringErrors];
                                                             return [[contentBuilder buildIgnoringErrors]
                                                                 serializedDataIgnoringErrors];
                                                         }];
                                     }]];
    [items
        addObject:[OWSTableItem
                      itemWithTitle:@"Send bad attachment data message"
                        actionBlock:^{
                            [DebugUIStress
                                sendStressMessage:thread
                                            block:^(SignalRecipient *recipient) {
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContentBuilder new];
                                                SSKProtoDataMessageBuilder *dataBuilder =
                                                    [SSKProtoDataMessageBuilder new];
                                                SSKProtoAttachmentPointerBuilder *attachmentPointer =
                                                    [SSKProtoAttachmentPointerBuilder new];
                                                [attachmentPointer setId:arc4random_uniform(32) + 1];
                                                [attachmentPointer setContentType:@"1"];
                                                [attachmentPointer setSize:arc4random_uniform(32) + 1];
                                                [attachmentPointer setDigest:[Cryptography generateRandomBytes:1]];
                                                [attachmentPointer setFileName:@" "];
                                                [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                                contentBuilder.dataMessage = [dataBuilder buildIgnoringErrors];
                                                return
                                                    [[contentBuilder buildIgnoringErrors] serializedDataIgnoringErrors];
                                            }];
                        }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send normal text data message"
                                     actionBlock:^{
                                         [DebugUIStress
                                             sendStressMessage:thread
                                                         block:^(SignalRecipient *recipient) {
                                                             SSKProtoContentBuilder *contentBuilder =
                                                                 [SSKProtoContentBuilder new];
                                                             SSKProtoDataMessageBuilder *dataBuilder =
                                                                 [SSKProtoDataMessageBuilder new];
                                                             dataBuilder.body = @"alice";
                                                             [DebugUIStress ensureGroupOfDataBuilder:dataBuilder
                                                                                              thread:thread];
                                                             contentBuilder.dataMessage =
                                                                 [dataBuilder buildIgnoringErrors];
                                                             return [[contentBuilder buildIgnoringErrors]
                                                                 serializedDataIgnoringErrors];
                                                         }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send N text messages with same timestamp"
                                     actionBlock:^{
                                         uint64_t timestamp = [NSDate ows_millisecondTimeStamp];
                                         for (int i = 0; i < 3; i++) {
                                             [DebugUIStress
                                                 sendStressMessage:thread
                                                         timestamp:timestamp
                                                             block:^(SignalRecipient *recipient) {
                                                                 SSKProtoContentBuilder *contentBuilder =
                                                                     [SSKProtoContentBuilder new];
                                                                 SSKProtoDataMessageBuilder *dataBuilder =
                                                                     [SSKProtoDataMessageBuilder new];
                                                                 dataBuilder.body = [NSString stringWithFormat:@"%@ %d",
                                                                                              [NSUUID UUID].UUIDString,
                                                                                              i];
                                                                 [DebugUIStress ensureGroupOfDataBuilder:dataBuilder
                                                                                                  thread:thread];
                                                                 contentBuilder.dataMessage =
                                                                     [dataBuilder buildIgnoringErrors];
                                                                 return [[contentBuilder buildIgnoringErrors]
                                                                     serializedDataIgnoringErrors];
                                                             }];
                                         }
                                     }]];
    [items addObject:[OWSTableItem
                         itemWithTitle:@"Send text message with current timestamp"
                           actionBlock:^{
                               uint64_t timestamp = [NSDate ows_millisecondTimeStamp];
                               [DebugUIStress
                                   sendStressMessage:thread
                                           timestamp:timestamp
                                               block:^(SignalRecipient *recipient) {
                                                   SSKProtoContentBuilder *contentBuilder =
                                                       [SSKProtoContentBuilder new];
                                                   SSKProtoDataMessageBuilder *dataBuilder =
                                                       [SSKProtoDataMessageBuilder new];
                                                   dataBuilder.body =
                                                       [[NSUUID UUID].UUIDString stringByAppendingString:@" now"];
                                                   [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                                   contentBuilder.dataMessage = [dataBuilder buildIgnoringErrors];
                                                   return [[contentBuilder buildIgnoringErrors]
                                                       serializedDataIgnoringErrors];
                                               }];
                           }]];
    [items addObject:[OWSTableItem
                         itemWithTitle:@"Send text message with future timestamp"
                           actionBlock:^{
                               uint64_t timestamp = [NSDate ows_millisecondTimeStamp];
                               timestamp += kHourInMs;
                               [DebugUIStress
                                   sendStressMessage:thread
                                           timestamp:timestamp
                                               block:^(SignalRecipient *recipient) {
                                                   SSKProtoContentBuilder *contentBuilder =
                                                       [SSKProtoContentBuilder new];
                                                   SSKProtoDataMessageBuilder *dataBuilder =
                                                       [SSKProtoDataMessageBuilder new];
                                                   dataBuilder.body =
                                                       [[NSUUID UUID].UUIDString stringByAppendingString:@" now"];
                                                   [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                                   contentBuilder.dataMessage = [dataBuilder buildIgnoringErrors];
                                                   return [[contentBuilder buildIgnoringErrors]
                                                       serializedDataIgnoringErrors];
                                               }];
                           }]];
    [items addObject:[OWSTableItem
                         itemWithTitle:@"Send text message with past timestamp"
                           actionBlock:^{
                               uint64_t timestamp = [NSDate ows_millisecondTimeStamp];
                               timestamp -= kHourInMs;
                               [DebugUIStress
                                   sendStressMessage:thread
                                           timestamp:timestamp
                                               block:^(SignalRecipient *recipient) {
                                                   SSKProtoContentBuilder *contentBuilder =
                                                       [SSKProtoContentBuilder new];
                                                   SSKProtoDataMessageBuilder *dataBuilder =
                                                       [SSKProtoDataMessageBuilder new];
                                                   dataBuilder.body =
                                                       [[NSUUID UUID].UUIDString stringByAppendingString:@" now"];
                                                   [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                                   contentBuilder.dataMessage = [dataBuilder buildIgnoringErrors];
                                                   return [[contentBuilder buildIgnoringErrors]
                                                       serializedDataIgnoringErrors];
                                               }];
                           }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send N text messages with same timestamp"
                                     actionBlock:^{
                                         SSKProtoContentBuilder *contentBuilder = [SSKProtoContentBuilder new];
                                         SSKProtoDataMessageBuilder *dataBuilder = [SSKProtoDataMessageBuilder new];
                                         dataBuilder.body = @"alice";
                                         contentBuilder.dataMessage = [dataBuilder buildIgnoringErrors];
                                         [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                         NSData *data =
                                             [[contentBuilder buildIgnoringErrors] serializedDataIgnoringErrors];

                                         uint64_t timestamp = [NSDate ows_millisecondTimeStamp];

                                         for (int i = 0; i < 3; i++) {
                                             [DebugUIStress sendStressMessage:thread
                                                                    timestamp:timestamp
                                                                        block:^(SignalRecipient *recipient) {
                                                                            return data;
                                                                        }];
                                         }
                                     }]];
    [items
        addObject:[OWSTableItem
                      itemWithTitle:@"Send malformed sync sent message 1"
                        actionBlock:^{
                            [DebugUIStress
                                sendStressMessage:thread
                                            block:^(SignalRecipient *recipient) {
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContentBuilder new];
                                                SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                    [SSKProtoSyncMessageBuilder new];
                                                SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                    [SSKProtoSyncMessageSentBuilder new];
                                                sentBuilder.destination = @"abc";
                                                sentBuilder.timestamp = arc4random_uniform(32) + 1;
                                                SSKProtoDataMessageBuilder *dataBuilder =
                                                    [SSKProtoDataMessageBuilder new];
                                                sentBuilder.message = [dataBuilder buildIgnoringErrors];
                                                syncMessageBuilder.sent = [sentBuilder buildIgnoringErrors];
                                                contentBuilder.syncMessage = [syncMessageBuilder buildIgnoringErrors];
                                                return
                                                    [[contentBuilder buildIgnoringErrors] serializedDataIgnoringErrors];
                                            }];
                        }]];
    [items
        addObject:[OWSTableItem
                      itemWithTitle:@"Send malformed sync sent message 2"
                        actionBlock:^{
                            [DebugUIStress
                                sendStressMessage:thread
                                            block:^(SignalRecipient *recipient) {
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContentBuilder new];
                                                SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                    [SSKProtoSyncMessageBuilder new];
                                                SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                    [SSKProtoSyncMessageSentBuilder new];
                                                sentBuilder.destination = @"abc";
                                                sentBuilder.timestamp = 0;
                                                SSKProtoDataMessageBuilder *dataBuilder =
                                                    [SSKProtoDataMessageBuilder new];
                                                sentBuilder.message = [dataBuilder buildIgnoringErrors];
                                                syncMessageBuilder.sent = [sentBuilder buildIgnoringErrors];
                                                contentBuilder.syncMessage = [syncMessageBuilder buildIgnoringErrors];
                                                return
                                                    [[contentBuilder buildIgnoringErrors] serializedDataIgnoringErrors];
                                            }];
                        }]];
    [items
        addObject:[OWSTableItem
                      itemWithTitle:@"Send malformed sync sent message 3"
                        actionBlock:^{
                            [DebugUIStress
                                sendStressMessage:thread
                                            block:^(SignalRecipient *recipient) {
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContentBuilder new];
                                                SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                    [SSKProtoSyncMessageBuilder new];
                                                SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                    [SSKProtoSyncMessageSentBuilder new];
                                                sentBuilder.destination = @"abc";
                                                sentBuilder.timestamp = 0;
                                                SSKProtoDataMessageBuilder *dataBuilder =
                                                    [SSKProtoDataMessageBuilder new];
                                                dataBuilder.body = @" ";
                                                sentBuilder.message = [dataBuilder buildIgnoringErrors];
                                                syncMessageBuilder.sent = [sentBuilder buildIgnoringErrors];
                                                contentBuilder.syncMessage = [syncMessageBuilder buildIgnoringErrors];
                                                return
                                                    [[contentBuilder buildIgnoringErrors] serializedDataIgnoringErrors];
                                            }];
                        }]];
    [items
        addObject:[OWSTableItem
                      itemWithTitle:@"Send malformed sync sent message 4"
                        actionBlock:^{
                            [DebugUIStress
                                sendStressMessage:thread
                                            block:^(SignalRecipient *recipient) {
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContentBuilder new];
                                                SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                    [SSKProtoSyncMessageBuilder new];
                                                SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                    [SSKProtoSyncMessageSentBuilder new];
                                                sentBuilder.destination = @"abc";
                                                sentBuilder.timestamp = 0;
                                                SSKProtoDataMessageBuilder *dataBuilder =
                                                    [SSKProtoDataMessageBuilder new];
                                                dataBuilder.body = @" ";
                                                SSKProtoGroupContextBuilder *groupBuilder =
                                                    [SSKProtoGroupContextBuilder new];
                                                [groupBuilder setId:[Cryptography generateRandomBytes:1]];
                                                dataBuilder.group = [groupBuilder buildIgnoringErrors];
                                                sentBuilder.message = [dataBuilder buildIgnoringErrors];
                                                syncMessageBuilder.sent = [sentBuilder buildIgnoringErrors];
                                                contentBuilder.syncMessage = [syncMessageBuilder buildIgnoringErrors];
                                                return
                                                    [[contentBuilder buildIgnoringErrors] serializedDataIgnoringErrors];
                                            }];
                        }]];
    [items
        addObject:[OWSTableItem
                      itemWithTitle:@"Send malformed sync sent message 5"
                        actionBlock:^{
                            [DebugUIStress
                                sendStressMessage:thread
                                            block:^(SignalRecipient *recipient) {
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContentBuilder new];
                                                SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                    [SSKProtoSyncMessageBuilder new];
                                                SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                    [SSKProtoSyncMessageSentBuilder new];
                                                sentBuilder.destination = @"abc";
                                                sentBuilder.timestamp = 0;
                                                SSKProtoDataMessageBuilder *dataBuilder =
                                                    [SSKProtoDataMessageBuilder new];
                                                dataBuilder.body = @" ";
                                                SSKProtoGroupContextBuilder *groupBuilder =
                                                    [SSKProtoGroupContextBuilder new];
                                                [groupBuilder setId:[Cryptography generateRandomBytes:1]];
                                                dataBuilder.group = [groupBuilder buildIgnoringErrors];
                                                sentBuilder.message = [dataBuilder buildIgnoringErrors];
                                                syncMessageBuilder.sent = [sentBuilder buildIgnoringErrors];
                                                contentBuilder.syncMessage = [syncMessageBuilder buildIgnoringErrors];
                                                return
                                                    [[contentBuilder buildIgnoringErrors] serializedDataIgnoringErrors];
                                            }];
                        }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send empty sync sent message 6"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread
                                                                    block:^(SignalRecipient *recipient) {
                                                                        SSKProtoContentBuilder *contentBuilder =
                                                                            [SSKProtoContentBuilder new];
                                                                        SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                                            [SSKProtoSyncMessageBuilder new];
                                                                        SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                                            [SSKProtoSyncMessageSentBuilder new];
                                                                        sentBuilder.destination = @"abc";
                                                                        syncMessageBuilder.sent =
                                                                            [sentBuilder buildIgnoringErrors];
                                                                        contentBuilder.syncMessage =
                                                                            [syncMessageBuilder buildIgnoringErrors];
                                                                        return [[contentBuilder buildIgnoringErrors]
                                                                            serializedDataIgnoringErrors];
                                                                    }];
                                     }]];

    if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        [items addObject:[OWSTableItem itemWithTitle:@"Hallucinate twin group"
                                         actionBlock:^{
                                             [DebugUIStress hallucinateTwinGroup:groupThread];
                                         }]];
    }

#endif

    return [OWSTableSection sectionWithTitle:self.name items:items];
}

#ifdef DEBUG

+ (void)ensureGroupOfDataBuilder:(SSKProtoDataMessageBuilder *)dataBuilder thread:(TSThread *)thread
{
    OWSAssertDebug(dataBuilder);
    OWSAssertDebug(thread);

    if (![thread isKindOfClass:[TSGroupThread class]]) {
        return;
    }

    TSGroupThread *groupThread = (TSGroupThread *)thread;
    SSKProtoGroupContextBuilder *groupBuilder = [SSKProtoGroupContextBuilder new];
    [groupBuilder setType:SSKProtoGroupContextTypeDeliver];
    [groupBuilder setId:groupThread.groupModel.groupId];
    [dataBuilder setGroup:groupBuilder.buildIgnoringErrors];
}

+ (void)sendStressMessage:(TSOutgoingMessage *)message
{
    OWSAssertDebug(message);

    OWSMessageSender *messageSender = SSKEnvironment.shared.messageSender;
    [messageSender enqueueMessage:message
        success:^{
            OWSLogInfo(@"Successfully sent message.");
        }
        failure:^(NSError *error) {
            OWSLogWarn(@"Failed to deliver message with error: %@", error);
        }];
}

+ (void)sendStressMessage:(TSThread *)thread
                    block:(DynamicOutgoingMessageBlock)block
{
    OWSAssertDebug(thread);
    OWSAssertDebug(block);

    OWSDynamicOutgoingMessage *message =
        [[OWSDynamicOutgoingMessage alloc] initWithPlainTextDataBlock:block thread:thread];

    [self sendStressMessage:message];
}

+ (void)sendStressMessage:(TSThread *)thread timestamp:(uint64_t)timestamp block:(DynamicOutgoingMessageBlock)block
{
    OWSAssertDebug(thread);
    OWSAssertDebug(block);

    OWSDynamicOutgoingMessage *message =
        [[OWSDynamicOutgoingMessage alloc] initWithPlainTextDataBlock:block timestamp:timestamp thread:thread];

    [self sendStressMessage:message];
}

// Creates a new group (by cloning the current group) without informing the,
// other members. This can be used to test "group info requests", etc.
+ (void)hallucinateTwinGroup:(TSGroupThread *)groupThread
{
    __block TSGroupThread *thread;
    [OWSPrimaryStorage.dbReadWriteConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            TSGroupModel *groupModel =
                [[TSGroupModel alloc] initWithTitle:[groupThread.groupModel.groupName stringByAppendingString:@" Copy"]
                                          memberIds:groupThread.groupModel.groupMemberIds
                                              image:groupThread.groupModel.groupImage
                                            groupId:[Randomness generateRandomBytes:16]];
            thread = [TSGroupThread getOrCreateThreadWithGroupModel:groupModel transaction:transaction];
        }];
    OWSAssertDebug(thread);

    [SignalApp.sharedApp presentConversationForThread:thread animated:YES];
}

#endif

@end

NS_ASSUME_NONNULL_END
