#import "YapProxyObject.h"
#import "YapCollectionKey.h"

@class YapDatabaseReadTransaction;


@interface YapProxyObject ()

- (void)reset;

- (void)resetWithRealObject:(id)inRealObject;

- (void)resetWithRowid:(int64_t)rowid
         collectionKey:(YapCollectionKey *)collectionKey
            isMetadata:(BOOL)isMetadata
           transaction:(YapDatabaseReadTransaction *)transaction;

@end
