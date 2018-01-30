//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DebugUIMessages.h"
#import "DebugUIContacts.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <AFNetworking/AFNetworking.h>
#import <AxolotlKit/PreKeyBundle.h>
#import <Curve25519Kit/Randomness.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/OWSBatchMessageProcessor.h>
#import <SignalServiceKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSSyncGroupsRequestMessage.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/SecurityUtils.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSDatabaseView.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSStorageManager+SessionStore.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIMessages

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Messages";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    OWSAssert(thread);

    NSMutableArray<OWSTableItem *> *items = [@[
        [OWSTableItem itemWithTitle:@"Perform 100 random actions"
                        actionBlock:^{
                            [DebugUIMessages performRandomActions:100 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Perform 1,000 random actions"
                        actionBlock:^{
                            [DebugUIMessages performRandomActions:1000 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 10 messages (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendTextMessages:10 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 100 messages (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendTextMessages:100 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 1,000 messages (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendTextMessages:1000 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 3,000 messages (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendTextMessages:3000 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 10 tiny text messages (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendTinyTextMessages:10 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 100 tiny text messages (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendTinyTextMessages:100 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 10 tiny attachments"
                        actionBlock:^{
                            [DebugUIMessages sendTinyAttachments:10 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 100 tiny attachments"
                        actionBlock:^{
                            [DebugUIMessages sendTinyAttachments:100 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 1,000 tiny attachments"
                        actionBlock:^{
                            [DebugUIMessages sendTinyAttachments:1000 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 3,000 tiny attachments"
                        actionBlock:^{
                            [DebugUIMessages sendTinyAttachments:3000 thread:thread];
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
        [OWSTableItem itemWithTitle:@"Create 1 fake unread messages"
                        actionBlock:^{
                            [DebugUIMessages createFakeUnreadMessages:1 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Create 10 fake unread messages"
                        actionBlock:^{
                            [DebugUIMessages createFakeUnreadMessages:10 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Create 10 fake large attachments"
                        actionBlock:^{
                            [DebugUIMessages createFakeLargeOutgoingAttachments:10 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Create 100 fake large attachments"
                        actionBlock:^{
                            [DebugUIMessages createFakeLargeOutgoingAttachments:100 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Create 1k fake large attachments"
                        actionBlock:^{
                            [DebugUIMessages createFakeLargeOutgoingAttachments:1000 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Create 10k fake large attachments"
                        actionBlock:^{
                            [DebugUIMessages createFakeLargeOutgoingAttachments:10000 thread:thread];
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
        [OWSTableItem itemWithTitle:@"Send 1 Random GIF (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendRandomGifs:1 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 10 Random GIF (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendRandomGifs:10 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 100 Random GIF (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendRandomGifs:100 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 1 Random JPEG (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendRandomJpegs:1 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 10 Random JPEG (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendRandomJpegs:10 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 100 Random JPEG (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendRandomJpegs:100 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 1 Random Mp3 (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendRandomMp3s:1 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 10 Random Mp3 (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendRandomMp3s:10 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 100 Random Mp3 (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendRandomMp3s:100 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 1 Random Mp4 (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendRandomMp4s:1 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 10 Random Mp4 (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendRandomMp4s:10 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 100 Random Mp4 (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendRandomMp4s:100 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 10 media (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendMediaAttachments:10 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 100 media (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendMediaAttachments:100 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Send 1,000 media (1/sec.)"
                        actionBlock:^{
                            [DebugUIMessages sendMediaAttachments:1000 thread:thread];
                        }],
        [OWSTableItem itemWithTitle:@"Create all system messages"
                        actionBlock:^{
                            [DebugUIMessages createSystemMessagesInThread:thread];
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
                  DDLogInfo(@"%@ Requesting bogus group info for thread: %@", self.logTag, thread);
                  OWSSyncGroupsRequestMessage *syncGroupsRequestMessage =
                      [[OWSSyncGroupsRequestMessage alloc] initWithThread:thread
                                                                  groupId:[Randomness generateRandomBytes:16]];
                  [[Environment current].messageSender enqueueMessage:syncGroupsRequestMessage
                      success:^{
                          DDLogWarn(@"%@ Successfully sent Request Group Info message.", self.logTag);
                      }
                      failure:^(NSError *error) {
                          DDLogError(
                              @"%@ Failed to send Request Group Info message with error: %@", self.logTag, error);
                      }];
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
    ] mutableCopy];
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
    return [OWSTableSection sectionWithTitle:self.name items:items];
}

+ (void)sendMessages:(int)counter toAllMembersOfGroup:(TSGroupThread *)groupThread
{
    for (NSString *recipientId in groupThread.groupModel.groupMemberIds) {
        TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:recipientId];
        [DebugUIMessages sendTextMessages:counter thread:contactThread];
    }
}

+ (void)sendTextMessageInThread:(TSThread *)thread counter:(int)counter
{
    DDLogInfo(@"%@ sendTextMessageInThread: %d", self.logTag, counter);
    [DDLog flushLog];

    NSString *randomText = [self randomText];
    NSString *text = [[[@(counter) description] stringByAppendingString:@" "] stringByAppendingString:randomText];
    OWSMessageSender *messageSender = [Environment current].messageSender;
    TSOutgoingMessage *message = [ThreadUtil sendMessageWithText:text inThread:thread messageSender:messageSender];
    DDLogError(@"%@ sendTextMessageInThread timestamp: %llu.", self.logTag, message.timestamp);
}

+ (void)sendTextMessages:(int)counter thread:(TSThread *)thread
{
    if (counter < 1) {
        return;
    }
    [self sendTextMessageInThread:thread counter:counter];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self sendTextMessages:counter - 1 thread:thread];
    });
}

+ (void)sendTinyTextMessageInThread:(TSThread *)thread counter:(int)counter
{
    NSString *randomText = [[self randomText] substringToIndex:arc4random_uniform(4)];
    NSString *text = [[[@(counter) description] stringByAppendingString:@" "] stringByAppendingString:randomText];
    OWSMessageSender *messageSender = [Environment current].messageSender;
    [ThreadUtil sendMessageWithText:text inThread:thread messageSender:messageSender];
}

+ (void)sendTinyTextMessages:(int)counter thread:(TSThread *)thread
{
    if (counter < 1) {
        return;
    }
    [self sendTinyTextMessageInThread:thread counter:counter];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self sendTinyTextMessages:counter - 1 thread:thread];
    });
}

+ (void)ensureRandomFileWithURL:(NSString *)url
                       filename:(NSString *)filename
                        success:(nullable void (^)(NSString *filePath))success
                        failure:(nullable void (^)(void))failure
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *documentDirectoryURL =
        [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSString *randomFilesDirectoryPath =
        [[documentDirectoryURL path] stringByAppendingPathComponent:@"cached_random_files"];
    [OWSFileSystem ensureDirectoryExists:randomFilesDirectoryPath];
    NSString *filePath = [randomFilesDirectoryPath stringByAppendingPathComponent:filename];
    if ([fileManager fileExistsAtPath:filePath]) {
        success(filePath);
    } else {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        AFHTTPSessionManager *sessionManager =
            [[AFHTTPSessionManager alloc] initWithSessionConfiguration:configuration];
        sessionManager.responseSerializer = [AFHTTPResponseSerializer serializer];
        OWSAssert(sessionManager.responseSerializer);
        [sessionManager GET:url
            parameters:nil
            progress:nil
            success:^(NSURLSessionDataTask *task, NSData *_Nullable responseObject) {
                if ([responseObject writeToFile:filePath atomically:YES]) {
                    success(filePath);
                } else {
                    OWSFail(@"Error write url response [%@]: %@", url, filePath);
                    failure();
                }
            }
            failure:^(NSURLSessionDataTask *_Nullable task, NSError *requestError) {
                OWSFail(@"Error downloading url[%@]: %@", url, requestError);
                failure();
            }];
    }
}

+ (void)sendAttachment:(NSString *)filePath
                thread:(TSThread *)thread
               success:(nullable void (^)(void))success
               failure:(nullable void (^)(void))failure
{
    OWSAssert(filePath);
    OWSAssert(thread);

    OWSMessageSender *messageSender = [Environment current].messageSender;
    NSString *filename = [filePath lastPathComponent];
    NSString *utiType = [MIMETypeUtil utiTypeForFileExtension:filename.pathExtension];
    DataSource *_Nullable dataSource = [DataSourcePath dataSourceWithFilePath:filePath];
    [dataSource setSourceFilename:filename];
    SignalAttachment *attachment =
        [SignalAttachment attachmentWithDataSource:dataSource dataUTI:utiType imageQuality:TSImageQualityOriginal];
    if (arc4random_uniform(100) > 50) {
        attachment.captionText = [self randomCaptionText];
    }

    OWSAssert(attachment);
    if ([attachment hasError]) {
        DDLogError(@"attachment[%@]: %@", [attachment sourceFilename], [attachment errorName]);
        [DDLog flushLog];
    }
    OWSAssert(![attachment hasError]);
    [ThreadUtil sendMessageWithAttachment:attachment inThread:thread messageSender:messageSender completion:nil];
    success();
}

+ (void)ensureRandomGifWithSuccess:(nullable void (^)(NSString *filePath))success
                           failure:(nullable void (^)(void))failure
{
    [self ensureRandomFileWithURL:@"https://s3.amazonaws.com/ows-data/example_attachment_media/random-gif.gif"
                         filename:@"random-gif.gif"
                          success:success
                          failure:failure];
}

+ (void)sendRandomGifInThread:(TSThread *)thread
                      success:(nullable void (^)(void))success
                      failure:(nullable void (^)(void))failure
{
    [self ensureRandomGifWithSuccess:^(NSString *filePath) {
        [self sendAttachment:filePath thread:thread success:success failure:failure];
    }
                             failure:failure];
}

+ (void)sendRandomGifs:(int)count thread:(TSThread *)thread
{
    OWSAssert(count > 0);
    [self ensureRandomGifWithSuccess:^(NSString *filePath) {
        [self
            sendAttachment:filePath
                    thread:thread
                   success:^{
                       if (count <= 1) {
                           return;
                       }
                       dispatch_after(
                           dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                               [self sendRandomGifs:count - 1 thread:thread];
                           });
                   }
                   failure:^{
                   }];
    }
                             failure:^{
                             }];
}

+ (void)ensureRandomJpegWithSuccess:(nullable void (^)(NSString *filePath))success
                            failure:(nullable void (^)(void))failure
{
    [self ensureRandomFileWithURL:@"https://s3.amazonaws.com/ows-data/example_attachment_media/random-jpg.JPG"
                         filename:@"random-jpg.jpg"
                          success:success
                          failure:failure];
}

+ (void)sendRandomJpegInThread:(TSThread *)thread
                       success:(nullable void (^)(void))success
                       failure:(nullable void (^)(void))failure
{
    [self ensureRandomJpegWithSuccess:^(NSString *filePath) {
        [self sendAttachment:filePath thread:thread success:success failure:failure];
    }
                              failure:failure];
}

+ (void)sendRandomJpegs:(int)count thread:(TSThread *)thread
{
    OWSAssert(count > 0);
    [self ensureRandomJpegWithSuccess:^(NSString *filePath) {
        [self
            sendAttachment:filePath
                    thread:thread
                   success:^{
                       if (count <= 1) {
                           return;
                       }
                       dispatch_after(
                           dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                               [self sendRandomJpegs:count - 1 thread:thread];
                           });
                   }
                   failure:^{
                   }];
    }
                              failure:^{
                              }];
}

+ (void)ensureRandomMp3WithSuccess:(nullable void (^)(NSString *filePath))success
                           failure:(nullable void (^)(void))failure
{
    [self ensureRandomFileWithURL:@"https://s3.amazonaws.com/ows-data/example_attachment_media/random-mp3.mp3"
                         filename:@"random-mp3.mp3"
                          success:success
                          failure:failure];
}

+ (void)sendRandomMp3InThread:(TSThread *)thread
                      success:(nullable void (^)(void))success
                      failure:(nullable void (^)(void))failure
{
    [self ensureRandomMp3WithSuccess:^(NSString *filePath) {
        [self sendAttachment:filePath thread:thread success:success failure:failure];
    }
                             failure:failure];
}

+ (void)sendRandomMp3s:(int)count thread:(TSThread *)thread
{
    OWSAssert(count > 0);
    [self ensureRandomMp3WithSuccess:^(NSString *filePath) {
        [self
            sendAttachment:filePath
                    thread:thread
                   success:^{
                       if (count <= 1) {
                           return;
                       }
                       dispatch_after(
                           dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                               [self sendRandomMp3s:count - 1 thread:thread];
                           });
                   }
                   failure:^{
                   }];
    }
                             failure:^{
                             }];
}

+ (void)ensureRandomMp4WithSuccess:(nullable void (^)(NSString *filePath))success
                           failure:(nullable void (^)(void))failure
{
    [self ensureRandomFileWithURL:@"https://s3.amazonaws.com/ows-data/example_attachment_media/random-mp4.mp4"
                         filename:@"random-mp4.mp4"
                          success:success
                          failure:failure];
}

+ (void)sendRandomMp4InThread:(TSThread *)thread
                      success:(nullable void (^)(void))success
                      failure:(nullable void (^)(void))failure
{
    [self ensureRandomMp4WithSuccess:^(NSString *filePath) {
        [self sendAttachment:filePath thread:thread success:success failure:failure];
    }
                             failure:failure];
}

+ (void)sendRandomMp4s:(int)count thread:(TSThread *)thread
{
    OWSAssert(count > 0);
    [self ensureRandomMp4WithSuccess:^(NSString *filePath) {
        [self
            sendAttachment:filePath
                    thread:thread
                   success:^{
                       if (count <= 1) {
                           return;
                       }
                       dispatch_after(
                           dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                               [self sendRandomMp4s:count - 1 thread:thread];
                           });
                   }
                   failure:^{
                   }];
    }
                             failure:^{
                             }];
}

+ (void)sendMediaAttachments:(int)count thread:(TSThread *)thread
{
    OWSAssert(count > 0);

    void (^success)(void) = ^{
        if (count <= 1) {
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self sendMediaAttachments:count - 1 thread:thread];
        });
    };

    switch (arc4random_uniform(4)) {
        case 0: {
            [self ensureRandomGifWithSuccess:^(NSString *filePath) {
                [self sendAttachment:filePath
                              thread:thread
                             success:success
                             failure:^{
                             }];
            }
                                     failure:^{
                                     }];
            break;
        }
        case 1: {
            [self ensureRandomJpegWithSuccess:^(NSString *filePath) {
                [self sendAttachment:filePath
                              thread:thread
                             success:success
                             failure:^{
                             }];
            }
                                      failure:^{
                                      }];
            break;
        }
        case 2: {
            [self ensureRandomMp3WithSuccess:^(NSString *filePath) {
                [self sendAttachment:filePath
                              thread:thread
                             success:success
                             failure:^{
                             }];
            }
                                     failure:^{
                                     }];
            break;
        }
        case 3: {
            [self ensureRandomMp4WithSuccess:^(NSString *filePath) {
                [self sendAttachment:filePath
                              thread:thread
                             success:success
                             failure:^{
                             }];
            }
                                     failure:^{
                                     }];
            break;
        }
    }
}

+ (void)sendOversizeTextMessage:(TSThread *)thread
{
    OWSMessageSender *messageSender = [Environment current].messageSender;
    NSMutableString *message = [NSMutableString new];
    for (int i = 0; i < 32; i++) {
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

    DataSource *_Nullable dataSource = [DataSourceValue dataSourceWithOversizeText:message];
    SignalAttachment *attachment =
        [SignalAttachment attachmentWithDataSource:dataSource dataUTI:kOversizeTextAttachmentUTI];
    [ThreadUtil sendMessageWithAttachment:attachment inThread:thread messageSender:messageSender completion:nil];
}

+ (NSData *)createRandomNSDataOfSize:(size_t)size
{
    OWSAssert(size % 4 == 0);

    NSMutableData *data = [NSMutableData dataWithCapacity:size];
    for (size_t i = 0; i < size / 4; ++i) {
        u_int32_t randomBits = arc4random();
        [data appendBytes:(void *)&randomBits length:4];
    }
    return data;
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
    OWSMessageSender *messageSender = [Environment current].messageSender;
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
                            messageSender:messageSender
                             ignoreErrors:YES
                               completion:nil];
}
+ (OWSSignalServiceProtosEnvelope *)createEnvelopeForThread:(TSThread *)thread
{
    OWSAssert(thread);

    OWSSignalServiceProtosEnvelopeBuilder *builder = [OWSSignalServiceProtosEnvelopeBuilder new];

    if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *gThread = (TSGroupThread *)thread;
        [builder setSource:gThread.groupModel.groupMemberIds[0]];
    } else if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        [builder setSource:contactThread.contactIdentifier];
    }

    return [builder build];
}

+ (NSArray<TSInteraction *> *)unsavedSystemMessagesInThread:(TSThread *)thread
{
    OWSAssert(thread);

    NSMutableArray<TSInteraction *> *result = [NSMutableArray new];

    [TSStorageManager.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

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
                                                       callType:RPRecentCallTypeMissed
                                                       inThread:contactThread]];
            [result addObject:[[TSCall alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                 withCallNumber:@"+19174054215"
                                                       callType:RPRecentCallTypeMissedBecauseOfChangedIdentity
                                                       inThread:contactThread]];
            [result addObject:[[TSCall alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                 withCallNumber:@"+19174054215"
                                                       callType:RPRecentCallTypeOutgoingIncomplete
                                                       inThread:contactThread]];
            [result addObject:[[TSCall alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                 withCallNumber:@"+19174054215"
                                                       callType:RPRecentCallTypeIncomingIncomplete
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
                                  createdByRemoteName:@"Alice"]];
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
                                  createdByRemoteName:@"Alice"]];
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
                                  createdByRemoteName:@"Alice"]];
        }

        [result addObject:[TSInfoMessage userNotRegisteredMessageInThread:thread]];

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
        [result addObject:[TSInvalidIdentityKeyReceivingErrorMessage
                              untrustedKeyWithEnvelope:[self createEnvelopeForThread:thread]
                                       withTransaction:transaction]];
        [result addObject:[TSErrorMessage corruptedMessageWithEnvelope:[self createEnvelopeForThread:thread]
                                                       withTransaction:transaction]];

        [result addObject:[[TSErrorMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                           inThread:thread
                                                  failedMessageType:TSErrorMessageNonBlockingIdentityChange
                                                        recipientId:@"+19174054215"]];

    }];

    return result;
}

+ (void)createSystemMessagesInThread:(TSThread *)thread
{
    OWSAssert(thread);

    NSArray<TSInteraction *> *messages = [self unsavedSystemMessagesInThread:thread];
    [TSStorageManager.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (TSInteraction *message in messages) {
            [message saveWithTransaction:transaction];
        }
    }];
}

+ (void)createSystemMessageInThread:(TSThread *)thread
{
    OWSAssert(thread);

    NSArray<TSInteraction *> *messages = [self unsavedSystemMessagesInThread:thread];
    TSInteraction *message = messages[(NSUInteger)arc4random_uniform((uint32_t)messages.count)];
    [TSStorageManager.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [message saveWithTransaction:transaction];
    }];
}

+ (void)sendTextAndSystemMessages:(int)counter thread:(TSThread *)thread
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

+ (void)createFakeUnreadMessages:(int)counter thread:(TSThread *)thread
{
    [TSStorageManager.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (int i = 0; i < counter; i++) {
            NSString *randomText = [self randomText];
            TSIncomingMessage *message = [[TSIncomingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                             inThread:thread
                                                                             authorId:@"+19174054215"
                                                                       sourceDeviceId:0
                                                                          messageBody:randomText];
            [message saveWithTransaction:transaction];
        }
    }];
}

+ (void)createFakeThreads:(NSUInteger)threadCount withFakeMessages:(NSUInteger)messageCount
{
    [DebugUIContacts
        createRandomContacts:threadCount
              contactHandler:^(CNContact *_Nonnull contact, NSUInteger idx, BOOL *_Nonnull stop) {
                  NSString *phoneNumberText = contact.phoneNumbers.firstObject.value.stringValue;
                  OWSAssert(phoneNumberText);
                  PhoneNumber *phoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumberText];
                  OWSAssert(phoneNumber);
                  OWSAssert(phoneNumber.toE164);

                  TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:phoneNumber.toE164];
                  [self sendFakeMessages:messageCount thread:contactThread];
                  DDLogError(@"Create fake thread: %@, interactions: %zd",
                      phoneNumber.toE164,
                      contactThread.numberOfInteractions);
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
        [TSStorageManager.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [self sendFakeMessages:counter thread:thread isTextOnly:isTextOnly transaction:transaction];
        }];
    } else {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSUInteger remainder = counter;
            while (remainder > 0) {
                NSUInteger batchSize = MIN(kMaxBatchSize, remainder);
                [TSStorageManager.dbReadWriteConnection
                    readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                        [self sendFakeMessages:batchSize thread:thread isTextOnly:isTextOnly transaction:transaction];
                    }];
                remainder -= batchSize;
                DDLogInfo(@"%@ sendFakeMessages %zd / %zd", self.logTag, counter - remainder, counter);
            }
        });
    }
}

+ (void)sendFakeMessages:(NSUInteger)counter
                  thread:(TSThread *)thread
              isTextOnly:(BOOL)isTextOnly
             transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    DDLogInfo(@"%@ sendFakeMessages: %zd", self.logTag, counter);

    for (NSUInteger i = 0; i < counter; i++) {
        NSString *randomText = [self randomText];
        switch (arc4random_uniform(isTextOnly ? 2 : 4)) {
            case 0: {
                TSIncomingMessage *message =
                    [[TSIncomingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                        inThread:thread
                                                        authorId:@"+19174054215"
                                                  sourceDeviceId:0
                                                     messageBody:randomText];
                [message markAsReadWithTransaction:transaction sendReadReceipt:NO updateExpiration:NO];
                break;
            }
            case 1: {
                TSOutgoingMessage *message =
                    [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                        inThread:thread
                                                     messageBody:randomText];
                [message saveWithTransaction:transaction];
                [message updateWithMessageState:TSOutgoingMessageStateUnsent transaction:transaction];
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
                                                            relay:@""
                                                   sourceFilename:@"test.mp3"
                                                   attachmentType:TSAttachmentTypeDefault];
                pointer.state = TSAttachmentPointerStateFailed;
                [pointer saveWithTransaction:transaction];
                TSIncomingMessage *message =
                    [[TSIncomingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                        inThread:thread
                                                        authorId:@"+19174054215"
                                                  sourceDeviceId:0
                                                     messageBody:nil
                                                   attachmentIds:@[
                                                       pointer.uniqueId,
                                                   ]
                                                expiresInSeconds:0];
                [message markAsReadWithTransaction:transaction sendReadReceipt:NO updateExpiration:NO];
                break;
            }
            case 3: {
                TSOutgoingMessage *message =
                    [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                        inThread:thread
                                                     messageBody:nil
                                                  isVoiceMessage:NO
                                                expiresInSeconds:0];

                NSString *filename = @"test.mp3";
                UInt32 filesize = 16;

                TSAttachmentStream *attachmentStream = [[TSAttachmentStream alloc] initWithContentType:@"audio/mp3"
                                                                                             byteCount:filesize
                                                                                        sourceFilename:filename];

                NSError *error;
                BOOL success = [attachmentStream writeData:[self createRandomNSDataOfSize:filesize] error:&error];
                OWSAssert(success && !error);

                [attachmentStream saveWithTransaction:transaction];
                [message.attachmentIds addObject:attachmentStream.uniqueId];
                if (filename) {
                    message.attachmentFilenameMap[attachmentStream.uniqueId] = filename;
                }
                [message saveWithTransaction:transaction];
                [message updateWithMessageState:TSOutgoingMessageStateUnsent transaction:transaction];
                break;
            }
        }
    }
}

+ (void)createFakeLargeOutgoingAttachments:(int)counter thread:(TSThread *)thread
{
    if (counter < 1) {
        return;
    }

    [TSStorageManager.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                         inThread:thread
                                                                      messageBody:nil
                                                                   isVoiceMessage:NO
                                                                 expiresInSeconds:0];
        DDLogError(@"%@ sendFakeMessages outgoing attachment timestamp: %llu.", self.logTag, message.timestamp);

        NSString *filename = @"test.mp3";
        UInt32 filesize = 8 * 1024 * 1024;

        TSAttachmentStream *attachmentStream =
            [[TSAttachmentStream alloc] initWithContentType:@"audio/mp3" byteCount:filesize sourceFilename:filename];

        NSError *error;
        BOOL success = [attachmentStream writeData:[self createRandomNSDataOfSize:filesize] error:&error];
        OWSAssert(success && !error);

        [attachmentStream saveWithTransaction:transaction];
        [message.attachmentIds addObject:attachmentStream.uniqueId];
        if (filename) {
            message.attachmentFilenameMap[attachmentStream.uniqueId] = filename;
        }
        [message updateWithMessageState:TSOutgoingMessageStateUnsent transaction:transaction];
        [message saveWithTransaction:transaction];
    }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self createFakeLargeOutgoingAttachments:counter - 1 thread:thread];
    });
}

+ (void)sendTinyAttachments:(int)counter thread:(TSThread *)thread
{
    if (counter < 1) {
        return;
    }

    NSArray<NSString *> *utis = @[
        (NSString *)kUTTypePDF,
        (NSString *)kUTTypeMP3,
        (NSString *)kUTTypeGIF,
        (NSString *)kUTTypeMPEG4,
        (NSString *)kUTTypeJPEG,
    ];
    NSString *uti = utis[(NSUInteger)arc4random_uniform((uint32_t)utis.count)];
    [self sendRandomAttachment:thread uti:uti length:16];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self sendTinyAttachments:counter - 1 thread:thread];
    });
}

