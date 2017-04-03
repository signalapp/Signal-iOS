//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUITableViewController.h"
#import "Environment.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <SignalServiceKit/TSStorageManager+SessionStore.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUITableViewController

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

+ (void)presentDebugUIForThread:(TSThread *)thread
             fromViewController:(UIViewController *)fromViewController {
    OWSAssert(thread);
    OWSAssert(fromViewController);

    OWSTableContents *contents = [OWSTableContents new];
    contents.title = @"Debug: Conversation";
    
    [contents addSection:[OWSTableSection sectionWithTitle:@"Messages View"
                                                     items:@[
                                                             [OWSTableItem actionWithTitle:@"Send 10 messages (1/sec.)"
                                                                               actionBlock:^{
                                                                                   [DebugUITableViewController sendTextMessage:10
                                                                                                                        thread:thread];
                                                                               }],
                                                             [OWSTableItem actionWithTitle:@"Send 100 messages (1/sec.)"
                                                                               actionBlock:^{
                                                                                   [DebugUITableViewController sendTextMessage:100
                                                                                                                        thread:thread];
                                                                               }],
                                                             [OWSTableItem actionWithTitle:@"Send text/x-signal-plain"
                                                                               actionBlock:^{
                                                                                   [DebugUITableViewController sendOversizeTextMessage:thread];
                                                                               }],
                                                             [OWSTableItem actionWithTitle:@"Send unknown mimetype"
                                                                               actionBlock:^{
                                                                                   [DebugUITableViewController sendRandomAttachment:thread
                                                                                                                                uti:SignalAttachment.kUnknownTestAttachmentUTI];
                                                                               }],
                                                             [OWSTableItem actionWithTitle:@"Send pdf"
                                                                               actionBlock:^{
                                                                                   [DebugUITableViewController sendRandomAttachment:thread
                                                                                                                                uti:(NSString *) kUTTypePDF];
                                                                               }],
                                                             ]]];

    [contents addSection:[OWSTableSection sectionWithTitle:@"Print to Debug Log"
                                                     items:@[ [OWSTableItem actionWithTitle:@"Print all sessions"
                                                                                actionBlock:^{
                                                                                    [[TSStorageManager sharedManager]
                                                                                        printAllSessions];
                                                                                }] ]]];

    DebugUITableViewController *viewController = [DebugUITableViewController new];
    viewController.contents = contents;
    [viewController presentFromViewController:fromViewController];
}

+ (void)sendTextMessage:(int)counter
                 thread:(TSThread *)thread {
    OWSMessageSender *messageSender = [Environment getCurrent].messageSender;
    if (counter < 1) {
        return;
    }
    [ThreadUtil sendMessageWithText:[@(counter) description]
                           inThread:thread
                      messageSender:messageSender];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) 1.f * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
                       [self sendTextMessage:counter - 1 thread:thread];
                   });
}

+ (void)sendOversizeTextMessage:(TSThread *)thread {
    OWSMessageSender *messageSender = [Environment getCurrent].messageSender;
    NSMutableString *message = [NSMutableString new];
    for (int i=0; i < 32; i++) {
        [message appendString:@"Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse rutrum, nulla vitae pretium hendrerit, tellus turpis pharetra libero, vitae sodales tortor ante vel sem. Fusce sed nisl a lorem gravida tincidunt. Suspendisse efficitur non quam ac sodales. Aenean ut velit maximus, posuere sem a, accumsan nunc. Donec ullamcorper turpis lorem. Quisque dignissim purus eu placerat ultricies. Proin at urna eget mi semper congue. Aenean non elementum ex. Praesent pharetra quam at sem vestibulum, vestibulum ornare dolor elementum. Vestibulum massa tortor, scelerisque sit amet pulvinar a, rhoncus vitae nisl. Sed mi nunc, tempus at varius in, malesuada vitae dui. Vivamus efficitur pulvinar erat vitae congue. Proin vehicula turpis non felis congue facilisis. Nullam aliquet dapibus ligula ac mollis. Etiam sit amet posuere lorem, in rhoncus nisi."];
    }
    
    SignalAttachment *attachment = [SignalAttachment oversizeTextAttachmentWithText:message];
    [ThreadUtil sendMessageWithAttachment:attachment
                                 inThread:thread
                            messageSender:messageSender];
}

+ (NSData*)createRandomNSDataOfSize:(size_t)size
{
    OWSAssert(size % 4 == 0);
    
    NSMutableData* data = [NSMutableData dataWithCapacity:size];
    for (size_t i = 0; i < size / 4; ++i)
    {
        u_int32_t randomBits = arc4random();
        [data appendBytes:(void *)&randomBits length:4];
    }
    return data;
}

+ (void)sendRandomAttachment:(TSThread *)thread
                         uti:(NSString *)uti {
    OWSMessageSender *messageSender = [Environment getCurrent].messageSender;
    SignalAttachment *attachment = [SignalAttachment genericAttachmentWithData:[self createRandomNSDataOfSize:256]
                                                                       dataUTI:uti];
    [ThreadUtil sendMessageWithAttachment:attachment
                                 inThread:thread
                            messageSender:messageSender];
}

@end

NS_ASSUME_NONNULL_END
