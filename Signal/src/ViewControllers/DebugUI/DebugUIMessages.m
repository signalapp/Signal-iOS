//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DebugUIMessages.h"
#import "DebugUIContacts.h"
#import "DebugUIMessagesAction.h"
#import "DebugUIMessagesAssetLoader.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import <Curve25519Kit/Randomness.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/OWSBatchMessageProcessor.h>
#import <SignalServiceKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSMessageUtils.h>
#import <SignalServiceKit/OWSPrimaryStorage+SessionStore.h>
#import <SignalServiceKit/OWSSyncGroupsRequestMessage.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSIncomingMessage (DebugUI)

@property (nonatomic, getter=wasRead) BOOL read;

@end

#pragma mark -

@interface TSOutgoingMessage (PostDatingDebug)

- (void)setReceivedAtTimestamp:(uint64_t)value;

@end

#pragma mark -

@implementation DebugUIMessages

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Messages";
}

#ifdef DEBUG

- (NSArray<OWSTableItem *> *)itemsForActions:(NSArray<DebugUIMessagesAction *> *)actions
{
    NSMutableArray<OWSTableItem *> *items = [NSMutableArray new];

    for (DebugUIMessagesAction *action in actions) {
        [items addObject:[OWSTableItem itemWithTitle:action.label
                                         actionBlock:^{
                                             // For "all in group" actions, do each subaction in the group
                                             // exactly once, in a predictable order.
                                             if ([action isKindOfClass:[DebugUIMessagesGroupAction class]]) {
                                                 DebugUIMessagesGroupAction *groupAction
                                                     = (DebugUIMessagesGroupAction *)action;
                                                 if (groupAction.subactionMode == SubactionMode_Ordered) {
                                                     [action prepareAndPerformNTimes:groupAction.subactions.count];
                                                     return;
                                                 }
                                             }
                                             [DebugUIMessages performActionNTimes:action];
                                         }]];
    }

    return items;
}

#endif

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    OWSAssertDebug(thread);

    NSMutableArray<OWSTableItem *> *items = [NSMutableArray new];

