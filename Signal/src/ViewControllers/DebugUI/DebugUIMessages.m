//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "DebugUIMessages.h"
#import "DebugContactsUtils.h"
#import "DebugUIContacts.h"
#import "DebugUIMessagesAction.h"
#import "DebugUIMessagesAssetLoader.h"
#import "Signal-Swift.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSGroupInfoRequestMessage.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalUI/OWSTableViewController.h>

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSUInteger, MessageContentType) {
    MessageContentTypeNormal,
    MessageContentTypeLongText,
    MessageContentTypeShortText
};

#pragma mark -

@interface TSIncomingMessage (DebugUI)

@property (nonatomic, getter=wasRead) BOOL read;

@end

#pragma mark -

@implementation DebugUIMessages

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Messages";
}

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

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    OWSAssertDebug(thread);

    NSMutableArray<OWSTableItem *> *items = [NSMutableArray new];

    [items addObjectsFromArray:@[
        [OWSTableItem itemWithTitle:@"Delete all messages in thread"
                        actionBlock:^{ [DebugUIMessages deleteAllMessagesInThread:thread]; }],
        [OWSTableItem itemWithTitle:@"👷 Create Fake Messages"
                        actionBlock:^{
                            [DebugUIMessages askForQuantityWithTitle:@"How many messages?"
                                                          completion:^(NSUInteger quantity) {
                                                              [DebugUIMessages
                                                                  createFakeMessagesInBatches:quantity
                                                                                       thread:thread
                                                                           messageContentType:MessageContentTypeNormal];
                                                          }];
                        }],
        [OWSTableItem itemWithTitle:@"Create Fake Messages (textonly)"
                        actionBlock:^{
                            [DebugUIMessages
                                askForQuantityWithTitle:@"How many messages?"
                                             completion:^(NSUInteger messageQuantity) {
                                                 [DebugUIMessages
                                                     createFakeMessagesInBatches:messageQuantity
                                                                          thread:thread
                                                              messageContentType:MessageContentTypeLongText];
                                             }];
                        }],
        [OWSTableItem itemWithTitle:@"Create Fake Messages (tiny text)"
                        actionBlock:^{
                            [DebugUIMessages
                                askForQuantityWithTitle:@"How many messages?"
                                             completion:^(NSUInteger messageQuantity) {
                                                 [DebugUIMessages
                                                     createFakeMessagesInBatches:messageQuantity
                                                                          thread:thread
                                                              messageContentType:MessageContentTypeShortText];
                                             }];
                        }],
        [OWSTableItem
            itemWithTitle:@"Thrash insert/deletes"
              actionBlock:^{ [DebugUIMessages thrashInsertAndDeleteForThread:(TSThread *)thread counter:300]; }]
    ]];

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
                        actionBlock:^{ [DebugUIMessages sendNTextMessagesInThread:thread]; }],
        [OWSTableItem itemWithTitle:@"Receive UUID message"
                        actionBlock:^{ [DebugUIMessages receiveUUIDEnvelopeInNewThread]; }],
        [OWSTableItem itemWithTitle:@"Create UUID group" actionBlock:^{ [DebugUIMessages createUUIDGroup]; }],
        [OWSTableItem itemWithTitle:@"Send Media Gallery"
                        actionBlock:^{ [DebugUIMessages sendMediaAlbumInThread:thread]; }],
        [OWSTableItem itemWithTitle:@"Send Exemplary Media Galleries"
                        actionBlock:^{ [DebugUIMessages sendExemplaryMediaGalleriesInThread:thread]; }],
        [OWSTableItem itemWithTitle:@"Select Fake" actionBlock:^{ [DebugUIMessages selectFakeAction:thread]; }],
        [OWSTableItem itemWithTitle:@"Select Send Media"
                        actionBlock:^{ [DebugUIMessages selectSendMediaAction:thread]; }],
        [OWSTableItem itemWithTitle:@"Send All Contact Shares"
                        actionBlock:^{ [DebugUIMessages sendAllContacts:thread]; }],
        [OWSTableItem itemWithTitle:@"Select Quoted Reply"
                        actionBlock:^{ [DebugUIMessages selectQuotedReplyAction:thread]; }],
        [OWSTableItem itemWithTitle:@"Select Back-Dated"
                        actionBlock:^{ [DebugUIMessages selectBackDatedAction:thread]; }],

#pragma mark - Misc.

        [OWSTableItem itemWithTitle:@"Perform random actions"
                        actionBlock:^{
                            [DebugUIMessages askForQuantityWithTitle:@"How many actions?"
                                                          completion:^(NSUInteger quantity) {
                                                              [DebugUIMessages performRandomActions:quantity
                                                                                             thread:thread];
                                                          }];
                        }],
        [OWSTableItem itemWithTitle:@"Create Threads"
                        actionBlock:^{
                            [DebugUIMessages
                                askForQuantityWithTitle:@"How many threads?"
                                             completion:^(NSUInteger threadQuantity) {
                                                 [DebugUIMessages
                                                     askForQuantityWithTitle:@"How many messages in each thread?"
                                                                  completion:^(NSUInteger messageQuantity) {
                                                                      [DebugUIMessages
                                                                          createFakeThreads:threadQuantity
                                                                           withFakeMessages:messageQuantity];
                                                                  }];
                                             }];
                        }],
        [OWSTableItem itemWithTitle:@"Send text/x-signal-plain"
                        actionBlock:^{ [DebugUIMessages sendOversizeTextMessage:thread]; }],
        [OWSTableItem itemWithTitle:@"Send unknown mimetype"
                        actionBlock:^{ [DebugUIMessages sendRandomAttachment:thread uti:kUnknownTestAttachmentUTI]; }],
        [OWSTableItem itemWithTitle:@"Send pdf"
                        actionBlock:^{ [DebugUIMessages sendRandomAttachment:thread uti:(NSString *)kUTTypePDF]; }],
        [OWSTableItem itemWithTitle:@"Create all system messages"
                        actionBlock:^{ [DebugUIMessages createSystemMessagesInThread:thread]; }],
        [OWSTableItem itemWithTitle:@"Create messages with variety of timestamps"
                        actionBlock:^{ [DebugUIMessages createTimestampMessagesInThread:thread]; }],
        [OWSTableItem itemWithTitle:@"Send text and system messages"
                        actionBlock:^{
                            [DebugUIMessages askForQuantityWithTitle:@"How many messages?"
                                                          completion:^(NSUInteger quantity) {
                                                              [DebugUIMessages sendTextAndSystemMessages:quantity
                                                                                                  thread:thread];
                                                          }];
                        }],
        [OWSTableItem itemWithTitle:@"Request Bogus group info"
                        actionBlock:^{
                            OWSLogInfo(@"Requesting bogus group info for thread: %@", thread);
                            DatabaseStorageWrite(
                                SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *_Nonnull transaction) {
                                    OWSGroupInfoRequestMessage *groupInfoRequestMessage =
                                        [[OWSGroupInfoRequestMessage alloc]
                                            initWithThread:thread
                                                   groupId:[TSGroupModel generateRandomV1GroupId]
                                               transaction:transaction];

                                    [self.messageSenderJobQueue addMessage:groupInfoRequestMessage.asPreparer
                                                               transaction:transaction];
                                });
                        }],
        [OWSTableItem
            itemWithTitle:@"Message with stalled timer"
              actionBlock:^{ [DebugUIMessages createDisappearingMessagesWhichFailedToStartInThread:thread]; }],
        [OWSTableItem itemWithTitle:@"Inject fake incoming messages"
                        actionBlock:^{
                            [DebugUIMessages askForQuantityWithTitle:@"How many messages?"
                                                          completion:^(NSUInteger quantity) {
                                                              [DebugUIMessages injectFakeIncomingMessages:quantity
                                                                                                   thread:thread];
                                                          }];
                        }],
        [OWSTableItem itemWithTitle:@"Test Indic Scripts"
                        actionBlock:^{ [DebugUIMessages testIndicScriptsInThread:thread]; }],
        [OWSTableItem itemWithTitle:@"Test Zalgo" actionBlock:^{ [DebugUIMessages testZalgoTextInThread:thread]; }],
        [OWSTableItem itemWithTitle:@"Test Directional Filenames"
                        actionBlock:^{ [DebugUIMessages testDirectionalFilenamesInThread:thread]; }],
        [OWSTableItem itemWithTitle:@"Test Linkification"
                        actionBlock:^{ [DebugUIMessages testLinkificationInThread:thread]; }],

    ]];

    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        SignalServiceAddress *recipientAddress = contactThread.contactAddress;
        [items addObject:[OWSTableItem itemWithTitle:@"Create new groups"
                                         actionBlock:^{
                                             [DebugUIMessages askForQuantityWithTitle:@"How many Groups?"
                                                                           completion:^(NSUInteger quantity) {
                                                                               [DebugUIMessages
                                                                                    createNewGroups:quantity
                                                                                   recipientAddress:recipientAddress];
                                                                           }];
                                         }]];
    }
    if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        [items addObject:[OWSTableItem itemWithTitle:@"Send message to all members"
                                         actionBlock:^{
                                             [DebugUIMessages sendMessages:1 toAllMembersOfGroup:groupThread];
                                         }]];
        [items addObject:[OWSTableItem itemWithTitle:@"Send Group Info Request"
                                         actionBlock:^{
                                             [DebugUIMessages requestGroupInfoForGroupThread:groupThread];
                                         }]];
    }

    return [OWSTableSection sectionWithTitle:self.name items:items];
}

+ (void)sendMessages:(NSUInteger)count toAllMembersOfGroup:(TSGroupThread *)groupThread
{
    for (SignalServiceAddress *address in groupThread.groupModel.groupMembers) {
        TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactAddress:address];
        [[self sendTextMessagesActionInThread:contactThread] prepareAndPerformNTimes:count];
    }
}

+ (void)sendTextMessageInThread:(TSThread *)thread counter:(NSUInteger)counter
{
    OWSLogInfo(@"sendTextMessageInThread: %zd", counter);
    OWSLogFlush();

    NSString *randomText = [self randomText];
    NSString *text = [[[@(counter) description] stringByAppendingString:@" "] stringByAppendingString:randomText];
    __block TSOutgoingMessage *message;
    DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
        message = [ThreadUtil enqueueMessageWithBody:[[MessageBody alloc] initWithText:text
                                                                                ranges:MessageBodyRanges.empty]
                                    mediaAttachments:@[]
                                              thread:thread
                                    quotedReplyModel:nil
                                    linkPreviewDraft:nil
                        persistenceCompletionHandler:nil
                                         transaction:transaction];
    });
    OWSLogInfo(@"sendTextMessageInThread timestamp: %llu.", message.timestamp);
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
                                       SDSAnyWriteTransaction *transaction,
                                       ActionSuccessBlock success,
                                       ActionFailureBlock failure) {
                                       dispatch_async(dispatch_get_main_queue(), ^{
                                           [self sendTextMessageInThread:thread counter:index];
                                           // TODO:
                                           success();
                                       });
                                   }];
}

