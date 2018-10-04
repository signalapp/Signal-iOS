//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DebugUIStress.h"
#import "OWSMessageSender.h"
#import "OWSTableViewController.h"
#import "SignalApp.h"
#import "ThreadUtil.h"
#import <RelayMessaging/Environment.h>

@import RelayServiceKit;

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIStress

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Stress";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    OWSAssert(thread);
    
    NSMutableArray<OWSTableItem *> *items = [NSMutableArray new];
    [items addObject:[OWSTableItem itemWithTitle:@"Send empty message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread block:^(RelayRecipient *recipient) {
                                             return [NSData new];
                                         }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send random noise message"
                                     actionBlock:^{
                                         [DebugUIStress
                                             sendStressMessage:thread
                                                         block:^(RelayRecipient *recipient) {
                                                             NSUInteger contentLength = arc4random_uniform(32);
                                                             return [Cryptography generateRandomBytes:contentLength];
                                                         }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send no payload message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread block:^(RelayRecipient *recipient) {
                                             OWSSignalServiceProtosContentBuilder *contentBuilder = [OWSSignalServiceProtosContentBuilder new];
                                             return [[contentBuilder build] data];
                                         }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send empty null message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread block:^(RelayRecipient *recipient) {
                                             OWSSignalServiceProtosContentBuilder *contentBuilder = [OWSSignalServiceProtosContentBuilder new];
                                             OWSSignalServiceProtosNullMessageBuilder *nullMessageBuilder = [OWSSignalServiceProtosNullMessageBuilder new];
                                             contentBuilder.nullMessage = [nullMessageBuilder build];
                                             return [[contentBuilder build] data];
                                         }];
                                     }]];
    [items
        addObject:[OWSTableItem itemWithTitle:@"Send random null message"
                                  actionBlock:^{
                                      [DebugUIStress
                                          sendStressMessage:thread
                                                      block:^(RelayRecipient *recipient) {
                                                          OWSSignalServiceProtosContentBuilder *contentBuilder =
                                                              [OWSSignalServiceProtosContentBuilder new];
                                                          OWSSignalServiceProtosNullMessageBuilder *nullMessageBuilder =
                                                              [OWSSignalServiceProtosNullMessageBuilder new];
                                                          NSUInteger contentLength = arc4random_uniform(32);
                                                          nullMessageBuilder.padding =
                                                              [Cryptography generateRandomBytes:contentLength];
                                                          contentBuilder.nullMessage = [nullMessageBuilder build];
                                                          return [[contentBuilder build] data];
                                                      }];
                                  }]];
    [items
        addObject:[OWSTableItem itemWithTitle:@"Send empty sync message"
                                  actionBlock:^{
                                      [DebugUIStress
                                          sendStressMessage:thread
                                                      block:^(RelayRecipient *recipient) {
                                                          OWSSignalServiceProtosContentBuilder *contentBuilder =
                                                              [OWSSignalServiceProtosContentBuilder new];
                                                          OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder =
                                                              [OWSSignalServiceProtosSyncMessageBuilder new];
                                                          contentBuilder.syncMessage = [syncMessageBuilder build];
                                                          return [[contentBuilder build] data];
                                                      }];
                                  }]];
    [items
        addObject:[OWSTableItem itemWithTitle:@"Send empty sync sent message"
                                  actionBlock:^{
                                      [DebugUIStress
                                          sendStressMessage:thread
                                                      block:^(RelayRecipient *recipient) {
                                                          OWSSignalServiceProtosContentBuilder *contentBuilder =
                                                              [OWSSignalServiceProtosContentBuilder new];
                                                          OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder =
                                                              [OWSSignalServiceProtosSyncMessageBuilder new];
                                                          OWSSignalServiceProtosSyncMessageSentBuilder *sentBuilder =
                                                              [OWSSignalServiceProtosSyncMessageSentBuilder new];
                                                          syncMessageBuilder.sent = [sentBuilder build];
                                                          contentBuilder.syncMessage = [syncMessageBuilder build];
                                                          return [[contentBuilder build] data];
                                                      }];
                                  }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send whitespace text data message"
                                     actionBlock:^{
                                         [DebugUIStress
                                             sendStressMessage:thread
                                                         block:^(RelayRecipient *recipient) {
                                                             OWSSignalServiceProtosContentBuilder *contentBuilder =
                                                                 [OWSSignalServiceProtosContentBuilder new];
                                                             OWSSignalServiceProtosDataMessageBuilder *dataBuilder =
                                                                 [OWSSignalServiceProtosDataMessageBuilder new];
                                                             dataBuilder.body = @" ";
                                                             [DebugUIStress ensureGroupOfDataBuilder:dataBuilder
                                                                                              thread:thread];
                                                             contentBuilder.dataMessage = [dataBuilder build];
                                                             return [[contentBuilder build] data];
                                                         }];
                                     }]];
    [items addObject:[OWSTableItem
                         itemWithTitle:@"Send bad attachment data message"
                           actionBlock:^{
                               [DebugUIStress
                                   sendStressMessage:thread
                                               block:^(RelayRecipient *recipient) {
                                                   OWSSignalServiceProtosContentBuilder *contentBuilder =
                                                       [OWSSignalServiceProtosContentBuilder new];
                                                   OWSSignalServiceProtosDataMessageBuilder *dataBuilder =
                                                       [OWSSignalServiceProtosDataMessageBuilder new];
                                                   OWSSignalServiceProtosAttachmentPointerBuilder *attachmentPointer =
                                                       [OWSSignalServiceProtosAttachmentPointerBuilder new];
                                                   [attachmentPointer setId:arc4random_uniform(32) + 1];
                                                   [attachmentPointer setContentType:@"1"];
                                                   [attachmentPointer setSize:arc4random_uniform(32) + 1];
                                                   [attachmentPointer setDigest:[Cryptography generateRandomBytes:1]];
                                                   [attachmentPointer setFileName:@" "];
                                                   [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                                   contentBuilder.dataMessage = [dataBuilder build];
                                                   return [[contentBuilder build] data];
                                               }];
                           }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send normal text data message"
                                     actionBlock:^{
                                         [DebugUIStress
                                             sendStressMessage:thread
                                                         block:^(RelayRecipient *recipient) {
                                                             OWSSignalServiceProtosContentBuilder *contentBuilder =
                                                                 [OWSSignalServiceProtosContentBuilder new];
                                                             OWSSignalServiceProtosDataMessageBuilder *dataBuilder =
                                                                 [OWSSignalServiceProtosDataMessageBuilder new];
                                                             dataBuilder.body = @"alice";
                                                             [DebugUIStress ensureGroupOfDataBuilder:dataBuilder
                                                                                              thread:thread];
                                                             contentBuilder.dataMessage = [dataBuilder build];
                                                             return [[contentBuilder build] data];
                                                         }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send N text messages with same timestamp"
                                     actionBlock:^{
                                         uint64_t timestamp = [NSDate ows_millisecondTimeStamp];
                                         for (int i = 0; i < 3; i++) {
                                             [DebugUIStress
                                                 sendStressMessage:thread
                                                         timestamp:timestamp
                                                             block:^(RelayRecipient *recipient) {
                                                                 OWSSignalServiceProtosContentBuilder *contentBuilder =
                                                                     [OWSSignalServiceProtosContentBuilder new];
                                                                 OWSSignalServiceProtosDataMessageBuilder *dataBuilder =
                                                                     [OWSSignalServiceProtosDataMessageBuilder new];
                                                                 dataBuilder.body = [NSString stringWithFormat:@"%@ %d",
                                                                                              [NSUUID UUID].UUIDString,
                                                                                              i];
                                                                 [DebugUIStress ensureGroupOfDataBuilder:dataBuilder
                                                                                                  thread:thread];
                                                                 contentBuilder.dataMessage = [dataBuilder build];
                                                                 return [[contentBuilder build] data];
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
                                               block:^(RelayRecipient *recipient) {
                                                   OWSSignalServiceProtosContentBuilder *contentBuilder =
                                                       [OWSSignalServiceProtosContentBuilder new];
                                                   OWSSignalServiceProtosDataMessageBuilder *dataBuilder =
                                                       [OWSSignalServiceProtosDataMessageBuilder new];
                                                   dataBuilder.body =
                                                       [[NSUUID UUID].UUIDString stringByAppendingString:@" now"];
                                                   [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                                   contentBuilder.dataMessage = [dataBuilder build];
                                                   return [[contentBuilder build] data];
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
                                               block:^(RelayRecipient *recipient) {
                                                   OWSSignalServiceProtosContentBuilder *contentBuilder =
                                                       [OWSSignalServiceProtosContentBuilder new];
                                                   OWSSignalServiceProtosDataMessageBuilder *dataBuilder =
                                                       [OWSSignalServiceProtosDataMessageBuilder new];
                                                   dataBuilder.body =
                                                       [[NSUUID UUID].UUIDString stringByAppendingString:@" now"];
                                                   [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                                   contentBuilder.dataMessage = [dataBuilder build];
                                                   return [[contentBuilder build] data];
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
                                               block:^(RelayRecipient *recipient) {
                                                   OWSSignalServiceProtosContentBuilder *contentBuilder =
                                                       [OWSSignalServiceProtosContentBuilder new];
                                                   OWSSignalServiceProtosDataMessageBuilder *dataBuilder =
                                                       [OWSSignalServiceProtosDataMessageBuilder new];
                                                   dataBuilder.body =
                                                       [[NSUUID UUID].UUIDString stringByAppendingString:@" now"];
                                                   [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                                   contentBuilder.dataMessage = [dataBuilder build];
                                                   return [[contentBuilder build] data];
                                               }];
                           }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send N text messages with same timestamp"
                                     actionBlock:^{
                                         OWSSignalServiceProtosContentBuilder *contentBuilder =
                                             [OWSSignalServiceProtosContentBuilder new];
                                         OWSSignalServiceProtosDataMessageBuilder *dataBuilder =
                                             [OWSSignalServiceProtosDataMessageBuilder new];
                                         dataBuilder.body = @"alice";
                                         contentBuilder.dataMessage = [dataBuilder build];
                                         [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                         NSData *data = [[contentBuilder build] data];

                                         uint64_t timestamp = [NSDate ows_millisecondTimeStamp];

                                         for (int i = 0; i < 3; i++) {
                                             [DebugUIStress sendStressMessage:thread
                                                                    timestamp:timestamp
                                                                        block:^(RelayRecipient *recipient) {
                                                                            return data;
                                                                        }];
                                         }
                                     }]];
    [items
        addObject:[OWSTableItem itemWithTitle:@"Send malformed sync sent message 1"
                                  actionBlock:^{
                                      [DebugUIStress
                                          sendStressMessage:thread
                                                      block:^(RelayRecipient *recipient) {
                                                          OWSSignalServiceProtosContentBuilder *contentBuilder =
                                                              [OWSSignalServiceProtosContentBuilder new];
                                                          OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder =
                                                              [OWSSignalServiceProtosSyncMessageBuilder new];
                                                          OWSSignalServiceProtosSyncMessageSentBuilder *sentBuilder =
                                                              [OWSSignalServiceProtosSyncMessageSentBuilder new];
                                                          sentBuilder.destination = @"abc";
                                                          sentBuilder.timestamp = arc4random_uniform(32) + 1;
                                                          OWSSignalServiceProtosDataMessageBuilder *dataBuilder =
                                                              [OWSSignalServiceProtosDataMessageBuilder new];
                                                          sentBuilder.message = [dataBuilder build];
                                                          syncMessageBuilder.sent = [sentBuilder build];
                                                          contentBuilder.syncMessage = [syncMessageBuilder build];
                                                          return [[contentBuilder build] data];
                                                      }];
                                  }]];
    [items
        addObject:[OWSTableItem itemWithTitle:@"Send malformed sync sent message 2"
                                  actionBlock:^{
                                      [DebugUIStress
                                          sendStressMessage:thread
                                                      block:^(RelayRecipient *recipient) {
                                                          OWSSignalServiceProtosContentBuilder *contentBuilder =
                                                              [OWSSignalServiceProtosContentBuilder new];
                                                          OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder =
                                                              [OWSSignalServiceProtosSyncMessageBuilder new];
                                                          OWSSignalServiceProtosSyncMessageSentBuilder *sentBuilder =
                                                              [OWSSignalServiceProtosSyncMessageSentBuilder new];
                                                          sentBuilder.destination = @"abc";
                                                          sentBuilder.timestamp = 0;
                                                          OWSSignalServiceProtosDataMessageBuilder *dataBuilder =
                                                              [OWSSignalServiceProtosDataMessageBuilder new];
                                                          sentBuilder.message = [dataBuilder build];
                                                          syncMessageBuilder.sent = [sentBuilder build];
                                                          contentBuilder.syncMessage = [syncMessageBuilder build];
                                                          return [[contentBuilder build] data];
                                                      }];
                                  }]];
    [items
        addObject:[OWSTableItem itemWithTitle:@"Send malformed sync sent message 3"
                                  actionBlock:^{
                                      [DebugUIStress
                                          sendStressMessage:thread
                                                      block:^(RelayRecipient *recipient) {
                                                          OWSSignalServiceProtosContentBuilder *contentBuilder =
                                                              [OWSSignalServiceProtosContentBuilder new];
                                                          OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder =
                                                              [OWSSignalServiceProtosSyncMessageBuilder new];
                                                          OWSSignalServiceProtosSyncMessageSentBuilder *sentBuilder =
                                                              [OWSSignalServiceProtosSyncMessageSentBuilder new];
                                                          sentBuilder.destination = @"abc";
                                                          sentBuilder.timestamp = 0;
                                                          OWSSignalServiceProtosDataMessageBuilder *dataBuilder =
                                                              [OWSSignalServiceProtosDataMessageBuilder new];
                                                          dataBuilder.body = @" ";
                                                          sentBuilder.message = [dataBuilder build];
                                                          syncMessageBuilder.sent = [sentBuilder build];
                                                          contentBuilder.syncMessage = [syncMessageBuilder build];
                                                          return [[contentBuilder build] data];
                                                      }];
                                  }]];
    [items
        addObject:[OWSTableItem itemWithTitle:@"Send malformed sync sent message 4"
                                  actionBlock:^{
                                      [DebugUIStress
                                          sendStressMessage:thread
                                                      block:^(RelayRecipient *recipient) {
                                                          OWSSignalServiceProtosContentBuilder *contentBuilder =
                                                              [OWSSignalServiceProtosContentBuilder new];
                                                          OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder =
                                                              [OWSSignalServiceProtosSyncMessageBuilder new];
                                                          OWSSignalServiceProtosSyncMessageSentBuilder *sentBuilder =
                                                              [OWSSignalServiceProtosSyncMessageSentBuilder new];
                                                          sentBuilder.destination = @"abc";
                                                          sentBuilder.timestamp = 0;
                                                          OWSSignalServiceProtosDataMessageBuilder *dataBuilder =
                                                              [OWSSignalServiceProtosDataMessageBuilder new];
                                                          dataBuilder.body = @" ";
                                                          OWSSignalServiceProtosGroupContextBuilder *groupBuilder =
                                                              [OWSSignalServiceProtosGroupContextBuilder new];
                                                          [groupBuilder setId:[Cryptography generateRandomBytes:1]];
                                                          dataBuilder.group = [groupBuilder build];
                                                          sentBuilder.message = [dataBuilder build];
                                                          syncMessageBuilder.sent = [sentBuilder build];
                                                          contentBuilder.syncMessage = [syncMessageBuilder build];
                                                          return [[contentBuilder build] data];
                                                      }];
                                  }]];
    [items
        addObject:[OWSTableItem itemWithTitle:@"Send malformed sync sent message 5"
                                  actionBlock:^{
                                      [DebugUIStress
                                          sendStressMessage:thread
                                                      block:^(RelayRecipient *recipient) {
                                                          OWSSignalServiceProtosContentBuilder *contentBuilder =
                                                              [OWSSignalServiceProtosContentBuilder new];
                                                          OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder =
                                                              [OWSSignalServiceProtosSyncMessageBuilder new];
                                                          OWSSignalServiceProtosSyncMessageSentBuilder *sentBuilder =
                                                              [OWSSignalServiceProtosSyncMessageSentBuilder new];
                                                          sentBuilder.destination = @"abc";
                                                          sentBuilder.timestamp = 0;
                                                          OWSSignalServiceProtosDataMessageBuilder *dataBuilder =
                                                              [OWSSignalServiceProtosDataMessageBuilder new];
                                                          dataBuilder.body = @" ";
                                                          OWSSignalServiceProtosGroupContextBuilder *groupBuilder =
                                                              [OWSSignalServiceProtosGroupContextBuilder new];
                                                          [groupBuilder setId:[Cryptography generateRandomBytes:1]];
                                                          dataBuilder.group = [groupBuilder build];
                                                          sentBuilder.message = [dataBuilder build];
                                                          syncMessageBuilder.sent = [sentBuilder build];
                                                          contentBuilder.syncMessage = [syncMessageBuilder build];
                                                          return [[contentBuilder build] data];
                                                      }];
                                  }]];
    [items
        addObject:[OWSTableItem itemWithTitle:@"Send empty sync sent message 6"
                                  actionBlock:^{
                                      [DebugUIStress
                                          sendStressMessage:thread
                                                      block:^(RelayRecipient *recipient) {
                                                          OWSSignalServiceProtosContentBuilder *contentBuilder =
                                                              [OWSSignalServiceProtosContentBuilder new];
                                                          OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder =
                                                              [OWSSignalServiceProtosSyncMessageBuilder new];
                                                          OWSSignalServiceProtosSyncMessageSentBuilder *sentBuilder =
                                                              [OWSSignalServiceProtosSyncMessageSentBuilder new];
                                                          sentBuilder.destination = @"abc";
                                                          syncMessageBuilder.sent = [sentBuilder build];
                                                          contentBuilder.syncMessage = [syncMessageBuilder build];
                                                          return [[contentBuilder build] data];
                                                      }];
                                  }]];
    
    if (thread) {
        TSThread *groupThread = (TSThread *)thread;
        [items addObject:[OWSTableItem itemWithTitle:@"Hallucinate twin group"
                                         actionBlock:^{
                                             [DebugUIStress hallucinateTwinGroup:groupThread];
                                         }]];
    }
    return [OWSTableSection sectionWithTitle:self.name items:items];
}

+ (void)ensureGroupOfDataBuilder:(OWSSignalServiceProtosDataMessageBuilder *)dataBuilder thread:(TSThread *)thread
{
    OWSAssert(dataBuilder);
    OWSAssert(thread);

    if (thread.isOneOnOne) {
        return;
    }

    OWSSignalServiceProtosGroupContextBuilder *groupBuilder = [OWSSignalServiceProtosGroupContextBuilder new];
    [groupBuilder setType:OWSSignalServiceProtosGroupContextTypeDeliver];
    [groupBuilder setId:[thread.uniqueId dataUsingEncoding:NSUTF8StringEncoding]];
    [dataBuilder setGroup:groupBuilder.build];
}

+ (void)sendStressMessage:(TSOutgoingMessage *)message
{
    OWSAssert(message);

    OWSMessageSender *messageSender = [Environment current].messageSender;
    [messageSender enqueueMessage:message
        success:^{
            DDLogInfo(@"%@ Successfully sent message.", self.logTag);
        }
        failure:^(NSError *error) {
            DDLogWarn(@"%@ Failed to deliver message with error: %@", self.logTag, error);
        }];
}

+ (void)sendStressMessage:(TSThread *)thread
                    block:(DynamicOutgoingMessageBlock)block
{
    OWSAssert(thread);
    OWSAssert(block);

    OWSDynamicOutgoingMessage *message =
        [[OWSDynamicOutgoingMessage alloc] initWithPlainTextDataBlock:block thread:thread];

    [self sendStressMessage:message];
}

+ (void)sendStressMessage:(TSThread *)thread timestamp:(uint64_t)timestamp block:(DynamicOutgoingMessageBlock)block
{
    OWSAssert(thread);
    OWSAssert(block);

    OWSDynamicOutgoingMessage *message =
        [[OWSDynamicOutgoingMessage alloc] initWithPlainTextDataBlock:block timestamp:timestamp thread:thread];

    [self sendStressMessage:message];
}

// Creates a new group (by cloning the current group) without informing the,
// other members. This can be used to test "group info requests", etc.
+ (void)hallucinateTwinGroup:(TSThread *)groupThread
{
    __block TSThread *newthread;
    [OWSPrimaryStorage.dbReadWriteConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
             newthread = [TSThread getOrCreateThreadWithParticipants:groupThread.participantIds transaction:transaction];
        }];
    OWSAssert(newthread);

    [SignalApp.sharedApp presentConversationForThread:newthread];
}

@end

NS_ASSUME_NONNULL_END
