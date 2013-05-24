#import <Foundation/Foundation.h>

@class YapAbstractDatabaseExtension;


@interface YapAbstractDatabaseExtensionConnection : NSObject

/**
 * A connection maintains a strong reference to its parent.
 *
 * This is to enforce the following core architecture rule:
 * An extension instance cannot be deallocated if a corresponding connection is stil alive.
**/
@property (nonatomic, strong, readonly) YapAbstractDatabaseExtension *abstractExtension;

@end
