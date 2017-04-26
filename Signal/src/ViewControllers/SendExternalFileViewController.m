//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SendExternalFileViewController.h"
#import "Environment.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface SendExternalFileViewController () <SelectThreadViewControllerDelegate>

@property (nonatomic, readonly) OWSMessageSender *messageSender;

@end

#pragma mark -

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

    [ThreadUtil sendMessageWithAttachment:self.attachment inThread:thread messageSender:self.messageSender];

    [Environment messageThreadId:thread.uniqueId];
}

- (BOOL)canSelectBlockedContact
{
    return NO;
}

- (nullable UIView *)createHeader:(UIView *)superview
{
    return nil;
}

@end

NS_ASSUME_NONNULL_END
