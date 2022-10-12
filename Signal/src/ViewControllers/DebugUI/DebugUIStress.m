//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "DebugUIStress.h"
#import "Signal-Swift.h"
#import "SignalApp.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/ThreadUtil.h>
#import <SignalServiceKit/MessageSender.h>
#import <SignalServiceKit/OWSDynamicOutgoingMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalUI/OWSTableViewController.h>

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

@interface DebugUIStress ()

@property (nonatomic, nullable) NSTimer *thrashTimer;

@end

#pragma mark -

@implementation DebugUIStress

+ (instancetype)shared
{
    static DebugUIStress *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [self new];
    });
    return instance;
}

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Stress";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    OWSAssertDebug(thread);
    
    NSMutableArray<OWSTableItem *> *items = [NSMutableArray new];

    [items addObject:[OWSTableItem
                         itemWithTitle:@"Send empty message"
                           actionBlock:^{ [DebugUIStress sendStressMessage:thread block:^{ return [NSData new]; }]; }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send random noise message"
                                     actionBlock:^{
                                         [DebugUIStress
                                             sendStressMessage:thread
                                                         block:^{
                                                             NSUInteger contentLength = arc4random_uniform(32);
                                                             return [Cryptography generateRandomBytes:contentLength];
                                                         }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send no payload message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread
                                                                    block:^{
                                                                        SSKProtoContentBuilder *contentBuilder =
                                                                            [SSKProtoContent builder];
                                                                        return [[contentBuilder buildIgnoringErrors]
                                                                            serializedDataIgnoringErrors];
                                                                    }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send empty null message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread
                                                                    block:^{
                                                                        SSKProtoContentBuilder *contentBuilder =
                                                                            [SSKProtoContent builder];
                                                                        SSKProtoNullMessageBuilder *nullMessageBuilder =
                                                                            [SSKProtoNullMessage builder];
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
                                                         block:^{
                                                             SSKProtoContentBuilder *contentBuilder =
                                                                 [SSKProtoContent builder];
                                                             SSKProtoNullMessageBuilder *nullMessageBuilder =
                                                                 [SSKProtoNullMessage builder];
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
                                                                    block:^{
                                                                        SSKProtoContentBuilder *contentBuilder =
                                                                            [SSKProtoContent builder];
                                                                        SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                                            [SSKProtoSyncMessage builder];
                                                                        contentBuilder.syncMessage =
                                                                            [syncMessageBuilder buildIgnoringErrors];
                                                                        return [[contentBuilder buildIgnoringErrors]
                                                                            serializedDataIgnoringErrors];
                                                                    }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send empty sync sent message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread
                                                                    block:^{
                                                                        SSKProtoContentBuilder *contentBuilder =
                                                                            [SSKProtoContent builder];
                                                                        SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                                            [SSKProtoSyncMessage builder];
                                                                        SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                                            [SSKProtoSyncMessageSent builder];
                                                                        syncMessageBuilder.sent =
                                                                            [sentBuilder buildIgnoringErrors];
                                                                        contentBuilder.syncMessage =
                                                                            [syncMessageBuilder buildIgnoringErrors];
                                                                        return [[contentBuilder buildIgnoringErrors]
                                                                            serializedDataIgnoringErrors];
                                                                    }];
                                     }]];
    [items addObject:[OWSTableItem
                         itemWithTitle:@"Send whitespace text data message"
                           actionBlock:^{
                               [DebugUIStress
                                   sendStressMessage:thread
                                               block:^{
                                                   SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                   SSKProtoDataMessageBuilder *dataBuilder =
                                                       [SSKProtoDataMessage builder];
                                                   dataBuilder.body = @" ";
                                                   [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                                   contentBuilder.dataMessage = [dataBuilder buildIgnoringErrors];
                                                   return [[contentBuilder buildIgnoringErrors]
                                                       serializedDataIgnoringErrors];
                                               }];
                           }]];
    [items addObject:[OWSTableItem
                         itemWithTitle:@"Send bad attachment data message"
                           actionBlock:^{
                               [DebugUIStress
                                   sendStressMessage:thread
                                               block:^{
                                                   SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                   SSKProtoDataMessageBuilder *dataBuilder =
                                                       [SSKProtoDataMessage builder];
                                                   SSKProtoAttachmentPointerBuilder *attachmentPointer =
                                                       [SSKProtoAttachmentPointer builder];
                                                   attachmentPointer.cdnID = arc4random_uniform(32) + 1;
                                                   [attachmentPointer setContentType:@"1"];
                                                   [attachmentPointer setSize:arc4random_uniform(32) + 1];
                                                   [attachmentPointer setDigest:[Cryptography generateRandomBytes:1]];
                                                   [attachmentPointer setFileName:@" "];
                                                   [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                                   contentBuilder.dataMessage = [dataBuilder buildIgnoringErrors];
                                                   return [[contentBuilder buildIgnoringErrors]
                                                       serializedDataIgnoringErrors];
                                               }];
                           }]];
    [items addObject:[OWSTableItem
                         itemWithTitle:@"Send normal text data message"
                           actionBlock:^{
                               [DebugUIStress
                                   sendStressMessage:thread
                                               block:^{
                                                   SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                   SSKProtoDataMessageBuilder *dataBuilder =
                                                       [SSKProtoDataMessage builder];
                                                   dataBuilder.body = @"alice";
                                                   [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                                   contentBuilder.dataMessage = [dataBuilder buildIgnoringErrors];
                                                   return [[contentBuilder buildIgnoringErrors]
                                                       serializedDataIgnoringErrors];
                                               }];
                           }]];
    [items
        addObject:[OWSTableItem
                      itemWithTitle:@"Send N text messages with same timestamp"
                        actionBlock:^{
                            uint64_t timestamp = [NSDate ows_millisecondTimeStamp];
                            for (int i = 0; i < 3; i++) {
                                [DebugUIStress
                                    sendStressMessage:thread
                                            timestamp:timestamp
                                                block:^{
                                                    SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                    SSKProtoDataMessageBuilder *dataBuilder =
                                                        [SSKProtoDataMessage builder];
                                                    dataBuilder.body = [NSString
                                                        stringWithFormat:@"%@ %d", [NSUUID UUID].UUIDString, i];
                                                    [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                                    contentBuilder.dataMessage = [dataBuilder buildIgnoringErrors];
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
                                               block:^{
                                                   SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                   SSKProtoDataMessageBuilder *dataBuilder =
                                                       [SSKProtoDataMessage builder];
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
                                               block:^{
                                                   SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                   SSKProtoDataMessageBuilder *dataBuilder =
                                                       [SSKProtoDataMessage builder];
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
                                               block:^{
                                                   SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                   SSKProtoDataMessageBuilder *dataBuilder =
                                                       [SSKProtoDataMessage builder];
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
                                         SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                         SSKProtoDataMessageBuilder *dataBuilder = [SSKProtoDataMessage builder];
                                         dataBuilder.body = @"alice";
                                         contentBuilder.dataMessage = [dataBuilder buildIgnoringErrors];
                                         [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                         NSData *data =
                                             [[contentBuilder buildIgnoringErrors] serializedDataIgnoringErrors];

                                         uint64_t timestamp = [NSDate ows_millisecondTimeStamp];

                                         for (int i = 0; i < 3; i++) {
                                             [DebugUIStress sendStressMessage:thread
                                                                    timestamp:timestamp
                                                                        block:^{ return data; }];
                                         }
                                     }]];
    [items
        addObject:[OWSTableItem
                      itemWithTitle:@"Send malformed sync sent message 1"
                        actionBlock:^{
                            [DebugUIStress
                                sendStressMessage:thread
                                            block:^{
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                    [SSKProtoSyncMessage builder];
                                                SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                    [SSKProtoSyncMessageSent builder];
                                                sentBuilder.destinationUuid = @"abc";
                                                sentBuilder.timestamp = arc4random_uniform(32) + 1;
                                                SSKProtoDataMessageBuilder *dataBuilder = [SSKProtoDataMessage builder];
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
                                            block:^{
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                    [SSKProtoSyncMessage builder];
                                                SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                    [SSKProtoSyncMessageSent builder];
                                                sentBuilder.destinationUuid = @"abc";
                                                sentBuilder.timestamp = 0;
                                                SSKProtoDataMessageBuilder *dataBuilder = [SSKProtoDataMessage builder];
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
                                            block:^{
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                    [SSKProtoSyncMessage builder];
                                                SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                    [SSKProtoSyncMessageSent builder];
                                                sentBuilder.destinationUuid = @"abc";
                                                sentBuilder.timestamp = 0;
                                                SSKProtoDataMessageBuilder *dataBuilder = [SSKProtoDataMessage builder];
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
                                            block:^{
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                    [SSKProtoSyncMessage builder];
                                                SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                    [SSKProtoSyncMessageSent builder];
                                                sentBuilder.destinationUuid = @"abc";
                                                sentBuilder.timestamp = 0;
                                                SSKProtoDataMessageBuilder *dataBuilder = [SSKProtoDataMessage builder];
                                                dataBuilder.body = @" ";
                                                SSKProtoGroupContextBuilder *groupBuilder = [SSKProtoGroupContext
                                                    builderWithId:[Cryptography generateRandomBytes:1]];
                                                [groupBuilder setType:SSKProtoGroupContextTypeDeliver];
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
                                            block:^{
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                    [SSKProtoSyncMessage builder];
                                                SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                    [SSKProtoSyncMessageSent builder];
                                                sentBuilder.destinationUuid = @"abc";
                                                sentBuilder.timestamp = 0;
                                                SSKProtoDataMessageBuilder *dataBuilder = [SSKProtoDataMessage builder];
                                                dataBuilder.body = @" ";
                                                SSKProtoGroupContextBuilder *groupBuilder = [SSKProtoGroupContext
                                                    builderWithId:[Cryptography generateRandomBytes:1]];
                                                [groupBuilder setType:SSKProtoGroupContextTypeDeliver];
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
                                                                    block:^{
                                                                        SSKProtoContentBuilder *contentBuilder =
                                                                            [SSKProtoContent builder];
                                                                        SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                                            [SSKProtoSyncMessage builder];
                                                                        SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                                            [SSKProtoSyncMessageSent builder];
                                                                        sentBuilder.destinationUuid = @"abc";
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
        [items addObject:[OWSTableItem itemWithTitle:@"Clone as v1 group"
                                         actionBlock:^{
            [DebugUIStress cloneAsV1Group:groupThread];
        }]];
        [items addObject:[OWSTableItem itemWithTitle:@"Clone as v2 group"
                                         actionBlock:^{
            [DebugUIStress cloneAsV2Group:groupThread];
        }]];
        [items addObject:[OWSTableItem itemWithTitle:@"Copy members to another group"
                                         actionBlock:^{
                                             UIViewController *fromViewController =
                                                 [[UIApplication sharedApplication] frontmostViewController];
                                             [DebugUIStress copyToAnotherGroup:groupThread
                                                            fromViewController:fromViewController];
                                         }]];
        [items addObject:[OWSTableItem itemWithTitle:@"Add debug members to group"
                                         actionBlock:^{
            [DebugUIStress addDebugMembersToGroup:groupThread];
        }]];
        if (thread.isGroupV2Thread) {
            [items addObject:[OWSTableItem itemWithTitle:@"Make all members admins"
                                             actionBlock:^{ [DebugUIStress makeAllMembersAdmin:groupThread]; }]];
        }
        [items addObject:[OWSTableItem itemWithTitle:@"Log membership"
                                         actionBlock:^{ [DebugUIStress logMembership:groupThread]; }]];
    }

    [items addObject:[OWSTableItem itemWithTitle:@"Make group w. unregistered users"
                                     actionBlock:^{
                                         [DebugUIStress makeUnregisteredGroup];
                                     }]];

    __weak DebugUIStress *weakSelf = self;
    [items addObject:[OWSTableItem itemWithTitle:@"Thrash writes 10/second"
                                     actionBlock:^{
                                         [weakSelf thrashWithMaxWritesPerSecond:10 thread:thread];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Thrash writes 100/second"
                                     actionBlock:^{
                                         [weakSelf thrashWithMaxWritesPerSecond:100 thread:thread];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Stop thrash" actionBlock:^{ [weakSelf stopThrash]; }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Delete other profiles"
                                     actionBlock:^{ [DebugUIStress deleteOtherProfiles]; }]];

    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        [items addObject:[OWSTableItem
                             itemWithTitle:@"Log groups for contact"
                               actionBlock:^{ [DebugUIStress logGroupsForAddress:contactThread.contactAddress]; }]];
    }

    return [OWSTableSection sectionWithTitle:self.name items:items];
}

+ (void)ensureGroupOfDataBuilder:(SSKProtoDataMessageBuilder *)dataBuilder thread:(TSThread *)thread
{
    OWSAssertDebug(dataBuilder);
    OWSAssertDebug(thread);

    if (![thread isKindOfClass:[TSGroupThread class]]) {
        return;
    }

    TSGroupThread *groupThread = (TSGroupThread *)thread;
    SSKProtoGroupContextBuilder *groupBuilder = [SSKProtoGroupContext builderWithId:groupThread.groupModel.groupId];
    [groupBuilder setType:SSKProtoGroupContextTypeDeliver];
    [groupBuilder setId:groupThread.groupModel.groupId];
    [dataBuilder setGroup:groupBuilder.buildIgnoringErrors];
}

+ (void)sendStressMessage:(TSOutgoingMessage *)message
{
    OWSAssertDebug(message);

    BOOL isDynamic = [message isKindOfClass:[OWSDynamicOutgoingMessage class]];
    BOOL shouldSendDurably = !isDynamic;

    if (shouldSendDurably) {
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [self.messageSenderJobQueue addMessage:message.asPreparer transaction:transaction];
        });
    } else {
        [self.messageSender sendMessage:message.asPreparer
            success:^{ OWSLogInfo(@"Success."); }
            failure:^(NSError *error) { OWSFailDebug(@"Error: %@", error); }];
    }
}

+ (void)sendStressMessage:(TSThread *)thread
                    block:(DynamicOutgoingMessageBlock)block
{
    OWSAssertDebug(thread);
    OWSAssertDebug(block);

    __block OWSDynamicOutgoingMessage *message;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        message = [[OWSDynamicOutgoingMessage alloc] initWithThread:thread
                                                        transaction:transaction
                                                 plainTextDataBlock:block];
    }];

    [self sendStressMessage:message];
}

+ (void)sendStressMessage:(TSThread *)thread timestamp:(uint64_t)timestamp block:(DynamicOutgoingMessageBlock)block
{
    OWSAssertDebug(thread);
    OWSAssertDebug(block);

    __block OWSDynamicOutgoingMessage *message;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        message = [[OWSDynamicOutgoingMessage alloc] initWithThread:thread
                                                          timestamp:timestamp
                                                        transaction:transaction
                                                 plainTextDataBlock:block];
    }];

    [self sendStressMessage:message];
}

+ (void)makeUnregisteredGroup
{
    NSMutableArray<SignalServiceAddress *> *recipientAddresses = [NSMutableArray new];
    for (int i = 0; i < 3; i++) {
        NSMutableString *recipientNumber = [@"+1999" mutableCopy];
        for (int j = 0; j < 3; j++) {
            uint32_t digit = arc4random_uniform(10);
            [recipientNumber appendFormat:@"%d", (int)digit];
        }
        [recipientAddresses addObject:[[SignalServiceAddress alloc] initWithUuid:[NSUUID UUID]
                                                                     phoneNumber:recipientNumber]];
    }
    [recipientAddresses addObject:self.tsAccountManager.localAddress];

    for (int i = 0; i < 3; i++) {
        [recipientAddresses addObject:[[SignalServiceAddress alloc] initWithUuid:[NSUUID UUID] phoneNumber:nil]];
    }

    [GroupManager localCreateNewGroupObjcWithMembers:recipientAddresses
        groupId:nil
        name:NSUUID.UUID.UUIDString
        avatarData:nil
        disappearingMessageToken:DisappearingMessageToken.disabledToken
        newGroupSeed:nil
        shouldSendMessage:NO
        success:^(TSGroupThread *thread) { [SignalApp.shared presentConversationForThread:thread animated:YES]; }
        failure:^(NSError *error) { OWSFailDebug(@"Error: %@", error); }];
}

- (void)thrashWithMaxWritesPerSecond:(NSUInteger)maxWritesPerSecond thread:(TSThread *)thread
{
    NSTimeInterval delaySeconds = kSecondInterval / maxWritesPerSecond;
    __block uint64_t counter = 0;
    [self stopThrash];
    DebugUIStress.shared.thrashTimer = [NSTimer
        scheduledTimerWithTimeInterval:delaySeconds
                               repeats:YES
                                 block:^(NSTimer *timer) {
                                     counter = counter + 1;
                                     OWSLogVerbose(@"counter: %llu", counter);
                                     dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                                         [self thrashWritesWithThread:thread];
                                     });
                                 }];
}

- (void)thrashWritesWithThread:(TSThread *)thread
{
    __block TSThread *interactionThread = thread;
    __block TSThread *_Nullable otherThread = nil;
    BOOL shouldUseOtherThread = arc4random_uniform(2) == 0;
    if (shouldUseOtherThread) {
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            BOOL shouldUseGroupThread = arc4random_uniform(2) == 0;
            if (shouldUseGroupThread) {
                NSError *_Nullable error;
                otherThread =
                    [GroupManager remoteUpsertExistingGroupV1WithGroupId:[TSGroupModel generateRandomV1GroupId]
                                                                    name:NSUUID.UUID.UUIDString
                                                              avatarData:nil
                                                                 members:@[]
                                                disappearingMessageToken:nil
                                                groupUpdateSourceAddress:nil
                                                       infoMessagePolicy:InfoMessagePolicyAlways
                                                             transaction:transaction
                                                                   error:&error]
                        .groupThread;
                if (error != nil) {
                    OWSFailDebug(@"error: %@", error);
                }
            } else {
                SignalServiceAddress *otherAddress = [[SignalServiceAddress alloc] initWithUuid:NSUUID.UUID];
                otherThread = [TSContactThread getOrCreateThreadWithContactAddress:otherAddress
                                                                       transaction:transaction];
            }
            interactionThread = otherThread;
        });
    }

    NSString *text = NSUUID.UUID.UUIDString;
    TSOutgoingMessageBuilder *messageBuilder =
        [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:interactionThread messageBody:text];
    TSOutgoingMessage *message = [messageBuilder buildWithSneakyTransaction];

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [message anyInsertWithTransaction:transaction];
    });

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [message updateWithFakeMessageState:TSOutgoingMessageStateSending transaction:transaction];
        [message updateWithFakeMessageState:TSOutgoingMessageStateFailed transaction:transaction];
    });

    BOOL shouldDelete = arc4random_uniform(2) == 0;
    if (shouldDelete) {
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [message anyRemoveWithTransaction:transaction];
            if (otherThread != nil) {
                [otherThread anyRemoveWithTransaction:transaction];
            }
        });
    }
}

- (void)stopThrash
{
    [DebugUIStress.shared.thrashTimer invalidate];
    DebugUIStress.shared.thrashTimer = nil;
}

@end

NS_ASSUME_NONNULL_END

#endif