+ (void)sendAttachmentWithFilePath:(NSString *)filePath
                            thread:(TSThread *)thread
                             label:(NSString *)label
                        hasCaption:(BOOL)hasCaption
                           success:(nullable void (^)(void))success
                           failure:(nullable void (^)(void))failure
{
    OWSAssertDebug(filePath);
    OWSAssertDebug(thread);

    NSString *filename = [filePath lastPathComponent];
    NSString *utiType = [MIMETypeUtil utiTypeForFileExtension:filename.pathExtension];
    NSError *error;
    _Nullable id<DataSource> dataSource = [DataSourcePath dataSourceWithFilePath:filePath
                                                      shouldDeleteOnDeallocation:NO
                                                                           error:&error];
    if (dataSource == nil) {
        OWSFailDebug(@"error while creating data source: %@", error);
        failure();
        return;
    }

    [dataSource setSourceFilename:filename];
    SignalAttachment *attachment = [SignalAttachment attachmentWithDataSource:dataSource dataUTI:utiType];

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
        OWSLogFlush();
    }
    OWSAssertDebug(![attachment hasError]);

    [self sendAttachment:attachment thread:thread messageBody:messageBody];

    success();
}

#pragma mark - Infrastructure

+ (void)askForQuantityWithTitle:(NSString *)title completion:(void (^)(NSUInteger))completion
{
    OWSAssertIsOnMainThread();
    ActionSheetController *alert = [[ActionSheetController alloc] initWithTitle:title message:nil];
    for (NSNumber *countValue in @[
             @(1),
             @(10),
             @(25),
             @(100),
             @(1 * 1000),
             @(10 * 1000),
         ]) {
        [alert addAction:[[ActionSheetAction alloc] initWithTitle:countValue.stringValue
                                                            style:ActionSheetActionStyleDefault
                                                          handler:^(ActionSheetAction *ignore) {
                                                              completion(countValue.unsignedIntegerValue);
                                                          }]];
    }

    [alert addAction:[OWSActionSheets cancelAction]];
    UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
    [fromViewController presentActionSheet:alert];
}