+ (void)createNewGroups:(int)counter recipientId:(NSString *)recipientId
{
    if (counter < 1) {
        return;
    }

    NSString *groupName = [NSUUID UUID].UUIDString;
    NSMutableArray<NSString *> *recipientIds = [@[
        recipientId,
        [TSAccountManager localNumber],
    ] mutableCopy];
    NSData *groupId = [SecurityUtils generateRandomBytes:16];
    TSGroupModel *groupModel =
        [[TSGroupModel alloc] initWithTitle:groupName memberIds:recipientIds image:nil groupId:groupId];

    __block TSGroupThread *thread;
    [TSStorageManager.dbReadWriteConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            thread = [TSGroupThread getOrCreateThreadWithGroupModel:groupModel transaction:transaction];
        }];
    OWSAssert(thread);

    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                     inThread:thread
                                                             groupMetaMessage:TSGroupMessageNew];
    [message updateWithCustomMessage:NSLocalizedString(@"GROUP_CREATED", nil)];

    OWSMessageSender *messageSender = [Environment current].messageSender;
    void (^completion)(void) = ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [ThreadUtil sendMessageWithText:[@(counter) description] inThread:thread messageSender:messageSender];
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

+ (void)injectFakeIncomingMessages:(int)counter thread:(TSThread *)thread
{
    // Wait 5 seconds so debug user has time to navigate to another
    // view before message processing occurs.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.f * NSEC_PER_SEC)),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        ^{
            for (int i = 0; i < counter; i++) {
                [self injectIncomingMessageInThread:thread counter:counter - i];
            }
        });
}

