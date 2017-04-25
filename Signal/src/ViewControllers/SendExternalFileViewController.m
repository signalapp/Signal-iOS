//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SendExternalFileViewController.h"
#import "Environment.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/TSThread.h>

@interface SendExternalFileViewController () <SelectThreadViewControllerDelegate>

@property (nonatomic, readonly) OWSMessageSender *messageSender;

@end

@implementation SendExternalFileViewController

- (void)loadView
{
    [super loadView];

    self.delegate = self;

    _messageSender = [Environment getCurrent].messageSender;

    self.title = NSLocalizedString(@"SEND_EXTERNAL_FILE_VIEW_TITLE", @"Title for the 'send external file' view.");
}

#pragma mark - SelectThreadViewControllerDelegate

- (void)threadWasSelected:(TSThread *)thread
{
    OWSAssert(self.attachment);
    OWSAssert(thread);

    // We should have a valid filename.
    OWSAssert(self.attachment.filename.length > 0);
    NSString *fileExtension = [self.attachment.filename pathExtension].lowercaseString;
    OWSAssert(fileExtension.length > 0);
    NSSet<NSString *> *textExtensions = [NSSet setWithArray:@[
        @"txt",
        @"url",
    ]];
    NSString *text = nil;
    if ([textExtensions containsObject:fileExtension]) {
        text = [[NSString alloc] initWithData:self.attachment.data encoding:NSUTF8StringEncoding];
        OWSAssert(text);
    }

    if (text) {
        [ThreadUtil sendMessageWithText:text inThread:thread messageSender:self.messageSender];
    } else {
        [ThreadUtil sendMessageWithAttachment:self.attachment inThread:thread messageSender:self.messageSender];
    }

    [Environment messageThreadId:thread.uniqueId];
}

- (BOOL)canSelectBlockedContact
{
    return NO;
}

@end