#ifdef DEBUG

    [items addObject:[OWSTableItem itemWithTitle:@"Delete all messages in thread"
                                     actionBlock:^{
                                         [DebugUIMessages deleteAllMessagesInThread:thread];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"👷 Thrash insert/deletes"
                                     actionBlock:^{
                                         [DebugUIMessages thrashInsertAndDeleteForThread:(TSThread *)thread
                                                                                 counter:300];
                                     }]];

    [items addObjectsFromArray:[self itemsForActions:@[
        [DebugUIMessages fakeAllContactShareAction:thread],
        [DebugUIMessages sendMessageVariationsAction:thread],
        // Send Media
        [DebugUIMessages sendAllMediaAction:thread],
        [DebugUIMessages sendRandomMediaAction:thread],
        // Fake Media
        [DebugUIMessages fakeAllMediaAction:thread],
        [DebugUIMessages fakeRandomMediaAction:thread],
        // Fake Text
        [DebugUIMessages fakeAllTextAction:thread],
        [DebugUIMessages fakeRandomTextAction:thread],
        // Sequences
        [DebugUIMessages allFakeSequencesAction:thread],
        // Quoted Replies
        [DebugUIMessages allQuotedReplyAction:thread],
        // Exemplary
        [DebugUIMessages allFakeAction:thread],
        [DebugUIMessages allFakeBackDatedAction:thread],
    ]]];

    [items addObjectsFromArray:@[

#pragma mark - Actions

        [OWSTableItem itemWithTitle:@"Send N text messages (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendNTextMessagesInThread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Select Fake"
                        actionBlock:^{
                            [DebugUIMessages selectFakeAction:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Select Send Media"
                        actionBlock:^{
                            [DebugUIMessages selectSendMediaAction:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send All Contact Shares"
                        actionBlock:^{
                            [DebugUIMessages sendAllContacts:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Select Quoted Reply"
                        actionBlock:^{
                            [DebugUIMessages selectQuotedReplyAction:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Select Back-Dated"
                        actionBlock:^{
                            [DebugUIMessages selectBackDatedAction:thread];
                        }],


#pragma mark - Misc.

        [OWSTableItem itemWithTitle:@"Perform 100 random actions"
                        actionBlock:^{
                            [DebugUIMessages performRandomActions:100 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Perform 1,000 random actions"
                        actionBlock:^{
                            [DebugUIMessages performRandomActions:1000 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Create 10 fake messages"
                        actionBlock:^{
                            [DebugUIMessages sendFakeMessages:10 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Create 1 fake thread with 1 message"
                        actionBlock:^{
                            [DebugUIMessages createFakeThreads:1 withFakeMessages:1];
                        }],
        [OWSTableItem itemWithTitle:@"Create 100 fake threads with 10 messages"
                        actionBlock:^{
                            [DebugUIMessages createFakeThreads:100 withFakeMessages:10];
                        }],
        [OWSTableItem itemWithTitle:@"Create 10 fake threads with 100 messages"
                        actionBlock:^{
                            [DebugUIMessages createFakeThreads:10 withFakeMessages:100];
                        }],
        [OWSTableItem itemWithTitle:@"Create 10 fake threads with 10 messages"
                        actionBlock:^{
                            [DebugUIMessages createFakeThreads:10 withFakeMessages:10];
                        }],
        [OWSTableItem itemWithTitle:@"Create 100 fake threads with 100 messages"
                        actionBlock:^{
                            [DebugUIMessages createFakeThreads:100 withFakeMessages:100];
                        }],
        [OWSTableItem itemWithTitle:@"Create 1k fake threads with 1 message"
                        actionBlock:^{
                            [DebugUIMessages createFakeThreads:1000 withFakeMessages:1];
                        }],
        [OWSTableItem itemWithTitle:@"Create 1k fake messages"
                        actionBlock:^{
                            [DebugUIMessages sendFakeMessages:1000 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Create 10k fake messages"
                        actionBlock:^{
                            [DebugUIMessages sendFakeMessages:10 * 1000 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Create 100k fake messages"
                        actionBlock:^{
                            [DebugUIMessages sendFakeMessages:100 * 1000 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Create 100k fake text messages"
                        actionBlock:^{
                            [DebugUIMessages sendFakeMessages:100 * 1000 thread:thread isTextOnly:YES];
                        }],
        [OWSTableItem itemWithTitle:@"Send text/x-signal-plain"
                        actionBlock:^{
                            [DebugUIMessages sendOversizeTextMessage:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send unknown mimetype"
                        actionBlock:^{
                            [DebugUIMessages sendRandomAttachment:thread uti:kUnknownTestAttachmentUTI];
                        }],
        [OWSTableItem itemWithTitle:@"Send pdf"
                        actionBlock:^{
                            [DebugUIMessages sendRandomAttachment:thread uti:(NSString *)kUTTypePDF];
                        }],
        [OWSTableItem itemWithTitle:@"Create all system messages"
                        actionBlock:^{
                            [DebugUIMessages createSystemMessagesInThread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Create messages with variety of timestamps"
                        actionBlock:^{
                            [DebugUIMessages createTimestampMessagesInThread:thread];
                        }],

        [OWSTableItem itemWithTitle:@"Send 10 text and system messages"
                        actionBlock:^{
                            [DebugUIMessages sendTextAndSystemMessages:10 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 100 text and system messages"
                        actionBlock:^{
                            [DebugUIMessages sendTextAndSystemMessages:100 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 1,000 text and system messages"
                        actionBlock:^{
                            [DebugUIMessages sendTextAndSystemMessages:1000 thread:thread];
                        }],
        [OWSTableItem
            itemWithTitle:@"Request Bogus group info"
              actionBlock:^{
                  OWSLogInfo(@"Requesting bogus group info for thread: %@", thread);
                  OWSSyncGroupsRequestMessage *syncGroupsRequestMessage =
                      [[OWSSyncGroupsRequestMessage alloc] initWithThread:thread
                                                                  groupId:[Randomness generateRandomBytes:16]];
                  [SSKEnvironment.shared.messageSender enqueueMessage:syncGroupsRequestMessage
                      success:^{
                          OWSLogWarn(@"Successfully sent Request Group Info message.");
                      }
                      failure:^(NSError *error) {
                          OWSLogError(@"Failed to send Request Group Info message with error: %@", error);
                      }];
              }],
        [OWSTableItem itemWithTitle:@"Message with stalled timer"
                        actionBlock:^{
                            [DebugUIMessages createDisappearingMessagesWhichFailedToStartInThread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Inject 10 fake incoming messages"
                        actionBlock:^{
                            [DebugUIMessages injectFakeIncomingMessages:10 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Inject 100 fake incoming messages"
                        actionBlock:^{
                            [DebugUIMessages injectFakeIncomingMessages:100 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Inject 1,000 fake incoming messages"
                        actionBlock:^{
                            [DebugUIMessages injectFakeIncomingMessages:1000 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Test Indic Scripts"
                        actionBlock:^{
                            [DebugUIMessages testIndicScriptsInThread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Test Zalgo"
                        actionBlock:^{
                            [DebugUIMessages testZalgoTextInThread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Test Directional Filenames"
                        actionBlock:^{
                            [DebugUIMessages testDirectionalFilenamesInThread:thread];
                        }],
    ]];

    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        NSString *recipientId = contactThread.contactIdentifier;
        [items addObject:[OWSTableItem itemWithTitle:@"Create 10 new groups"
                                         actionBlock:^{
                                             [DebugUIMessages createNewGroups:10 recipientId:recipientId];
                                         }]];
        [items addObject:[OWSTableItem itemWithTitle:@"Create 100 new groups"
                                         actionBlock:^{
                                             [DebugUIMessages createNewGroups:100 recipientId:recipientId];
                                         }]];
        [items addObject:[OWSTableItem itemWithTitle:@"Create 1,000 new groups"
                                         actionBlock:^{
                                             [DebugUIMessages createNewGroups:1000 recipientId:recipientId];
                                         }]];
    }
    if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        [items addObject:[OWSTableItem itemWithTitle:@"Send message to all members"
                                         actionBlock:^{
                                             [DebugUIMessages sendMessages:1 toAllMembersOfGroup:groupThread];
                                         }]];
    }

#endif

    return [OWSTableSection sectionWithTitle:self.name items:items];
}

#ifdef DEBUG

+ (void)sendMessages:(NSUInteger)count toAllMembersOfGroup:(TSGroupThread *)groupThread
{
    for (NSString *recipientId in groupThread.groupModel.groupMemberIds) {
        TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:recipientId];
        [[self sendTextMessagesActionInThread:contactThread] prepareAndPerformNTimes:count];
    }
}

+ (void)sendTextMessageInThread:(TSThread *)thread counter:(NSUInteger)counter
{
    OWSLogInfo(@"sendTextMessageInThread: %zd", counter);
    [DDLog flushLog];

    NSString *randomText = [self randomText];
    NSString *text = [[[@(counter) description] stringByAppendingString:@" "] stringByAppendingString:randomText];
    OWSMessageSender *messageSender = SSKEnvironment.shared.messageSender;
    TSOutgoingMessage *message =
        [ThreadUtil sendMessageWithText:text inThread:thread quotedReplyModel:nil messageSender:messageSender];
    OWSLogError(@"sendTextMessageInThread timestamp: %llu.", message.timestamp);
}

+ (void)sendNTextMessagesInThread:(TSThread *)thread
{
    [self performActionNTimes:[self sendTextMessagesActionInThread:thread]];
}

+ (DebugUIMessagesAction *)sendTextMessagesActionInThread:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesSingleAction actionWithLabel:@"Send Text Message"
                                   staggeredActionBlock:^(NSUInteger index,
                                       YapDatabaseReadWriteTransaction *transaction,
                                       ActionSuccessBlock success,
                                       ActionFailureBlock failure) {
                                       dispatch_async(dispatch_get_main_queue(), ^{
                                           [self sendTextMessageInThread:thread counter:index];
                                           // TODO:
                                           success();
                                       });
                                   }];
}

+ (void)sendAttachment:(NSString *)filePath
                thread:(TSThread *)thread
                 label:(NSString *)label
            hasCaption:(BOOL)hasCaption
               success:(nullable void (^)(void))success
               failure:(nullable void (^)(void))failure
{
    OWSAssertDebug(filePath);
    OWSAssertDebug(thread);

    OWSMessageSender *messageSender = SSKEnvironment.shared.messageSender;
    NSString *filename = [filePath lastPathComponent];
    NSString *utiType = [MIMETypeUtil utiTypeForFileExtension:filename.pathExtension];
    DataSource *_Nullable dataSource = [DataSourcePath dataSourceWithFilePath:filePath shouldDeleteOnDeallocation:NO];
    [dataSource setSourceFilename:filename];
    SignalAttachment *attachment =
        [SignalAttachment attachmentWithDataSource:dataSource dataUTI:utiType imageQuality:TSImageQualityOriginal];

    NSString *messageBody = nil;
    if (hasCaption) {
        // We want a message body that is "more than one line on all devices,
        // using all dynamic type sizes."
        NSString *sampleText = @"Lorem ipsum dolor sit amet, consectetur adipiscing elit. Lorem ipsum dolor sit amet, "
                               @"consectetur adipiscing elit.";
        messageBody = [[label stringByAppendingString:@" "] stringByAppendingString:sampleText];

        messageBody = [messageBody stringByAppendingString:@" 🔤"];
    }
    attachment.captionText = messageBody;

    OWSAssertDebug(attachment);
    if ([attachment hasError]) {
        OWSLogError(@"attachment[%@]: %@", [attachment sourceFilename], [attachment errorName]);
        [DDLog flushLog];
    }
    OWSAssertDebug(![attachment hasError]);
    [ThreadUtil sendMessageWithAttachment:attachment
                                 inThread:thread
                         quotedReplyModel:nil
                            messageSender:messageSender
                               completion:nil];
    success();
}

#pragma mark - Infrastructure

+ (void)performActionNTimes:(DebugUIMessagesAction *)action
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(action);

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"How many?"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *countValue in @[
             @(1),
             @(10),
             @(100),
             @(1 * 1000),
             @(10 * 1000),
         ]) {
        [alert addAction:[UIAlertAction actionWithTitle:countValue.stringValue
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *ignore) {
                                                    [action prepareAndPerformNTimes:countValue.unsignedIntegerValue];
                                                }]];
    }

    [alert addAction:[OWSAlerts cancelAction]];
    UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
    [fromViewController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Send Media

+ (NSArray<DebugUIMessagesAction *> *)allSendMediaActions:(TSThread *)thread
{
    OWSAssertDebug(thread);

    NSArray<DebugUIMessagesAction *> *actions = @[
        [self sendJpegAction:thread hasCaption:NO],
        [self sendJpegAction:thread hasCaption:YES],
        [self sendGifAction:thread hasCaption:NO],
        [self sendGifAction:thread hasCaption:YES],
        [self sendLargeGifAction:thread hasCaption:NO],
        [self sendLargeGifAction:thread hasCaption:YES],
        [self sendMp3Action:thread hasCaption:NO],
        [self sendMp3Action:thread hasCaption:YES],
        [self sendMp4Action:thread hasCaption:NO],
        [self sendMp4Action:thread hasCaption:YES],
    ];
    return actions;
}

+ (DebugUIMessagesAction *)sendJpegAction:(TSThread *)thread hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self sendMediaAction:@"Send Jpeg"
                      hasCaption:hasCaption
                 fakeAssetLoader:[DebugUIMessagesAssetLoader jpegInstance]
                          thread:thread];
}

+ (DebugUIMessagesAction *)sendGifAction:(TSThread *)thread hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self sendMediaAction:@"Send Gif"
                      hasCaption:hasCaption
                 fakeAssetLoader:[DebugUIMessagesAssetLoader gifInstance]
                          thread:thread];
}

+ (DebugUIMessagesAction *)sendLargeGifAction:(TSThread *)thread hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self sendMediaAction:@"Send Large Gif"
                      hasCaption:hasCaption
                 fakeAssetLoader:[DebugUIMessagesAssetLoader largeGifInstance]
                          thread:thread];
}

+ (DebugUIMessagesAction *)sendMp3Action:(TSThread *)thread hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self sendMediaAction:@"Send Mp3"
                      hasCaption:hasCaption
                 fakeAssetLoader:[DebugUIMessagesAssetLoader mp3Instance]
                          thread:thread];
}

+ (DebugUIMessagesAction *)sendMp4Action:(TSThread *)thread hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self sendMediaAction:@"Send Mp4"
                      hasCaption:hasCaption
                 fakeAssetLoader:[DebugUIMessagesAssetLoader mp4Instance]
                          thread:thread];
}

+ (DebugUIMessagesAction *)sendMediaAction:(NSString *)labelParam
                                hasCaption:(BOOL)hasCaption
                           fakeAssetLoader:(DebugUIMessagesAssetLoader *)fakeAssetLoader
                                    thread:(TSThread *)thread
{
    OWSAssertDebug(labelParam.length > 0);
    OWSAssertDebug(fakeAssetLoader);
    OWSAssertDebug(thread);

    NSString *label = labelParam;
    if (hasCaption) {
        label = [label stringByAppendingString:@" 🔤"];
    }

    return [DebugUIMessagesSingleAction
             actionWithLabel:label
        staggeredActionBlock:^(NSUInteger index,
            YapDatabaseReadWriteTransaction *transaction,
            ActionSuccessBlock success,
            ActionFailureBlock failure) {
            dispatch_async(dispatch_get_main_queue(), ^{
                OWSAssertDebug(fakeAssetLoader.filePath.length > 0);
                [self sendAttachment:fakeAssetLoader.filePath
                              thread:thread
                               label:label
                          hasCaption:hasCaption
                             success:success
                             failure:failure];
            });
        }
                prepareBlock:fakeAssetLoader.prepareBlock];
}

+ (DebugUIMessagesAction *)sendAllMediaAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesGroupAction allGroupActionWithLabel:@"All Send Media"
                                                    subactions:[self allSendMediaActions:thread]];
}

+ (DebugUIMessagesAction *)sendRandomMediaAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesGroupAction randomGroupActionWithLabel:@"Random Send Media"
                                                       subactions:[self allSendMediaActions:thread]];
}

+ (void)selectSendMediaAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    [self selectActionUI:[self allSendMediaActions:thread] label:@"Select Send Media"];
}

#pragma mark - Fake Outgoing Media

+ (DebugUIMessagesAction *)fakeOutgoingJpegAction:(TSThread *)thread
                                     messageState:(TSOutgoingMessageState)messageState
                                       hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:@"Fake Outgoing Jpeg"
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader jpegInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingGifAction:(TSThread *)thread
                                    messageState:(TSOutgoingMessageState)messageState
                                      hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:@"Fake Outgoing Gif"
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader gifInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingLargeGifAction:(TSThread *)thread
                                         messageState:(TSOutgoingMessageState)messageState
                                           hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:@"Fake Outgoing Large Gif"
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader largeGifInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingMp3Action:(TSThread *)thread
                                    messageState:(TSOutgoingMessageState)messageState
                                      hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:@"Fake Outgoing Mp3"
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader mp3Instance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingMp4Action:(TSThread *)thread
                                    messageState:(TSOutgoingMessageState)messageState
                                      hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:@"Fake Outgoing Mp4"
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader mp4Instance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingCompactPortraitPngAction:(TSThread *)thread
                                                   messageState:(TSOutgoingMessageState)messageState
                                                     hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:@"Fake Outgoing Portrait Png"
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader compactLandscapePngInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingCompactLandscapePngAction:(TSThread *)thread
                                                    messageState:(TSOutgoingMessageState)messageState
                                                      hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:@"Fake Outgoing Landscape Png"
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader compactPortraitPngInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingTallPortraitPngAction:(TSThread *)thread
                                                messageState:(TSOutgoingMessageState)messageState
                                                  hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:@"Fake Outgoing Tall Portrait Png"
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader tallPortraitPngInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingWideLandscapePngAction:(TSThread *)thread
                                                 messageState:(TSOutgoingMessageState)messageState
                                                   hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:@"Fake Outgoing Wide Landscape Png"
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader wideLandscapePngInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingLargePngAction:(TSThread *)thread
                                         messageState:(TSOutgoingMessageState)messageState
                                           hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:@"Fake Outgoing Large Png"
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader largePngInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingTinyPngAction:(TSThread *)thread
                                        messageState:(TSOutgoingMessageState)messageState
                                          hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:@"Fake Outgoing Tiny Png"
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader tinyPngInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingPngAction:(TSThread *)thread
                                     actionLabel:(NSString *)actionLabel
                                       imageSize:(CGSize)imageSize
                                 backgroundColor:(UIColor *)backgroundColor
                                       textColor:(UIColor *)textColor
                                      imageLabel:(NSString *)imageLabel
                                    messageState:(TSOutgoingMessageState)messageState
                                      hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:actionLabel
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader pngInstanceWithSize:imageSize
                                                                         backgroundColor:backgroundColor
                                                                               textColor:textColor
                                                                                   label:imageLabel]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingTinyPdfAction:(TSThread *)thread
                                        messageState:(TSOutgoingMessageState)messageState
                                          hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:@"Fake Outgoing Tiny Pdf"
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader tinyPdfInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingLargePdfAction:(TSThread *)thread
                                         messageState:(TSOutgoingMessageState)messageState
                                           hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:@"Fake Outgoing Large Pdf"
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader largePdfInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingMissingPngAction:(TSThread *)thread
                                           messageState:(TSOutgoingMessageState)messageState
                                             hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:@"Fake Outgoing Missing Png"
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader missingPngInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingMissingPdfAction:(TSThread *)thread
                                           messageState:(TSOutgoingMessageState)messageState
                                             hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:@"Fake Outgoing Missing Pdf"
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader missingPdfInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingOversizeTextAction:(TSThread *)thread
                                             messageState:(TSOutgoingMessageState)messageState
                                               hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeOutgoingMediaAction:@"Fake Outgoing Oversize Text"
                            messageState:messageState
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader oversizeTextInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeOutgoingMediaAction:(NSString *)labelParam
                                      messageState:(TSOutgoingMessageState)messageState
                                        hasCaption:(BOOL)hasCaption
                                   fakeAssetLoader:(DebugUIMessagesAssetLoader *)fakeAssetLoader
                                            thread:(TSThread *)thread
{
    OWSAssertDebug(labelParam.length > 0);
    OWSAssertDebug(fakeAssetLoader);
    OWSAssertDebug(thread);

    NSString *label = [labelParam stringByAppendingString:[self actionLabelForHasCaption:hasCaption
                                                                    outgoingMessageState:messageState
                                                                             isDelivered:NO
                                                                                  isRead:NO]];

    return
        [DebugUIMessagesSingleAction actionWithLabel:label
                              unstaggeredActionBlock:^(NSUInteger index, YapDatabaseReadWriteTransaction *transaction) {
                                  OWSAssertDebug(fakeAssetLoader.filePath.length > 0);
                                  [self createFakeOutgoingMedia:index
                                                   messageState:messageState
                                                     hasCaption:hasCaption
                                                fakeAssetLoader:fakeAssetLoader
                                                         thread:thread
                                                    transaction:transaction];
                              }
                                        prepareBlock:fakeAssetLoader.prepareBlock];
}

+ (void)createFakeOutgoingMedia:(NSUInteger)index
                   messageState:(TSOutgoingMessageState)messageState
                     hasCaption:(BOOL)hasCaption
                fakeAssetLoader:(DebugUIMessagesAssetLoader *)fakeAssetLoader
                         thread:(TSThread *)thread
                    transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(thread);
    OWSAssertDebug(fakeAssetLoader.filePath);
    OWSAssertDebug(transaction);

    // Random time within last n years. Helpful for filling out a media gallery over time.
    //    double yearsMillis = 4.0 * kYearsInMs;
    //    uint64_t millisAgo = (uint64_t)(((double)arc4random() / ((double)0xffffffff)) * yearsMillis);
    //    uint64_t timestamp = [NSDate ows_millisecondTimeStamp] - millisAgo;
    uint64_t timestamp = [NSDate ows_millisecondTimeStamp];

    NSString *messageBody = nil;
    if (hasCaption) {
        // We want a message body that is "more than one line on all devices,
        // using all dynamic type sizes."
        NSString *sampleText = @"Lorem ipsum dolor sit amet, consectetur adipiscing elit. Lorem ipsum dolor sit amet, "
                               @"consectetur adipiscing elit.";
        messageBody = [[@(index).stringValue stringByAppendingString:@" "] stringByAppendingString:sampleText];
        messageBody = [messageBody stringByAppendingString:[self actionLabelForHasCaption:hasCaption
                                                                     outgoingMessageState:messageState
                                                                              isDelivered:NO
                                                                                   isRead:NO]];
    }

    TSOutgoingMessage *message = [self createFakeOutgoingMessage:thread
                                                     messageBody:messageBody
                                                 fakeAssetLoader:fakeAssetLoader
                                                    messageState:messageState
                                                     isDelivered:YES
                                                          isRead:NO
                                                   quotedMessage:nil
                                                    contactShare:nil
                                                     transaction:transaction];

    // This is a hack to "back-date" the message.
    [message setReceivedAtTimestamp:timestamp];

    [message saveWithTransaction:transaction];
}

#pragma mark - Fake Incoming Media

+ (DebugUIMessagesAction *)fakeIncomingJpegAction:(TSThread *)thread
                           isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                       hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:@"Fake Incoming Jpeg"
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader jpegInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingGifAction:(TSThread *)thread
                          isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                      hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:@"Fake Incoming Gif"
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader gifInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingLargeGifAction:(TSThread *)thread
                               isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                           hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:@"Fake Incoming Large Gif"
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader largeGifInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingMp3Action:(TSThread *)thread
                          isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                      hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:@"Fake Incoming Mp3"
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader mp3Instance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingMp4Action:(TSThread *)thread
                          isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                      hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:@"Fake Incoming Mp4"
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader mp4Instance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingCompactPortraitPngAction:(TSThread *)thread
                                         isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                                     hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:@"Fake Incoming Portrait Png"
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader compactPortraitPngInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingCompactLandscapePngAction:(TSThread *)thread
                                          isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                                      hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:@"Fake Incoming Landscape Png"
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader compactLandscapePngInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingTallPortraitPngAction:(TSThread *)thread
                                      isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                                  hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:@"Fake Incoming Tall Portrait Png"
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader tallPortraitPngInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingWideLandscapePngAction:(TSThread *)thread
                                       isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                                   hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:@"Fake Incoming Wide Landscape Png"
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader wideLandscapePngInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingLargePngAction:(TSThread *)thread
                               isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                           hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:@"Fake Incoming Large Png"
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader largePngInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingTinyPngAction:(TSThread *)thread
                              isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                          hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:@"Tiny Incoming Large Png"
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader tinyPngInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingPngAction:(TSThread *)thread
                                     actionLabel:(NSString *)actionLabel
                                       imageSize:(CGSize)imageSize
                                 backgroundColor:(UIColor *)backgroundColor
                                       textColor:(UIColor *)textColor
                                      imageLabel:(NSString *)imageLabel
                          isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                      hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:actionLabel
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader pngInstanceWithSize:imageSize
                                                                         backgroundColor:backgroundColor
                                                                               textColor:textColor
                                                                                   label:imageLabel]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingTinyPdfAction:(TSThread *)thread
                              isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                          hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:@"Fake Incoming Tiny Pdf"
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader tinyPdfInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingLargePdfAction:(TSThread *)thread
                               isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                           hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:@"Fake Incoming Large Pdf"
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader largePdfInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingMissingPngAction:(TSThread *)thread
                                 isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                             hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:@"Fake Incoming Missing Png"
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader missingPngInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingMissingPdfAction:(TSThread *)thread
                                 isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                             hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:@"Fake Incoming Missing Pdf"
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader missingPdfInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingOversizeTextAction:(TSThread *)thread
                                   isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                               hasCaption:(BOOL)hasCaption
{
    OWSAssertDebug(thread);

    return [self fakeIncomingMediaAction:@"Fake Incoming Oversize Text"
                  isAttachmentDownloaded:isAttachmentDownloaded
                              hasCaption:hasCaption
                         fakeAssetLoader:[DebugUIMessagesAssetLoader oversizeTextInstance]
                                  thread:thread];
}

+ (DebugUIMessagesAction *)fakeIncomingMediaAction:(NSString *)labelParam
                            isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                        hasCaption:(BOOL)hasCaption
                                   fakeAssetLoader:(DebugUIMessagesAssetLoader *)fakeAssetLoader
                                            thread:(TSThread *)thread
{
    OWSAssertDebug(labelParam.length > 0);
    OWSAssertDebug(fakeAssetLoader);
    OWSAssertDebug(thread);

    NSString *label = labelParam;
    if (hasCaption) {
        label = [label stringByAppendingString:@" 🔤"];
    }

    if (isAttachmentDownloaded) {
        label = [label stringByAppendingString:@" 👍"];
    }

    return
        [DebugUIMessagesSingleAction actionWithLabel:label
                              unstaggeredActionBlock:^(NSUInteger index, YapDatabaseReadWriteTransaction *transaction) {
                                  OWSAssertDebug(fakeAssetLoader.filePath.length > 0);
                                  [self createFakeIncomingMedia:index
                                         isAttachmentDownloaded:isAttachmentDownloaded
                                                     hasCaption:hasCaption
                                                fakeAssetLoader:fakeAssetLoader
                                                         thread:thread
                                                    transaction:transaction];
                              }
                                        prepareBlock:fakeAssetLoader.prepareBlock];
}

+ (TSIncomingMessage *)createFakeIncomingMedia:(NSUInteger)index
                        isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                    hasCaption:(BOOL)hasCaption
                               fakeAssetLoader:(DebugUIMessagesAssetLoader *)fakeAssetLoader
                                        thread:(TSThread *)thread
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSString *_Nullable caption = nil;
    if (hasCaption) {
        // We want a message body that is "more than one line on all devices,
        // using all dynamic type sizes."
        caption = @"Lorem ipsum dolor sit amet, consectetur adipiscing elit. Lorem ipsum dolor sit amet, "
                  @"consectetur adipiscing elit.";
    }
    return [self createFakeIncomingMedia:index
                  isAttachmentDownloaded:isAttachmentDownloaded
                                 caption:caption
                         fakeAssetLoader:fakeAssetLoader
                                  thread:thread
                             transaction:transaction];
}

+ (TSIncomingMessage *)createFakeIncomingMedia:(NSUInteger)index
                        isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                       caption:(nullable NSString *)caption
                               fakeAssetLoader:(DebugUIMessagesAssetLoader *)fakeAssetLoader
                                        thread:(TSThread *)thread
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(thread);
    OWSAssertDebug(fakeAssetLoader.filePath);
    OWSAssertDebug(transaction);

    //    // Random time within last n years. Helpful for filling out a media gallery over time.
    //    double yearsMillis = 4.0 * kYearsInMs;
    //    uint64_t millisAgo = (uint64_t)(((double)arc4random() / ((double)0xffffffff)) * yearsMillis);
    //    uint64_t timestamp = [NSDate ows_millisecondTimeStamp] - millisAgo;

    NSString *messageBody = nil;
    if (caption) {
        messageBody = [[@(index).stringValue stringByAppendingString:@" "] stringByAppendingString:caption];

        messageBody = [messageBody stringByAppendingString:@" 🔤"];

        if (isAttachmentDownloaded) {
            messageBody = [messageBody stringByAppendingString:@" 👍"];
        }
    }

    return [self createFakeIncomingMessage:thread
                               messageBody:messageBody
                           fakeAssetLoader:fakeAssetLoader
                    isAttachmentDownloaded:isAttachmentDownloaded
                             quotedMessage:nil
                               transaction:transaction];
}

#pragma mark - Fake Media

+ (NSArray<DebugUIMessagesAction *> *)allFakeMediaActions:(TSThread *)thread includeLabels:(BOOL)includeLabels
{
    OWSAssertDebug(thread);

    NSMutableArray<DebugUIMessagesAction *> *actions = [NSMutableArray new];

    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Jpeg ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeOutgoingJpegAction:thread messageState:TSOutgoingMessageStateFailed hasCaption:NO],
        [self fakeOutgoingJpegAction:thread messageState:TSOutgoingMessageStateFailed hasCaption:YES],
        [self fakeOutgoingJpegAction:thread messageState:TSOutgoingMessageStateSending hasCaption:NO],
        [self fakeOutgoingJpegAction:thread messageState:TSOutgoingMessageStateSending hasCaption:YES],
        [self fakeOutgoingJpegAction:thread messageState:TSOutgoingMessageStateSent hasCaption:NO],
        [self fakeOutgoingJpegAction:thread messageState:TSOutgoingMessageStateSent hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Gif ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        // Don't bother with multiple GIF states.
        [self fakeOutgoingGifAction:thread messageState:TSOutgoingMessageStateSent hasCaption:NO],
        [self fakeOutgoingLargeGifAction:thread messageState:TSOutgoingMessageStateSent hasCaption:NO],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Mp3 ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeOutgoingMp3Action:thread messageState:TSOutgoingMessageStateSending hasCaption:YES],
        [self fakeOutgoingMp3Action:thread messageState:TSOutgoingMessageStateSending hasCaption:NO],
        [self fakeOutgoingMp3Action:thread messageState:TSOutgoingMessageStateFailed hasCaption:NO],
        [self fakeOutgoingMp3Action:thread messageState:TSOutgoingMessageStateFailed hasCaption:YES],
        [self fakeOutgoingMp3Action:thread messageState:TSOutgoingMessageStateSent hasCaption:NO],
        [self fakeOutgoingMp3Action:thread messageState:TSOutgoingMessageStateSent hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Mp4 ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeOutgoingMp4Action:thread messageState:TSOutgoingMessageStateSending hasCaption:NO],
        [self fakeOutgoingMp4Action:thread messageState:TSOutgoingMessageStateSending hasCaption:YES],
        [self fakeOutgoingMp4Action:thread messageState:TSOutgoingMessageStateFailed hasCaption:NO],
        [self fakeOutgoingMp4Action:thread messageState:TSOutgoingMessageStateFailed hasCaption:YES],
        [self fakeOutgoingMp4Action:thread messageState:TSOutgoingMessageStateSent hasCaption:NO],
        [self fakeOutgoingMp4Action:thread messageState:TSOutgoingMessageStateSent hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Compact Landscape Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeOutgoingCompactLandscapePngAction:thread messageState:TSOutgoingMessageStateSending hasCaption:NO],
        [self fakeOutgoingCompactLandscapePngAction:thread messageState:TSOutgoingMessageStateSending hasCaption:YES],
        [self fakeOutgoingCompactLandscapePngAction:thread messageState:TSOutgoingMessageStateFailed hasCaption:NO],
        [self fakeOutgoingCompactLandscapePngAction:thread messageState:TSOutgoingMessageStateFailed hasCaption:YES],
        [self fakeOutgoingCompactLandscapePngAction:thread messageState:TSOutgoingMessageStateSent hasCaption:NO],
        [self fakeOutgoingCompactLandscapePngAction:thread messageState:TSOutgoingMessageStateSent hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Compact Portrait Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeOutgoingCompactPortraitPngAction:thread messageState:TSOutgoingMessageStateSending hasCaption:NO],
        [self fakeOutgoingCompactPortraitPngAction:thread messageState:TSOutgoingMessageStateSending hasCaption:YES],
        [self fakeOutgoingCompactPortraitPngAction:thread messageState:TSOutgoingMessageStateFailed hasCaption:NO],
        [self fakeOutgoingCompactPortraitPngAction:thread messageState:TSOutgoingMessageStateFailed hasCaption:YES],
        [self fakeOutgoingCompactPortraitPngAction:thread messageState:TSOutgoingMessageStateSent hasCaption:NO],
        [self fakeOutgoingCompactPortraitPngAction:thread messageState:TSOutgoingMessageStateSent hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Wide Landscape Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeOutgoingWideLandscapePngAction:thread messageState:TSOutgoingMessageStateSending hasCaption:NO],
        [self fakeOutgoingWideLandscapePngAction:thread messageState:TSOutgoingMessageStateSending hasCaption:YES],
        [self fakeOutgoingWideLandscapePngAction:thread messageState:TSOutgoingMessageStateFailed hasCaption:NO],
        [self fakeOutgoingWideLandscapePngAction:thread messageState:TSOutgoingMessageStateFailed hasCaption:YES],
        [self fakeOutgoingWideLandscapePngAction:thread messageState:TSOutgoingMessageStateSent hasCaption:NO],
        [self fakeOutgoingWideLandscapePngAction:thread messageState:TSOutgoingMessageStateSent hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Tall Portrait Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeOutgoingTallPortraitPngAction:thread messageState:TSOutgoingMessageStateSending hasCaption:NO],
        [self fakeOutgoingTallPortraitPngAction:thread messageState:TSOutgoingMessageStateSending hasCaption:YES],
        [self fakeOutgoingTallPortraitPngAction:thread messageState:TSOutgoingMessageStateFailed hasCaption:NO],
        [self fakeOutgoingTallPortraitPngAction:thread messageState:TSOutgoingMessageStateFailed hasCaption:YES],
        [self fakeOutgoingTallPortraitPngAction:thread messageState:TSOutgoingMessageStateSent hasCaption:NO],
        [self fakeOutgoingTallPortraitPngAction:thread messageState:TSOutgoingMessageStateSent hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Large Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeOutgoingLargePngAction:thread messageState:TSOutgoingMessageStateSent hasCaption:NO],
        [self fakeOutgoingLargePngAction:thread messageState:TSOutgoingMessageStateSent hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Tiny Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeOutgoingTinyPngAction:thread messageState:TSOutgoingMessageStateSent hasCaption:NO],
        [self fakeOutgoingTinyPngAction:thread messageState:TSOutgoingMessageStateSent hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Reserved Color Png ⚠️"]];
    }
    
    ConversationStyle *conversationStyle = [[ConversationStyle alloc] initWithThread:thread];
    [actions addObjectsFromArray:@[
        [self fakeOutgoingPngAction:thread
                        actionLabel:@"Fake Outgoing White Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[UIColor whiteColor]
                          textColor:[UIColor ows_signalBrandBlueColor]
                         imageLabel:@"W"
                       messageState:TSOutgoingMessageStateFailed
                         hasCaption:YES],
        [self fakeOutgoingPngAction:thread
                        actionLabel:@"Fake Outgoing White Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[UIColor whiteColor]
                          textColor:[UIColor ows_signalBrandBlueColor]
                         imageLabel:@"W"
                       messageState:TSOutgoingMessageStateSending
                         hasCaption:YES],
        [self fakeOutgoingPngAction:thread
                        actionLabel:@"Fake Outgoing White Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[UIColor whiteColor]
                          textColor:[UIColor ows_signalBrandBlueColor]
                         imageLabel:@"W"
                       messageState:TSOutgoingMessageStateSent
                         hasCaption:YES],

        [self fakeOutgoingPngAction:thread
                        actionLabel:@"Fake Outgoing 'Outgoing' Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[conversationStyle bubbleColorWithIsIncoming:NO]
                          textColor:[UIColor whiteColor]
                         imageLabel:@"W"
                       messageState:TSOutgoingMessageStateFailed
                         hasCaption:YES],
        [self fakeOutgoingPngAction:thread
                        actionLabel:@"Fake Outgoing 'Outgoing' Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[conversationStyle bubbleColorWithIsIncoming:NO]
                          textColor:[UIColor whiteColor]
                         imageLabel:@"W"
                       messageState:TSOutgoingMessageStateSending
                         hasCaption:YES],
        [self fakeOutgoingPngAction:thread
                        actionLabel:@"Fake Outgoing 'Outgoing' Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[conversationStyle bubbleColorWithIsIncoming:NO]
                          textColor:[UIColor whiteColor]
                         imageLabel:@"W"
                       messageState:TSOutgoingMessageStateSent
                         hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Tiny Pdf ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeOutgoingTinyPdfAction:thread messageState:TSOutgoingMessageStateSending hasCaption:NO],
        [self fakeOutgoingTinyPdfAction:thread messageState:TSOutgoingMessageStateSending hasCaption:YES],
        [self fakeOutgoingTinyPdfAction:thread messageState:TSOutgoingMessageStateFailed hasCaption:NO],
        [self fakeOutgoingTinyPdfAction:thread messageState:TSOutgoingMessageStateFailed hasCaption:YES],
        [self fakeOutgoingTinyPdfAction:thread messageState:TSOutgoingMessageStateSent hasCaption:NO],
        [self fakeOutgoingTinyPdfAction:thread messageState:TSOutgoingMessageStateSent hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Large Pdf ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeOutgoingLargePdfAction:thread messageState:TSOutgoingMessageStateFailed hasCaption:NO],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Missing Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeOutgoingMissingPngAction:thread messageState:TSOutgoingMessageStateFailed hasCaption:NO],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Large Pdf ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeOutgoingMissingPdfAction:thread messageState:TSOutgoingMessageStateFailed hasCaption:NO],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Oversize Text ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeOutgoingOversizeTextAction:thread messageState:TSOutgoingMessageStateFailed hasCaption:NO],
        [self fakeOutgoingOversizeTextAction:thread messageState:TSOutgoingMessageStateSending hasCaption:NO],
        [self fakeOutgoingOversizeTextAction:thread messageState:TSOutgoingMessageStateSent hasCaption:NO],
    ]];

    // Incoming

    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Jpg ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingJpegAction:thread isAttachmentDownloaded:NO hasCaption:NO],
        [self fakeIncomingJpegAction:thread isAttachmentDownloaded:YES hasCaption:NO],
        [self fakeIncomingJpegAction:thread isAttachmentDownloaded:NO hasCaption:YES],
        [self fakeIncomingJpegAction:thread isAttachmentDownloaded:YES hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Gif ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingGifAction:thread isAttachmentDownloaded:YES hasCaption:NO],
        [self fakeIncomingLargeGifAction:thread isAttachmentDownloaded:YES hasCaption:NO],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Mp3 ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingMp3Action:thread isAttachmentDownloaded:NO hasCaption:NO],
        [self fakeIncomingMp3Action:thread isAttachmentDownloaded:YES hasCaption:NO],
        [self fakeIncomingMp3Action:thread isAttachmentDownloaded:NO hasCaption:YES],
        [self fakeIncomingMp3Action:thread isAttachmentDownloaded:YES hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Mp4 ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingMp4Action:thread isAttachmentDownloaded:NO hasCaption:NO],
        [self fakeIncomingMp4Action:thread isAttachmentDownloaded:YES hasCaption:NO],
        [self fakeIncomingMp4Action:thread isAttachmentDownloaded:NO hasCaption:YES],
        [self fakeIncomingMp4Action:thread isAttachmentDownloaded:YES hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions
            addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Compact Landscape Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingCompactLandscapePngAction:thread isAttachmentDownloaded:NO hasCaption:NO],
        [self fakeIncomingCompactLandscapePngAction:thread isAttachmentDownloaded:YES hasCaption:NO],
        [self fakeIncomingCompactLandscapePngAction:thread isAttachmentDownloaded:NO hasCaption:YES],
        [self fakeIncomingCompactLandscapePngAction:thread isAttachmentDownloaded:YES hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions
            addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Compact Portrait Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingCompactPortraitPngAction:thread isAttachmentDownloaded:NO hasCaption:NO],
        [self fakeIncomingCompactPortraitPngAction:thread isAttachmentDownloaded:YES hasCaption:NO],
        [self fakeIncomingCompactPortraitPngAction:thread isAttachmentDownloaded:NO hasCaption:YES],
        [self fakeIncomingCompactPortraitPngAction:thread isAttachmentDownloaded:YES hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions
            addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Wide Landscape Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingWideLandscapePngAction:thread isAttachmentDownloaded:NO hasCaption:NO],
        [self fakeIncomingWideLandscapePngAction:thread isAttachmentDownloaded:YES hasCaption:NO],
        [self fakeIncomingWideLandscapePngAction:thread isAttachmentDownloaded:NO hasCaption:YES],
        [self fakeIncomingWideLandscapePngAction:thread isAttachmentDownloaded:YES hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions
            addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Tall Portrait Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingTallPortraitPngAction:thread isAttachmentDownloaded:NO hasCaption:NO],
        [self fakeIncomingTallPortraitPngAction:thread isAttachmentDownloaded:YES hasCaption:NO],
        [self fakeIncomingTallPortraitPngAction:thread isAttachmentDownloaded:NO hasCaption:YES],
        [self fakeIncomingTallPortraitPngAction:thread isAttachmentDownloaded:YES hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Large Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingLargePngAction:thread isAttachmentDownloaded:YES hasCaption:NO],
        [self fakeIncomingLargePngAction:thread isAttachmentDownloaded:YES hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Tiny Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingTinyPngAction:thread isAttachmentDownloaded:YES hasCaption:NO],
        [self fakeIncomingTinyPngAction:thread isAttachmentDownloaded:YES hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions
            addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Reserved Color Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingPngAction:thread
                        actionLabel:@"Fake Incoming White Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[UIColor whiteColor]
                          textColor:[UIColor ows_signalBrandBlueColor]
                         imageLabel:@"W"
             isAttachmentDownloaded:YES
                         hasCaption:YES],
        [self fakeIncomingPngAction:thread
                        actionLabel:@"Fake Incoming White Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[UIColor whiteColor]
                          textColor:[UIColor ows_signalBrandBlueColor]
                         imageLabel:@"W"
             isAttachmentDownloaded:NO
                         hasCaption:YES],
        [self fakeIncomingPngAction:thread
                        actionLabel:@"Fake Incoming 'Incoming' Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[conversationStyle conversationColor].primaryColor
                          textColor:[UIColor whiteColor]
                         imageLabel:@"W"
             isAttachmentDownloaded:YES
                         hasCaption:YES],
        [self fakeIncomingPngAction:thread
                        actionLabel:@"Fake Incoming 'Incoming' Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[conversationStyle conversationColor].shadeColor
                          textColor:[UIColor whiteColor]
                         imageLabel:@"W"
             isAttachmentDownloaded:YES
                         hasCaption:YES],
        [self fakeIncomingPngAction:thread
                        actionLabel:@"Fake Incoming 'Incoming' Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[conversationStyle conversationColor].primaryColor
                          textColor:[UIColor whiteColor]
                         imageLabel:@"W"
             isAttachmentDownloaded:NO
                         hasCaption:YES],
        [self fakeIncomingPngAction:thread
                        actionLabel:@"Fake Incoming 'Incoming' Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[conversationStyle conversationColor].shadeColor
                          textColor:[UIColor whiteColor]
                         imageLabel:@"W"
             isAttachmentDownloaded:NO
                         hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Tiny Pdf ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingTinyPdfAction:thread isAttachmentDownloaded:NO hasCaption:NO],
        [self fakeIncomingTinyPdfAction:thread isAttachmentDownloaded:YES hasCaption:NO],
        [self fakeIncomingTinyPdfAction:thread isAttachmentDownloaded:NO hasCaption:YES],
        [self fakeIncomingTinyPdfAction:thread isAttachmentDownloaded:YES hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Large Pdf ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingLargePdfAction:thread isAttachmentDownloaded:YES hasCaption:NO],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Missing Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingMissingPngAction:thread isAttachmentDownloaded:YES hasCaption:NO],
        [self fakeIncomingMissingPngAction:thread isAttachmentDownloaded:YES hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Missing Pdf ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingMissingPdfAction:thread isAttachmentDownloaded:YES hasCaption:NO],
        [self fakeIncomingMissingPdfAction:thread isAttachmentDownloaded:YES hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Oversize Text ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingOversizeTextAction:thread isAttachmentDownloaded:NO hasCaption:NO],
        [self fakeIncomingOversizeTextAction:thread isAttachmentDownloaded:YES hasCaption:NO],
    ]];
    return actions;
}

+ (DebugUIMessagesAction *)fakeAllMediaAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesGroupAction allGroupActionWithLabel:@"All Fake Media"
                                                    subactions:[self allFakeMediaActions:thread includeLabels:YES]];
}

+ (DebugUIMessagesAction *)fakeRandomMediaAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesGroupAction randomGroupActionWithLabel:@"Random Fake Media"
                                                       subactions:[self allFakeMediaActions:thread includeLabels:NO]];
}

#pragma mark - Send Text Messages

+ (DebugUIMessagesAction *)sendShortTextMessageAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesSingleAction actionWithLabel:@"Send Short Text Message"
                                   staggeredActionBlock:^(NSUInteger index,
                                       YapDatabaseReadWriteTransaction *transaction,
                                       ActionSuccessBlock success,
                                       ActionFailureBlock failure) {
                                       dispatch_async(dispatch_get_main_queue(), ^{
                                           [self sendTextMessageInThread:thread counter:index];
                                       });
                                   }];
}

