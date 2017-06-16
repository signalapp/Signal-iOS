//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUIMessages.h"
#import "Environment.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <AFNetworking/AFNetworking.h>
#import <AxolotlKit/PreKeyBundle.h>
#import <SignalServiceKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSStorageManager+SessionStore.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIMessages

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

+ (OWSTableSection *)sectionForThread:(TSThread *)thread
{
    OWSAssert(thread);

    return [OWSTableSection
        sectionWithTitle:@"Messages"
                   items:@[
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
                       [OWSTableItem itemWithTitle:@"Send fake 10 messages"
                                       actionBlock:^{
                                           [DebugUIMessages sendFakeMessages:10 thread:thread];
                                       }],
                       [OWSTableItem itemWithTitle:@"Send fake 1k messages"
                                       actionBlock:^{
                                           [DebugUIMessages sendFakeMessages:1000 thread:thread];
                                       }],
                       [OWSTableItem itemWithTitle:@"Send fake 10k messages"
                                       actionBlock:^{
                                           [DebugUIMessages sendFakeMessages:10 * 1000 thread:thread];
                                       }],
                       [OWSTableItem itemWithTitle:@"Send text/x-signal-plain"
                                       actionBlock:^{
                                           [DebugUIMessages sendOversizeTextMessage:thread];
                                       }],
                       [OWSTableItem itemWithTitle:@"Send unknown mimetype"
                                       actionBlock:^{
                                           [DebugUIMessages
                                               sendRandomAttachment:thread
                                                                uti:SignalAttachment.kUnknownTestAttachmentUTI];
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
                   ]];
}

+ (void)sendTextMessageInThread:(TSThread *)thread counter:(int)counter
{
    NSString *randomText = [self randomText];
    NSString *text = [[[@(counter) description] stringByAppendingString:@" "] stringByAppendingString:randomText];
    OWSMessageSender *messageSender = [Environment getCurrent].messageSender;
    [ThreadUtil sendMessageWithText:text inThread:thread messageSender:messageSender];
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

+ (void)ensureRandomFileWithURL:(NSString *)url
                       filename:(NSString *)filename
                        success:(nullable void (^)(NSString *filePath))success
                        failure:(nullable void (^)())failure
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *documentDirectoryURL =
        [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSString *randomFilesDirectoryPath =
        [[documentDirectoryURL path] stringByAppendingPathComponent:@"cached_random_files"];
    NSError *error;
    if (![fileManager fileExistsAtPath:randomFilesDirectoryPath]) {
        [fileManager createDirectoryAtPath:randomFilesDirectoryPath
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:&error];
        OWSAssert(!error);
        if (error) {
            DDLogError(@"Error creating directory: %@", error);
            failure();
            return;
        }
    }
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
                    DDLogError(@"Error write url response [%@]: %@", url, filePath);
                    OWSAssert(0);
                    failure();
                }
            }
            failure:^(NSURLSessionDataTask *_Nullable task, NSError *requestError) {
                DDLogError(@"Error downloading url[%@]: %@", url, requestError);
                OWSAssert(0);
                failure();
            }];
    }
}

+ (void)sendAttachment:(NSString *)filePath
                thread:(TSThread *)thread
               success:(nullable void (^)())success
               failure:(nullable void (^)())failure
{
    OWSAssert(filePath);
    OWSAssert(thread);

    OWSMessageSender *messageSender = [Environment getCurrent].messageSender;
    NSString *filename = [filePath lastPathComponent];
    NSString *utiType = [MIMETypeUtil utiTypeForFileExtension:filename.pathExtension];
    NSData *data = [NSData dataWithContentsOfFile:filePath];
    OWSAssert(data);
    if (!data) {
        DDLogError(@"Couldn't read attachment: %@", filePath);
        failure();
        return;
    }
    SignalAttachment *attachment = [SignalAttachment attachmentWithData:data dataUTI:utiType filename:filename];
    OWSAssert(attachment);
    if ([attachment hasError]) {
        DDLogError(@"attachment[%@]: %@", [attachment filename], [attachment errorName]);
        [DDLog flushLog];
    }
    OWSAssert(![attachment hasError]);
    [ThreadUtil sendMessageWithAttachment:attachment inThread:thread messageSender:messageSender];
    success();
}

+ (void)ensureRandomGifWithSuccess:(nullable void (^)(NSString *filePath))success failure:(nullable void (^)())failure
{
    [self ensureRandomFileWithURL:@"https://s3.amazonaws.com/ows-data/example_attachment_media/random-gif.gif"
                         filename:@"random-gif.gif"
                          success:success
                          failure:failure];
}

+ (void)sendRandomGifInThread:(TSThread *)thread
                      success:(nullable void (^)())success
                      failure:(nullable void (^)())failure
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

+ (void)ensureRandomJpegWithSuccess:(nullable void (^)(NSString *filePath))success failure:(nullable void (^)())failure
{
    [self ensureRandomFileWithURL:@"https://s3.amazonaws.com/ows-data/example_attachment_media/random-jpg.JPG"
                         filename:@"random-jpg.jpg"
                          success:success
                          failure:failure];
}

