//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG

#define AssertOnDispatchQueue(queue)                                                                                   \
    {                                                                                                                  \
            dispatch_assert_queue(queue);                                                                              \
    }

#else

#define AssertOnDispatchQueue(queue)

#endif

NS_ASSUME_NONNULL_END
