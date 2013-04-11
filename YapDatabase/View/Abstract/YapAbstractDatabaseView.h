#import <Foundation/Foundation.h>

#import "YapAbstractDatabaseViewConnection.h"
#import "YapAbstractDatabaseViewTransaction.h"


@interface YapAbstractDatabaseView : NSObject

@property (atomic, copy, readonly) NSString *registeredName;

@end