+ (DebugUIMessagesAction *)sendOversizeTextMessageAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesSingleAction actionWithLabel:@"Send Oversize Text Message"
                                   staggeredActionBlock:^(NSUInteger index,
                                       YapDatabaseReadWriteTransaction *transaction,
                                       ActionSuccessBlock success,
                                       ActionFailureBlock failure) {
                                       dispatch_async(dispatch_get_main_queue(), ^{
                                           [self sendOversizeTextMessage:thread];
                                       });
                                   }];
}

+ (DebugUIMessagesAction *)sendMessageVariationsAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    NSArray<DebugUIMessagesAction *> *actions = @[
        [self sendShortTextMessageAction:thread],
        [self sendOversizeTextMessageAction:thread],
    ];

    return [DebugUIMessagesGroupAction allGroupActionWithLabel:@"Send Conversation Cell Variations" subactions:actions];
}

#pragma mark - Fake Text Messages

+ (DebugUIMessagesAction *)fakeShortIncomingTextMessageAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesSingleAction
               actionWithLabel:@"Fake Short Incoming Text Message"
        unstaggeredActionBlock:^(NSUInteger index, YapDatabaseReadWriteTransaction *transaction) {
            NSString *messageBody =
                [[@(index).stringValue stringByAppendingString:@" "] stringByAppendingString:[self randomText]];
            [self createFakeIncomingMessage:thread
                                messageBody:messageBody
                            fakeAssetLoader:nil
                     isAttachmentDownloaded:NO
                              quotedMessage:nil
                                transaction:transaction];
        }];
}

+ (SignalAttachment *)signalAttachmentForFilePath:(NSString *)filePath
{
    OWSAssertDebug(filePath);

    NSString *filename = [filePath lastPathComponent];
    NSString *utiType = [MIMETypeUtil utiTypeForFileExtension:filename.pathExtension];
    DataSource *_Nullable dataSource = [DataSourcePath dataSourceWithFilePath:filePath shouldDeleteOnDeallocation:NO];
    [dataSource setSourceFilename:filename];
    SignalAttachment *attachment =
        [SignalAttachment attachmentWithDataSource:dataSource dataUTI:utiType imageQuality:TSImageQualityOriginal];
    if (arc4random_uniform(100) > 50) {
        attachment.captionText = [self randomCaptionText];
    }

    OWSAssertDebug(attachment);
    if ([attachment hasError]) {
        OWSLogError(@"attachment[%@]: %@", [attachment sourceFilename], [attachment errorName]);
        [DDLog flushLog];
    }
    OWSAssertDebug(![attachment hasError]);
    return attachment;
}

+ (void)sendAttachment:(NSString *)filePath
                thread:(TSThread *)thread
               success:(nullable void (^)(void))success
               failure:(nullable void (^)(void))failure
{
    OWSAssertDebug(filePath);
    OWSAssertDebug(thread);

    SignalAttachment *attachment = [self signalAttachmentForFilePath:filePath];
    OWSMessageSender *messageSender = SSKEnvironment.shared.messageSender;
    [ThreadUtil sendMessageWithAttachment:attachment
                                 inThread:thread
                         quotedReplyModel:nil
                            messageSender:messageSender
                               completion:nil];
    success();
}

+ (DebugUIMessagesAction *)fakeIncomingTextMessageAction:(TSThread *)thread text:(NSString *)text
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesSingleAction
               actionWithLabel:[NSString stringWithFormat:@"Fake Incoming Text Message (%@)", text]
        unstaggeredActionBlock:^(NSUInteger index, YapDatabaseReadWriteTransaction *transaction) {
            NSString *messageBody = [[@(index).stringValue stringByAppendingString:@" "] stringByAppendingString:text];
            [self createFakeIncomingMessage:thread
                                messageBody:messageBody
                            fakeAssetLoader:nil
                     isAttachmentDownloaded:NO
                              quotedMessage:nil
                                transaction:transaction];
        }];
}

+ (DebugUIMessagesAction *)fakeOutgoingTextMessageAction:(TSThread *)thread
                                            messageState:(TSOutgoingMessageState)messageState
                                                    text:(NSString *)text
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesSingleAction
               actionWithLabel:[NSString stringWithFormat:@"Fake Incoming Text Message (%@)", text]
        unstaggeredActionBlock:^(NSUInteger index, YapDatabaseReadWriteTransaction *transaction) {
            NSString *messageBody = [[@(index).stringValue stringByAppendingString:@" "] stringByAppendingString:text];
            [self createFakeOutgoingMessage:thread
                                messageBody:messageBody
                            fakeAssetLoader:nil
                               messageState:messageState
                                isDelivered:NO
                                     isRead:NO
                              quotedMessage:nil
                               contactShare:nil
                                transaction:transaction];
        }];
}

+ (DebugUIMessagesAction *)fakeShortOutgoingTextMessageAction:(TSThread *)thread
                                                 messageState:(TSOutgoingMessageState)messageState
{
    return [self fakeShortOutgoingTextMessageAction:thread messageState:messageState isDelivered:NO isRead:NO];
}

+ (DebugUIMessagesAction *)fakeShortOutgoingTextMessageAction:(TSThread *)thread
                                                 messageState:(TSOutgoingMessageState)messageState
                                                  isDelivered:(BOOL)isDelivered
                                                       isRead:(BOOL)isRead
{
    return [self fakeShortOutgoingTextMessageAction:(TSThread *)thread
                                               text:[self randomText]
                                       messageState:messageState
                                        isDelivered:isDelivered
                                             isRead:isRead];
}

+ (DebugUIMessagesAction *)fakeShortOutgoingTextMessageAction:(TSThread *)thread
                                                         text:(NSString *)text
                                                 messageState:(TSOutgoingMessageState)messageState
                                                  isDelivered:(BOOL)isDelivered
                                                       isRead:(BOOL)isRead
{
    OWSAssertDebug(thread);

    NSString *label = @"Fake Short Incoming Text Message";
    label = [label stringByAppendingString:[self actionLabelForHasCaption:YES
                                                     outgoingMessageState:messageState
                                                              isDelivered:isDelivered
                                                                   isRead:isRead]];

    return [DebugUIMessagesSingleAction
               actionWithLabel:label
        unstaggeredActionBlock:^(NSUInteger index, YapDatabaseReadWriteTransaction *transaction) {
            NSString *messageBody = [[@(index).stringValue stringByAppendingString:@" "] stringByAppendingString:text];
            [self createFakeOutgoingMessage:thread
                                messageBody:messageBody
                            fakeAssetLoader:nil
                               messageState:messageState
                                isDelivered:isDelivered
                                     isRead:isRead
                              quotedMessage:nil
                               contactShare:nil
                                transaction:transaction];
        }];
}

+ (NSArray<DebugUIMessagesAction *> *)allFakeTextActions:(TSThread *)thread includeLabels:(BOOL)includeLabels
{
    OWSAssertDebug(thread);

    NSArray<NSString *> *messageBodies = @[
        @"Hi",
        @"1️⃣",
        @"1️⃣2️⃣",
        @"1️⃣2️⃣3️⃣",
        @"落",
        @"﷽",
    ];

    NSMutableArray<DebugUIMessagesAction *> *actions = [NSMutableArray new];

    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"⚠️ Incoming Message Bodies ⚠️"]];
    }
    [actions addObject:[self fakeShortIncomingTextMessageAction:thread]];
    for (NSString *messageBody in messageBodies) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread text:messageBody]];
    }

    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Statuses ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeShortOutgoingTextMessageAction:thread messageState:TSOutgoingMessageStateFailed],
        [self fakeShortOutgoingTextMessageAction:thread messageState:TSOutgoingMessageStateSending],
        [self fakeShortOutgoingTextMessageAction:thread messageState:TSOutgoingMessageStateSent],
        [self fakeShortOutgoingTextMessageAction:thread
                                    messageState:TSOutgoingMessageStateSent
                                     isDelivered:YES
                                          isRead:NO],
        [self fakeShortOutgoingTextMessageAction:thread
                                    messageState:TSOutgoingMessageStateSent
                                     isDelivered:YES
                                          isRead:YES],
    ]];

    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Outgoing Message Bodies ⚠️"]];
    }
    for (NSString *messageBody in messageBodies) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:messageBody]];
    }
    return actions;
}

+ (DebugUIMessagesAction *)fakeAllTextAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesGroupAction allGroupActionWithLabel:@"All Fake Text"
                                                    subactions:[self allFakeTextActions:thread includeLabels:YES]];
}

+ (DebugUIMessagesAction *)fakeRandomTextAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesGroupAction randomGroupActionWithLabel:@"Random Fake Text"
                                                       subactions:[self allFakeTextActions:thread includeLabels:NO]];
}

#pragma mark - Fake Quoted Replies

