//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUIMessages.h"
#import "Environment.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <AFNetworking/AFNetworking.h>
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
                                           [DebugUIMessages sendTextMessage:10 thread:thread];
                                       }],
                       [OWSTableItem itemWithTitle:@"Send 100 messages (1/sec.)"
                                       actionBlock:^{
                                           [DebugUIMessages sendTextMessage:100 thread:thread];
                                       }],
                       [OWSTableItem itemWithTitle:@"Send 1,000 messages (1/sec.)"
                                       actionBlock:^{
                                           [DebugUIMessages sendTextMessage:1000 thread:thread];
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
                   ]];
}

+ (void)sendTextMessage:(int)counter thread:(TSThread *)thread
{
    OWSMessageSender *messageSender = [Environment getCurrent].messageSender;
    if (counter < 1) {
        return;
    }
    [ThreadUtil
        sendMessageWithText:[[@(counter) description]
                                stringByAppendingString:@" Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
                                                        @"Suspendisse rutrum, nulla vitae pretium hendrerit, tellus "
                                                        @"turpis pharetra libero, vitae sodales tortor ante vel sem."]
                   inThread:thread
              messageSender:messageSender];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self sendTextMessage:counter - 1 thread:thread];
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
    OWSMessageSender *messageSender = [Environment getCurrent].messageSender;
    SignalAttachment *attachment =
        [SignalAttachment attachmentWithData:[self createRandomNSDataOfSize:256] dataUTI:uti filename:nil];
    [ThreadUtil sendMessageWithAttachment:attachment inThread:thread messageSender:messageSender];
}

@end

NS_ASSUME_NONNULL_END
