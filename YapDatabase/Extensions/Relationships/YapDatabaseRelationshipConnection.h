#import <Foundation/Foundation.h>
#import "YapDatabaseExtensionConnection.h"

@class YapDatabaseRelationship;


@interface YapDatabaseRelationshipConnection : YapDatabaseExtensionConnection

/**
 * Returns the parent view instance.
**/
@property (nonatomic, strong, readonly) YapDatabaseRelationship *relationship;

@end
