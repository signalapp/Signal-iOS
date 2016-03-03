#import <Foundation/Foundation.h>
#import "YapDatabaseExtensionConnection.h"

@class YapDatabaseCloudKit;

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseCloudKitConnection : YapDatabaseExtensionConnection

/**
 * Returns the parent view instance.
**/
@property (nonatomic, strong, readonly) YapDatabaseCloudKit *cloudKit;

@end

NS_ASSUME_NONNULL_END