+ (DebugUIMessagesAction *)
              fakeQuotedReplyAction:(TSThread *)thread
                 quotedMessageLabel:(NSString *)quotedMessageLabel
            isQuotedMessageIncoming:(BOOL)isQuotedMessageIncoming
                  // Optional. At least one of quotedMessageBody and quotedMessageAssetLoader should be non-nil.
                  quotedMessageBody:(nullable NSString *)quotedMessageBody
           // Optional. At least one of quotedMessageBody and quotedMessageAssetLoader should be non-nil.
           quotedMessageAssetLoader:(nullable DebugUIMessagesAssetLoader *)quotedMessageAssetLoader
                         replyLabel:(NSString *)replyLabel
                    isReplyIncoming:(BOOL)isReplyIncoming
                   replyMessageBody:(nullable NSString *)replyMessageBody
                   replyAssetLoader:(nullable DebugUIMessagesAssetLoader *)replyAssetLoader
                  // Only applies if !isReplyIncoming.
                  replyMessageState:(TSOutgoingMessageState)replyMessageState
{
    OWSAssertDebug(thread);

    // Used fixed values for properties that shouldn't matter much.
    BOOL quotedMessageIsDelivered = NO;
    BOOL quotedMessageIsRead = NO;
    TSOutgoingMessageState quotedMessageMessageState = TSOutgoingMessageStateSent;
    BOOL replyIsDelivered = NO;
    BOOL replyIsRead = NO;

    // Seamlessly convert oversize text messages to oversize text attachments.
    if ([quotedMessageBody lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= kOversizeTextMessageSizeThreshold) {
        OWSAssertDebug(!quotedMessageAssetLoader);
        quotedMessageAssetLoader = [DebugUIMessagesAssetLoader oversizeTextInstanceWithText:quotedMessageBody];
        quotedMessageBody = nil;
    }
    if (replyMessageBody &&
        [replyMessageBody lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= kOversizeTextMessageSizeThreshold) {
        OWSAssertDebug(!replyAssetLoader);
        replyAssetLoader = [DebugUIMessagesAssetLoader oversizeTextInstanceWithText:replyMessageBody];
        replyMessageBody = nil;
    }

    NSMutableString *label = [NSMutableString new];
    [label appendString:@"Quoted Reply ("];
    [label appendString:replyLabel];
    if (isReplyIncoming) {
    } else {
        [label appendString:[self actionLabelForHasCaption:NO
                                      outgoingMessageState:replyMessageState
                                               isDelivered:replyIsDelivered
                                                    isRead:replyIsRead]];
    }
    [label appendString:@") to ("];
    [label appendString:quotedMessageLabel];
    if (quotedMessageAssetLoader) {
        [label appendFormat:@" %@", quotedMessageAssetLoader.labelEmoji];
    }
    if (isQuotedMessageIncoming) {
    } else {
        [label appendString:[self actionLabelForHasCaption:quotedMessageBody.length > 0
                                      outgoingMessageState:quotedMessageMessageState
                                               isDelivered:quotedMessageIsDelivered
                                                    isRead:quotedMessageIsRead]];
    }
    [label appendString:@")"];

    NSMutableArray<ActionPrepareBlock> *prepareBlocks = [NSMutableArray new];
    if (quotedMessageAssetLoader.prepareBlock) {
        [prepareBlocks addObject:quotedMessageAssetLoader.prepareBlock];
    }
    if (replyAssetLoader.prepareBlock) {
        [prepareBlocks addObject:replyAssetLoader.prepareBlock];
    }

    // We don't need to configure ConversationStyle's view width in this case.
    ConversationStyle *conversationStyle = [[ConversationStyle alloc] initWithThread:thread];

    return [DebugUIMessagesSingleAction
               actionWithLabel:label
        unstaggeredActionBlock:^(NSUInteger index, YapDatabaseReadWriteTransaction *transaction) {
            NSString *_Nullable quotedMessageBodyWIndex
                = (quotedMessageBody ? [NSString stringWithFormat:@"%zd %@", index, quotedMessageBody] : nil);
            TSQuotedMessage *_Nullable quotedMessage = nil;
            if (isQuotedMessageIncoming) {
                TSIncomingMessage *_Nullable messageToQuote = nil;
                messageToQuote = [self createFakeIncomingMessage:thread
                                                     messageBody:quotedMessageBodyWIndex
                                                 fakeAssetLoader:quotedMessageAssetLoader
                                          isAttachmentDownloaded:YES
                                                   quotedMessage:nil
                                                     transaction:transaction];
                OWSAssertDebug(messageToQuote);
                OWSLogVerbose(@"%@", label);
                [DDLog flushLog];
                id<ConversationViewItem> viewItem =
                    [[ConversationInteractionViewItem alloc] initWithInteraction:messageToQuote
                                                                   isGroupThread:thread.isGroupThread
                                                                     transaction:transaction
                                                               conversationStyle:conversationStyle];
                quotedMessage = [
                    [OWSQuotedReplyModel quotedReplyForSendingWithConversationViewItem:viewItem transaction:transaction]
                    buildQuotedMessageForSending];
            } else {
                TSOutgoingMessage *_Nullable messageToQuote = [self createFakeOutgoingMessage:thread
                                                                                  messageBody:quotedMessageBodyWIndex
                                                                              fakeAssetLoader:quotedMessageAssetLoader
                                                                                 messageState:quotedMessageMessageState
                                                                                  isDelivered:quotedMessageIsDelivered
                                                                                       isRead:quotedMessageIsRead
                                                                                quotedMessage:nil
                                                                                 contactShare:nil
                                                                                  transaction:transaction];
                OWSAssertDebug(messageToQuote);

                id<ConversationViewItem> viewItem =
                    [[ConversationInteractionViewItem alloc] initWithInteraction:messageToQuote
                                                                   isGroupThread:thread.isGroupThread
                                                                     transaction:transaction
                                                               conversationStyle:conversationStyle];
                quotedMessage = [
                    [OWSQuotedReplyModel quotedReplyForSendingWithConversationViewItem:viewItem transaction:transaction]
                    buildQuotedMessageForSending];
            }
            OWSAssertDebug(quotedMessage);

            NSString *_Nullable replyMessageBodyWIndex
                = (replyMessageBody ? [NSString stringWithFormat:@"%zd %@", index, replyMessageBody] : nil);
            if (isReplyIncoming) {
                [self createFakeIncomingMessage:thread
                                    messageBody:replyMessageBodyWIndex
                                fakeAssetLoader:replyAssetLoader
                         isAttachmentDownloaded:NO
                                  quotedMessage:quotedMessage
                                    transaction:transaction];
            } else {
                [self createFakeOutgoingMessage:thread
                                    messageBody:replyMessageBodyWIndex
                                fakeAssetLoader:replyAssetLoader
                                   messageState:replyMessageState
                                    isDelivered:replyIsDelivered
                                         isRead:replyIsRead
                                  quotedMessage:quotedMessage
                                   contactShare:nil
                                    transaction:transaction];
            }
        }
                  prepareBlock:[self groupPrepareBlockWithPrepareBlocks:prepareBlocks]];
}

// Recursively perform a group of "prepare blocks" in sequence, aborting
// if any fail.
+ (ActionPrepareBlock)groupPrepareBlockWithPrepareBlocks:(NSArray<ActionPrepareBlock> *)prepareBlocks
{
    return ^(ActionSuccessBlock success, ActionFailureBlock failure) {
        [self groupPrepareBlockStepWithPrepareBlocks:[prepareBlocks mutableCopy] success:success failure:failure];
    };
}

+ (void)groupPrepareBlockStepWithPrepareBlocks:(NSMutableArray<ActionPrepareBlock> *)prepareBlocks
                                       success:(ActionSuccessBlock)success
                                       failure:(ActionFailureBlock)failure
{
    if (prepareBlocks.count < 1) {
        success();
        return;
    }
    ActionPrepareBlock nextPrepareBlock = [prepareBlocks lastObject];
    [prepareBlocks removeLastObject];

    nextPrepareBlock(
        ^{
            [self groupPrepareBlockStepWithPrepareBlocks:prepareBlocks success:success failure:failure];
        },
        failure);
}

+ (NSArray<DebugUIMessagesAction *> *)allFakeQuotedReplyActions:(TSThread *)thread includeLabels:(BOOL)includeLabels
{
    OWSAssertDebug(thread);

    NSString *shortText = @"Lorem ipsum";
    NSString *mediumText = @"Lorem ipsum dolor sit amet, consectetur adipiscing elit. Lorem ipsum dolor sit amet, "
                           @"consectetur adipiscing elit.";
    NSString *longText = [self randomOversizeText];

    NSMutableArray<DebugUIMessagesAction *> *actions = [NSMutableArray new];

    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread
                                                          text:@"⚠️ Quoted Replies (Message Lengths) ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Short Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Short Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Medium Text"
                     isReplyIncoming:NO
                    replyMessageBody:mediumText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Medium Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:mediumText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Medium Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:mediumText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Medium Text"
                     isReplyIncoming:NO
                    replyMessageBody:mediumText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Long Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:longText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Long Text"
                     isReplyIncoming:NO
                    replyMessageBody:longText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],
    ]];

    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread
                                                          text:@"⚠️ Quoted Replies (Attachment Types) ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Jpg"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader jpegInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Jpg"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader jpegInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Mp3"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader mp3Instance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Mp3"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader mp3Instance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Mp4"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader mp4Instance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Mp4"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader mp4Instance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Gif"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader gifInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Gif"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader gifInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Pdf"
             isQuotedMessageIncoming:YES
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader tinyPdfInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Missing Pdf"
             isQuotedMessageIncoming:YES
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader missingPdfInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Tiny Png"
             isQuotedMessageIncoming:YES
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader tinyPngInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Missing Png"
             isQuotedMessageIncoming:YES
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader missingPngInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],
    ]];

    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread
                                                          text:@"⚠️ Quoted Replies (Attachment Layout) ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Tall Portrait Png"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader tallPortraitPngInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Tall Portrait Png"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader tallPortraitPngInstance]
                          replyLabel:@"Medium Text"
                     isReplyIncoming:NO
                    replyMessageBody:mediumText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Tall Portrait Png"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader tallPortraitPngInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Wide Landscape Png"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader wideLandscapePngInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Wide Landscape Png"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader wideLandscapePngInstance]
                          replyLabel:@"Medium Text"
                     isReplyIncoming:NO
                    replyMessageBody:mediumText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Wide Landscape Png"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader wideLandscapePngInstance]
                          replyLabel:@"Medium Text"
                     isReplyIncoming:NO
                    replyMessageBody:mediumText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Tiny Png"
             isQuotedMessageIncoming:YES
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader tinyPngInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Tiny Png"
             isQuotedMessageIncoming:YES
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader tinyPngInstance]
                          replyLabel:@"Medium Text"
                     isReplyIncoming:NO
                    replyMessageBody:mediumText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],
    ]];

    void (^directionActions)(BOOL, BOOL) = ^(BOOL isQuotedMessageIncoming, BOOL isReplyIncoming) {
        [actions addObjectsFromArray:@[
            [self fakeQuotedReplyAction:thread
                      quotedMessageLabel:@"Short Text"
                 isQuotedMessageIncoming:isQuotedMessageIncoming
                       quotedMessageBody:shortText
                quotedMessageAssetLoader:nil
                              replyLabel:@"Short Text"
                         isReplyIncoming:isReplyIncoming
                        replyMessageBody:shortText
                        replyAssetLoader:nil
                       replyMessageState:TSOutgoingMessageStateSent],
        ]];
    };

    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread
                                                          text:@"⚠️ Quoted Replies (Incoming v. Outgoing) ⚠️"]];
    }
    directionActions(NO, NO);
    directionActions(YES, NO);
    directionActions(NO, YES);
    directionActions(YES, YES);

    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread
                                                          text:@"⚠️ Quoted Replies (Message States) ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Jpg"
             isQuotedMessageIncoming:YES
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader jpegInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Mp3"
             isQuotedMessageIncoming:YES
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader mp3Instance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Mp4"
             isQuotedMessageIncoming:YES
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader mp4Instance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Gif"
             isQuotedMessageIncoming:YES
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader gifInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Pdf"
             isQuotedMessageIncoming:YES
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader tinyPdfInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Missing Pdf"
             isQuotedMessageIncoming:YES
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader missingPdfInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Tiny Png"
             isQuotedMessageIncoming:YES
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader tinyPngInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Missing Png"
             isQuotedMessageIncoming:YES
                   quotedMessageBody:nil
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader missingPngInstance]
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Short Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSending],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Short Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Short Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateFailed],
    ]];


    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread
                                                          text:@"⚠️ Quoted Replies (Reply W. Attachment) ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        // Png + Text -> Png + Text
        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Tall Portrait Png"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:[DebugUIMessagesAssetLoader tallPortraitPngInstance]
                          replyLabel:@"Tall Portrait Png"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:[DebugUIMessagesAssetLoader tallPortraitPngInstance]
                   replyMessageState:TSOutgoingMessageStateSent],

        // Text -> Png + Text
        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Short Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Tall Portrait Png"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:nil
                   replyMessageState:TSOutgoingMessageStateSent],

        // Text -> Png
        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Short Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Tall Portrait Png"
                     isReplyIncoming:NO
                    replyMessageBody:nil
                    replyAssetLoader:[DebugUIMessagesAssetLoader tallPortraitPngInstance]
                   replyMessageState:TSOutgoingMessageStateSent],

        // Png -> Png + Text
        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Short Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Tall Portrait Png"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:[DebugUIMessagesAssetLoader tallPortraitPngInstance]
                   replyMessageState:TSOutgoingMessageStateSent],

        // Png -> Portrait Png + Text
        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Short Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Tall Portrait Png"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:[DebugUIMessagesAssetLoader tallPortraitPngInstance]
                   replyMessageState:TSOutgoingMessageStateSent],

        // Png -> Landscape Png + Text
        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Short Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Wide Landscape Png"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:[DebugUIMessagesAssetLoader wideLandscapePngInstance]
                   replyMessageState:TSOutgoingMessageStateSent],


        // Png -> Landscape Png + Text
        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Short Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Wide Landscape Png + Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:[DebugUIMessagesAssetLoader wideLandscapePngInstance]
                   replyMessageState:TSOutgoingMessageStateSent],

        // Png -> Landscape Png + Text
        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Short Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Wide Landscape Png + Short Text"
                     isReplyIncoming:NO
                    replyMessageBody:shortText
                    replyAssetLoader:[DebugUIMessagesAssetLoader wideLandscapePngInstance]
                   replyMessageState:TSOutgoingMessageStateSent],

        // Png -> Landscape Png + Text
        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Short Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Wide Landscape Png + Medium Text"
                     isReplyIncoming:NO
                    replyMessageBody:mediumText
                    replyAssetLoader:[DebugUIMessagesAssetLoader wideLandscapePngInstance]
                   replyMessageState:TSOutgoingMessageStateSent],

        // Png -> Landscape Png + Text
        [self fakeQuotedReplyAction:thread
                  quotedMessageLabel:@"Short Text"
             isQuotedMessageIncoming:NO
                   quotedMessageBody:shortText
            quotedMessageAssetLoader:nil
                          replyLabel:@"Wide Landscape Png + Medium Text"
                     isReplyIncoming:NO
                    replyMessageBody:mediumText
                    replyAssetLoader:[DebugUIMessagesAssetLoader wideLandscapePngInstance]
                   replyMessageState:TSOutgoingMessageStateSent],
    ]];

    return actions;
}

+ (DebugUIMessagesAction *)allQuotedReplyAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return
        [DebugUIMessagesGroupAction allGroupActionWithLabel:@"All Quoted Reply"
                                                 subactions:[self allFakeQuotedReplyActions:thread includeLabels:YES]];
}

+ (void)selectQuotedReplyAction:(TSThread *)thread
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(thread);

    [self selectActionUI:[self allFakeQuotedReplyActions:thread includeLabels:NO] label:@"Select QuotedReply"];
}

+ (DebugUIMessagesAction *)randomQuotedReplyAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesGroupAction
        randomGroupActionWithLabel:@"Random Quoted Reply"
                        subactions:[self allFakeQuotedReplyActions:thread includeLabels:NO]];
}

#pragma mark - Exemplary

+ (NSArray<DebugUIMessagesAction *> *)allFakeActions:(TSThread *)thread includeLabels:(BOOL)includeLabels
{
    OWSAssertDebug(thread);

    NSMutableArray<DebugUIMessagesAction *> *actions = [NSMutableArray new];
    [actions addObjectsFromArray:[self allFakeMediaActions:thread includeLabels:includeLabels]];
    [actions addObjectsFromArray:[self allFakeTextActions:thread includeLabels:includeLabels]];
    [actions addObjectsFromArray:[self allFakeSequenceActions:thread includeLabels:includeLabels]];
    [actions addObjectsFromArray:[self allFakeQuotedReplyActions:thread includeLabels:includeLabels]];
    [actions addObjectsFromArray:[self allFakeBackDatedActions:thread includeLabels:includeLabels]];
    [actions addObjectsFromArray:[self allFakeContactShareActions:thread includeLabels:includeLabels]];
    return actions;
}

+ (DebugUIMessagesAction *)allFakeAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesGroupAction allGroupActionWithLabel:@"All Fake"
                                                    subactions:[self allFakeActions:thread includeLabels:YES]];
}

+ (void)selectFakeAction:(TSThread *)thread
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(thread);

    [self selectActionUI:[self allFakeActions:thread includeLabels:NO] label:@"Select Fake"];
}

