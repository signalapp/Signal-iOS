#import <Foundation/Foundation.h>

@class YapMutationStackItem_Abstract;

NS_ASSUME_NONNULL_BEGIN

@interface YapMutationStack_Abstract : NSObject

- (instancetype)init;
- (void)clear;
@end

@interface YapMutationStackItem_Abstract : NSObject

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@class YapMutationStackItem_Bool;

@interface YapMutationStack_Bool : YapMutationStack_Abstract
- (YapMutationStackItem_Bool *)push;

//- (void)pop;    <- defined in superclass
//- (void)popAll; <- defined in superclass

- (void)markAsMutated;
@end

@interface YapMutationStackItem_Bool : YapMutationStackItem_Abstract

@property (nonatomic, readonly) BOOL isMutated;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@class YapMutationStackItem_Set;

@interface YapMutationStack_Set : YapMutationStack_Abstract

- (YapMutationStackItem_Set *)push;

//- (void)pop;    <- defined in superclass
//- (void)popAll; <- defined in superclass

- (void)markAsMutated:(id)object;

@end

@interface YapMutationStackItem_Set : YapMutationStackItem_Abstract

- (BOOL)isMutated:(id)object;

@end

NS_ASSUME_NONNULL_END
