//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class YapDatabaseReadWriteTransaction;

typedef void (^ActionSuccessBlock)(void);
typedef void (^ActionFailureBlock)(void);
typedef void (^ActionPrepareBlock)(ActionSuccessBlock success, ActionFailureBlock failure);
typedef void (^StaggeredActionBlock)(NSUInteger index,
    YapDatabaseReadWriteTransaction *transaction,
    ActionSuccessBlock success,
    ActionFailureBlock failure);
typedef void (^UnstaggeredActionBlock)(NSUInteger index, YapDatabaseReadWriteTransaction *transaction);

NS_ASSUME_NONNULL_END
