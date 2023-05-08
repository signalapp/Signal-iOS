//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#ifdef USE_DEBUG_UI

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyWriteTransaction;

typedef void (^ActionSuccessBlock)(void);
typedef void (^ActionFailureBlock)(void);
typedef void (^ActionPrepareBlock)(ActionSuccessBlock success, ActionFailureBlock failure);
typedef void (^StaggeredActionBlock)(
    NSUInteger index, SDSAnyWriteTransaction *transaction, ActionSuccessBlock success, ActionFailureBlock failure);
typedef void (^UnstaggeredActionBlock)(NSUInteger index, SDSAnyWriteTransaction *transaction);

NS_ASSUME_NONNULL_END

#endif