+ (void)performActionNTimes:(DebugUIMessagesAction *)action
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(action);

    [self askForQuantityWithTitle:@"How many?"
                       completion:^(NSUInteger quantity) {
                           [action prepareAndPerformNTimes:quantity];
                       }];
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

    return [DebugUIMessagesSingleAction actionWithLabel:label
                                   staggeredActionBlock:^(NSUInteger index,
                                       SDSAnyWriteTransaction *transaction,
                                       ActionSuccessBlock success,
                                       ActionFailureBlock failure) {
                                       dispatch_async(dispatch_get_main_queue(), ^{
                                           OWSAssertDebug(fakeAssetLoader.filePath.length > 0);
                                           [self sendAttachmentWithFilePath:fakeAssetLoader.filePath
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

    return [DebugUIMessagesSingleAction actionWithLabel:label
                                 unstaggeredActionBlock:^(NSUInteger index, SDSAnyWriteTransaction *transaction) {
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
                    transaction:(SDSAnyWriteTransaction *)transaction
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
                                                     linkPreview:nil
                                                  messageSticker:nil
                                                     transaction:transaction];

    // This is a hack to "back-date" the message.
    [message replaceReceivedAtTimestamp:timestamp transaction:transaction];
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

    return [DebugUIMessagesSingleAction actionWithLabel:label
                                 unstaggeredActionBlock:^(NSUInteger index, SDSAnyWriteTransaction *transaction) {
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
                                   transaction:(SDSAnyWriteTransaction *)transaction
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
                                   transaction:(SDSAnyWriteTransaction *)transaction
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

    ConversationStyle *conversationStyle = [ConversationViewController buildDefaultConversationStyleWithThread:thread];

    [actions addObjectsFromArray:@[
        [self fakeOutgoingPngAction:thread
                        actionLabel:@"Fake Outgoing White Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[UIColor whiteColor]
                          textColor:Theme.accentBlueColor
                         imageLabel:@"W"
                       messageState:TSOutgoingMessageStateFailed
                         hasCaption:YES],
        [self fakeOutgoingPngAction:thread
                        actionLabel:@"Fake Outgoing White Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[UIColor whiteColor]
                          textColor:Theme.accentBlueColor
                         imageLabel:@"W"
                       messageState:TSOutgoingMessageStateSending
                         hasCaption:YES],
        [self fakeOutgoingPngAction:thread
                        actionLabel:@"Fake Outgoing White Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[UIColor whiteColor]
                          textColor:Theme.accentBlueColor
                         imageLabel:@"W"
                       messageState:TSOutgoingMessageStateSent
                         hasCaption:YES],

        [self fakeOutgoingPngAction:thread
                        actionLabel:@"Fake Outgoing 'Outgoing' Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:conversationStyle.bubbleColorIncoming
                          textColor:[UIColor whiteColor]
                         imageLabel:@"W"
                       messageState:TSOutgoingMessageStateFailed
                         hasCaption:YES],
        [self fakeOutgoingPngAction:thread
                        actionLabel:@"Fake Outgoing 'Outgoing' Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:conversationStyle.bubbleColorIncoming
                          textColor:[UIColor whiteColor]
                         imageLabel:@"W"
                       messageState:TSOutgoingMessageStateSending
                         hasCaption:YES],
        [self fakeOutgoingPngAction:thread
                        actionLabel:@"Fake Outgoing 'Outgoing' Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:conversationStyle.bubbleColorIncoming
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
        [actions addObject:[self fakeIncomingTextMessageAction:thread
                                                          text:@"⚠️ Incoming Compact Landscape Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingCompactLandscapePngAction:thread isAttachmentDownloaded:NO hasCaption:NO],
        [self fakeIncomingCompactLandscapePngAction:thread isAttachmentDownloaded:YES hasCaption:NO],
        [self fakeIncomingCompactLandscapePngAction:thread isAttachmentDownloaded:NO hasCaption:YES],
        [self fakeIncomingCompactLandscapePngAction:thread isAttachmentDownloaded:YES hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread
                                                          text:@"⚠️ Incoming Compact Portrait Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingCompactPortraitPngAction:thread isAttachmentDownloaded:NO hasCaption:NO],
        [self fakeIncomingCompactPortraitPngAction:thread isAttachmentDownloaded:YES hasCaption:NO],
        [self fakeIncomingCompactPortraitPngAction:thread isAttachmentDownloaded:NO hasCaption:YES],
        [self fakeIncomingCompactPortraitPngAction:thread isAttachmentDownloaded:YES hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread
                                                          text:@"⚠️ Incoming Wide Landscape Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingWideLandscapePngAction:thread isAttachmentDownloaded:NO hasCaption:NO],
        [self fakeIncomingWideLandscapePngAction:thread isAttachmentDownloaded:YES hasCaption:NO],
        [self fakeIncomingWideLandscapePngAction:thread isAttachmentDownloaded:NO hasCaption:YES],
        [self fakeIncomingWideLandscapePngAction:thread isAttachmentDownloaded:YES hasCaption:YES],
    ]];
    if (includeLabels) {
        [actions addObject:[self fakeIncomingTextMessageAction:thread
                                                          text:@"⚠️ Incoming Tall Portrait Png ⚠️"]];
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
        [actions addObject:[self fakeIncomingTextMessageAction:thread
                                                          text:@"⚠️ Incoming Reserved Color Png ⚠️"]];
    }
    [actions addObjectsFromArray:@[
        [self fakeIncomingPngAction:thread
                        actionLabel:@"Fake Incoming White Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[UIColor whiteColor]
                          textColor:Theme.accentBlueColor
                         imageLabel:@"W"
             isAttachmentDownloaded:YES
                         hasCaption:YES],
        [self fakeIncomingPngAction:thread
                        actionLabel:@"Fake Incoming White Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:[UIColor whiteColor]
                          textColor:Theme.accentBlueColor
                         imageLabel:@"W"
             isAttachmentDownloaded:NO
                         hasCaption:YES],
        [self fakeIncomingPngAction:thread
                        actionLabel:@"Fake Incoming 'Incoming' Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:Theme.accentBlueColor
                          textColor:[UIColor whiteColor]
                         imageLabel:@"W"
             isAttachmentDownloaded:YES
                         hasCaption:YES],
        [self fakeIncomingPngAction:thread
                        actionLabel:@"Fake Incoming 'Incoming' Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:Theme.accentBlueColor
                          textColor:[UIColor whiteColor]
                         imageLabel:@"W"
             isAttachmentDownloaded:YES
                         hasCaption:YES],
        [self fakeIncomingPngAction:thread
                        actionLabel:@"Fake Incoming 'Incoming' Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:Theme.accentBlueColor
                          textColor:[UIColor whiteColor]
                         imageLabel:@"W"
             isAttachmentDownloaded:NO
                         hasCaption:YES],
        [self fakeIncomingPngAction:thread
                        actionLabel:@"Fake Incoming 'Incoming' Png"
                          imageSize:CGSizeMake(200.f, 200.f)
                    backgroundColor:Theme.accentBlueColor
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
                                       SDSAnyWriteTransaction *transaction,
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
                                       SDSAnyWriteTransaction *transaction,
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

    return [DebugUIMessagesSingleAction actionWithLabel:@"Fake Short Incoming Text Message"
                                 unstaggeredActionBlock:^(NSUInteger index, SDSAnyWriteTransaction *transaction) {
                                     NSString *messageBody = [[@(index).stringValue stringByAppendingString:@" "]
                                         stringByAppendingString:[self randomText]];
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
    NSError *error;
    _Nullable id<DataSource> dataSource = [DataSourcePath dataSourceWithFilePath:filePath
                                                      shouldDeleteOnDeallocation:NO
                                                                           error:&error];
    OWSAssertDebug(dataSource != nil);
    [dataSource setSourceFilename:filename];
    SignalAttachment *attachment = [SignalAttachment attachmentWithDataSource:dataSource dataUTI:utiType];
    if (arc4random_uniform(100) > 50) {
        attachment.captionText = [self randomCaptionText];
    }

    OWSAssertDebug(attachment);
    if ([attachment hasError]) {
        OWSLogError(@"attachment[%@]: %@", [attachment sourceFilename], [attachment errorName]);
        OWSLogFlush();
    }
    OWSAssertDebug(![attachment hasError]);
    return attachment;
}

+ (void)sendAttachment:(nullable SignalAttachment *)attachment
                thread:(TSThread *)thread
           messageBody:(nullable NSString *)messageBody
{
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        NSArray<SignalAttachment *> *attachments = @[];
        if (attachment != nil) {
            attachments = @[ attachment ];
        }
        [ThreadUtil enqueueMessageWithBody:[[MessageBody alloc] initWithText:messageBody ranges:MessageBodyRanges.empty]
                          mediaAttachments:attachments
                                    thread:thread
                          quotedReplyModel:nil
                          linkPreviewDraft:nil
              persistenceCompletionHandler:nil
                               transaction:transaction];
    }];
}


+ (DebugUIMessagesAction *)fakeIncomingTextMessageAction:(TSThread *)thread text:(NSString *)text
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesSingleAction
               actionWithLabel:[NSString stringWithFormat:@"Fake Incoming Text Message (%@)", text]
        unstaggeredActionBlock:^(NSUInteger index, SDSAnyWriteTransaction *transaction) {
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
        unstaggeredActionBlock:^(NSUInteger index, SDSAnyWriteTransaction *transaction) {
            NSString *messageBody = [[@(index).stringValue stringByAppendingString:@" "] stringByAppendingString:text];
            [self createFakeOutgoingMessage:thread
                                messageBody:messageBody
                            fakeAssetLoader:nil
                               messageState:messageState
                                isDelivered:NO
                                     isRead:NO
                              quotedMessage:nil
                               contactShare:nil
                                linkPreview:nil
                             messageSticker:nil
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
        unstaggeredActionBlock:^(NSUInteger index, SDSAnyWriteTransaction *transaction) {
            NSString *messageBody = [[@(index).stringValue stringByAppendingString:@" "] stringByAppendingString:text];
            [self createFakeOutgoingMessage:thread
                                messageBody:messageBody
                            fakeAssetLoader:nil
                               messageState:messageState
                                isDelivered:isDelivered
                                     isRead:isRead
                              quotedMessage:nil
                               contactShare:nil
                                linkPreview:nil
                             messageSticker:nil
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

    return [DebugUIMessagesSingleAction
               actionWithLabel:label
        unstaggeredActionBlock:^(NSUInteger index, SDSAnyWriteTransaction *transaction) {
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
                ThreadAssociatedData *threadAssociatedData = [self createFakeThreadAssociatedData:thread];
                OWSAssertDebug(messageToQuote);

                UIView *containerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
                CVRenderItem *renderItem = [CVLoader buildStandaloneRenderItemWithInteraction:messageToQuote
                                                                                       thread:thread
                                                                         threadAssociatedData:threadAssociatedData
                                                                                containerView:containerView
                                                                                  transaction:transaction];
                CVItemViewModelImpl *itemViewModel = [[CVItemViewModelImpl alloc] initWithRenderItem:renderItem];

                quotedMessage =
                    [[OWSQuotedReplyModel quotedReplyForSendingWithItem:itemViewModel
                                                            transaction:transaction] buildQuotedMessageForSending];
            } else {
                TSOutgoingMessage *_Nullable messageToQuote = [self createFakeOutgoingMessage:thread
                                                                                  messageBody:quotedMessageBodyWIndex
                                                                              fakeAssetLoader:quotedMessageAssetLoader
                                                                                 messageState:quotedMessageMessageState
                                                                                  isDelivered:quotedMessageIsDelivered
                                                                                       isRead:quotedMessageIsRead
                                                                                quotedMessage:nil
                                                                                 contactShare:nil
                                                                                  linkPreview:nil
                                                                               messageSticker:nil
                                                                                  transaction:transaction];
                OWSAssertDebug(messageToQuote);
                ThreadAssociatedData *threadAssociatedData = [self createFakeThreadAssociatedData:thread];

                UIView *containerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
                CVRenderItem *renderItem = [CVLoader buildStandaloneRenderItemWithInteraction:messageToQuote
                                                                                       thread:thread
                                                                         threadAssociatedData:threadAssociatedData
                                                                                containerView:containerView
                                                                                  transaction:transaction];
                CVItemViewModelImpl *itemViewModel = [[CVItemViewModelImpl alloc] initWithRenderItem:renderItem];

                quotedMessage =
                    [[OWSQuotedReplyModel quotedReplyForSendingWithItem:itemViewModel
                                                            transaction:transaction] buildQuotedMessageForSending];
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
                                    linkPreview:nil
                                 messageSticker:nil
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

    return [DebugUIMessagesGroupAction allGroupActionWithLabel:@"All Quoted Reply"
                                                    subactions:[self allFakeQuotedReplyActions:thread
                                                                                 includeLabels:YES]];
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

    return [DebugUIMessagesGroupAction randomGroupActionWithLabel:@"Random Quoted Reply"
                                                       subactions:[self allFakeQuotedReplyActions:thread
                                                                                    includeLabels:NO]];
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
    ActionSheetController *alert = [[ActionSheetController alloc] initWithTitle:label message:nil];
    for (DebugUIMessagesAction *action in actions) {
        [alert addAction:[[ActionSheetAction alloc] initWithTitle:action.label
                                                            style:ActionSheetActionStyleDefault
                                                          handler:^(ActionSheetAction *ignore) {
                                                              [self performActionNTimes:action];
                                                          }]];
    }

    [alert addAction:[OWSActionSheets cancelAction]];

    UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
    [fromViewController presentActionSheet:alert];
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
    [actions addObject:[self fakeOutgoingTextMessageAction:thread
                                              messageState:TSOutgoingMessageStateSent
                                                      text:@"Outgoing"]];
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
    [actions addObject:[self fakeIncomingTextMessageAction:thread
                                                      text:[@"Incoming 1" stringByAppendingString:longText]]];
    [actions addObject:[self fakeIncomingTextMessageAction:thread
                                                      text:[@"Incoming 2" stringByAppendingString:longText]]];
    [actions addObject:[self fakeIncomingTextMessageAction:thread
                                                      text:[@"Incoming 3" stringByAppendingString:longText]]];
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
        unstaggeredActionBlock:^(NSUInteger index, SDSAnyWriteTransaction *transaction) {
            NSString *messageBody = [@[ @(index).stringValue, self.randomText, label ] componentsJoinedByString:@" "];
            TSOutgoingMessage *message = [self createFakeOutgoingMessage:thread
                                                             messageBody:messageBody
                                                         fakeAssetLoader:nil
                                                            messageState:TSOutgoingMessageStateSent
                                                             isDelivered:NO
                                                                  isRead:NO
                                                           quotedMessage:nil
                                                            contactShare:nil
                                                             linkPreview:nil
                                                          messageSticker:nil
                                                             transaction:transaction];
            uint64_t timestamp = (uint64_t)((int64_t)[NSDate ows_millisecondTimeStamp] + dateOffset);
            [message replaceTimestamp:timestamp transaction:transaction];
            [message replaceReceivedAtTimestamp:timestamp transaction:transaction];
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

    [actions addObject:[self fakeBackDatedMessageAction:thread
                                                  label:@"One Minute Ago"
                                             dateOffset:-(int64_t)kMinuteInMs]];
    [actions addObject:[self fakeBackDatedMessageAction:thread label:@"One Hour Ago" dateOffset:-(int64_t)kHourInMs]];
    [actions addObject:[self fakeBackDatedMessageAction:thread label:@"One Day Ago" dateOffset:-(int64_t)kDayInMs]];
    [actions addObject:[self fakeBackDatedMessageAction:thread
                                                  label:@"Two Days Ago"
                                             dateOffset:-(int64_t)kDayInMs * 2]];
    [actions addObject:[self fakeBackDatedMessageAction:thread
                                                  label:@"Ten Days Ago"
                                             dateOffset:-(int64_t)kDayInMs * 10]];
    [actions addObject:[self fakeBackDatedMessageAction:thread
                                                  label:@"5 Months Ago"
                                             dateOffset:-(int64_t)kMonthInMs * 5]];
    [actions addObject:[self fakeBackDatedMessageAction:thread
                                                  label:@"7 Months Ago"
                                             dateOffset:-(int64_t)kMonthInMs * 7]];
    [actions addObject:[self fakeBackDatedMessageAction:thread
                                                  label:@"400 Days Ago"
                                             dateOffset:-(int64_t)kDayInMs * 400]];

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

typedef OWSContact * (^OWSContactBlock)(SDSAnyWriteTransaction *transaction);

+ (DebugUIMessagesAction *)fakeContactShareMessageAction:(TSThread *)thread
                                                   label:(NSString *)label
                                            contactBlock:(OWSContactBlock)contactBlock
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesSingleAction actionWithLabel:[NSString stringWithFormat:@"Fake Contact Share (%@)", label]
                                 unstaggeredActionBlock:^(NSUInteger index, SDSAnyWriteTransaction *transaction) {
                                     OWSContact *contact = contactBlock(transaction);
                                     __unused TSOutgoingMessage *message =
                                         [self createFakeOutgoingMessage:thread
                                                             messageBody:nil
                                                         fakeAssetLoader:nil
                                                            messageState:TSOutgoingMessageStateSent
                                                             isDelivered:NO
                                                                  isRead:NO
                                                           quotedMessage:nil
                                                            contactShare:contact
                                                             linkPreview:nil
                                                          messageSticker:nil
                                                             transaction:transaction];
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
                                              contactBlock:^(SDSAnyWriteTransaction *transaction) {
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
                                              contactBlock:^(SDSAnyWriteTransaction *transaction) {
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
                                              contactBlock:^(SDSAnyWriteTransaction *transaction) {
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
                                                      [AvatarBuilder buildRandomAvatarWithDiameterPoints:200];
                                                  [contact saveAvatarImage:avatarImage transaction:transaction];

                                                  return contact;
                                              }]];
    [actions addObject:[self fakeContactShareMessageAction:thread
                                                     label:@"Long values"
                                              contactBlock:^(SDSAnyWriteTransaction *transaction) {
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
                                              contactBlock:^(SDSAnyWriteTransaction *transaction) {
                                                  OWSContact *contact = [OWSContact new];
                                                  OWSContactName *name = [OWSContactName new];
                                                  contact.name = name;
                                                  name.givenName = @"Add Me To Your Contacts";
                                                  OWSContactPhoneNumber *phoneNumber = [OWSContactPhoneNumber new];
                                                  phoneNumber.phoneType = OWSContactPhoneType_Work;
                                                  phoneNumber.phoneNumber = @"+32460205391";
                                                  contact.phoneNumbers = @[
                                                      phoneNumber,
                                                  ];
                                                  return contact;
                                              }]];
    [actions addObject:[self fakeContactShareMessageAction:thread
                                                     label:@"System Contact w. Signal"
                                              contactBlock:^(SDSAnyWriteTransaction *transaction) {
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

    return [DebugUIMessagesGroupAction allGroupActionWithLabel:@"All Fake Contact Shares"
                                                    subactions:[self allFakeContactShareActions:thread
                                                                                  includeLabels:YES]];
}


+ (DebugUIMessagesAction *)sendContactShareMessageAction:(TSThread *)thread
                                                   label:(NSString *)label
                                            contactBlock:(OWSContactBlock)contactBlock
{
    OWSAssertDebug(thread);

    return [DebugUIMessagesSingleAction actionWithLabel:[NSString stringWithFormat:@"Send Contact Share (%@)", label]
                                   staggeredActionBlock:^(NSUInteger index,
                                       SDSAnyWriteTransaction *transaction,
                                       ActionSuccessBlock success,
                                       ActionFailureBlock failure) {
                                       OWSContact *contact = contactBlock(transaction);
                                       OWSLogVerbose(@"sending contact: %@", contact.debugDescription);
        
                                       [ThreadUtil enqueueMessageWithContactShare:contact thread:thread];

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
                                              contactBlock:^(SDSAnyWriteTransaction *transaction) {
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
                                              contactBlock:^(SDSAnyWriteTransaction *transaction) {
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
                                              contactBlock:^(SDSAnyWriteTransaction *transaction) {
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
                                                      [AvatarBuilder buildRandomAvatarWithDiameterPoints:200];
                                                  [contact saveAvatarImage:avatarImage transaction:transaction];

                                                  return contact;
                                              }]];
    [actions addObject:[self sendContactShareMessageAction:thread
                                                     label:@"Long values"
                                              contactBlock:^(SDSAnyWriteTransaction *transaction) {
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
                                              contactBlock:^(SDSAnyWriteTransaction *transaction) {
                                                  OWSContact *contact = [OWSContact new];
                                                  OWSContactName *name = [OWSContactName new];
                                                  contact.name = name;
                                                  name.givenName = @"Add Me To Your Contacts";
                                                  OWSContactPhoneNumber *phoneNumber = [OWSContactPhoneNumber new];
                                                  phoneNumber.phoneType = OWSContactPhoneType_Work;
                                                  phoneNumber.phoneNumber = @"+32460205391";
                                                  contact.phoneNumbers = @[
                                                      phoneNumber,
                                                  ];
                                                  return contact;
                                              }]];
    [actions addObject:[self sendContactShareMessageAction:thread
                                                     label:@"System Contact w. Signal"
                                              contactBlock:^(SDSAnyWriteTransaction *transaction) {
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
    DebugUIMessagesAction *action = [DebugUIMessagesGroupAction allGroupActionWithLabel:@"Send All Contact Shares"
                                                                             subactions:subactions];
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
    [self sendAttachment:nil thread:thread messageBody:[self randomOversizeText]];
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
    _Nullable id<DataSource> dataSource = [DataSourceValue dataSourceWithData:[self createRandomNSDataOfSize:length]
                                                                      utiType:uti];
    SignalAttachment *attachment = [SignalAttachment attachmentWithDataSource:dataSource dataUTI:uti];

    if (arc4random_uniform(100) > 50) {
        // give 1/2 our attachments captions, and add a hint that it's a caption since we
        // style them indistinguishably from a separate text message.
        attachment.captionText = [self randomCaptionText];
    }
    [self sendAttachment:attachment thread:thread messageBody:nil];
}

+ (SSKProtoEnvelope *_Nullable)createEnvelopeForThread:(TSThread *)thread
{
    OWSAssertDebug(thread);

    uint64_t timestamp = [NSDate ows_millisecondTimeStamp];
    SignalServiceAddress *source = ^{
        if ([thread isKindOfClass:[TSGroupThread class]]) {
            TSGroupThread *gThread = (TSGroupThread *)thread;
            return gThread.groupModel.groupMembers[0];
        } else if ([thread isKindOfClass:[TSContactThread class]]) {
            TSContactThread *contactThread = (TSContactThread *)thread;
            return contactThread.contactAddress;
        } else {
            OWSFailDebug(@"failure: unknown thread type");
            return [[SignalServiceAddress alloc] initWithPhoneNumber:@"unknown-source-id"];
        }
    }();

    SSKProtoEnvelopeBuilder *envelopeBuilder = [SSKProtoEnvelope builderWithTimestamp:timestamp];
    [envelopeBuilder setType:SSKProtoEnvelopeTypeCiphertext];
    [envelopeBuilder setSourceUuid:source.uuidString];
    [envelopeBuilder setSourceDevice:1];
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

    __block NSArray<TSInteraction *> *result;
    DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
        result = [self unsavedSystemMessagesInThread:thread transaction:transaction];
    });
    return result;
}

+ (NSArray<TSInteraction *> *)unsavedSystemMessagesInThread:(TSThread *)thread
                                                transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(thread);

    SignalServiceAddress *_Nullable incomingSenderAddress = [DebugUIMessages anyIncomingSenderAddressForThread:thread];
    if (incomingSenderAddress == nil) {
        OWSFailDebug(@"Missing incomingSenderAddress.");
        return @[];
    }
    SignalServiceAddress *otherAddress = incomingSenderAddress;

    NSMutableArray<TSInteraction *> *result = [NSMutableArray new];

    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;

        [result addObject:[[TSCall alloc] initWithCallType:RPRecentCallTypeIncoming
                                                 offerType:TSRecentCallOfferTypeAudio
                                                    thread:contactThread
                                           sentAtTimestamp:[NSDate ows_millisecondTimeStamp]]];
        [result addObject:[[TSCall alloc] initWithCallType:RPRecentCallTypeOutgoing
                                                 offerType:TSRecentCallOfferTypeAudio
                                                    thread:contactThread
                                           sentAtTimestamp:[NSDate ows_millisecondTimeStamp]]];
        [result addObject:[[TSCall alloc] initWithCallType:RPRecentCallTypeIncomingMissed
                                                 offerType:TSRecentCallOfferTypeAudio
                                                    thread:contactThread
                                           sentAtTimestamp:[NSDate ows_millisecondTimeStamp]]];
        [result addObject:[[TSCall alloc] initWithCallType:RPRecentCallTypeIncomingMissedBecauseOfChangedIdentity
                                                 offerType:TSRecentCallOfferTypeAudio
                                                    thread:contactThread
                                           sentAtTimestamp:[NSDate ows_millisecondTimeStamp]]];
        [result addObject:[[TSCall alloc] initWithCallType:RPRecentCallTypeOutgoingIncomplete
                                                 offerType:TSRecentCallOfferTypeAudio
                                                    thread:contactThread
                                           sentAtTimestamp:[NSDate ows_millisecondTimeStamp]]];
        [result addObject:[[TSCall alloc] initWithCallType:RPRecentCallTypeIncomingIncomplete
                                                 offerType:TSRecentCallOfferTypeAudio
                                                    thread:contactThread
                                           sentAtTimestamp:[NSDate ows_millisecondTimeStamp]]];
        [result addObject:[[TSCall alloc] initWithCallType:RPRecentCallTypeIncomingDeclined
                                                 offerType:TSRecentCallOfferTypeAudio
                                                    thread:contactThread
                                           sentAtTimestamp:[NSDate ows_millisecondTimeStamp]]];
        [result addObject:[[TSCall alloc] initWithCallType:RPRecentCallTypeOutgoingMissed
                                                 offerType:TSRecentCallOfferTypeAudio
                                                    thread:contactThread
                                           sentAtTimestamp:[NSDate ows_millisecondTimeStamp]]];
        [result addObject:[[TSCall alloc] initWithCallType:RPRecentCallTypeIncomingMissedBecauseOfDoNotDisturb
                                                 offerType:TSRecentCallOfferTypeAudio
                                                    thread:contactThread
                                           sentAtTimestamp:[NSDate ows_millisecondTimeStamp]]];
    }

    {
        NSNumber *durationSeconds = [OWSDisappearingMessagesConfiguration presetDurationsSeconds][0];
        OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration =
            [thread disappearingMessagesConfigurationWithTransaction:transaction];
        disappearingMessagesConfiguration =
            [disappearingMessagesConfiguration copyAsEnabledWithDurationSeconds:(uint32_t)[durationSeconds intValue]];

        [result addObject:[[OWSDisappearingConfigurationUpdateInfoMessage alloc]
                                      initWithThread:thread
                                       configuration:disappearingMessagesConfiguration
                                 createdByRemoteName:@"Alice"
                              createdInExistingGroup:NO]];
    }

    {
        NSNumber *durationSeconds = [OWSDisappearingMessagesConfiguration presetDurationsSeconds][0];
        OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration =
            [thread disappearingMessagesConfigurationWithTransaction:transaction];
        disappearingMessagesConfiguration =
            [disappearingMessagesConfiguration copyAsEnabledWithDurationSeconds:(uint32_t)[durationSeconds intValue]];

        [result addObject:[[OWSDisappearingConfigurationUpdateInfoMessage alloc]
                                      initWithThread:thread
                                       configuration:disappearingMessagesConfiguration
                                 createdByRemoteName:nil
                              createdInExistingGroup:YES]];
    }

    {
        NSNumber *durationSeconds = [[OWSDisappearingMessagesConfiguration presetDurationsSeconds] lastObject];
        OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration =
            [thread disappearingMessagesConfigurationWithTransaction:transaction];
        disappearingMessagesConfiguration =
            [disappearingMessagesConfiguration copyAsEnabledWithDurationSeconds:(uint32_t)[durationSeconds intValue]];

        [result addObject:[[OWSDisappearingConfigurationUpdateInfoMessage alloc]
                                      initWithThread:thread
                                       configuration:disappearingMessagesConfiguration
                                 createdByRemoteName:@"Alice"
                              createdInExistingGroup:NO]];
    }
    {
        OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration =
            [thread disappearingMessagesConfigurationWithTransaction:transaction];
        disappearingMessagesConfiguration = [disappearingMessagesConfiguration copyWithIsEnabled:NO];

        [result addObject:[[OWSDisappearingConfigurationUpdateInfoMessage alloc]
                                      initWithThread:thread
                                       configuration:disappearingMessagesConfiguration
                                 createdByRemoteName:@"Alice"
                              createdInExistingGroup:NO]];
    }

    [result addObject:[TSInfoMessage userNotRegisteredMessageInThread:thread address:otherAddress]];

    [result addObject:[[TSInfoMessage alloc] initWithThread:thread messageType:TSInfoMessageTypeSessionDidEnd]];
    // TODO: customMessage?
    [result addObject:[[TSInfoMessage alloc] initWithThread:thread messageType:TSInfoMessageTypeGroupUpdate]];
    // TODO: customMessage?
    [result addObject:[[TSInfoMessage alloc] initWithThread:thread messageType:TSInfoMessageTypeGroupQuit]];

    [result addObject:[[OWSVerificationStateChangeMessage alloc] initWithThread:thread
                                                               recipientAddress:otherAddress
                                                              verificationState:OWSVerificationStateDefault
                                                                  isLocalChange:YES]];

    [result addObject:[[OWSVerificationStateChangeMessage alloc] initWithThread:thread
                                                               recipientAddress:otherAddress
                                                              verificationState:OWSVerificationStateVerified
                                                                  isLocalChange:YES]];
    [result addObject:[[OWSVerificationStateChangeMessage alloc] initWithThread:thread
                                                               recipientAddress:otherAddress
                                                              verificationState:OWSVerificationStateNoLongerVerified
                                                                  isLocalChange:YES]];

    [result addObject:[[OWSVerificationStateChangeMessage alloc] initWithThread:thread
                                                               recipientAddress:otherAddress
                                                              verificationState:OWSVerificationStateDefault
                                                                  isLocalChange:NO]];
    [result addObject:[[OWSVerificationStateChangeMessage alloc] initWithThread:thread
                                                               recipientAddress:otherAddress
                                                              verificationState:OWSVerificationStateVerified
                                                                  isLocalChange:NO]];
    [result addObject:[[OWSVerificationStateChangeMessage alloc] initWithThread:thread
                                                               recipientAddress:otherAddress
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
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    TSInvalidIdentityKeyReceivingErrorMessage *_Nullable blockingSNChangeMessage =
        [TSInvalidIdentityKeyReceivingErrorMessage untrustedKeyWithEnvelope:[self createEnvelopeForThread:thread]
                                                             fakeSourceE164:@"+13215550123"
                                                            withTransaction:transaction];
#pragma clang diagnostic pop


    OWSAssertDebug(blockingSNChangeMessage);
    [result addObject:blockingSNChangeMessage];

    [result addObject:[TSErrorMessage nonblockingIdentityChangeInThread:thread
                                                                address:otherAddress
                                                    wasIdentityVerified:NO]];
    [result addObject:[TSErrorMessage nonblockingIdentityChangeInThread:thread
                                                                address:otherAddress
                                                    wasIdentityVerified:YES]];

    return result;
}

+ (void)createSystemMessagesInThread:(TSThread *)thread
{
    OWSAssertDebug(thread);

    NSArray<TSInteraction *> *messages = [self unsavedSystemMessagesInThread:thread];
    DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
        for (TSInteraction *message in messages) {
            [message anyInsertWithTransaction:transaction];
        }
    });
}

+ (void)createSystemMessageInThread:(TSThread *)thread
{
    OWSAssertDebug(thread);

    NSArray<TSInteraction *> *messages = [self unsavedSystemMessagesInThread:thread];
    TSInteraction *message = messages[(NSUInteger)arc4random_uniform((uint32_t)messages.count)];
    DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
        [message anyInsertWithTransaction:transaction];
    });
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
        (@"You cannot buy the revolution. You cannot make the revolution. You can only be the revolution. It is in "
         @"your "
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

+ (NSString *)randomShortText
{
    NSArray<NSString *> *randomTexts = @[
        @"a",
        @"b",
        @"c",
        @"d",
        @"e",
        @"f",
        @"g",
    ];
    NSString *randomText = randomTexts[(NSUInteger)arc4random_uniform((uint32_t)randomTexts.count)];
    return randomText;
}

+ (void)createFakeThreads:(NSUInteger)threadCount withFakeMessages:(NSUInteger)messageCount
{
    [DebugContactsUtils
        createRandomContacts:threadCount
              contactHandler:^(CNContact *_Nonnull contact, NSUInteger idx, BOOL *_Nonnull stop) {
                  NSString *phoneNumberText = contact.phoneNumbers.firstObject.value.stringValue;
                  OWSAssertDebug(phoneNumberText);
                  PhoneNumber *phoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumberText];
                  OWSAssertDebug(phoneNumber);
                  OWSAssertDebug(phoneNumber.toE164);

                  DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                      SignalServiceAddress *address =
                          [[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber.toE164];
                      TSContactThread *contactThread =
                          [TSContactThread getOrCreateThreadWithContactAddress:address transaction:transaction];
                      [self.profileManager addThreadToProfileWhitelist:contactThread transaction:transaction];
                      [self createFakeMessagesInBatches:messageCount
                                                 thread:contactThread
                                     messageContentType:MessageContentTypeLongText
                                            transaction:transaction];

                      NSUInteger interactionCount = [contactThread numberOfInteractionsWithTransaction:transaction];
                      OWSLogInfo(@"Create fake thread: %@, interactions: %lu",
                          phoneNumber.toE164,
                          (unsigned long)interactionCount);
                  });
              }];
}

+ (void)createFakeMessagesInBatches:(NSUInteger)counter
                             thread:(TSThread *)thread
                 messageContentType:(MessageContentType)messageContentType
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self createFakeMessagesInBatches:counter
                                   thread:thread
                       messageContentType:messageContentType
                              transaction:transaction];
    });
}

+ (void)createFakeMessagesInBatches:(NSUInteger)counter
                             thread:(TSThread *)thread
                 messageContentType:(MessageContentType)messageContentType
                        transaction:(SDSAnyWriteTransaction *)transaction
{
    const NSUInteger kMaxBatchSize = 200;
    NSUInteger remainder = counter;
    while (remainder > 0) {
        @autoreleasepool {
            NSUInteger batchSize = MIN(kMaxBatchSize, remainder);
            [self createFakeMessages:batchSize
                         batchOffset:counter - remainder
                              thread:thread
                  messageContentType:messageContentType
                         transaction:transaction];
            remainder -= batchSize;
            OWSLogInfo(@"createFakeMessages %lu / %lu", (unsigned long)(counter - remainder), (unsigned long)counter);
        }
    }
}

+ (void)thrashInsertAndDeleteForThread:(TSThread *)thread counter:(NSUInteger)counter
{
    if (counter == 0) {
        return;
    }
    uint32_t sendDelay = arc4random_uniform((uint32_t)(0.01 * NSEC_PER_SEC));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, sendDelay), dispatch_get_main_queue(), ^{
        [self createFakeMessagesInBatches:1 thread:thread messageContentType:MessageContentTypeLongText];
    });

    uint32_t deleteDelay = arc4random_uniform((uint32_t)(0.01 * NSEC_PER_SEC));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, deleteDelay), dispatch_get_main_queue(), ^{
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *_Nonnull transaction) {
                [self deleteRandomMessagesWithCount:1 thread:thread transaction:transaction];
            });
        });
        [self thrashInsertAndDeleteForThread:thread counter:counter - 1];
    });
}

// TODO: Remove.
+ (void)createFakeMessages:(NSUInteger)counter
               batchOffset:(NSUInteger)offset
                    thread:(TSThread *)thread
        messageContentType:(MessageContentType)messageContentType
               transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSLogInfo(@"createFakeMessages: %lu", (unsigned long)counter);

    SignalServiceAddress *_Nullable incomingSenderAddress = [DebugUIMessages anyIncomingSenderAddressForThread:thread];
    if (incomingSenderAddress == nil) {
        OWSFailDebug(@"Missing incomingSenderAddress.");
        return;
    }

    for (NSUInteger i = 0; i < counter; i++) {
        NSString *randomText
            = (messageContentType == MessageContentTypeShortText ? [self randomShortText] : [self randomText]);
        if (messageContentType == MessageContentTypeShortText) {
            randomText = [randomText stringByAppendingFormat:@" %lu", (unsigned long)i + 1 + offset];
        } else {
            randomText = [randomText stringByAppendingFormat:@" (sequence: %lu)", (unsigned long)i + 1 + offset];
        }
        BOOL isTextOnly = (messageContentType != MessageContentTypeNormal);
        switch (arc4random_uniform(isTextOnly ? 2 : 4)) {
            case 0: {
                TSIncomingMessageBuilder *incomingMessageBuilder =
                    [TSIncomingMessageBuilder incomingMessageBuilderWithThread:thread messageBody:randomText];
                incomingMessageBuilder.authorAddress = incomingSenderAddress;
                TSIncomingMessage *message = [incomingMessageBuilder build];
                [message anyInsertWithTransaction:transaction];
                [message debugonly_markAsReadNowWithTransaction:transaction];
                break;
            }
            case 1: {
                [self createFakeOutgoingMessage:thread
                                    messageBody:randomText
                                fakeAssetLoader:nil
                                   messageState:TSOutgoingMessageStateSent
                                    isDelivered:NO
                                         isRead:NO
                                  quotedMessage:nil
                                   contactShare:nil
                                    linkPreview:nil
                                 messageSticker:nil
                                    transaction:transaction];
                break;
            }
            case 2: {
                UInt32 filesize = 64;
                TSAttachmentPointer *pointer =
                    [[TSAttachmentPointer alloc] initWithServerId:237391539706350548
                                                           cdnKey:@""
                                                        cdnNumber:0
                                                              key:[self createRandomNSDataOfSize:filesize]
                                                           digest:nil
                                                        byteCount:filesize
                                                      contentType:@"image/jpg"
                                                   sourceFilename:@"test.jpg"
                                                          caption:nil
                                                   albumMessageId:nil
                                                   attachmentType:TSAttachmentTypeDefault
                                                        mediaSize:CGSizeZero
                                                         blurHash:nil
                                                  uploadTimestamp:0];
                [pointer setAttachmentPointerStateDebug:TSAttachmentPointerStateFailed];
                [pointer anyInsertWithTransaction:transaction];
                TSIncomingMessageBuilder *incomingMessageBuilder =
                    [TSIncomingMessageBuilder incomingMessageBuilderWithThread:thread messageBody:nil];
                incomingMessageBuilder.authorAddress = incomingSenderAddress;
                incomingMessageBuilder.attachmentIds = [@[
                    pointer.uniqueId,
                ] mutableCopy];
                TSIncomingMessage *message = [incomingMessageBuilder build];
                [message anyInsertWithTransaction:transaction];
                [message debugonly_markAsReadNowWithTransaction:transaction];
                break;
            }
            case 3: {
                ConversationFactory *conversationFactory = [ConversationFactory new];
                // We want to produce a variety of album sizes, but favoring smaller albums
                conversationFactory.attachmentCount = MAX(0,
                    MIN(SignalAttachment.maxAttachmentsAllowed,
                        ((NSInteger)((double)UINT32_MAX / (double)arc4random()) - 1)));
                conversationFactory.threadCreator = ^(SDSAnyWriteTransaction *_transaction){
                    return thread;
                };
                
                [conversationFactory createSentMessageWithTransaction:transaction];
                break;
            }
        }
    }
}

#pragma mark -

+ (void)createNewGroups:(NSUInteger)counter recipientAddress:(SignalServiceAddress *)recipientAddress
{
    if (counter < 1) {
        return;
    }

    void (^completion)(TSGroupThread *) = ^(TSGroupThread *thread) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
                [ThreadUtil enqueueMessageWithBody:[[MessageBody alloc] initWithText:[@(counter) description]
                                                                              ranges:MessageBodyRanges.empty]
                                  mediaAttachments:@[]
                                            thread:thread
                                  quotedReplyModel:nil
                                  linkPreviewDraft:nil
                      persistenceCompletionHandler:nil
                                       transaction:transaction];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self createNewGroups:counter - 1 recipientAddress:recipientAddress];
            });
        });
    };

    NSString *groupName = [NSUUID UUID].UUIDString;
    [self createRandomGroupWithName:groupName member:recipientAddress success:completion];
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
    randomText = [[randomText stringByAppendingString:randomText] stringByAppendingString:@"\n"];
    randomText = [[randomText stringByAppendingString:randomText] stringByAppendingString:@"\n"];
    randomText = [[randomText stringByAppendingString:randomText] stringByAppendingString:@"\n"];
    randomText = [[randomText stringByAppendingString:randomText] stringByAppendingString:@"\n"];
    randomText = [[randomText stringByAppendingString:randomText] stringByAppendingString:@"\n"];
    NSString *text = [[[@(counter) description] stringByAppendingString:@" "] stringByAppendingString:randomText];

    SSKProtoDataMessageBuilder *dataMessageBuilder = [SSKProtoDataMessage builder];
    [dataMessageBuilder setBody:text];

    if ([thread isKindOfClass:[TSGroupThread class]]) {
        if (thread.isGroupV2Thread) {
            TSGroupThread *groupThread = (TSGroupThread *)thread;
            TSGroupModelV2 *groupModel = (TSGroupModelV2 *)groupThread.groupModel;

            NSError *error;
            SSKProtoGroupContextV2 *_Nullable groupContextV2 =
                [self.groupsV2 buildGroupContextV2ProtoWithGroupModel:groupModel
                                               changeActionsProtoData:nil
                                                                error:&error];
            if (groupContextV2 == nil || error != nil) {
                OWSFailDebug(@"Error: %@", error);
            }
            [dataMessageBuilder setGroupV2:groupContextV2];
        } else {
            TSGroupThread *groupThread = (TSGroupThread *)thread;
            SSKProtoGroupContextBuilder *groupBuilder =
                [SSKProtoGroupContext builderWithId:groupThread.groupModel.groupId];
            [groupBuilder setType:SSKProtoGroupContextTypeDeliver];
            [dataMessageBuilder setGroup:groupBuilder.buildIgnoringErrors];
        }
    }

    SSKProtoContentBuilder *payloadBuilder = [SSKProtoContent builder];
    [payloadBuilder setDataMessage:dataMessageBuilder.buildIgnoringErrors];
    NSData *plaintextData = [payloadBuilder buildIgnoringErrors].serializedDataIgnoringErrors;

    // Try to use an arbitrary member of the current thread that isn't
    // ourselves as the sender.
    SignalServiceAddress *_Nullable address = [[thread recipientAddressesWithSneakyTransaction] firstObject];
    // This might be an "empty" group with no other members.  If so, use a fake
    // sender id.
    if (!address) {
        address = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12345678901"];
    }

    uint64_t timestamp = [NSDate ows_millisecondTimeStamp];
    SignalServiceAddress *source = address;
    uint32_t sourceDevice = 1;
    SSKProtoEnvelopeType envelopeType = SSKProtoEnvelopeTypeCiphertext;
    NSData *content = plaintextData;

    SSKProtoEnvelopeBuilder *envelopeBuilder = [SSKProtoEnvelope builderWithTimestamp:timestamp];
    [envelopeBuilder setType:envelopeType];
    [envelopeBuilder setSourceUuid:source.uuidString];
    [envelopeBuilder setSourceDevice:sourceDevice];
    envelopeBuilder.content = content;
    NSError *envelopeError;
    SSKProtoEnvelope *_Nullable envelope = [envelopeBuilder buildAndReturnError:&envelopeError];
    if (envelopeError || !envelope) {
        OWSFailDebug(@"Could not serialize envelope: %@.", envelopeError);
        return;
    }

    [self processDecryptedEnvelope:envelope plaintextData:plaintextData];
}

+ (void)performRandomActions:(NSUInteger)counter thread:(TSThread *)thread
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self performRandomActionInThread:thread counter:counter];
        if (counter > 0) {
            [self performRandomActions:counter - 1 thread:thread];
        }
    });
}

+ (void)performRandomActionInThread:(TSThread *)thread counter:(NSUInteger)counter
{
    typedef void (^TransactionBlock)(SDSAnyWriteTransaction *transaction);
    NSArray<TransactionBlock> *actionBlocks = @[
        ^(SDSAnyWriteTransaction *transaction) {
            // injectIncomingMessageInThread doesn't take a transaction.
            dispatch_async(dispatch_get_main_queue(), ^{
                [self injectIncomingMessageInThread:thread counter:counter];
            });
        },
        ^(SDSAnyWriteTransaction *transaction) {
            // sendTextMessageInThread doesn't take a transaction.
            dispatch_async(dispatch_get_main_queue(), ^{
                [self sendTextMessageInThread:thread counter:counter];
            });
        },
        ^(SDSAnyWriteTransaction *transaction) {
            NSUInteger messageCount = (NSUInteger)(1 + arc4random_uniform(4));
            [self createFakeMessages:messageCount
                         batchOffset:0
                              thread:thread
                  messageContentType:MessageContentTypeNormal
                         transaction:transaction];
        },
        ^(SDSAnyWriteTransaction *transaction) {
            NSUInteger messageCount = (NSUInteger)(1 + arc4random_uniform(4));
            [self deleteRandomMessagesWithCount:messageCount thread:thread transaction:transaction];
        },
        ^(SDSAnyWriteTransaction *transaction) {
            NSUInteger messageCount = (NSUInteger)(1 + arc4random_uniform(4));
            [self deleteLastMessages:messageCount thread:thread transaction:transaction];
        },
        ^(SDSAnyWriteTransaction *transaction) {
            NSUInteger messageCount = (NSUInteger)(1 + arc4random_uniform(4));
            [self deleteRandomRecentMessages:messageCount thread:thread transaction:transaction];
        },
        ^(SDSAnyWriteTransaction *transaction) {
            NSUInteger messageCount = (NSUInteger)(1 + arc4random_uniform(4));
            [self insertAndDeleteNewOutgoingMessages:messageCount thread:thread transaction:transaction];
        },
        ^(SDSAnyWriteTransaction *transaction) {
            NSUInteger messageCount = (NSUInteger)(1 + arc4random_uniform(4));
            [self resurrectNewOutgoingMessages1:messageCount thread:thread transaction:transaction];
        },
        ^(SDSAnyWriteTransaction *transaction) {
            NSUInteger messageCount = (NSUInteger)(1 + arc4random_uniform(4));
            [self resurrectNewOutgoingMessages2:messageCount thread:thread transaction:transaction];
        },
    ];
    DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
        NSUInteger actionCount = 1 + (NSUInteger)arc4random_uniform(3);
        for (NSUInteger actionIdx = 0; actionIdx < actionCount; actionIdx++) {
            TransactionBlock actionBlock = actionBlocks[(NSUInteger)arc4random_uniform((uint32_t)actionBlocks.count)];
            actionBlock(transaction);
        }
    });
}

+ (void)deleteLastMessages:(NSUInteger)count thread:(TSThread *)thread transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSLogInfo(@"deleteLastMessages");

    InteractionFinder *interactionFinder = [[InteractionFinder alloc] initWithThreadUniqueId:thread.uniqueId];
    NSMutableArray<NSString *> *interactionIds = [NSMutableArray new];
    NSError *error;
    [interactionFinder enumerateInteractionIdsWithTransaction:transaction
                                                        error:&error
                                                        block:^(NSString *interactionId, BOOL *stop) {
                                                            [interactionIds addObject:interactionId];
                                                            if (interactionIds.count >= count) {
                                                                *stop = YES;
                                                            }
                                                        }];
    if (error != nil) {
        OWSFailDebug(@"error: %@", error);
    }
    for (NSString *interactionId in interactionIds) {
        TSInteraction *_Nullable interaction = [TSInteraction anyFetchWithUniqueId:interactionId
                                                                       transaction:transaction];
        if (interaction == nil) {
            OWSFailDebug(@"Couldn't load interaction.");
            continue;
        }
        [interaction anyRemoveWithTransaction:transaction];
    }
}

+ (void)deleteRandomRecentMessages:(NSUInteger)count
                            thread:(TSThread *)thread
                       transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSLogInfo(@"deleteRandomRecentMessages: %zd", count);

    const NSInteger kRecentMessageCount = 10;
    InteractionFinder *interactionFinder = [[InteractionFinder alloc] initWithThreadUniqueId:thread.uniqueId];
    NSMutableArray<NSString *> *interactionIds = [NSMutableArray new];
    NSError *error;
    [interactionFinder enumerateInteractionIdsWithTransaction:transaction
                                                        error:&error
                                                        block:^(NSString *interactionId, BOOL *stop) {
                                                            [interactionIds addObject:interactionId];
                                                            if (interactionIds.count >= kRecentMessageCount) {
                                                                *stop = YES;
                                                            }
                                                        }];
    if (error != nil) {
        OWSFailDebug(@"error: %@", error);
    }

    for (NSUInteger i = 0; i < count && interactionIds.count > 0; i++) {
        NSUInteger idx = (NSUInteger)arc4random_uniform((uint32_t)interactionIds.count);
        NSString *interactionId = interactionIds[idx];
        [interactionIds removeObjectAtIndex:idx];

        TSInteraction *_Nullable interaction = [TSInteraction anyFetchWithUniqueId:interactionId
                                                                       transaction:transaction];
        if (interaction == nil) {
            OWSFailDebug(@"Couldn't load interaction.");
            continue;
        }
        [interaction anyRemoveWithTransaction:transaction];
    }
}

