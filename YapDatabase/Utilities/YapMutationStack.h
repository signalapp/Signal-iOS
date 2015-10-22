#import <Foundation/Foundation.h>


@class YapMutationStackItem_Abstract;

@interface YapMutationStack_Abstract : NSObject
NS_ASSUME_NONNULL_BEGIN

- (instancetype)init;
- (void)clear;

NS_ASSUME_NONNULL_END
@end

@interface YapMutationStackItem_Abstract : NSObject

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@class YapMutationStackItem_Bool;

@interface YapMutationStack_Bool : YapMutationStack_Abstract
NS_ASSUME_NONNULL_BEGIN

- (YapMutationStackItem_Bool *)push;

//- (void)pop;    <- defined in superclass
//- (void)popAll; <- defined in superclass

- (void)markAsMutated;

NS_ASSUME_NONNULL_END
@end

@interface YapMutationStackItem_Bool : YapMutationStackItem_Abstract

@property (nonatomic, readonly) BOOL isMutated;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@class YapMutationStackItem_Set;

@interface YapMutationStack_Set : YapMutationStack_Abstract
NS_ASSUME_NONNULL_BEGIN

- (YapMutationStackItem_Set *)push;

//- (void)pop;    <- defined in superclass
//- (void)popAll; <- defined in superclass

- (void)markAsMutated:(id)object;

NS_ASSUME_NONNULL_END
@end

@interface YapMutationStackItem_Set : YapMutationStackItem_Abstract
NS_ASSUME_NONNULL_BEGIN

- (BOOL)isMutated:(id)object;

NS_ASSUME_NONNULL_END
@end
