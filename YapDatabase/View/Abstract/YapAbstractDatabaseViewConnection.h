#import <Foundation/Foundation.h>

@class YapAbstractDatabaseView;


@interface YapAbstractDatabaseViewConnection : NSObject

/**
 * A connection maintains a strong reference to its parent.
 *
 * This is to enforce the following core architecture rule:
 * A view instance cannot be deallocated if a corresponding connection is stil alive.
**/
@property (nonatomic, strong, readonly) YapAbstractDatabaseView *abstractView;

@end