+ (void)insertAndDeleteNewOutgoingMessages:(NSUInteger)count
                                    thread:(TSThread *)thread
                               transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSLogInfo(@"insertAndDeleteNewOutgoingMessages: %zd", count);

    NSMutableArray<TSOutgoingMessage *> *messages = [NSMutableArray new];
    for (NSUInteger i =0; i < count; i++) {
        NSString *text = [self randomText];
        OWSDisappearingMessagesConfiguration *configuration =
            [thread disappearingMessagesConfigurationWithTransaction:transaction];

        uint32_t expiresInSeconds = (configuration.isEnabled ? configuration.durationSeconds : 0);
        TSOutgoingMessage *message = [TSOutgoingMessage outgoingMessageInThread:thread
                                                                    messageBody:text
                                                                   attachmentId:nil
                                                               expiresInSeconds:expiresInSeconds];
        OWSLogInfo(@"insertAndDeleteNewOutgoingMessages timestamp: %llu.", message.timestamp);
        [messages addObject:message];
    }

    for (TSOutgoingMessage *message in messages) {
        [message anyInsertWithTransaction:transaction];
    }
    for (TSOutgoingMessage *message in messages) {
        [message anyRemoveWithTransaction:transaction];
    }
}

+ (void)resurrectNewOutgoingMessages1:(NSUInteger)count
                               thread:(TSThread *)thread
                          transaction:(SDSAnyWriteTransaction *)initialTransaction
{
    OWSLogInfo(@"resurrectNewOutgoingMessages1.1: %zd", count);

    NSMutableArray<TSOutgoingMessage *> *messages = [NSMutableArray new];
    for (NSUInteger i =0; i < count; i++) {
        NSString *text = [self randomText];
        OWSDisappearingMessagesConfiguration *configuration =
            [thread disappearingMessagesConfigurationWithTransaction:initialTransaction];

        uint32_t expiresInSeconds = (configuration.isEnabled ? configuration.durationSeconds : 0);
        TSOutgoingMessage *message = [TSOutgoingMessage outgoingMessageInThread:thread
                                                                    messageBody:text
                                                                   attachmentId:nil
                                                               expiresInSeconds:expiresInSeconds];
        OWSLogInfo(@"resurrectNewOutgoingMessages1 timestamp: %llu.", message.timestamp);
        [messages addObject:message];
    }

    for (TSOutgoingMessage *message in messages) {
        [message anyInsertWithTransaction:initialTransaction];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        OWSLogInfo(@"resurrectNewOutgoingMessages1.2: %zd", count);
        DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
            for (TSOutgoingMessage *message in messages) {
                [message anyRemoveWithTransaction:transaction];
            }
            for (TSOutgoingMessage *message in messages) {
                [message anyInsertWithTransaction:transaction];
            }
        });
    });
}

