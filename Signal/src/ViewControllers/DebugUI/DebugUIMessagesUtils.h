//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#ifdef DEBUG

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
