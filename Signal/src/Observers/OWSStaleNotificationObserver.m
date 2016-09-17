//  Created by Michael Kirk on 9/14/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSStaleNotificationObserver.h"
#import "PushManager.h"
#import <SignalServiceKit/OWSReadReceiptsProcessor.h>
#import <SignalServiceKit/TSIncomingMessage.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSStaleNotificationObserver ()

@property (nonatomic, readonly) PushManager *pushManager;

@end

@implementation OWSStaleNotificationObserver

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init
{
    return [self initWithPushManager:[PushManager sharedManager]];
}

- (instancetype)initWithPushManager:(PushManager *)pushManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _pushManager = pushManager;

    return self;
}

- (void)startObserving
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleMessageRead:)
                                                 name:OWSReadReceiptsProcessorMarkedMessageAsReadNotification
                                               object:nil];
}

- (void)handleMessageRead:(NSNotification *)notification
{
    if ([notification.object isKindOfClass:[TSIncomingMessage class]]) {
        TSIncomingMessage *message = (TSIncomingMessage *)notification.object;

        DDLogDebug(@"%@ canceled notification for message:%@", self.tag, message);
        [self.pushManager cancelNotificationsWithThreadId:message.uniqueThreadId];
    }
}

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