+ (void)resurrectNewOutgoingMessages2:(NSUInteger)count
                               thread:(TSThread *)thread
                          transaction:(SDSAnyWriteTransaction *)initialTransaction
{
    OWSLogInfo(@"resurrectNewOutgoingMessages2.1: %zd", count);

    NSMutableArray<TSOutgoingMessage *> *messages = [NSMutableArray new];
    for (NSUInteger i =0; i < count; i++) {
        NSString *text = [self randomText];
        OWSDisappearingMessagesConfiguration *configuration =
            [thread disappearingMessagesConfigurationWithTransaction:initialTransaction];

        TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread
                                                                                                  messageBody:text];
        [messageBuilder applyDisappearingMessagesConfiguration:configuration];
        TSOutgoingMessage *message = [messageBuilder buildWithTransaction:initialTransaction];
        OWSLogInfo(@"resurrectNewOutgoingMessages2 timestamp: %llu.", message.timestamp);
        [messages addObject:message];
    }

    for (TSOutgoingMessage *message in messages) {
        [message updateWithFakeMessageState:TSOutgoingMessageStateSending transaction:initialTransaction];
        [message anyInsertWithTransaction:initialTransaction];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        OWSLogInfo(@"resurrectNewOutgoingMessages2.2: %zd", count);
        DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
            for (TSOutgoingMessage *message in messages) {
                [message anyRemoveWithTransaction:transaction];
            }
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            OWSLogInfo(@"resurrectNewOutgoingMessages2.3: %zd", count);
            DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
                for (TSOutgoingMessage *message in messages) {
                    [message anyInsertWithTransaction:transaction];
                }
            });
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

    SignalServiceAddress *_Nullable incomingSenderAddress = [DebugUIMessages anyIncomingSenderAddressForThread:thread];
    if (incomingSenderAddress == nil) {
        OWSFailDebug(@"Missing incomingSenderAddress.");
        return;
    }
    SignalServiceAddress *address = incomingSenderAddress;

    DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
        for (NSNumber *timestamp in timestamps) {
            NSString *randomText = [self randomText];
            {
                // Legit usage of SenderTimestamp to backdate incoming sent messages for Debug
                TSIncomingMessageBuilder *incomingMessageBuilder =
                    [TSIncomingMessageBuilder incomingMessageBuilderWithThread:thread messageBody:randomText];
                incomingMessageBuilder.timestamp = timestamp.unsignedLongLongValue;
                incomingMessageBuilder.authorAddress = address;
                TSIncomingMessage *message = [incomingMessageBuilder build];
                [message anyInsertWithTransaction:transaction];
                [message debugonly_markAsReadNowWithTransaction:transaction];
            }
            {
                // MJK TODO - this might be the one place we actually use senderTimestamp
                TSOutgoingMessageBuilder *messageBuilder =
                    [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread messageBody:randomText];
                messageBuilder.timestamp = timestamp.unsignedLongLongValue;
                TSOutgoingMessage *message = [messageBuilder buildWithTransaction:transaction];
                [message anyInsertWithTransaction:transaction];
                [message updateWithFakeMessageState:TSOutgoingMessageStateSent transaction:transaction];
                [message updateWithSentRecipient:address wasSentByUD:NO transaction:transaction];
                [message updateWithDeliveredRecipient:address
                                    recipientDeviceId:0
                                    deliveryTimestamp:timestamp.unsignedLongLongValue
                                              context:[[PassthroughDeliveryReceiptContext alloc] init]
                                          transaction:transaction];
                [message updateWithReadRecipient:address
                               recipientDeviceId:0
                                   readTimestamp:timestamp.unsignedLongLongValue
                                     transaction:transaction];
            }
        }
    });
}

