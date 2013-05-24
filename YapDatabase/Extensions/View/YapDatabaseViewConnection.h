#import <Foundation/Foundation.h>
#import "YapAbstractDatabaseExtensionConnection.h"

@class YapDatabaseView;


@interface YapDatabaseViewConnection : YapAbstractDatabaseExtensionConnection

@property (nonatomic, strong, readonly) YapDatabaseView *view;

@end
