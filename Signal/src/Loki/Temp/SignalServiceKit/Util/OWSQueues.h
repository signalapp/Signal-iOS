//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG

#define AssertOnDispatchQueue(queue)                                                                                   \
    {                                                                                                                  \
        if (@available(iOS 10.0, *)) {                                                                                 \
            dispatch_assert_queue(queue);                                                                              \
        } else {                                                                                                       \
            _Pragma("clang diagnostic push") _Pragma("clang diagnostic ignored \"-Wdeprecated-declarations\"")         \
                OWSAssertDebug(dispatch_get_current_queue() == queue);                                                      \
            _Pragma("clang diagnostic pop")                                                                            \
        }                                                                                                              \
    }

#else

#define AssertOnDispatchQueue(queue)

#endif

NS_ASSUME_NONNULL_END