+ (void)createDisappearingMessagesWhichFailedToStartInThread:(TSThread *)thread
{
    uint64_t now = [NSDate ows_millisecondTimeStamp];
    NSString *messageBody = [NSString stringWithFormat:@"Should disappear 60s after %lu", (unsigned long)now];

    SignalServiceAddress *address = thread.recipientAddressesWithSneakyTransaction.firstObject;
    TSIncomingMessageBuilder *incomingMessageBuilder =
        [TSIncomingMessageBuilder incomingMessageBuilderWithThread:thread messageBody:messageBody];
    incomingMessageBuilder.authorAddress = address;
    incomingMessageBuilder.expiresInSeconds = 60;
    TSIncomingMessage *message = [incomingMessageBuilder build];
    // private setter to avoid starting expire machinery.
    message.read = YES;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [message anyInsertWithTransaction:transaction];
    });
}

+ (void)testLinkificationInThread:(TSThread *)thread
{
    NSArray<NSString *> *strings = @[@"google.com",
                                     @"foo.google.com",
                                     @"https://foo.google.com",
                                     @"https://foo.google.com/some/path.html",
                                     @"http://кц.com",
                                     @"кц.com",
                                     @"http://asĸ.com",
                                     @"кц.рф",
                                     @"кц.рф/some/path",
                                     @"https://кц.рф/some/path",
                                     @"http://foo.кц.рф"];

    DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
        for (NSString *string in strings) {
            // DO NOT log these strings with the debugger attached.
            //        OWSLogInfo(@"%@", string);

            [self createFakeIncomingMessage:thread
                                messageBody:string
                            fakeAssetLoader:nil
                     isAttachmentDownloaded:NO
                              quotedMessage:nil
                                transaction:transaction];

            SignalServiceAddress *member = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+1323555555"];
            [self createRandomGroupWithName:string
                                     member:member
                                    success:^(TSGroupThread *ignore) {
                                        // Do nothing.
                                    }];
        }
    });
}

