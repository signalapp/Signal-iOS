#import <Foundation/Foundation.h>

#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseActionManager.h"
#import "YapDatabaseActionManagerConnection.h"
#import "YapDatabaseActionManagerTransaction.h"

#import "YapDatabasePrivate.h"
#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabaseViewPrivate.h"

#import "YapCache.h"

@interface YapDatabaseActionManagerConnection () {
@public

	YapCache<YapCollectionKey *, id> *actionItemsCache;
}

@end

@interface YapDatabaseActionManagerTransaction ()

- (NSArray *)actionItemsForCollectionKey:(YapCollectionKey *)ck;
- (NSArray *)actionItemsForKey:(NSString *)key inCollection:(NSString *)collection;

@end