+ (void)injectIncomingMessageInThread:(TSThread *)thread counter:(int)counter
{
    OWSAssert(thread);

    DDLogInfo(@"%@ injectIncomingMessageInThread: %d", self.logTag, counter);

    NSString *randomText = [self randomText];
    NSString *text = [[[@(counter) description] stringByAppendingString:@" "] stringByAppendingString:randomText];

    OWSSignalServiceProtosDataMessageBuilder *dataMessageBuilder = [OWSSignalServiceProtosDataMessageBuilder new];
    [dataMessageBuilder setBody:text];

    if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        OWSSignalServiceProtosGroupContextBuilder *groupBuilder = [OWSSignalServiceProtosGroupContextBuilder new];
        [groupBuilder setType:OWSSignalServiceProtosGroupContextTypeDeliver];
        [groupBuilder setId:groupThread.groupModel.groupId];
        [dataMessageBuilder setGroup:groupBuilder.build];
    }

    OWSSignalServiceProtosContentBuilder *payloadBuilder = [OWSSignalServiceProtosContentBuilder new];
    [payloadBuilder setDataMessage:dataMessageBuilder.build];
    NSData *plaintextData = [payloadBuilder build].data;

    // Try to use an arbitrary member of the current thread that isn't
    // ourselves as the sender.
    NSString *_Nullable recipientId = [[thread recipientIdentifiers] firstObject];
    // This might be an "empty" group with no other members.  If so, use a fake
    // sender id.
    if (!recipientId) {
        recipientId = @"+12345678901";
    }

    OWSSignalServiceProtosEnvelopeBuilder *envelopeBuilder = [OWSSignalServiceProtosEnvelopeBuilder new];
    [envelopeBuilder setType:OWSSignalServiceProtosEnvelopeTypeCiphertext];
    [envelopeBuilder setSource:recipientId];
    [envelopeBuilder setSourceDevice:1];
    [envelopeBuilder setTimestamp:[NSDate ows_millisecondTimeStamp]];
    [envelopeBuilder setContent:plaintextData];

    NSData *envelopeData = [envelopeBuilder build].data;
    OWSAssert(envelopeData);

    [TSStorageManager.protocolStoreDBConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [[OWSBatchMessageProcessor sharedInstance] enqueueEnvelopeData:envelopeData
                                                         plaintextData:plaintextData
                                                           transaction:transaction];
    }];
}

