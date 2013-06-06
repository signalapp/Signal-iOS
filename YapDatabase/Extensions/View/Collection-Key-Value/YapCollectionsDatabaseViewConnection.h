#import <Foundation/Foundation.h>
#import "YapAbstractDatabaseExtensionConnection.h"

@class YapCollectionsDatabaseView;


@interface YapCollectionsDatabaseViewConnection : YapAbstractDatabaseExtensionConnection

@property (nonatomic, strong, readonly) YapCollectionsDatabaseView *view;

@end