+ (void)createRandomGroupWithName:(NSString *)groupName
                           member:(SignalServiceAddress *)member
                          success:(void (^)(TSGroupThread *))success
{
    NSArray<SignalServiceAddress *> *members = @[
        member,
        TSAccountManager.localAddress,
    ];
    [GroupManager localCreateNewGroupObjcWithMembers:members
        groupId:nil
        name:groupName
        avatarData:nil
        disappearingMessageToken:DisappearingMessageToken.disabledToken
        newGroupSeed:nil
        shouldSendMessage:YES
        success:^(TSGroupThread *thread) { success(thread); }
        failure:^(NSError *error) { OWSFailDebug(@"Error: %@", error); }];
}

+ (void)testIndicScriptsInThread:(TSThread *)thread
{
    NSArray<NSString *> *strings = @[
        @"\u0C1C\u0C4D\u0C1E\u200C\u0C3E",
        @"\u09B8\u09CD\u09B0\u200C\u09C1",
        @"non-crashing string",
    ];

    DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
        for (NSString *string in strings) {
            // DO NOT log these strings with the debugger attached.
            //        OWSLogInfo(@"%@", string);

            [self createFakeIncomingMessage:thread
                                messageBody:string
                            fakeAssetLoader:nil
                     isAttachmentDownloaded:NO
                              quotedMessage:nil
                                transaction:transaction];

            SignalServiceAddress *member = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+1323555555"];
            [self createRandomGroupWithName:string
                                     member:member
                                    success:^(TSGroupThread *ignore) {
                                        // Do nothing.
                                    }];
        }
    });
}

+ (void)testZalgoTextInThread:(TSThread *)thread
{
    NSArray<NSString *> *strings = @[
        @"Ṱ̴̤̺̣͚͚̭̰̤̮̑̓̀͂͘͡h̵̢̤͔̼̗̦̖̬͌̀͒̀͘i̴̮̤͎͎̝̖̻͓̅̆͆̓̎͘͡ͅŝ̡̡̳͔̓͗̾̀̇͒͘͢͢͡͡ ỉ̛̲̩̫̝͉̀̒͐͋̾͘͢͡͞s̶̨̫̞̜̹͛́̇͑̅̒̊̈ s̵͍̲̗̠̗͈̦̬̉̿͂̏̐͆̾͐͊̾ǫ̶͍̼̝̉͊̉͢͜͞͝ͅͅṁ̵̡̨̬̤̝͔̣̄̍̋͊̿̄͋̈ͅe̪̪̻̱͖͚͈̲̍̃͘͠͝ z̷̢̢̛̩̦̱̺̼͑́̉̾ą͕͎̠̮̹̱̓̔̓̈̈́̅̐͢l̵̨͚̜͉̟̜͉͎̃͆͆͒͑̍̈̚͜͞ğ͔̖̫̞͎͍̒̂́̒̿̽̆͟o̶̢̬͚̘̤̪͇̻̒̋̇̊̏͢͡͡͠ͅ t̡̛̥̦̪̮̅̓̑̈́̉̓̽͛͢͡ȩ̡̩͓͈̩͎͗̔͑̌̓͊͆͝x̫̦͓̤͓̘̝̪͊̆͌͊̽̃̏͒͘͘͢ẗ̶̢̨̛̰̯͕͔́̐͗͌͟͠.̷̩̼̼̩̞̘̪́͗̅͊̎̾̅̏̀̕͟ͅ",
        @"This is some normal text",
    ];

    DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
        for (NSString *string in strings) {
            OWSLogInfo(@"sending zalgo");

            [self createFakeIncomingMessage:thread
                                messageBody:string
                            fakeAssetLoader:nil
                     isAttachmentDownloaded:NO
                              quotedMessage:nil
                                transaction:transaction];


            SignalServiceAddress *member = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+1323555555"];
            [self createRandomGroupWithName:string
                                     member:member
                                    success:^(TSGroupThread *ignore) {
                                        // Do nothing.
                                    }];
        }
    });
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
        NSString *utiType = (NSString *)kUTTypeData;
        const NSUInteger kDataLength = 32;
        _Nullable id<DataSource> dataSource =
            [DataSourceValue dataSourceWithData:[self createRandomNSDataOfSize:kDataLength] utiType:utiType];
        [dataSource setSourceFilename:filename];
        SignalAttachment *attachment = [SignalAttachment attachmentWithDataSource:dataSource dataUTI:utiType];

        OWSAssertDebug(attachment);
        if ([attachment hasError]) {
            OWSLogError(@"attachment[%@]: %@", [attachment sourceFilename], [attachment errorName]);
            OWSLogFlush();
        }
        OWSAssertDebug(![attachment hasError]);
        [self sendAttachment:attachment thread:thread messageBody:nil];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            sendUnsafeFile();
            sendUnsafeFile = nil;
        });
    };
}

+ (void)deleteAllMessagesInThread:(TSThread *)thread
{
    DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
        [thread removeAllThreadInteractionsWithTransaction:transaction];
    });
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

+ (ThreadAssociatedData *)createFakeThreadAssociatedData:(TSThread *)thread
{
    return [[ThreadAssociatedData alloc] initWithThreadUniqueId:thread.uniqueId
                                                     isArchived:NO
                                                 isMarkedUnread:NO
                                            mutedUntilTimestamp:0
                                              audioPlaybackRate:1];
}

+ (TSOutgoingMessage *)createFakeOutgoingMessage:(TSThread *)thread
                                     messageBody:(nullable NSString *)messageBody
                                 fakeAssetLoader:(nullable DebugUIMessagesAssetLoader *)fakeAssetLoader
                                    messageState:(TSOutgoingMessageState)messageState
                                     isDelivered:(BOOL)isDelivered
                                          isRead:(BOOL)isRead
                                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                                    contactShare:(nullable OWSContact *)contactShare
                                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                                  messageSticker:(nullable MessageSticker *)messageSticker
                                     transaction:(SDSAnyWriteTransaction *)transaction
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
                                attachment:attachment
                                  filename:fakeAssetLoader.filename
                              messageState:messageState
                               isDelivered:isDelivered
                                    isRead:isRead
                            isVoiceMessage:attachment.isVoiceMessage
                             quotedMessage:quotedMessage
                              contactShare:contactShare
                               linkPreview:linkPreview
                            messageSticker:messageSticker
                               transaction:transaction];
}

+ (TSOutgoingMessage *)createFakeOutgoingMessage:(TSThread *)thread
                                     messageBody:(nullable NSString *)messageBody
                                      attachment:(nullable TSAttachment *)attachment
                                        filename:(nullable NSString *)filename
                                    messageState:(TSOutgoingMessageState)messageState
                                     isDelivered:(BOOL)isDelivered
                                          isRead:(BOOL)isRead
                                  isVoiceMessage:(BOOL)isVoiceMessage
                                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                                    contactShare:(nullable OWSContact *)contactShare
                                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                                  messageSticker:(nullable MessageSticker *)messageSticker
                                     transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(thread);
    OWSAssertDebug(transaction);
    OWSAssertDebug(messageBody.length > 0 || attachment != nil || contactShare);

    NSMutableArray<NSString *> *attachmentIds = [NSMutableArray new];
    if (attachment != nil) {
        [attachmentIds addObject:attachment.uniqueId];
    }

    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread
                                                                                              messageBody:messageBody];
    messageBuilder.attachmentIds = attachmentIds;
    messageBuilder.isVoiceMessage = isVoiceMessage;
    messageBuilder.quotedMessage = quotedMessage;
    messageBuilder.contactShare = contactShare;
    messageBuilder.linkPreview = linkPreview;
    messageBuilder.messageSticker = messageSticker;
    TSOutgoingMessage *message = [messageBuilder buildWithTransaction:transaction];

    [message anyInsertWithTransaction:transaction];
    [message updateWithFakeMessageState:messageState transaction:transaction];
    [self updateAttachment:attachment albumMessage:message transaction:transaction];
    if (isDelivered) {
        SignalServiceAddress *_Nullable address = [thread recipientAddressesWithTransaction:transaction].lastObject;
        if (address != nil) {
            OWSAssertDebug(address.isValid);
            [message updateWithDeliveredRecipient:address
                                recipientDeviceId:0
                                deliveryTimestamp:[NSDate ows_millisecondTimeStamp]
                                          context:[[PassthroughDeliveryReceiptContext alloc] init]
                                      transaction:transaction];
        }
    }
    if (isRead) {
        SignalServiceAddress *_Nullable address = [thread recipientAddressesWithTransaction:transaction].lastObject;
        if (address != nil) {
            OWSAssertDebug(address.isValid);
            [message updateWithReadRecipient:address
                           recipientDeviceId:0
                               readTimestamp:[NSDate ows_millisecondTimeStamp]
                                 transaction:transaction];
        }
    }
    return message;
}