+ (void)sendRandomJpegInThread:(TSThread *)thread
                       success:(nullable void (^)())success
                       failure:(nullable void (^)())failure
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

+ (void)ensureRandomMp3WithSuccess:(nullable void (^)(NSString *filePath))success failure:(nullable void (^)())failure
{
    [self ensureRandomFileWithURL:@"https://s3.amazonaws.com/ows-data/example_attachment_media/random-mp3.mp3"
                         filename:@"random-mp3.mp3"
                          success:success
                          failure:failure];
}

+ (void)sendRandomMp3InThread:(TSThread *)thread
                      success:(nullable void (^)())success
                      failure:(nullable void (^)())failure
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

+ (void)ensureRandomMp4WithSuccess:(nullable void (^)(NSString *filePath))success failure:(nullable void (^)())failure
{
    [self ensureRandomFileWithURL:@"https://s3.amazonaws.com/ows-data/example_attachment_media/random-mp4.mp4"
                         filename:@"random-mp4.mp4"
                          success:success
                          failure:failure];
}

+ (void)sendRandomMp4InThread:(TSThread *)thread
                      success:(nullable void (^)())success
                      failure:(nullable void (^)())failure
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

    void (^success)() = ^{
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
    OWSMessageSender *messageSender = [Environment getCurrent].messageSender;
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
                              @"lorem, in rhoncus nisi."];
    }

    SignalAttachment *attachment = [SignalAttachment attachmentWithData:[message dataUsingEncoding:NSUTF8StringEncoding]
                                                                dataUTI:SignalAttachment.kOversizeTextAttachmentUTI
                                                               filename:nil];
    [ThreadUtil sendMessageWithAttachment:attachment inThread:thread messageSender:messageSender];
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

+ (void)sendRandomAttachment:(TSThread *)thread uti:(NSString *)uti length:(NSUInteger)length
{
    OWSMessageSender *messageSender = [Environment getCurrent].messageSender;
    SignalAttachment *attachment =
        [SignalAttachment attachmentWithData:[self createRandomNSDataOfSize:length] dataUTI:uti filename:nil];
    [ThreadUtil sendMessageWithAttachment:attachment inThread:thread messageSender:messageSender ignoreErrors:YES];
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

    [[TSStorageManager sharedManager].dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

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
    [[TSStorageManager sharedManager].dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
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
    [[TSStorageManager sharedManager].dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
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
        @"You cannot buy the revolution. You cannot make the revolution. You can only be the revolution. It is in your "
        @"spirit, or it is nowhere.",
        @"That is what I have always understood to be the essence of anarchism: the conviction that the burden of "
        @"proof has to be placed on authority, and that it should be dismantled if that burden cannot be met.",
        @"Ask for work. If they don't give you work, ask for bread. If they do not give you work or bread, then take "
        @"bread.",
        @"Every society has the criminals it deserves.",
        @"Anarchism is founded on the observation that since few men are wise enough to rule themselves, even fewer "
        @"are wise enough to rule others.",
        @"If you would know who controls you see who you may not criticise.",
        @"At one time in the world there were woods that no one owned."
    ];
    NSString *randomText = randomTexts[(NSUInteger)arc4random_uniform((uint32_t)randomTexts.count)];
    return randomText;
}

+ (void)sendFakeMessages:(int)counter thread:(TSThread *)thread
{
    [TSStorageManager.sharedManager.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (int i = 0; i < counter; i++) {
            NSString *randomText = [self randomText];
            switch (arc4random_uniform(4)) {
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
                    break;
                }
                case 2: {
                    TSAttachmentPointer *pointer =
                        [[TSAttachmentPointer alloc] initWithServerId:237391539706350548
                                                                  key:[self createRandomNSDataOfSize:64]
                                                               digest:nil
                                                          contentType:@"audio/mp3"
                                                                relay:@""
                                                       sourceFilename:@"test.mp3"
                                                       attachmentType:TSAttachmentTypeDefault];
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
                    OWSDisappearingMessagesConfiguration *configuration =
                        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:thread.uniqueId
                                                                          transaction:transaction];
                    TSOutgoingMessage *message = [[TSOutgoingMessage alloc]
                        initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                 inThread:thread
                           isVoiceMessage:NO
                         expiresInSeconds:(configuration.isEnabled ? configuration.durationSeconds : 0)];

                    NSString *filename = @"test.mp3";
                    TSAttachmentStream *attachmentStream =
                        [[TSAttachmentStream alloc] initWithContentType:@"audio/mp3" sourceFilename:filename];

                    NSError *error;
                    [attachmentStream writeData:[self createRandomNSDataOfSize:16] error:&error];
                    OWSAssert(!error);

                    [attachmentStream saveWithTransaction:transaction];
                    [message.attachmentIds addObject:attachmentStream.uniqueId];
                    if (filename) {
                        message.attachmentFilenameMap[attachmentStream.uniqueId] = filename;
                    }
                    [message saveWithTransaction:transaction];
                    break;
                }
            }
        }
    }];
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

@end

NS_ASSUME_NONNULL_END
