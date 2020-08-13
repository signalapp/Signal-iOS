//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSTimer (OWS)

// This method avoids the classic NSTimer retain cycle bug
// by using a weak reference to the target.
+ (NSTimer *)weakScheduledTimerWithTimeInterval:(NSTimeInterval)timeInterval
                                         target:(id)target
                                       selector:(SEL)selector
                                       userInfo:(nullable id)userInfo
                                        repeats:(BOOL)repeats;

+ (NSTimer *)weakTimerWithTimeInterval:(NSTimeInterval)timeInterval
                                target:(id)target
                              selector:(SEL)selector
                              userInfo:(nullable id)userInfo
                               repeats:(BOOL)repeats;

@end

NS_ASSUME_NONNULL_END
