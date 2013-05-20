#import <Foundation/Foundation.h>

#import "YapAbstractDatabaseViewConnection.h"
#import "YapAbstractDatabaseViewTransaction.h"


@interface YapAbstractDatabaseView : NSObject

/**
 * After a view has been successfully registered with a database,
 * the registeredName property will be set by the database.
**/
@property (atomic, copy, readonly) NSString *registeredName;

@end