+ (void)performRandomActions:(int)counter thread:(TSThread *)thread
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

+ (void)performRandomActionInThread:(TSThread *)thread
                            counter:(int)counter
{
    typedef void (^ActionBlock)(YapDatabaseReadWriteTransaction *transaction);
    NSArray<ActionBlock> *actionBlocks = @[
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
    [TSStorageManager.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        int actionCount = 1 + (int)arc4random_uniform(3);
        for (int actionIdx = 0; actionIdx < actionCount; actionIdx++) {
            ActionBlock actionBlock = actionBlocks[(NSUInteger)arc4random_uniform((uint32_t)actionBlocks.count)];
            actionBlock(transaction);
        }
    }];
}

+ (void)deleteRandomMessages:(NSUInteger)count
                      thread:(TSThread *)thread
                 transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    DDLogInfo(@"%@ deleteRandomMessages: %zd", self.logTag, count);

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
        OWSAssert(interaction);
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
    DDLogInfo(@"%@ deleteLastMessages", self.logTag);

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
        OWSAssert(interaction);
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
    DDLogInfo(@"%@ deleteRandomRecentMessages: %zd", self.logTag, count);

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
        OWSAssert(interaction);
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
    DDLogInfo(@"%@ insertAndDeleteNewOutgoingMessages: %zd", self.logTag, count);

    NSMutableArray<TSOutgoingMessage *> *messages = [NSMutableArray new];
    for (NSUInteger i =0; i < count; i++) {
        NSString *text = [self randomText];
        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:thread.uniqueId transaction:transaction];
        TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                            inThread:thread
                                         messageBody:text
                                       attachmentIds:[NSMutableArray new]
                                    expiresInSeconds:(configuration.isEnabled ? configuration.durationSeconds : 0)];
        DDLogError(@"%@ insertAndDeleteNewOutgoingMessages timestamp: %llu.", self.logTag, message.timestamp);
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
    DDLogInfo(@"%@ resurrectNewOutgoingMessages1.1: %zd", self.logTag, count);

    NSMutableArray<TSOutgoingMessage *> *messages = [NSMutableArray new];
    for (NSUInteger i =0; i < count; i++) {
        NSString *text = [self randomText];
        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:thread.uniqueId
                                                              transaction:initialTransaction];
        TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                            inThread:thread
                                         messageBody:text
                                       attachmentIds:[NSMutableArray new]
                                    expiresInSeconds:(configuration.isEnabled ? configuration.durationSeconds : 0)];
        DDLogError(@"%@ resurrectNewOutgoingMessages1 timestamp: %llu.", self.logTag, message.timestamp);
        [messages addObject:message];
    }

    for (TSOutgoingMessage *message in messages) {
        [message saveWithTransaction:initialTransaction];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DDLogInfo(@"%@ resurrectNewOutgoingMessages1.2: %zd", self.logTag, count);
        [TSStorageManager.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
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
    DDLogInfo(@"%@ resurrectNewOutgoingMessages2.1: %zd", self.logTag, count);

    NSMutableArray<TSOutgoingMessage *> *messages = [NSMutableArray new];
    for (NSUInteger i =0; i < count; i++) {
        NSString *text = [self randomText];
        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:thread.uniqueId
                                                              transaction:initialTransaction];
        TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                            inThread:thread
                                         messageBody:text
                                       attachmentIds:[NSMutableArray new]
                                    expiresInSeconds:(configuration.isEnabled ? configuration.durationSeconds : 0)];
        DDLogError(@"%@ resurrectNewOutgoingMessages2 timestamp: %llu.", self.logTag, message.timestamp);
        [messages addObject:message];
    }

    for (TSOutgoingMessage *message in messages) {
        [message updateWithMessageState:TSOutgoingMessageStateAttemptingOut transaction:initialTransaction];
        [message saveWithTransaction:initialTransaction];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DDLogInfo(@"%@ resurrectNewOutgoingMessages2.2: %zd", self.logTag, count);
        [TSStorageManager.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            for (TSOutgoingMessage *message in messages) {
                [message removeWithTransaction:transaction];
            }
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DDLogInfo(@"%@ resurrectNewOutgoingMessages2.3: %zd", self.logTag, count);
            [TSStorageManager.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                for (TSOutgoingMessage *message in messages) {
                    [message saveWithTransaction:transaction];
                }
            }];
        });
    });
}

@end

NS_ASSUME_NONNULL_END