+ (void)selectActionUI:(NSArray<DebugUIMessagesAction *> *)actions label:(NSString *)label
{
    OWSAssertIsOnMainThread();
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:label message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (DebugUIMessagesAction *action in actions) {
        [alert addAction:[UIAlertAction actionWithTitle:action.label
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *ignore) {
                                                    [self performActionNTimes:action];
                                                }]];
    }

    [alert addAction:[OWSAlerts cancelAction]];

    UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
    [fromViewController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Sequences

+ (NSArray<DebugUIMessagesAction *> *)allFakeSequenceActions:(TSThread *)thread includeLabels:(BOOL)includeLabels
{
    OWSAssertDebug(thread);

    NSMutableArray<DebugUIMessagesAction *> *actions = [NSMutableArray new];

    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Short Message Sequences ⚠️"]];
    }

    [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"Incoming"]];
    [actions
        addObject:[self fakeOutgoingTextMessageAction:thread messageState:TSOutgoingMessageStateSent text:@"Outgoing"]];
    [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"Incoming 1"]];
    [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"Incoming 2"]];
    [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"Incoming 3"]];
    [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                              messageState:TSOutgoingMessageStateFailed
                                                      text:@"Outgoing Unsent 1"]];
    [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                              messageState:TSOutgoingMessageStateFailed
                                                      text:@"Outgoing Unsent 2"]];
    [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                              messageState:TSOutgoingMessageStateSending
                                                      text:@"Outgoing Sending 1"]];
    [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                              messageState:TSOutgoingMessageStateSending
                                                      text:@"Outgoing Sending 2"]];
    [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                              messageState:TSOutgoingMessageStateSent
                                                      text:@"Outgoing Sent 1"]];
    [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                              messageState:TSOutgoingMessageStateSent
                                                      text:@"Outgoing Sent 2"]];
    [actions addObject:[self fakeShortOutgoingTextMessageAction:thread
                                                           text:@"Outgoing Delivered 1"
                                                   messageState:TSOutgoingMessageStateSent
                                                    isDelivered:YES
                                                         isRead:NO]];
    [actions addObject:[self fakeShortOutgoingTextMessageAction:thread
                                                           text:@"Outgoing Delivered 2"
                                                   messageState:TSOutgoingMessageStateSent
                                                    isDelivered:YES
                                                         isRead:NO]];
    [actions addObject:[self fakeShortOutgoingTextMessageAction:thread
                                                           text:@"Outgoing Read 1"
                                                   messageState:TSOutgoingMessageStateSent
                                                    isDelivered:YES
                                                         isRead:YES]];
    [actions addObject:[self fakeShortOutgoingTextMessageAction:thread
                                                           text:@"Outgoing Read 2"
                                                   messageState:TSOutgoingMessageStateSent
                                                    isDelivered:YES
                                                         isRead:YES]];
    [actions addObject:[self fakeIncomingTextMessageAction:thread text:@"Incoming"]];

    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Long Message Sequences ⚠️"]];
    }

    NSString *longText = @"\nLorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse rutrum, nulla "
                         @"vitae pretium hendrerit, tellus turpis pharetra libero...";

    [actions addObject:[self fakeIncomingTextMessageAction:thread text:[@"Incoming" stringByAppendingString:longText]]];
    [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                              messageState:TSOutgoingMessageStateSent
                                                      text:[@"Outgoing" stringByAppendingString:longText]]];
    [actions
        addObject:[self fakeIncomingTextMessageAction:thread text:[@"Incoming 1" stringByAppendingString:longText]]];
    [actions
        addObject:[self fakeIncomingTextMessageAction:thread text:[@"Incoming 2" stringByAppendingString:longText]]];
    [actions
        addObject:[self fakeIncomingTextMessageAction:thread text:[@"Incoming 3" stringByAppendingString:longText]]];
    [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                              messageState:TSOutgoingMessageStateFailed
                                                      text:[@"Outgoing Unsent 1" stringByAppendingString:longText]]];
    [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                              messageState:TSOutgoingMessageStateFailed
                                                      text:[@"Outgoing Unsent 2" stringByAppendingString:longText]]];
    [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                              messageState:TSOutgoingMessageStateSending
                                                      text:[@"Outgoing Sending 1" stringByAppendingString:longText]]];
    [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                              messageState:TSOutgoingMessageStateSending
                                                      text:[@"Outgoing Sending 2" stringByAppendingString:longText]]];
    [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                              messageState:TSOutgoingMessageStateSent
                                                      text:[@"Outgoing Sent 1" stringByAppendingString:longText]]];
    [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                              messageState:TSOutgoingMessageStateSent
                                                      text:[@"Outgoing Sent 2" stringByAppendingString:longText]]];
    [actions
        addObject:[self fakeShortOutgoingTextMessageAction:thread
                                                      text:[@"Outgoing Delivered 1" stringByAppendingString:longText]
                                              messageState:TSOutgoingMessageStateSent
                                               isDelivered:YES
                                                    isRead:NO]];
    [actions
        addObject:[self fakeShortOutgoingTextMessageAction:thread
                                                      text:[@"Outgoing Delivered 2" stringByAppendingString:longText]
                                              messageState:TSOutgoingMessageStateSent
                                               isDelivered:YES
                                                    isRead:NO]];
    [actions addObject:[self fakeShortOutgoingTextMessageAction:thread
                                                           text:[@"Outgoing Read 1" stringByAppendingString:longText]
                                                   messageState:TSOutgoingMessageStateSent
                                                    isDelivered:YES
                                                         isRead:YES]];
    [actions addObject:[self fakeShortOutgoingTextMessageAction:thread
                                                           text:[@"Outgoing Read 2" stringByAppendingString:longText]
                                                   messageState:TSOutgoingMessageStateSent
                                                    isDelivered:YES
                                                         isRead:YES]];
    [actions addObject:[self fakeIncomingTextMessageAction:thread text:[@"Incoming" stringByAppendingString:longText]]];

    return actions;
}

+ (DebugUIMessagesAction *)allFakeSequencesAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesGroupAction allGroupActionWithLabel:@"All Fake Sequences"
                                                    subactions:[self allFakeSequenceActions:thread includeLabels:YES]];
}

#pragma mark - Back-dated

+ (DebugUIMessagesAction *)fakeBackDatedMessageAction:(TSThread *)thread
                                                label:(NSString *)label
                                           dateOffset:(int64_t)dateOffset
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesSingleAction
               actionWithLabel:[NSString stringWithFormat:@"Fake Back-Date Message (%@)", label]
        unstaggeredActionBlock:^(NSUInteger index, YapDatabaseReadWriteTransaction *transaction) {
            NSString *messageBody =
                [[@(index).stringValue stringByAppendingString:@" "] stringByAppendingString:self.randomText];
            TSOutgoingMessage *message = [self createFakeOutgoingMessage:thread
                                                             messageBody:messageBody
                                                         fakeAssetLoader:nil
                                                            messageState:TSOutgoingMessageStateSent
                                                             isDelivered:NO
                                                                  isRead:NO
                                                           quotedMessage:nil
                                                            contactShare:nil
                                                             transaction:transaction];
            [message setReceivedAtTimestamp:(uint64_t)((int64_t)[NSDate ows_millisecondTimeStamp] + dateOffset)];
            [message saveWithTransaction:transaction];
        }];
}

+ (NSArray<DebugUIMessagesAction *> *)allFakeBackDatedActions:(TSThread *)thread includeLabels:(BOOL)includeLabels
{
    OWSAssertDebug(thread);

    NSMutableArray<DebugUIMessagesAction *> *actions = [NSMutableArray new];

    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Back-Dated ⚠️"]];
    }

    [actions
        addObject:[self fakeBackDatedMessageAction:thread label:@"One Minute Ago" dateOffset:-(int64_t)kMinuteInMs]];
    [actions addObject:[self fakeBackDatedMessageAction:thread label:@"One Hour Ago" dateOffset:-(int64_t)kHourInMs]];
    [actions addObject:[self fakeBackDatedMessageAction:thread label:@"One Day Ago" dateOffset:-(int64_t)kDayInMs]];
    [actions
        addObject:[self fakeBackDatedMessageAction:thread label:@"Two Days Ago" dateOffset:-(int64_t)kDayInMs * 2]];
    [actions
        addObject:[self fakeBackDatedMessageAction:thread label:@"Ten Days Ago" dateOffset:-(int64_t)kDayInMs * 10]];
    [actions
        addObject:[self fakeBackDatedMessageAction:thread label:@"400 Days Ago" dateOffset:-(int64_t)kDayInMs * 400]];

    return actions;
}

+ (DebugUIMessagesAction *)allFakeBackDatedAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesGroupAction allGroupActionWithLabel:@"All Fake Back-Dated"
                                                    subactions:[self allFakeBackDatedActions:thread includeLabels:YES]];
}

+ (void)selectBackDatedAction:(TSThread *)thread
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(thread);

    [self selectActionUI:[self allFakeBackDatedActions:thread includeLabels:NO] label:@"Select Back-Dated"];
}

#pragma mark - Contact Shares

typedef OWSContact * (^OWSContactBlock)(YapDatabaseReadWriteTransaction *transaction);

+ (DebugUIMessagesAction *)fakeContactShareMessageAction:(TSThread *)thread
                                                   label:(NSString *)label
                                            contactBlock:(OWSContactBlock)contactBlock
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesSingleAction
               actionWithLabel:[NSString stringWithFormat:@"Fake Contact Share (%@)", label]
        unstaggeredActionBlock:^(NSUInteger index, YapDatabaseReadWriteTransaction *transaction) {
            OWSContact *contact = contactBlock(transaction);
            TSOutgoingMessage *message = [self createFakeOutgoingMessage:thread
                                                             messageBody:nil
                                                         fakeAssetLoader:nil
                                                            messageState:TSOutgoingMessageStateSent
                                                             isDelivered:NO
                                                                  isRead:NO
                                                           quotedMessage:nil
                                                            contactShare:contact
                                                             transaction:transaction];
            [message saveWithTransaction:transaction];
        }];
}

+ (NSArray<DebugUIMessagesAction *> *)allFakeContactShareActions:(TSThread *)thread includeLabels:(BOOL)includeLabels
{
    OWSAssertDebug(thread);

    NSMutableArray<DebugUIMessagesAction *> *actions = [NSMutableArray new];

    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Share Contact ⚠️"]];
    }

    [actions addObject:[self fakeContactShareMessageAction:thread
                                                     label:@"Name & Number"
                                              contactBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                                  OWSContact *contact = [OWSContact new];
                                                  OWSContactName *name = [OWSContactName new];
                                                  contact.name = name;
                                                  name.givenName = @"Alice";
                                                  OWSContactPhoneNumber *phoneNumber = [OWSContactPhoneNumber new];
                                                  phoneNumber.phoneType = OWSContactPhoneType_Home;
                                                  phoneNumber.phoneNumber = @"+13213214321";
                                                  contact.phoneNumbers = @[
                                                      phoneNumber,
                                                  ];
                                                  return contact;
                                              }]];
    [actions addObject:[self fakeContactShareMessageAction:thread
                                                     label:@"Name & Email"
                                              contactBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                                  OWSContact *contact = [OWSContact new];
                                                  OWSContactName *name = [OWSContactName new];
                                                  contact.name = name;
                                                  name.givenName = @"Bob";
                                                  OWSContactEmail *email = [OWSContactEmail new];
                                                  email.emailType = OWSContactEmailType_Home;
                                                  email.email = @"a@b.com";
                                                  contact.emails = @[
                                                      email,
                                                  ];
                                                  return contact;
                                              }]];
    [actions addObject:[self fakeContactShareMessageAction:thread
                                                     label:@"Complicated"
                                              contactBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                                  OWSContact *contact = [OWSContact new];
                                                  OWSContactName *name = [OWSContactName new];
                                                  contact.name = name;
                                                  name.givenName = @"Alice";
                                                  name.familyName = @"Carol";
                                                  name.middleName = @"Bob";
                                                  name.namePrefix = @"Ms.";
                                                  name.nameSuffix = @"Esq.";
                                                  name.organizationName = @"Falafel Hut";

                                                  OWSContactPhoneNumber *phoneNumber1 = [OWSContactPhoneNumber new];
                                                  phoneNumber1.phoneType = OWSContactPhoneType_Home;
                                                  phoneNumber1.phoneNumber = @"+13213215555";
                                                  OWSContactPhoneNumber *phoneNumber2 = [OWSContactPhoneNumber new];
                                                  phoneNumber2.phoneType = OWSContactPhoneType_Custom;
                                                  phoneNumber2.label = @"Carphone";
                                                  phoneNumber2.phoneNumber = @"+13332226666";
                                                  contact.phoneNumbers = @[
                                                      phoneNumber1,
                                                      phoneNumber2,
                                                  ];

                                                  NSMutableArray<OWSContactEmail *> *emails = [NSMutableArray new];
                                                  for (NSUInteger i = 0; i < 16; i++) {
                                                      OWSContactEmail *email = [OWSContactEmail new];
                                                      email.emailType = OWSContactEmailType_Home;
                                                      email.email = [NSString stringWithFormat:@"a%zd@b.com", i];
                                                      [emails addObject:email];
                                                  }
                                                  contact.emails = emails;

                                                  OWSContactAddress *address1 = [OWSContactAddress new];
                                                  address1.addressType = OWSContactAddressType_Home;
                                                  address1.street = @"123 home st.";
                                                  address1.neighborhood = @"round the bend.";
                                                  address1.city = @"homeville";
                                                  address1.region = @"HO";
                                                  address1.postcode = @"12345";
                                                  address1.country = @"USA";
                                                  OWSContactAddress *address2 = [OWSContactAddress new];
                                                  address2.addressType = OWSContactAddressType_Custom;
                                                  address2.label = @"Otra casa";
                                                  address2.pobox = @"caja 123";
                                                  address2.street = @"123 casa calle";
                                                  address2.city = @"barrio norte";
                                                  address2.region = @"AB";
                                                  address2.postcode = @"53421";
                                                  address2.country = @"MX";
                                                  contact.addresses = @[
                                                      address1,
                                                      address2,
                                                  ];

                                                  UIImage *avatarImage =
                                                      [OWSAvatarBuilder buildRandomAvatarWithDiameter:200];
                                                  [contact saveAvatarImage:avatarImage transaction:transaction];

                                                  return contact;
                                              }]];
    [actions addObject:[self fakeContactShareMessageAction:thread
                                                     label:@"Long values"
                                              contactBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                                  OWSContact *contact = [OWSContact new];
                                                  OWSContactName *name = [OWSContactName new];
                                                  contact.name = name;
                                                  name.givenName = @"Bobasdjasdlkjasldkjas";
                                                  name.familyName = @"Bobasdjasdlkjasldkjas";
                                                  OWSContactEmail *email = [OWSContactEmail new];
                                                  email.emailType = OWSContactEmailType_Mobile;
                                                  email.email = @"asdlakjsaldkjasldkjasdlkjasdlkjasdlkajsa@b.com";
                                                  contact.emails = @[
                                                      email,
                                                  ];
                                                  return contact;
                                              }]];
    [actions addObject:[self fakeContactShareMessageAction:thread
                                                     label:@"System Contact w/o Signal"
                                              contactBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                                  OWSContact *contact = [OWSContact new];
                                                  OWSContactName *name = [OWSContactName new];
                                                  contact.name = name;
                                                  name.givenName = @"Add Me To Your Contacts";
                                                  OWSContactPhoneNumber *phoneNumber = [OWSContactPhoneNumber new];
                                                  phoneNumber.phoneType = OWSContactPhoneType_Work;
                                                  phoneNumber.phoneNumber = @"+324602053911";
                                                  contact.phoneNumbers = @[
                                                      phoneNumber,
                                                  ];
                                                  return contact;
                                              }]];
    [actions addObject:[self fakeContactShareMessageAction:thread
                                                     label:@"System Contact w. Signal"
                                              contactBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                                  OWSContact *contact = [OWSContact new];
                                                  OWSContactName *name = [OWSContactName new];
                                                  contact.name = name;
                                                  name.givenName = @"Add Me To Your Contacts";
                                                  OWSContactPhoneNumber *phoneNumber = [OWSContactPhoneNumber new];
                                                  phoneNumber.phoneType = OWSContactPhoneType_Work;
                                                  phoneNumber.phoneNumber = @"+32460205392";
                                                  contact.phoneNumbers = @[
                                                      phoneNumber,
                                                  ];
                                                  return contact;
                                              }]];

    return actions;
}

+ (DebugUIMessagesAction *)fakeAllContactShareAction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return
        [DebugUIMessagesGroupAction allGroupActionWithLabel:@"All Fake Contact Shares"
                                                 subactions:[self allFakeContactShareActions:thread includeLabels:YES]];
}


+ (DebugUIMessagesAction *)sendContactShareMessageAction:(TSThread *)thread
                                                   label:(NSString *)label
                                            contactBlock:(OWSContactBlock)contactBlock
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesSingleAction
             actionWithLabel:[NSString stringWithFormat:@"Send Contact Share (%@)", label]
        staggeredActionBlock:^(NSUInteger index,
            YapDatabaseReadWriteTransaction *transaction,
            ActionSuccessBlock success,
            ActionFailureBlock failure) {
            OWSContact *contact = contactBlock(transaction);
            OWSLogVerbose(@"sending contact: %@", contact.debugDescription);
            OWSMessageSender *messageSender = SSKEnvironment.shared.messageSender;
            [ThreadUtil sendMessageWithContactShare:contact inThread:thread messageSender:messageSender completion:nil];

            success();
        }];
}

+ (NSArray<DebugUIMessagesAction *> *)allSendContactShareActions:(TSThread *)thread includeLabels:(BOOL)includeLabels
{
    OWSAssertDebug(thread);

    NSMutableArray<DebugUIMessagesAction *> *actions = [NSMutableArray new];

    if (includeLabels) {
        [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                                  messageState:TSOutgoingMessageStateSent
                                                          text:@"⚠️ Send Share Contact ⚠️"]];
    }

    [actions addObject:[self sendContactShareMessageAction:thread
                                                     label:@"Name & Number"
                                              contactBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                                  OWSContact *contact = [OWSContact new];
                                                  OWSContactName *name = [OWSContactName new];
                                                  contact.name = name;
                                                  name.givenName = @"Alice";
                                                  OWSContactPhoneNumber *phoneNumber = [OWSContactPhoneNumber new];
                                                  phoneNumber.phoneType = OWSContactPhoneType_Home;
                                                  phoneNumber.phoneNumber = @"+13213214321";
                                                  contact.phoneNumbers = @[
                                                      phoneNumber,
                                                  ];
                                                  return contact;
                                              }]];
    [actions addObject:[self sendContactShareMessageAction:thread
                                                     label:@"Name & Email"
                                              contactBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                                  OWSContact *contact = [OWSContact new];
                                                  OWSContactName *name = [OWSContactName new];
                                                  contact.name = name;
                                                  name.givenName = @"Bob";
                                                  OWSContactEmail *email = [OWSContactEmail new];
                                                  email.emailType = OWSContactEmailType_Home;
                                                  email.email = @"a@b.com";
                                                  contact.emails = @[
                                                      email,
                                                  ];
                                                  return contact;
                                              }]];
    [actions addObject:[self sendContactShareMessageAction:thread
                                                     label:@"Complicated"
                                              contactBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                                  OWSContact *contact = [OWSContact new];
                                                  OWSContactName *name = [OWSContactName new];
                                                  contact.name = name;
                                                  name.givenName = @"Alice";
                                                  name.familyName = @"Carol";
                                                  name.middleName = @"Bob";
                                                  name.namePrefix = @"Ms.";
                                                  name.nameSuffix = @"Esq.";
                                                  name.organizationName = @"Falafel Hut";

                                                  OWSContactPhoneNumber *phoneNumber1 = [OWSContactPhoneNumber new];
                                                  phoneNumber1.phoneType = OWSContactPhoneType_Home;
                                                  phoneNumber1.phoneNumber = @"+13213214321";
                                                  OWSContactPhoneNumber *phoneNumber2 = [OWSContactPhoneNumber new];
                                                  phoneNumber2.phoneType = OWSContactPhoneType_Custom;
                                                  phoneNumber2.label = @"Carphone";
                                                  phoneNumber2.phoneNumber = @"+13332221111";
                                                  contact.phoneNumbers = @[
                                                      phoneNumber1,
                                                      phoneNumber2,
                                                  ];

                                                  NSMutableArray<OWSContactEmail *> *emails = [NSMutableArray new];
                                                  for (NSUInteger i = 0; i < 16; i++) {
                                                      OWSContactEmail *email = [OWSContactEmail new];
                                                      email.emailType = OWSContactEmailType_Home;
                                                      email.email = [NSString stringWithFormat:@"a%zd@b.com", i];
                                                      [emails addObject:email];
                                                  }
                                                  contact.emails = emails;

                                                  OWSContactAddress *address1 = [OWSContactAddress new];
                                                  address1.addressType = OWSContactAddressType_Home;
                                                  address1.street = @"123 home st.";
                                                  address1.neighborhood = @"round the bend.";
                                                  address1.city = @"homeville";
                                                  address1.region = @"HO";
                                                  address1.postcode = @"12345";
                                                  address1.country = @"USA";
                                                  OWSContactAddress *address2 = [OWSContactAddress new];
                                                  address2.addressType = OWSContactAddressType_Custom;
                                                  address2.label = @"Otra casa";
                                                  address2.pobox = @"caja 123";
                                                  address2.street = @"123 casa calle";
                                                  address2.city = @"barrio norte";
                                                  address2.region = @"AB";
                                                  address2.postcode = @"53421";
                                                  address2.country = @"MX";
                                                  contact.addresses = @[
                                                      address1,
                                                      address2,
                                                  ];

                                                  UIImage *avatarImage =
                                                      [OWSAvatarBuilder buildRandomAvatarWithDiameter:200];
                                                  [contact saveAvatarImage:avatarImage transaction:transaction];

                                                  return contact;
                                              }]];
    [actions addObject:[self sendContactShareMessageAction:thread
                                                     label:@"Long values"
                                              contactBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                                  OWSContact *contact = [OWSContact new];
                                                  OWSContactName *name = [OWSContactName new];
                                                  contact.name = name;
                                                  name.givenName = @"Bobasdjasdlkjasldkjas";
                                                  name.familyName = @"Bobasdjasdlkjasldkjas";
                                                  OWSContactEmail *email = [OWSContactEmail new];
                                                  email.emailType = OWSContactEmailType_Mobile;
                                                  email.email = @"asdlakjsaldkjasldkjasdlkjasdlkjasdlkajsa@b.com";
                                                  contact.emails = @[
                                                      email,
                                                  ];
                                                  return contact;
                                              }]];
    [actions addObject:[self sendContactShareMessageAction:thread
                                                     label:@"System Contact w/o Signal"
                                              contactBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                                  OWSContact *contact = [OWSContact new];
                                                  OWSContactName *name = [OWSContactName new];
                                                  contact.name = name;
                                                  name.givenName = @"Add Me To Your Contacts";
                                                  OWSContactPhoneNumber *phoneNumber = [OWSContactPhoneNumber new];
                                                  phoneNumber.phoneType = OWSContactPhoneType_Work;
                                                  phoneNumber.phoneNumber = @"+324602053911";
                                                  contact.phoneNumbers = @[
                                                      phoneNumber,
                                                  ];
                                                  return contact;
                                              }]];
    [actions addObject:[self sendContactShareMessageAction:thread
                                                     label:@"System Contact w. Signal"
                                              contactBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                                  OWSContact *contact = [OWSContact new];
                                                  OWSContactName *name = [OWSContactName new];
                                                  contact.name = name;
                                                  name.givenName = @"Add Me To Your Contacts";
                                                  OWSContactPhoneNumber *phoneNumber = [OWSContactPhoneNumber new];
                                                  phoneNumber.phoneType = OWSContactPhoneType_Work;
                                                  phoneNumber.phoneNumber = @"+32460205392";
                                                  contact.phoneNumbers = @[
                                                      phoneNumber,
                                                  ];
                                                  return contact;
                                              }]];

    return actions;
}

