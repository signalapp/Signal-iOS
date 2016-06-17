#import <Foundation/Foundation.h>

#import "YapDatabaseExtensionConnection.h"
@class YapDatabaseView;

NS_ASSUME_NONNULL_BEGIN


@interface YapDatabaseViewConnection : YapDatabaseExtensionConnection

/**
 * Returns the parent view instance.
**/
@property (nonatomic, strong, readonly) YapDatabaseView *parent;

@end

NS_ASSUME_NONNULL_END
