//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

#define AppReadinessLogPrefix()                                                                                        \
    ([NSString stringWithFormat:@"[%@:%d %s]: ",                                                                       \
               [[NSString stringWithUTF8String:__FILE__] lastPathComponent],                                           \
               __LINE__,                                                                                               \
               __PRETTY_FUNCTION__])

#define AppReadinessRunNowOrWhenAppWillBecomeReady(block)                                                              \
    do {                                                                                                               \
        [AppReadiness runNowOrWhenAppWillBecomeReady:block label:AppReadinessLogPrefix()];                             \
    } while (0)

#define AppReadinessRunNowOrWhenAppDidBecomeReadySync(block)                                                           \
    do {                                                                                                               \
        [AppReadiness runNowOrWhenAppDidBecomeReadySync:block label:AppReadinessLogPrefix()];                          \
    } while (0)

#define AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(block)                                                          \
    do {                                                                                                               \
        [AppReadiness runNowOrWhenAppDidBecomeReadyAsync:block label:AppReadinessLogPrefix()];                         \
    } while (0)

#define AppReadinessRunNowOrWhenMainAppDidBecomeReadyAsync(block)                                                      \
    do {                                                                                                               \
        [AppReadiness runNowOrWhenMainAppDidBecomeReadyAsync:block label:AppReadinessLogPrefix()];                     \
    } while (0)


NS_ASSUME_NONNULL_END