+ (void)sendAllContacts:(TSThread *)thread
{
    NSArray<DebugUIMessagesAction *> *subactions = [self allSendContactShareActions:thread includeLabels:NO];
    DebugUIMessagesAction *action =
        [DebugUIMessagesGroupAction allGroupActionWithLabel:@"Send All Contact Shares" subactions:subactions];
    [action prepareAndPerformNTimes:subactions.count];
}

#pragma mark -

+ (NSString *)randomOversizeText
{
    NSMutableString *message = [NSMutableString new];
    while (message.length < kOversizeTextMessageSizeThreshold) {
        [message appendString:@"Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse rutrum, nulla "
                              @"vitae pretium hendrerit, tellus turpis pharetra libero, vitae sodales tortor ante vel "
                              @"sem. Fusce sed nisl a lorem gravida tincidunt. Suspendisse efficitur non quam ac "
                              @"sodales. Aenean ut velit maximus, posuere sem a, accumsan nunc. Donec ullamcorper "
                              @"turpis lorem. Quisque dignissim purus eu placerat ultricies. Proin at urna eget mi "
                              @"semper congue. Aenean non elementum ex. Praesent pharetra quam at sem vestibulum, "
                              @"vestibulum ornare dolor elementum. Vestibulum massa tortor, scelerisque sit amet "
                              @"pulvinar a, rhoncus vitae nisl. Sed mi nunc, tempus at varius in, malesuada vitae "
                              @"dui. Vivamus efficitur pulvinar erat vitae congue. Proin vehicula turpis non felis "
                              @"congue facilisis. Nullam aliquet dapibus ligula ac mollis. Etiam sit amet posuere "
                              @"lorem, in rhoncus nisi.\n\n"];
    }
    return message;
}

+ (void)sendOversizeTextMessage:(TSThread *)thread
{
    OWSMessageSender *messageSender = SSKEnvironment.shared.messageSender;
    NSString *message = [self randomOversizeText];
    DataSource *_Nullable dataSource = [DataSourceValue dataSourceWithOversizeText:message];
    SignalAttachment *attachment =
        [SignalAttachment attachmentWithDataSource:dataSource dataUTI:kOversizeTextAttachmentUTI];
    [ThreadUtil sendMessageWithAttachment:attachment
                                 inThread:thread
                         quotedReplyModel:nil
                            messageSender:messageSender
                               completion:nil];
}

+ (NSData *)createRandomNSDataOfSize:(size_t)size
{
    OWSAssertDebug(size % 4 == 0);
    OWSAssertDebug(size < INT_MAX);

    return [Randomness generateRandomBytes:(int)size];
}

+ (void)sendRandomAttachment:(TSThread *)thread uti:(NSString *)uti
{
    [self sendRandomAttachment:thread uti:uti length:256];
}

+ (NSString *)randomCaptionText
{
    return [NSString stringWithFormat:@"%@ (caption)", [self randomText]];
}

+ (void)sendRandomAttachment:(TSThread *)thread uti:(NSString *)uti length:(NSUInteger)length
{
    OWSMessageSender *messageSender = SSKEnvironment.shared.messageSender;
    DataSource *_Nullable dataSource =
        [DataSourceValue dataSourceWithData:[self createRandomNSDataOfSize:length] utiType:uti];
    SignalAttachment *attachment =
        [SignalAttachment attachmentWithDataSource:dataSource dataUTI:uti imageQuality:TSImageQualityOriginal];

    if (arc4random_uniform(100) > 50) {
        // give 1/2 our attachments captions, and add a hint that it's a caption since we
        // style them indistinguishably from a separate text message.
        attachment.captionText = [self randomCaptionText];
    }
    [ThreadUtil sendMessageWithAttachment:attachment
                                 inThread:thread
                         quotedReplyModel:nil
                            messageSender:messageSender
                             ignoreErrors:YES
                               completion:nil];
}

+ (SSKProtoEnvelope *)createEnvelopeForThread:(TSThread *)thread
{
    OWSAssertDebug(thread);

    uint64_t timestamp = [NSDate ows_millisecondTimeStamp];
    NSString *source = ^{
        if ([thread isKindOfClass:[TSGroupThread class]]) {
            TSGroupThread *gThread = (TSGroupThread *)thread;
            return gThread.groupModel.groupMemberIds[0];
        } else if ([thread isKindOfClass:[TSContactThread class]]) {
            TSContactThread *contactThread = (TSContactThread *)thread;
            return contactThread.contactIdentifier;
        } else {
            OWSFailDebug(@"failure: unknown thread type");
            return @"unknown-source-id";
        }
    }();

    SSKProtoEnvelopeBuilder *envelopeBuilder =
        [[SSKProtoEnvelopeBuilder alloc] initWithType:SSKProtoEnvelopeTypeCiphertext
                                               source:source
                                         sourceDevice:1
                                            timestamp:timestamp];
    NSError *error;
    SSKProtoEnvelope *_Nullable envelope = [envelopeBuilder buildAndReturnError:&error];
    if (error || !envelope) {
        OWSFailDebug(@"Could not construct envelope: %@.", error);
        return nil;
    }
    return envelope;
}

+ (NSArray<TSInteraction *> *)unsavedSystemMessagesInThread:(TSThread *)thread
{
    OWSAssertDebug(thread);

    NSMutableArray<TSInteraction *> *result = [NSMutableArray new];

    [OWSPrimaryStorage.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        if ([thread isKindOfClass:[TSContactThread class]]) {
            TSContactThread *contactThread = (TSContactThread *)thread;

            [result addObject:[[TSCall alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                 withCallNumber:@"+19174054215"
                                                       callType:RPRecentCallTypeIncoming
                                                       inThread:contactThread]];
            [result addObject:[[TSCall alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                 withCallNumber:@"+19174054215"
                                                       callType:RPRecentCallTypeOutgoing
                                                       inThread:contactThread]];
            [result addObject:[[TSCall alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                 withCallNumber:@"+19174054215"
                                                       callType:RPRecentCallTypeIncomingMissed
                                                       inThread:contactThread]];
            [result addObject:[[TSCall alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                 withCallNumber:@"+19174054215"
                                                       callType:RPRecentCallTypeIncomingMissedBecauseOfChangedIdentity
                                                       inThread:contactThread]];
            [result addObject:[[TSCall alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                 withCallNumber:@"+19174054215"
                                                       callType:RPRecentCallTypeOutgoingIncomplete
                                                       inThread:contactThread]];
            [result addObject:[[TSCall alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                 withCallNumber:@"+19174054215"
                                                       callType:RPRecentCallTypeIncomingIncomplete
                                                       inThread:contactThread]];
            [result addObject:[[TSCall alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                 withCallNumber:@"+19174054215"
                                                       callType:RPRecentCallTypeIncomingDeclined
                                                       inThread:contactThread]];
            [result addObject:[[TSCall alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                 withCallNumber:@"+19174054215"
                                                       callType:RPRecentCallTypeOutgoingMissed
                                                       inThread:contactThread]];
        }

        {
            NSNumber *durationSeconds = [OWSDisappearingMessagesConfiguration validDurationsSeconds][0];
            OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration =
                [[OWSDisappearingMessagesConfiguration alloc] initWithThreadId:thread.uniqueId
                                                                       enabled:YES
                                                               durationSeconds:(uint32_t)[durationSeconds intValue]];
            [result addObject:[[OWSDisappearingConfigurationUpdateInfoMessage alloc]
                                       initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                  thread:thread
                                           configuration:disappearingMessagesConfiguration
                                     createdByRemoteName:@"Alice"
                                  createdInExistingGroup:NO]];
        }

        {
            NSNumber *durationSeconds = [OWSDisappearingMessagesConfiguration validDurationsSeconds][0];
            OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration =
                [[OWSDisappearingMessagesConfiguration alloc] initWithThreadId:thread.uniqueId
                                                                       enabled:YES
                                                               durationSeconds:(uint32_t)[durationSeconds intValue]];
            [result addObject:[[OWSDisappearingConfigurationUpdateInfoMessage alloc]
                                       initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                  thread:thread
                                           configuration:disappearingMessagesConfiguration
                                     createdByRemoteName:nil
                                  createdInExistingGroup:YES]];
        }

        {
            NSNumber *durationSeconds = [[OWSDisappearingMessagesConfiguration validDurationsSeconds] lastObject];
            OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration =
                [[OWSDisappearingMessagesConfiguration alloc] initWithThreadId:thread.uniqueId
                                                                       enabled:YES
                                                               durationSeconds:(uint32_t)[durationSeconds intValue]];
            [result addObject:[[OWSDisappearingConfigurationUpdateInfoMessage alloc]
                                       initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                  thread:thread
                                           configuration:disappearingMessagesConfiguration
                                     createdByRemoteName:@"Alice"
                                  createdInExistingGroup:NO]];
        }
        {
            OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration =
                [[OWSDisappearingMessagesConfiguration alloc] initWithThreadId:thread.uniqueId
                                                                       enabled:NO
                                                               durationSeconds:0];
            [result addObject:[[OWSDisappearingConfigurationUpdateInfoMessage alloc]
                                       initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                  thread:thread
                                           configuration:disappearingMessagesConfiguration
                                     createdByRemoteName:@"Alice"
                                  createdInExistingGroup:NO]];
        }

        [result addObject:[TSInfoMessage userNotRegisteredMessageInThread:thread recipientId:@"+19174054215"]];

        [result addObject:[[TSInfoMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                          inThread:thread
                                                       messageType:TSInfoMessageTypeSessionDidEnd]];
        // TODO: customMessage?
        [result addObject:[[TSInfoMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                          inThread:thread
                                                       messageType:TSInfoMessageTypeGroupUpdate]];
        // TODO: customMessage?
        [result addObject:[[TSInfoMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                          inThread:thread
                                                       messageType:TSInfoMessageTypeGroupQuit]];

        [result addObject:[[OWSVerificationStateChangeMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                                thread:thread
                                                                           recipientId:@"+19174054215"
                                                                     verificationState:OWSVerificationStateDefault
                                                                         isLocalChange:YES]];
        [result addObject:[[OWSVerificationStateChangeMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                                thread:thread
                                                                           recipientId:@"+19174054215"
                                                                     verificationState:OWSVerificationStateVerified
                                                                         isLocalChange:YES]];
        [result
            addObject:[[OWSVerificationStateChangeMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                            thread:thread
                                                                       recipientId:@"+19174054215"
                                                                 verificationState:OWSVerificationStateNoLongerVerified
                                                                     isLocalChange:YES]];
        [result addObject:[[OWSVerificationStateChangeMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                                thread:thread
                                                                           recipientId:@"+19174054215"
                                                                     verificationState:OWSVerificationStateDefault
                                                                         isLocalChange:NO]];
        [result addObject:[[OWSVerificationStateChangeMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                                thread:thread
                                                                           recipientId:@"+19174054215"
                                                                     verificationState:OWSVerificationStateVerified
                                                                         isLocalChange:NO]];
        [result
            addObject:[[OWSVerificationStateChangeMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                            thread:thread
                                                                       recipientId:@"+19174054215"
                                                                 verificationState:OWSVerificationStateNoLongerVerified
                                                                     isLocalChange:NO]];

        [result addObject:[TSErrorMessage missingSessionWithEnvelope:[self createEnvelopeForThread:thread]
                                                     withTransaction:transaction]];
        [result addObject:[TSErrorMessage invalidKeyExceptionWithEnvelope:[self createEnvelopeForThread:thread]
                                                          withTransaction:transaction]];
        [result addObject:[TSErrorMessage invalidVersionWithEnvelope:[self createEnvelopeForThread:thread]
                                                     withTransaction:transaction]];
        [result addObject:[TSErrorMessage corruptedMessageWithEnvelope:[self createEnvelopeForThread:thread]
                                                       withTransaction:transaction]];
        
        
        TSInvalidIdentityKeyReceivingErrorMessage *_Nullable blockingSNChangeMessage =
            [TSInvalidIdentityKeyReceivingErrorMessage untrustedKeyWithEnvelope:[self createEnvelopeForThread:thread]
                                                                withTransaction:transaction];
        OWSAssertDebug(blockingSNChangeMessage);
        [result addObject:blockingSNChangeMessage];
        [result addObject:[[TSErrorMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                           inThread:thread
                                                  failedMessageType:TSErrorMessageNonBlockingIdentityChange
                                                        recipientId:@"+19174054215"]];
    }];

    return result;
}

+ (void)createSystemMessagesInThread:(TSThread *)thread
{
    OWSAssertDebug(thread);

    NSArray<TSInteraction *> *messages = [self unsavedSystemMessagesInThread:thread];
    [OWSPrimaryStorage.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (TSInteraction *message in messages) {
            [message saveWithTransaction:transaction];
        }
    }];
}

+ (void)createSystemMessageInThread:(TSThread *)thread
{
    OWSAssertDebug(thread);

    NSArray<TSInteraction *> *messages = [self unsavedSystemMessagesInThread:thread];
    TSInteraction *message = messages[(NSUInteger)arc4random_uniform((uint32_t)messages.count)];
    [OWSPrimaryStorage.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [message saveWithTransaction:transaction];
    }];
}

+ (void)sendTextAndSystemMessages:(NSUInteger)counter thread:(TSThread *)thread
{
    if (counter < 1) {
        return;
    }
    if (arc4random_uniform(2) == 0) {
        [self sendTextMessageInThread:thread counter:counter];
    } else {
        [self createSystemMessageInThread:thread];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self sendTextAndSystemMessages:counter - 1 thread:thread];
    });
}

+ (NSString *)randomText
{
    NSArray<NSString *> *randomTexts = @[
        @"Lorem ipsum dolor sit amet, consectetur adipiscing elit. ",
        (@"Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
         @"Suspendisse rutrum, nulla vitae pretium hendrerit, tellus "
         @"turpis pharetra libero, vitae sodales tortor ante vel sem."),
        @"In a time of universal deceit - telling the truth is a revolutionary act.",
        @"If you want a vision of the future, imagine a boot stamping on a human face - forever.",
        @"Who controls the past controls the future. Who controls the present controls the past.",
        @"All animals are equal, but some animals are more equal than others.",
        @"War is peace. Freedom is slavery. Ignorance is strength.",
        (@"All the war-propaganda, all the screaming and lies and hatred, comes invariably from people who are not "
         @"fighting."),
        (@"Political language. . . is designed to make lies sound truthful and murder respectable, and to give an "
         @"appearance of solidity to pure wind."),
        (@"The nationalist not only does not disapprove of atrocities committed by his own side, but he has a "
         @"remarkable capacity for not even hearing about them."),
        (@"Every generation imagines itself to be more intelligent than the one that went before it, and wiser than "
         @"the "
         @"one that comes after it."),
        @"War against a foreign country only happens when the moneyed classes think they are going to profit from it.",
        @"People have only as much liberty as they have the intelligence to want and the courage to take.",
        (@"You cannot buy the revolution. You cannot make the revolution. You can only be the revolution. It is in your "
        @"spirit, or it is nowhere."),
        (@"That is what I have always understood to be the essence of anarchism: the conviction that the burden of "
        @"proof has to be placed on authority, and that it should be dismantled if that burden cannot be met."),
        (@"Ask for work. If they don't give you work, ask for bread. If they do not give you work or bread, then take "
        @"bread."),
        @"Every society has the criminals it deserves.",
        (@"Anarchism is founded on the observation that since few men are wise enough to rule themselves, even fewer "
        @"are wise enough to rule others."),
        @"If you would know who controls you see who you may not criticise.",
        @"At one time in the world there were woods that no one owned."
    ];
    NSString *randomText = randomTexts[(NSUInteger)arc4random_uniform((uint32_t)randomTexts.count)];
    return randomText;
}

+ (void)createFakeThreads:(NSUInteger)threadCount withFakeMessages:(NSUInteger)messageCount
{
    [DebugUIContacts
        createRandomContacts:threadCount
              contactHandler:^(CNContact *_Nonnull contact, NSUInteger idx, BOOL *_Nonnull stop) {
                  NSString *phoneNumberText = contact.phoneNumbers.firstObject.value.stringValue;
                  OWSAssertDebug(phoneNumberText);
                  PhoneNumber *phoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumberText];
                  OWSAssertDebug(phoneNumber);
                  OWSAssertDebug(phoneNumber.toE164);

                  TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:phoneNumber.toE164];
                  [self sendFakeMessages:messageCount thread:contactThread];
                  OWSLogError(@"Create fake thread: %@, interactions: %lu",
                      phoneNumber.toE164,
                      (unsigned long)contactThread.numberOfInteractions);
              }];
}

+ (void)sendFakeMessages:(NSUInteger)counter thread:(TSThread *)thread
{
    [self sendFakeMessages:counter thread:thread isTextOnly:NO];
}

+ (void)sendFakeMessages:(NSUInteger)counter thread:(TSThread *)thread isTextOnly:(BOOL)isTextOnly
{
    const NSUInteger kMaxBatchSize = 2500;
    if (counter < kMaxBatchSize) {
        [OWSPrimaryStorage.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [self sendFakeMessages:counter thread:thread isTextOnly:isTextOnly transaction:transaction];
        }];
    } else {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSUInteger remainder = counter;
            while (remainder > 0) {
                NSUInteger batchSize = MIN(kMaxBatchSize, remainder);
                [OWSPrimaryStorage.dbReadWriteConnection
                    readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                        [self sendFakeMessages:batchSize thread:thread isTextOnly:isTextOnly transaction:transaction];
                    }];
                remainder -= batchSize;
                OWSLogInfo(@"sendFakeMessages %lu / %lu", (unsigned long)(counter - remainder), (unsigned long)counter);
            }
        });
    }
}

+ (void)thrashInsertAndDeleteForThread:(TSThread *)thread counter:(NSUInteger)counter
{
    if (counter == 0) {
        return;
    }
    uint32_t sendDelay = arc4random_uniform((uint32_t)(0.01 * NSEC_PER_SEC));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, sendDelay), dispatch_get_main_queue(), ^{
        [self sendFakeMessages:1 thread:thread];
    });

    uint32_t deleteDelay = arc4random_uniform((uint32_t)(0.01 * NSEC_PER_SEC));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, deleteDelay), dispatch_get_main_queue(), ^{
        [OWSPrimaryStorage.sharedManager.dbReadWriteConnection
            asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                [self deleteRandomMessages:1 thread:thread transaction:transaction];
            }];
        [self thrashInsertAndDeleteForThread:thread counter:counter - 1];
    });
}

// TODO: Remove.
+ (void)sendFakeMessages:(NSUInteger)counter
                  thread:(TSThread *)thread
              isTextOnly:(BOOL)isTextOnly
             transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSLogInfo(@"sendFakeMessages: %lu", (unsigned long)counter);

    for (NSUInteger i = 0; i < counter; i++) {
        NSString *randomText = [self randomText];
        switch (arc4random_uniform(isTextOnly ? 2 : 4)) {
            case 0: {
                TSIncomingMessage *message =
                    [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                       inThread:thread
                                                                       authorId:@"+19174054215"
                                                                 sourceDeviceId:0
                                                                    messageBody:randomText
                                                                  attachmentIds:@[]
                                                               expiresInSeconds:0
                                                                  quotedMessage:nil
                                                                   contactShare:nil];
                [message markAsReadNowWithSendReadReceipt:NO transaction:transaction];
                break;
            }
            case 1: {
                [self createFakeOutgoingMessage:thread
                                    messageBody:randomText
                                fakeAssetLoader:nil
                                   messageState:TSOutgoingMessageStateFailed
                                    isDelivered:NO
                                         isRead:NO
                                  quotedMessage:nil
                                   contactShare:nil
                                    transaction:transaction];
                break;
            }
            case 2: {
                UInt32 filesize = 64;
                TSAttachmentPointer *pointer =
                    [[TSAttachmentPointer alloc] initWithServerId:237391539706350548
                                                              key:[self createRandomNSDataOfSize:filesize]
                                                           digest:nil
                                                        byteCount:filesize
                                                      contentType:@"audio/mp3"
                                                   sourceFilename:@"test.mp3"
                                                   attachmentType:TSAttachmentTypeDefault];
                pointer.state = TSAttachmentPointerStateFailed;
                [pointer saveWithTransaction:transaction];
                TSIncomingMessage *message =
                    [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                       inThread:thread
                                                                       authorId:@"+19174054215"
                                                                 sourceDeviceId:0
                                                                    messageBody:nil
                                                                  attachmentIds:@[
                                                                      pointer.uniqueId,
                                                                  ]
                                                               expiresInSeconds:0
                                                                  quotedMessage:nil
                                                                   contactShare:nil];
                [message markAsReadNowWithSendReadReceipt:NO transaction:transaction];
                break;
            }
            case 3: {
                NSString *filename = @"test.mp3";
                UInt32 filesize = 16;

                TSAttachmentStream *attachmentStream = [[TSAttachmentStream alloc] initWithContentType:@"audio/mp3"
                                                                                             byteCount:filesize
                                                                                        sourceFilename:filename];

                NSError *error;
                BOOL success = [attachmentStream writeData:[self createRandomNSDataOfSize:filesize] error:&error];
                OWSAssertDebug(success && !error);
                [attachmentStream saveWithTransaction:transaction];

                [self createFakeOutgoingMessage:thread
                                    messageBody:nil
                                   attachmentId:attachmentStream.uniqueId
                                       filename:filename
                                   messageState:TSOutgoingMessageStateFailed
                                    isDelivered:NO
                                         isRead:NO
                                 isVoiceMessage:NO
                                  quotedMessage:nil
                                   contactShare:nil
                                    transaction:transaction];
                break;
            }
        }
    }
}

#pragma mark -

+ (void)createNewGroups:(NSUInteger)counter recipientId:(NSString *)recipientId
{
    if (counter < 1) {
        return;
    }

    NSString *groupName = [NSUUID UUID].UUIDString;
    NSMutableArray<NSString *> *recipientIds = [@[
        recipientId,
        [TSAccountManager localNumber],
    ] mutableCopy];
    NSData *groupId = [Randomness generateRandomBytes:16];
    TSGroupModel *groupModel =
        [[TSGroupModel alloc] initWithTitle:groupName memberIds:recipientIds image:nil groupId:groupId];

    __block TSGroupThread *thread;
    [OWSPrimaryStorage.dbReadWriteConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            thread = [TSGroupThread getOrCreateThreadWithGroupModel:groupModel transaction:transaction];
        }];
    OWSAssertDebug(thread);

    TSOutgoingMessage *message =
        [TSOutgoingMessage outgoingMessageInThread:thread groupMetaMessage:TSGroupMetaMessageNew expiresInSeconds:0];
    [message updateWithCustomMessage:NSLocalizedString(@"GROUP_CREATED", nil)];

    OWSMessageSender *messageSender = SSKEnvironment.shared.messageSender;
    void (^completion)(void) = ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [ThreadUtil sendMessageWithText:[@(counter) description]
                                   inThread:thread
                           quotedReplyModel:nil
                              messageSender:messageSender];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self createNewGroups:counter - 1 recipientId:recipientId];
            });
        });
    };
    [messageSender enqueueMessage:message
                          success:completion
                          failure:^(NSError *error) {
                              completion();
                          }];
}