+ (TSIncomingMessage *)createFakeIncomingMessage:(TSThread *)thread
                                     messageBody:(nullable NSString *)messageBody
                                 fakeAssetLoader:(nullable DebugUIMessagesAssetLoader *)fakeAssetLoader
                          isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                                     transaction:(SDSAnyWriteTransaction *)transaction
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
                                attachment:attachment
                                  filename:fakeAssetLoader.filename
                    isAttachmentDownloaded:isAttachmentDownloaded
                             quotedMessage:quotedMessage
                               transaction:transaction];
}

+ (TSIncomingMessage *)createFakeIncomingMessage:(TSThread *)thread
                                     messageBody:(nullable NSString *)messageBody
                                      attachment:(nullable TSAttachment *)attachment
                                        filename:(nullable NSString *)filename
                          isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                                     transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(thread);
    OWSAssertDebug(transaction);
    OWSAssertDebug(messageBody.length > 0 || attachment != nil);

    NSMutableArray<NSString *> *attachmentIds = [NSMutableArray new];
    if (attachment != nil) {
        [attachmentIds addObject:attachment.uniqueId];
    }

    SignalServiceAddress *_Nullable incomingSenderAddress = [DebugUIMessages anyIncomingSenderAddressForThread:thread];
    SignalServiceAddress *address
        = (incomingSenderAddress != nil ? incomingSenderAddress
                                        : [[SignalServiceAddress alloc] initWithPhoneNumber:@"+19174054215"]);

    TSIncomingMessageBuilder *incomingMessageBuilder =
        [TSIncomingMessageBuilder incomingMessageBuilderWithThread:thread messageBody:messageBody];
    incomingMessageBuilder.authorAddress = address;
    incomingMessageBuilder.attachmentIds = attachmentIds;
    incomingMessageBuilder.quotedMessage = quotedMessage;
    TSIncomingMessage *message = [incomingMessageBuilder build];
    [message anyInsertWithTransaction:transaction];
    [message debugonly_markAsReadNowWithTransaction:transaction];
    [self updateAttachment:attachment albumMessage:message transaction:transaction];

    return message;
}

+ (TSAttachment *)createFakeAttachment:(DebugUIMessagesAssetLoader *)fakeAssetLoader
                isAttachmentDownloaded:(BOOL)isAttachmentDownloaded
                           transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(fakeAssetLoader);
    OWSAssertDebug(fakeAssetLoader.filePath);
    OWSAssertDebug(transaction);

    if (isAttachmentDownloaded) {
        NSError *error;
        id<DataSource> dataSource = [DataSourcePath dataSourceWithFilePath:fakeAssetLoader.filePath
                                                shouldDeleteOnDeallocation:NO
                                                                     error:&error];
        OWSAssertDebug(error == nil);
        NSString *filename = dataSource.sourceFilename;
        // To support "fake missing" attachments, we sometimes lie about the
        // length of the data.
        UInt32 nominalDataLength = (UInt32)MAX((NSUInteger)1, dataSource.dataLength);
        TSAttachmentStream *attachmentStream = [[TSAttachmentStream alloc] initWithContentType:fakeAssetLoader.mimeType
                                                                                     byteCount:nominalDataLength
                                                                                sourceFilename:filename
                                                                                       caption:nil
                                                                                albumMessageId:nil];
        BOOL success = [attachmentStream writeData:dataSource.data error:&error];
        OWSAssertDebug(success && error == nil);
        [attachmentStream anyInsertWithTransaction:transaction];
        return attachmentStream;
    } else {
        UInt32 filesize = 64;
        TSAttachmentPointer *attachmentPointer =
            [[TSAttachmentPointer alloc] initWithServerId:237391539706350548
                                                   cdnKey:@""
                                                cdnNumber:0
                                                      key:[self createRandomNSDataOfSize:filesize]
                                                   digest:nil
                                                byteCount:filesize
                                              contentType:fakeAssetLoader.mimeType
                                           sourceFilename:fakeAssetLoader.filename
                                                  caption:nil
                                           albumMessageId:nil
                                           attachmentType:TSAttachmentTypeDefault
                                                mediaSize:CGSizeZero
                                                 blurHash:nil
                                          uploadTimestamp:0];
        [attachmentPointer setAttachmentPointerStateDebug:TSAttachmentPointerStateFailed];
        [attachmentPointer anyInsertWithTransaction:transaction];
        return attachmentPointer;
    }
}

+ (void)updateAttachment:(nullable TSAttachment *)attachment
            albumMessage:(TSMessage *)albumMessage
             transaction:(SDSAnyWriteTransaction *)transaction
{
    [attachment anyUpdateWithTransaction:transaction
                                   block:^(TSAttachment *latest) {
                                       // There's no public setter for albumMessageId, since it's usually set in the
                                       // initializer. This isn't convenient for the DEBUG UI, so we abuse the
                                       // migrateAlbumMessageId method.
                                       [latest migrateAlbumMessageId:albumMessage.uniqueId];
                                   }];
    if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
        [MediaGalleryManager didInsertAttachmentStream:(TSAttachmentStream *)attachment transaction:transaction];
    }
}

+ (void)sendMediaAlbumInThread:(TSThread *)thread
{
    OWSLogInfo(@"");

    const uint32_t kMinImageCount = 2;
    const uint32_t kMaxImageCount = 10;
    uint32_t imageCount = kMinImageCount + arc4random_uniform(kMaxImageCount - kMinImageCount);
    NSString *_Nullable messageBody = (arc4random_uniform(2) > 0 ? @"This is the media gallery title..." : nil);
    [self sendMediaAlbumInThread:thread imageCount:imageCount messageBody:messageBody];
}

+ (void)sendExemplaryMediaGalleriesInThread:(TSThread *)thread
{
    OWSLogInfo(@"");

    [self sendMediaAlbumInThread:thread imageCount:2 messageBody:nil];
    [self sendMediaAlbumInThread:thread imageCount:3 messageBody:nil];
    [self sendMediaAlbumInThread:thread imageCount:4 messageBody:nil];
    [self sendMediaAlbumInThread:thread imageCount:5 messageBody:nil];
    [self sendMediaAlbumInThread:thread imageCount:6 messageBody:nil];
    [self sendMediaAlbumInThread:thread imageCount:7 messageBody:nil];
    NSString *messageBody = @"This is the media gallery title...";
    [self sendMediaAlbumInThread:thread imageCount:2 messageBody:messageBody];
    [self sendMediaAlbumInThread:thread imageCount:3 messageBody:messageBody];
    [self sendMediaAlbumInThread:thread imageCount:4 messageBody:messageBody];
    [self sendMediaAlbumInThread:thread imageCount:5 messageBody:messageBody];
    [self sendMediaAlbumInThread:thread imageCount:6 messageBody:messageBody];
    [self sendMediaAlbumInThread:thread imageCount:7 messageBody:messageBody];
}

+ (void)sendMediaAlbumInThread:(TSThread *)thread
                    imageCount:(uint32_t)imageCount
                   messageBody:(nullable NSString *)messageBody
              fakeAssetLoaders:(NSArray<DebugUIMessagesAssetLoader *> *)fakeAssetLoaders
{
    OWSAssertDebug(imageCount > 0);
    OWSLogInfo(@"");

    NSMutableArray<SignalAttachment *> *attachments = [NSMutableArray new];
    for (uint32_t i = 0; i < imageCount; i++) {
        DebugUIMessagesAssetLoader *fakeAssetLoader
            = fakeAssetLoaders[arc4random_uniform((uint32_t)fakeAssetLoaders.count)];
        OWSAssertDebug([NSFileManager.defaultManager fileExistsAtPath:fakeAssetLoader.filePath]);

        NSString *fileExtension = fakeAssetLoader.filePath.pathExtension;
        NSString *tempFilePath = [OWSFileSystem temporaryFilePathWithFileExtension:fileExtension];
        NSError *error;
        [NSFileManager.defaultManager copyItemAtPath:fakeAssetLoader.filePath toPath:tempFilePath error:&error];
        OWSAssertDebug(error == nil);

        id<DataSource> dataSource = [DataSourcePath dataSourceWithFilePath:tempFilePath
                                                shouldDeleteOnDeallocation:NO
                                                                     error:&error];
        OWSAssertDebug(error == nil);
        SignalAttachment *attachment =
            [SignalAttachment attachmentWithDataSource:dataSource
                                               dataUTI:[MIMETypeUtil utiTypeForMIMEType:fakeAssetLoader.mimeType]];
        if (arc4random_uniform(2) == 0) {
            attachment.captionText = [self randomText];
        }
        [attachments addObject:attachment];
    }

    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        TSOutgoingMessage *message = [ThreadUtil
                  enqueueMessageWithBody:[[MessageBody alloc] initWithText:messageBody ranges:MessageBodyRanges.empty]
                        mediaAttachments:attachments
                                  thread:thread
                        quotedReplyModel:nil
                        linkPreviewDraft:nil
            persistenceCompletionHandler:nil
                             transaction:transaction];
        OWSLogDebug(@"timestamp: %llu.", message.timestamp);
    }];
}

+ (void)sendMediaAlbumInThread:(TSThread *)thread
                    imageCount:(uint32_t)imageCount
                   messageBody:(nullable NSString *)messageBody
{
    OWSAssertDebug(thread);

    NSArray<DebugUIMessagesAssetLoader *> *fakeAssetLoaders = @[
        [DebugUIMessagesAssetLoader jpegInstance],
        [DebugUIMessagesAssetLoader largePngInstance],
        [DebugUIMessagesAssetLoader tinyPngInstance],
        [DebugUIMessagesAssetLoader gifInstance],
        [DebugUIMessagesAssetLoader mp4Instance],
        [DebugUIMessagesAssetLoader mediumFilesizePngInstance],
    ];
    [DebugUIMessagesAssetLoader prepareAssetLoaders:fakeAssetLoaders
        success:^{
            [self sendMediaAlbumInThread:thread
                              imageCount:imageCount
                             messageBody:messageBody
                        fakeAssetLoaders:fakeAssetLoaders];
        }
        failure:^{
            OWSLogError(@"Could not prepare fake asset loaders.");
        }];
}

+ (void)requestGroupInfoForGroupThread:(TSGroupThread *)groupThread
{
    DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *_Nonnull transaction) {
        for (SignalServiceAddress *address in groupThread.groupModel.groupMembers) {
            TSThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:address transaction:transaction];
            OWSLogInfo(@"Requesting group info for group thread from: %@", address);
            OWSGroupInfoRequestMessage *groupInfoRequestMessage =
                [[OWSGroupInfoRequestMessage alloc] initWithThread:thread
                                                           groupId:groupThread.groupModel.groupId
                                                       transaction:transaction];
            [self.messageSenderJobQueue addMessage:groupInfoRequestMessage.asPreparer transaction:transaction];
        }
    });
}

@end

NS_ASSUME_NONNULL_END

#endif
