#import <Foundation/Foundation.h>
#import "NSTimer+Proxying.h"
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSTimerProxy : NSObject

@property (nonatomic, weak) id target;
@property (nonatomic) SEL selector;

@end

@implementation NSTimerProxy

- (void)timerFired:(NSDictionary *)userInfo
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [self.target performSelector:self.selector withObject:userInfo];
#pragma clang diagnostic pop
}

@end

static void *kNSTimer_SN_Proxy = &kNSTimer_SN_Proxy;

@implementation NSTimer (Session)

- (NSTimerProxy *)sn_proxy
{
    return objc_getAssociatedObject(self, kNSTimer_SN_Proxy);
}

- (void)sn_setProxy:(NSTimerProxy *)proxy
{
    #if DEBUG
    assert(proxy != nil);
    #endif
    objc_setAssociatedObject(self, kNSTimer_SN_Proxy, proxy, OBJC_ASSOCIATION_RETAIN);
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
    [timer sn_setProxy:proxy];
    return timer;
}

@end

NS_ASSUME_NONNULL_END