+ (void)injectFakeIncomingMessages:(NSUInteger)counter thread:(TSThread *)thread
{
    // Wait 5 seconds so debug user has time to navigate to another
    // view before message processing occurs.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.f * NSEC_PER_SEC)),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        ^{
            for (NSUInteger i = 0; i < counter; i++) {
                [self injectIncomingMessageInThread:thread counter:counter - i];
            }
        });
}

+ (void)injectIncomingMessageInThread:(TSThread *)thread counter:(NSUInteger)counter
{
    OWSAssertDebug(thread);

    OWSLogInfo(@"injectIncomingMessageInThread: %lu", (unsigned long)counter);

    NSString *randomText = [self randomText];
    NSString *text = [[[@(counter) description] stringByAppendingString:@" "] stringByAppendingString:randomText];

    SSKProtoDataMessageBuilder *dataMessageBuilder = [SSKProtoDataMessageBuilder new];
    [dataMessageBuilder setBody:text];

    if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        SSKProtoGroupContextBuilder *groupBuilder =
            [[SSKProtoGroupContextBuilder alloc] initWithId:groupThread.groupModel.groupId
                                                       type:SSKProtoGroupContextTypeDeliver];
        [dataMessageBuilder setGroup:groupBuilder.buildIgnoringErrors];
    }

    SSKProtoContentBuilder *payloadBuilder = [SSKProtoContentBuilder new];
    [payloadBuilder setDataMessage:dataMessageBuilder.buildIgnoringErrors];
    NSData *plaintextData = [payloadBuilder buildIgnoringErrors].serializedDataIgnoringErrors;

    // Try to use an arbitrary member of the current thread that isn't
    // ourselves as the sender.
    NSString *_Nullable recipientId = [[thread recipientIdentifiers] firstObject];
    // This might be an "empty" group with no other members.  If so, use a fake
    // sender id.
    if (!recipientId) {
        recipientId = @"+12345678901";
    }

    uint64_t timestamp = [NSDate ows_millisecondTimeStamp];
    NSString *source = recipientId;
    uint32_t sourceDevice = 1;
    SSKProtoEnvelopeType envelopeType = SSKProtoEnvelopeTypeCiphertext;
    NSData *content = plaintextData;

    SSKProtoEnvelopeBuilder *envelopeBuilder = [[SSKProtoEnvelopeBuilder alloc] initWithType:envelopeType
                                                                                      source:source
                                                                                sourceDevice:sourceDevice
                                                                                   timestamp:timestamp];
    envelopeBuilder.content = content;
    NSError *error;
    NSData *_Nullable envelopeData = [envelopeBuilder buildSerializedDataAndReturnError:&error];
    if (error || !envelopeData) {
        OWSFailDebug(@"Could not serialize envelope: %@.", error);
        return;
    }

    [OWSPrimaryStorage.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [[OWSBatchMessageProcessor sharedInstance] enqueueEnvelopeData:envelopeData
                                                         plaintextData:plaintextData
                                                           transaction:transaction];
    }];
}

+ (void)performRandomActions:(NSUInteger)counter thread:(TSThread *)thread
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.f * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   ^{
                       [self performRandomActionInThread:thread counter:counter];
                       if (counter > 0) {
                           [self performRandomActions:counter - 1 thread:thread];
                       }
                   });
}

+ (void)performRandomActionInThread:(TSThread *)thread counter:(NSUInteger)counter
{
    typedef void (^TransactionBlock)(YapDatabaseReadWriteTransaction *transaction);
    NSArray<TransactionBlock> *actionBlocks = @[
        ^(YapDatabaseReadWriteTransaction *transaction) {
            // injectIncomingMessageInThread doesn't take a transaction.
            dispatch_async(dispatch_get_main_queue(), ^{
                [self injectIncomingMessageInThread:thread counter:counter];
            });
        },
        ^(YapDatabaseReadWriteTransaction *transaction) {
            // sendTextMessageInThread doesn't take a transaction.
            dispatch_async(dispatch_get_main_queue(), ^{
                [self sendTextMessageInThread:thread counter:counter];
            });
        },
        ^(YapDatabaseReadWriteTransaction *transaction) {
            NSUInteger messageCount = (NSUInteger)(1 + arc4random_uniform(4));
            [self sendFakeMessages:messageCount thread:thread isTextOnly:NO transaction:transaction];
        },
        ^(YapDatabaseReadWriteTransaction *transaction) {
            NSUInteger messageCount = (NSUInteger)(1 + arc4random_uniform(4));
            [self deleteRandomMessages:messageCount thread:thread transaction:transaction];
        },
        ^(YapDatabaseReadWriteTransaction *transaction) {
            NSUInteger messageCount = (NSUInteger)(1 + arc4random_uniform(4));
            [self deleteLastMessages:messageCount thread:thread transaction:transaction];
        },
        ^(YapDatabaseReadWriteTransaction *transaction) {
            NSUInteger messageCount = (NSUInteger)(1 + arc4random_uniform(4));
            [self deleteRandomRecentMessages:messageCount thread:thread transaction:transaction];
        },
        ^(YapDatabaseReadWriteTransaction *transaction) {
            NSUInteger messageCount = (NSUInteger)(1 + arc4random_uniform(4));
            [self insertAndDeleteNewOutgoingMessages:messageCount thread:thread transaction:transaction];
        },
        ^(YapDatabaseReadWriteTransaction *transaction) {
            NSUInteger messageCount = (NSUInteger)(1 + arc4random_uniform(4));
            [self resurrectNewOutgoingMessages1:messageCount thread:thread transaction:transaction];
        },
        ^(YapDatabaseReadWriteTransaction *transaction) {
            NSUInteger messageCount = (NSUInteger)(1 + arc4random_uniform(4));
            [self resurrectNewOutgoingMessages2:messageCount thread:thread transaction:transaction];
        },
    ];
    [OWSPrimaryStorage.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        NSUInteger actionCount = 1 + (NSUInteger)arc4random_uniform(3);
        for (NSUInteger actionIdx = 0; actionIdx < actionCount; actionIdx++) {
            TransactionBlock actionBlock = actionBlocks[(NSUInteger)arc4random_uniform((uint32_t)actionBlocks.count)];
            actionBlock(transaction);
        }
    }];
}

+ (void)deleteRandomMessages:(NSUInteger)count
                      thread:(TSThread *)thread
                 transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSLogInfo(@"deleteRandomMessages: %zd", count);

    YapDatabaseViewTransaction *interactionsByThread = [transaction ext:TSMessageDatabaseViewExtensionName];
    NSUInteger messageCount = [interactionsByThread numberOfItemsInGroup:thread.uniqueId];

    NSMutableArray<NSNumber *> *messageIndices = [NSMutableArray new];
    for (NSUInteger messageIdx = 0; messageIdx < messageCount; messageIdx++) {
        [messageIndices addObject:@(messageIdx)];
    }
    NSMutableArray<TSInteraction *> *interactions = [NSMutableArray new];
    for (NSUInteger i = 0; i < count && messageIndices.count > 0; i++) {
        NSUInteger idx = (NSUInteger)arc4random_uniform((uint32_t)messageIndices.count);
        NSNumber *messageIdx = messageIndices[idx];
        [messageIndices removeObjectAtIndex:idx];

        TSInteraction *_Nullable interaction =
            [interactionsByThread objectAtIndex:messageIdx.unsignedIntegerValue inGroup:thread.uniqueId];
        OWSAssertDebug(interaction);
        [interactions addObject:interaction];
    }

    for (TSInteraction *interaction in interactions) {
        [interaction removeWithTransaction:transaction];
    }
}

+ (void)deleteLastMessages:(NSUInteger)count
                    thread:(TSThread *)thread
               transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSLogInfo(@"deleteLastMessages");

    YapDatabaseViewTransaction *interactionsByThread = [transaction ext:TSMessageDatabaseViewExtensionName];
    NSUInteger messageCount = (NSUInteger)[interactionsByThread numberOfItemsInGroup:thread.uniqueId];

    NSMutableArray<NSNumber *> *messageIndices = [NSMutableArray new];
    for (NSUInteger i = 0; i < count && i < messageCount; i++) {
        NSUInteger messageIdx = messageCount - (1 + i);
        [messageIndices addObject:@(messageIdx)];
    }
    NSMutableArray<TSInteraction *> *interactions = [NSMutableArray new];
    for (NSNumber *messageIdx in messageIndices) {
        TSInteraction *_Nullable interaction =
            [interactionsByThread objectAtIndex:messageIdx.unsignedIntegerValue inGroup:thread.uniqueId];
        OWSAssertDebug(interaction);
        [interactions addObject:interaction];
    }
    for (TSInteraction *interaction in interactions) {
        [interaction removeWithTransaction:transaction];
    }
}

+ (void)deleteRandomRecentMessages:(NSUInteger)count
                            thread:(TSThread *)thread
                       transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSLogInfo(@"deleteRandomRecentMessages: %zd", count);

    YapDatabaseViewTransaction *interactionsByThread = [transaction ext:TSMessageDatabaseViewExtensionName];
    NSInteger messageCount = (NSInteger)[interactionsByThread numberOfItemsInGroup:thread.uniqueId];

    NSMutableArray<NSNumber *> *messageIndices = [NSMutableArray new];
    const NSInteger kRecentMessageCount = 10;
    for (NSInteger i = 0; i < kRecentMessageCount; i++) {
        NSInteger messageIdx = messageCount - (1 + i);
        if (messageIdx >= 0) {
            [messageIndices addObject:@(messageIdx)];
        }
    }
    NSMutableArray<TSInteraction *> *interactions = [NSMutableArray new];
    for (NSUInteger i = 0; i < count && messageIndices.count > 0; i++) {
        NSUInteger idx = (NSUInteger)arc4random_uniform((uint32_t)messageIndices.count);
        NSNumber *messageIdx = messageIndices[idx];
        [messageIndices removeObjectAtIndex:idx];

        TSInteraction *_Nullable interaction =
            [interactionsByThread objectAtIndex:messageIdx.unsignedIntegerValue inGroup:thread.uniqueId];
        OWSAssertDebug(interaction);
        [interactions addObject:interaction];
    }
    for (TSInteraction *interaction in interactions) {
        [interaction removeWithTransaction:transaction];
    }
}

+ (void)insertAndDeleteNewOutgoingMessages:(NSUInteger)count
                                    thread:(TSThread *)thread
                               transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSLogInfo(@"insertAndDeleteNewOutgoingMessages: %zd", count);

    NSMutableArray<TSOutgoingMessage *> *messages = [NSMutableArray new];
    for (NSUInteger i =0; i < count; i++) {
        NSString *text = [self randomText];
        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:thread.uniqueId transaction:transaction];

        uint32_t expiresInSeconds = (configuration.isEnabled ? configuration.durationSeconds : 0);
        TSOutgoingMessage *message = [TSOutgoingMessage outgoingMessageInThread:thread
                                                                    messageBody:text
                                                                   attachmentId:nil
                                                               expiresInSeconds:expiresInSeconds];
        OWSLogError(@"insertAndDeleteNewOutgoingMessages timestamp: %llu.", message.timestamp);
        [messages addObject:message];
    }

    for (TSOutgoingMessage *message in messages) {
        [message saveWithTransaction:transaction];
    }
    for (TSOutgoingMessage *message in messages) {
        [message removeWithTransaction:transaction];
    }
}

+ (void)resurrectNewOutgoingMessages1:(NSUInteger)count
                               thread:(TSThread *)thread
                          transaction:(YapDatabaseReadWriteTransaction *)initialTransaction
{
    OWSLogInfo(@"resurrectNewOutgoingMessages1.1: %zd", count);

    NSMutableArray<TSOutgoingMessage *> *messages = [NSMutableArray new];
    for (NSUInteger i =0; i < count; i++) {
        NSString *text = [self randomText];
        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:thread.uniqueId
                                                              transaction:initialTransaction];

        uint32_t expiresInSeconds = (configuration.isEnabled ? configuration.durationSeconds : 0);
        TSOutgoingMessage *message = [TSOutgoingMessage outgoingMessageInThread:thread
                                                                    messageBody:text
                                                                   attachmentId:nil
                                                               expiresInSeconds:expiresInSeconds];
        OWSLogError(@"resurrectNewOutgoingMessages1 timestamp: %llu.", message.timestamp);
        [messages addObject:message];
    }

    for (TSOutgoingMessage *message in messages) {
        [message saveWithTransaction:initialTransaction];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        OWSLogInfo(@"resurrectNewOutgoingMessages1.2: %zd", count);
        [OWSPrimaryStorage.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            for (TSOutgoingMessage *message in messages) {
                [message removeWithTransaction:transaction];
            }
            for (TSOutgoingMessage *message in messages) {
                [message saveWithTransaction:transaction];
            }
        }];
    });
}

