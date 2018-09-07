//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NSTimer+OWS.h"
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSTimerProxy : NSObject

@property (nonatomic, weak) id target;
@property (nonatomic) SEL selector;

@end

#pragma mark -

@implementation NSTimerProxy

- (void)timerFired:(NSDictionary *)userInfo
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [self.target performSelector:self.selector withObject:userInfo];
#pragma clang diagnostic pop
}

@end

#pragma mark -

static void *kNSTimer_OWS_Proxy = &kNSTimer_OWS_Proxy;

@implementation NSTimer (OWS)

- (NSTimerProxy *)ows_proxy
{
    return objc_getAssociatedObject(self, kNSTimer_OWS_Proxy);
}

- (void)ows_setProxy:(NSTimerProxy *)proxy
{
    OWSAssertDebug(proxy);

    objc_setAssociatedObject(self, kNSTimer_OWS_Proxy, proxy, OBJC_ASSOCIATION_RETAIN);
}

+ (NSTimer *)weakScheduledTimerWithTimeInterval:(NSTimeInterval)timeInterval
                                         target:(id)target
                                       selector:(SEL)selector
                                       userInfo:(nullable id)userInfo
                                        repeats:(BOOL)repeats
{
    NSTimerProxy *proxy = [NSTimerProxy new];
    proxy.target = target;
    proxy.selector = selector;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:timeInterval
                                                      target:proxy
                                                    selector:@selector(timerFired:)
                                                    userInfo:userInfo
                                                     repeats:repeats];
    [timer ows_setProxy:proxy];
    return timer;
}

@end

NS_ASSUME_NONNULL_END
