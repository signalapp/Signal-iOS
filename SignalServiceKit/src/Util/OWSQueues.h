//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
