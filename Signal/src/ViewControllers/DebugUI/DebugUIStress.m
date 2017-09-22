//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUIStress.h"
#import "Environment.h"
#import "OWSMessageSender.h"
#import "OWSTableViewController.h"
#import "ThreadUtil.h"
#import <SignalServiceKit/Cryptography.h>
#import <SignalServiceKit/OWSDynamicOutgoingMessage.h>
#import <SignalServiceKit/SecurityUtils.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIStress

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

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
                                         [DebugUIStress sendStressMessage:thread block:^(SignalRecipient *recipient) {
                                             return [NSData new];
                                         }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send no payload message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread block:^(SignalRecipient *recipient) {
                                             OWSSignalServiceProtosContentBuilder *contentBuilder = [OWSSignalServiceProtosContentBuilder new];
                                             return [[contentBuilder build] data];
                                         }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send empty null message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread block:^(SignalRecipient *recipient) {
                                             OWSSignalServiceProtosContentBuilder *contentBuilder = [OWSSignalServiceProtosContentBuilder new];
                                             OWSSignalServiceProtosNullMessageBuilder *nullMessageBuilder = [OWSSignalServiceProtosNullMessageBuilder new];
                                             contentBuilder.nullMessage = [nullMessageBuilder build];
                                             return [[contentBuilder build] data];
                                         }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send random null message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread block:^(SignalRecipient *recipient) {
                                             OWSSignalServiceProtosContentBuilder *contentBuilder = [OWSSignalServiceProtosContentBuilder new];
                                             OWSSignalServiceProtosNullMessageBuilder *nullMessageBuilder = [OWSSignalServiceProtosNullMessageBuilder new];
                                             NSUInteger contentLength = arc4random_uniform(32);
                                             nullMessageBuilder.padding = [Cryptography generateRandomBytes:contentLength];
                                             contentBuilder.nullMessage = [nullMessageBuilder build];
                                             //                                             contentBuilder.dataMessage = [self buildDataMessage:recipient.recipientId];
                                             return [[contentBuilder build] data];
                                         }];
                                     }]];

    if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        [items addObject:[OWSTableItem itemWithTitle:@"Hallucinate twin group"
                                         actionBlock:^{
                                             [DebugUIStress hallucinateTwinGroup:groupThread];
                                         }]];
    }
    return [OWSTableSection sectionWithTitle:self.name items:items];
}

+ (void)sendStressMessage:(TSOutgoingMessage *)message
{
    OWSAssert(message);
    
    OWSMessageSender *messageSender = [Environment getCurrent].messageSender;
    [messageSender sendMessage:message
                       success:^{
                           DDLogInfo(@"%@ Successfully sent message.", self.tag);
                       }
                       failure:^(NSError *error) {
                           DDLogWarn(@"%@ Failed to deliver message with error: %@", self.tag, error);
                       }];
}

+ (void)sendStressMessage:(TSThread *)thread
                    block:(DynamicOutgoingMessageBlock)block
{
    OWSAssert(thread);
    OWSAssert(block);
    
    OWSDynamicOutgoingMessage *message = [[OWSDynamicOutgoingMessage alloc] initWithBlock:block inThread:thread];
    
    [self sendStressMessage:message];
}

// Creates a new group (by cloning the current group) without informing the,
// other members. This can be used to test "group info requests", etc.
+ (void)hallucinateTwinGroup:(TSGroupThread *)groupThread
{
    __block TSGroupThread *thread;
    [[TSStorageManager sharedManager].dbReadWriteConnection
     readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
         TSGroupModel *groupModel =
         [[TSGroupModel alloc] initWithTitle:[groupThread.groupModel.groupName stringByAppendingString:@" Copy"]
                                   memberIds:[groupThread.groupModel.groupMemberIds mutableCopy]
                                       image:groupThread.groupModel.groupImage
                                     groupId:[SecurityUtils generateRandomBytes:16]];
         thread = [TSGroupThread getOrCreateThreadWithGroupModel:groupModel transaction:transaction];
     }];
    OWSAssert(thread);
    
    [Environment presentConversationForThread:thread];
}

@end

NS_ASSUME_NONNULL_END