+ (void)resurrectNewOutgoingMessages2:(NSUInteger)count
                               thread:(TSThread *)thread
                          transaction:(YapDatabaseReadWriteTransaction *)initialTransaction
{
    OWSLogInfo(@"resurrectNewOutgoingMessages2.1: %zd", count);

    NSMutableArray<TSOutgoingMessage *> *messages = [NSMutableArray new];
    for (NSUInteger i =0; i < count; i++) {
        NSString *text = [self randomText];
        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:thread.uniqueId
                                                              transaction:initialTransaction];
        TSOutgoingMessage *message = [[TSOutgoingMessage alloc]
            initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                    inThread:thread
                                 messageBody:text
                               attachmentIds:[NSMutableArray new]
                            expiresInSeconds:(configuration.isEnabled ? configuration.durationSeconds
                                                                      : 0)expireStartedAt:0
                              isVoiceMessage:NO
                            groupMetaMessage:TSGroupMetaMessageUnspecified
                               quotedMessage:nil
                                contactShare:nil];
        OWSLogError(@"resurrectNewOutgoingMessages2 timestamp: %llu.", message.timestamp);
        [messages addObject:message];
    }

    for (TSOutgoingMessage *message in messages) {
        [message updateWithFakeMessageState:TSOutgoingMessageStateSending transaction:initialTransaction];
        [message saveWithTransaction:initialTransaction];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        OWSLogInfo(@"resurrectNewOutgoingMessages2.2: %zd", count);
        [OWSPrimaryStorage.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            for (TSOutgoingMessage *message in messages) {
                [message removeWithTransaction:transaction];
            }
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            OWSLogInfo(@"resurrectNewOutgoingMessages2.3: %zd", count);
            [OWSPrimaryStorage.dbReadWriteConnection
                readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    for (TSOutgoingMessage *message in messages) {
                        [message saveWithTransaction:transaction];
                    }
                }];
        });
    });
}

+ (void)createTimestampMessagesInThread:(TSThread *)thread
{
    OWSAssertDebug(thread);

    long long now = (long long)[NSDate ows_millisecondTimeStamp];
    NSArray<NSNumber *> *timestamps = @[
        @(now + 1 * (long long)kHourInMs),
        @(now),
        @(now - 1 * (long long)kHourInMs),
        @(now - 12 * (long long)kHourInMs),
        @(now - 1 * (long long)kDayInMs),
        @(now - 2 * (long long)kDayInMs),
        @(now - 3 * (long long)kDayInMs),
        @(now - 6 * (long long)kDayInMs),
        @(now - 7 * (long long)kDayInMs),
        @(now - 8 * (long long)kDayInMs),
        @(now - 2 * (long long)kWeekInMs),
        @(now - 1 * (long long)kMonthInMs),
        @(now - 2 * (long long)kMonthInMs),
    ];
    NSMutableArray<NSString *> *recipientIds = [thread.recipientIdentifiers mutableCopy];
    [recipientIds removeObject:[TSAccountManager localNumber]];
    NSString *recipientId = (recipientIds.count > 0 ? recipientIds.firstObject : @"+19174054215");

    [OWSPrimaryStorage.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (NSNumber *timestamp in timestamps) {
            NSString *randomText = [self randomText];
            {
                TSIncomingMessage *message =
                    [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:timestamp.unsignedLongLongValue
                                                                       inThread:thread
                                                                       authorId:recipientId
                                                                 sourceDeviceId:0
                                                                    messageBody:randomText
                                                                  attachmentIds:[NSMutableArray new]
                                                               expiresInSeconds:0
                                                                  quotedMessage:nil
                                                                   contactShare:nil];
                [message markAsReadNowWithSendReadReceipt:NO transaction:transaction];
            }
            {
                TSOutgoingMessage *message =
                    [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:timestamp.unsignedLongLongValue
                                                                       inThread:thread
                                                                    messageBody:randomText
                                                                  attachmentIds:[NSMutableArray new]
                                                               expiresInSeconds:0
                                                                expireStartedAt:0
                                                                 isVoiceMessage:NO
                                                               groupMetaMessage:TSGroupMetaMessageUnspecified
                                                                  quotedMessage:nil
                                                                   contactShare:nil];
                [message saveWithTransaction:transaction];
                [message updateWithFakeMessageState:TSOutgoingMessageStateSent transaction:transaction];
                [message updateWithSentRecipient:recipientId transaction:transaction];
                [message updateWithDeliveredRecipient:recipientId deliveryTimestamp:timestamp transaction:transaction];
                [message updateWithReadRecipientId:recipientId
                                     readTimestamp:timestamp.unsignedLongLongValue
                                       transaction:transaction];
            }
        }
    }];
}

+ (void)createDisappearingMessagesWhichFailedToStartInThread:(TSThread *)thread
{
    uint64_t now = [NSDate ows_millisecondTimeStamp];
    TSIncomingMessage *message = [[TSIncomingMessage alloc]
        initIncomingMessageWithTimestamp:now
                                inThread:thread
                                authorId:thread.recipientIdentifiers.firstObject
                          sourceDeviceId:0
                             messageBody:[NSString
                                             stringWithFormat:@"Should disappear 60s after %lu", (unsigned long)now]
                           attachmentIds:[NSMutableArray new]
                        expiresInSeconds:60
                           quotedMessage:nil
                            contactShare:nil];
    // private setter to avoid starting expire machinery.
    message.read = YES;
    [message save];
}

+ (void)testIndicScriptsInThread:(TSThread *)thread
{
    NSArray<NSString *> *strings = @[
        @"\u0C1C\u0C4D\u0C1E\u200C\u0C3E",
        @"\u09B8\u09CD\u09B0\u200C\u09C1",
        @"non-crashing string",
    ];

    [OWSPrimaryStorage.sharedManager.dbReadWriteConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            for (NSString *string in strings) {
                // DO NOT log these strings with the debugger attached.
                //        OWSLogInfo(@"%@", string);

                {
                    [self createFakeIncomingMessage:thread
                                        messageBody:string
                                    fakeAssetLoader:nil
                             isAttachmentDownloaded:NO
                                      quotedMessage:nil
                                        transaction:transaction];
                }
                {
                    NSString *recipientId = @"+19174054215";
                    NSString *groupName = string;
                    NSMutableArray<NSString *> *recipientIds = [@[
                        recipientId,
                        [TSAccountManager localNumber],
                    ] mutableCopy];
                    NSData *groupId = [Randomness generateRandomBytes:16];
                    TSGroupModel *groupModel =
                        [[TSGroupModel alloc] initWithTitle:groupName memberIds:recipientIds image:nil groupId:groupId];

                    TSGroupThread *groupThread =
                        [TSGroupThread getOrCreateThreadWithGroupModel:groupModel transaction:transaction];
                    OWSAssertDebug(groupThread);
                }
            }
        }];
}

+ (void)testZalgoTextInThread:(TSThread *)thread
{
    NSArray<NSString *> *strings = @[
        @"Ṱ̴̤̺̣͚͚̭̰̤̮̑̓̀͂͘͡h̵̢̤͔̼̗̦̖̬͌̀͒̀͘i̴̮̤͎͎̝̖̻͓̅̆͆̓̎͘͡ͅŝ̡̡̳͔̓͗̾̀̇͒͘͢͢͡͡ ỉ̛̲̩̫̝͉̀̒͐͋̾͘͢͡͞s̶̨̫̞̜̹͛́̇͑̅̒̊̈ s̵͍̲̗̠̗͈̦̬̉̿͂̏̐͆̾͐͊̾ǫ̶͍̼̝̉͊̉͢͜͞͝ͅͅṁ̵̡̨̬̤̝͔̣̄̍̋͊̿̄͋̈ͅe̪̪̻̱͖͚͈̲̍̃͘͠͝ z̷̢̢̛̩̦̱̺̼͑́̉̾ą͕͎̠̮̹̱̓̔̓̈̈́̅̐͢l̵̨͚̜͉̟̜͉͎̃͆͆͒͑̍̈̚͜͞ğ͔̖̫̞͎͍̒̂́̒̿̽̆͟o̶̢̬͚̘̤̪͇̻̒̋̇̊̏͢͡͡͠ͅ t̡̛̥̦̪̮̅̓̑̈́̉̓̽͛͢͡ȩ̡̩͓͈̩͎͗̔͑̌̓͊͆͝x̫̦͓̤͓̘̝̪͊̆͌͊̽̃̏͒͘͘͢ẗ̶̢̨̛̰̯͕͔́̐͗͌͟͠.̷̩̼̼̩̞̘̪́͗̅͊̎̾̅̏̀̕͟ͅ",
        @"This is some normal text",
    ];

    [OWSPrimaryStorage.sharedManager.dbReadWriteConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            for (NSString *string in strings) {
                OWSLogInfo(@"sending zalgo");

                {
                    [self createFakeIncomingMessage:thread
                                        messageBody:string
                                    fakeAssetLoader:nil
                             isAttachmentDownloaded:NO
                                      quotedMessage:nil
                                        transaction:transaction];
                }
                {
                    NSString *recipientId = @"+19174054215";
                    NSString *groupName = string;
                    NSMutableArray<NSString *> *recipientIds = [@[
                        recipientId,
                        [TSAccountManager localNumber],
                    ] mutableCopy];
                    NSData *groupId = [Randomness generateRandomBytes:16];
                    TSGroupModel *groupModel =
                        [[TSGroupModel alloc] initWithTitle:groupName memberIds:recipientIds image:nil groupId:groupId];

                    TSGroupThread *groupThread =
                        [TSGroupThread getOrCreateThreadWithGroupModel:groupModel transaction:transaction];
                    OWSAssertDebug(groupThread);
                }
            }
        }];
}

+ (void)testDirectionalFilenamesInThread:(TSThread *)thread
{
    NSMutableArray<NSString *> *filenames = [@[
        @"a_test\u202Dabc.exe",
        @"b_test\u202Eabc.exe",
        @"c_testabc.exe",
    ] mutableCopy];
    __block void (^sendUnsafeFile)(void);
    sendUnsafeFile = ^{
        if (filenames.count < 1) {
            return;
        }
        NSString *filename = filenames.lastObject;
        [filenames removeLastObject];
        OWSMessageSender *messageSender = SSKEnvironment.shared.messageSender;
        NSString *utiType = (NSString *)kUTTypeData;
        const NSUInteger kDataLength = 32;
        DataSource *_Nullable dataSource =
            [DataSourceValue dataSourceWithData:[self createRandomNSDataOfSize:kDataLength] utiType:utiType];
        [dataSource setSourceFilename:filename];
        SignalAttachment *attachment =
            [SignalAttachment attachmentWithDataSource:dataSource dataUTI:utiType imageQuality:TSImageQualityOriginal];

        OWSAssertDebug(attachment);
        if ([attachment hasError]) {
            OWSLogError(@"attachment[%@]: %@", [attachment sourceFilename], [attachment errorName]);
            [DDLog flushLog];
        }
        OWSAssertDebug(![attachment hasError]);
        [ThreadUtil sendMessageWithAttachment:attachment
                                     inThread:thread
                             quotedReplyModel:nil
                                messageSender:messageSender
                                   completion:nil];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            sendUnsafeFile();
            sendUnsafeFile = nil;
        });
    };
}

+ (void)deleteAllMessagesInThread:(TSThread *)thread
{
    [OWSPrimaryStorage.sharedManager.newDatabaseConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [thread removeAllThreadInteractionsWithTransaction:transaction];
        }];
}

#pragma mark - Utility

+ (NSString *)actionLabelForHasCaption:(BOOL)hasCaption
                  outgoingMessageState:(TSOutgoingMessageState)outgoingMessageState
                           isDelivered:(BOOL)isDelivered
                                isRead:(BOOL)isRead
{
    NSMutableString *label = [NSMutableString new];
    if (hasCaption) {
        [label appendString:@" 🔤"];
    }
    if (outgoingMessageState == TSOutgoingMessageStateFailed) {
        [label appendString:@" (Unsent)"];
    } else if (outgoingMessageState == TSOutgoingMessageStateSending) {
        [label appendString:@" (Sending)"];
    } else if (outgoingMessageState == TSOutgoingMessageStateSent) {
        if (isRead) {
            [label appendString:@" (Read)"];
        } else if (isDelivered) {
            [label appendString:@" (Delivered)"];
        } else {
            [label appendString:@" (Sent)"];
        }
    } else {
        OWSFailDebug(@"unknown message state.");
    }
    return label;
}

+ (TSOutgoingMessage *)createFakeOutgoingMessage:(TSThread *)thread
                                     messageBody:(nullable NSString *)messageBody
                                 fakeAssetLoader:(nullable DebugUIMessagesAssetLoader *)fakeAssetLoader
                                    messageState:(TSOutgoingMessageState)messageState
                                     isDelivered:(BOOL)isDelivered
                                          isRead:(BOOL)isRead
                                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                                    contactShare:(nullable OWSContact *)contactShare
                                     transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(thread);

    // Seamlessly convert oversize text messages to oversize text attachments.
    if ([messageBody lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= kOversizeTextMessageSizeThreshold) {
        OWSAssertDebug(!fakeAssetLoader);
        fakeAssetLoader = [DebugUIMessagesAssetLoader oversizeTextInstanceWithText:messageBody];
        messageBody = nil;
    }

    TSAttachment *_Nullable attachment = nil;
    if (fakeAssetLoader) {
        attachment = [self createFakeAttachment:fakeAssetLoader isAttachmentDownloaded:YES transaction:transaction];
    }

    return [self createFakeOutgoingMessage:thread
                               messageBody:messageBody
                              attachmentId:attachment.uniqueId
                                  filename:fakeAssetLoader.filename
                              messageState:messageState
                               isDelivered:isDelivered
                                    isRead:isRead
                            isVoiceMessage:attachment.isVoiceMessage
                             quotedMessage:quotedMessage
                              contactShare:contactShare
                               transaction:transaction];
}

+ (TSOutgoingMessage *)createFakeOutgoingMessage:(TSThread *)thread
                                     messageBody:(nullable NSString *)messageBody
                                    attachmentId:(nullable NSString *)attachmentId
                                        filename:(nullable NSString *)filename
                                    messageState:(TSOutgoingMessageState)messageState
                                     isDelivered:(BOOL)isDelivered
                                          isRead:(BOOL)isRead
                                  isVoiceMessage:(BOOL)isVoiceMessage
                                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                                    contactShare:(nullable OWSContact *)contactShare
                                     transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(thread);
    OWSAssertDebug(transaction);
    OWSAssertDebug(messageBody.length > 0 || attachmentId.length > 0 || contactShare);

    NSMutableArray<NSString *> *attachmentIds = [NSMutableArray new];
    if (attachmentId) {
        [attachmentIds addObject:attachmentId];
    }

    TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                           inThread:thread
                                                        messageBody:messageBody
                                                      attachmentIds:attachmentIds
                                                   expiresInSeconds:0
                                                    expireStartedAt:0
                                                     isVoiceMessage:isVoiceMessage
                                                   groupMetaMessage:TSGroupMetaMessageUnspecified
                                                      quotedMessage:quotedMessage
                                                       contactShare:contactShare];

    if (attachmentId.length > 0 && filename.length > 0) {
        message.attachmentFilenameMap[attachmentId] = filename;
    }

    [message saveWithTransaction:transaction];
    [message updateWithFakeMessageState:messageState transaction:transaction];
    if (isDelivered) {
        NSString *_Nullable recipientId = thread.recipientIdentifiers.lastObject;
        OWSAssertDebug(recipientId.length > 0);
        [message updateWithDeliveredRecipient:recipientId
                            deliveryTimestamp:@([NSDate ows_millisecondTimeStamp])
                                  transaction:transaction];
    }
    if (isRead) {
        NSString *_Nullable recipientId = thread.recipientIdentifiers.lastObject;
        OWSAssertDebug(recipientId.length > 0);
        [message updateWithReadRecipientId:recipientId
                             readTimestamp:[NSDate ows_millisecondTimeStamp]
                               transaction:transaction];
    }
    return message;
}

+ (TSIncomingMessage *)createFakeIncomingMessage:(TSThread *)thread
                                     messageBody:(nullable NSString *)messageBody
                                 fakeAssetLoader:(nullable DebugUIMessagesAssetLoader *)fakeAssetLoader
                          isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                                     transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(thread);

    // Seamlessly convert oversize text messages to oversize text attachments.
    if ([messageBody lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= kOversizeTextMessageSizeThreshold) {
        OWSAssertDebug(!fakeAssetLoader);
        fakeAssetLoader = [DebugUIMessagesAssetLoader oversizeTextInstanceWithText:messageBody];
        messageBody = nil;
    }

    TSAttachment *_Nullable attachment = nil;
    if (fakeAssetLoader) {
        attachment = [self createFakeAttachment:fakeAssetLoader
                         isAttachmentDownloaded:isAttachmentDownloaded
                                    transaction:transaction];
    }

    return [self createFakeIncomingMessage:thread
                               messageBody:messageBody
                              attachmentId:attachment.uniqueId
                                  filename:fakeAssetLoader.filename
                    isAttachmentDownloaded:isAttachmentDownloaded
                             quotedMessage:quotedMessage
                               transaction:transaction];
}

+ (TSIncomingMessage *)createFakeIncomingMessage:(TSThread *)thread
                                     messageBody:(nullable NSString *)messageBody
                                    attachmentId:(nullable NSString *)attachmentId
                                        filename:(nullable NSString *)filename
                          isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                                     transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(thread);
    OWSAssertDebug(transaction);
    OWSAssertDebug(messageBody.length > 0 || attachmentId.length > 0);

    NSMutableArray<NSString *> *attachmentIds = [NSMutableArray new];
    if (attachmentId) {
        [attachmentIds addObject:attachmentId];
    }

    //    // Random time within last n years. Helpful for filling out a media gallery over time.
    //    double yearsMillis = 4.0 * kYearsInMs;
    //    uint64_t millisAgo = (uint64_t)(((double)arc4random() / ((double)0xffffffff)) * yearsMillis);
    //    uint64_t timestamp = [NSDate ows_millisecondTimeStamp] - millisAgo;

    TSIncomingMessage *message =
        [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                           inThread:thread
                                                           authorId:@"+19174054215"
                                                     sourceDeviceId:0
                                                        messageBody:messageBody
                                                      attachmentIds:attachmentIds
                                                   expiresInSeconds:0
                                                      quotedMessage:quotedMessage
                                                       contactShare:nil];
    [message markAsReadNowWithSendReadReceipt:NO transaction:transaction];
    return message;
}

+ (TSAttachment *)createFakeAttachment:(DebugUIMessagesAssetLoader *)fakeAssetLoader
                isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                           transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(fakeAssetLoader);
    OWSAssertDebug(fakeAssetLoader.filePath);
    OWSAssertDebug(transaction);

    if (isAttachmentDownloaded) {
        DataSource *dataSource =
            [DataSourcePath dataSourceWithFilePath:fakeAssetLoader.filePath shouldDeleteOnDeallocation:NO];
        NSString *filename = dataSource.sourceFilename;
        // To support "fake missing" attachments, we sometimes lie about the
        // length of the data.
        UInt32 nominalDataLength = (UInt32)MAX((NSUInteger)1, dataSource.dataLength);
        TSAttachmentStream *attachmentStream = [[TSAttachmentStream alloc] initWithContentType:fakeAssetLoader.mimeType
                                                                                     byteCount:nominalDataLength
                                                                                sourceFilename:filename];
        NSError *error;
        BOOL success = [attachmentStream writeData:dataSource.data error:&error];
        OWSAssertDebug(success && !error);
        [attachmentStream saveWithTransaction:transaction];
        return attachmentStream;
    } else {
        UInt32 filesize = 64;
        TSAttachmentPointer *attachmentPointer =
            [[TSAttachmentPointer alloc] initWithServerId:237391539706350548
                                                      key:[self createRandomNSDataOfSize:filesize]
                                                   digest:nil
                                                byteCount:filesize
                                              contentType:fakeAssetLoader.mimeType
                                           sourceFilename:fakeAssetLoader.filename
                                           attachmentType:TSAttachmentTypeDefault];
        attachmentPointer.state = TSAttachmentPointerStateFailed;
        [attachmentPointer saveWithTransaction:transaction];
        return attachmentPointer;
    }
}

#endif

@end

NS_ASSUME_NONNULL_END
