#import <Foundation/Foundation.h>

@interface YapDatabaseViewPage : NSObject <NSCopying>

- (id)init;
- (id)initWithCapacity:(NSUInteger)capacity;

- (NSData *)serialize;
- (void)deserialize:(NSData *)data;

- (NSUInteger)count;

- (int64_t)rowidAtIndex:(NSUInteger)index;

- (void)addRowid:(int64_t)rowid;
- (void)insertRowid:(int64_t)rowid atIndex:(NSUInteger)index;

- (void)removeRowidAtIndex:(NSUInteger)index;
- (void)removeRange:(NSRange)range;
- (void)removeAllRowids;

- (void)appendPage:(YapDatabaseViewPage *)page;
- (void)prependPage:(YapDatabaseViewPage *)page;

- (void)appendRange:(NSRange)range ofPage:(YapDatabaseViewPage *)page;
- (void)prependRange:(NSRange)range ofPage:(YapDatabaseViewPage *)page;

- (BOOL)getIndex:(NSUInteger *)indexPtr ofRowid:(int64_t)rowid;

- (void)enumerateRowidsUsingBlock:(void (^)(int64_t rowid, NSUInteger idx, BOOL *stop))block;

- (void)enumerateRowidsWithOptions:(NSEnumerationOptions)options
                        usingBlock:(void (^)(int64_t rowid, NSUInteger index, BOOL *stop))block;

- (void)enumerateRowidsWithOptions:(NSEnumerationOptions)options
                             range:(NSRange)range
                        usingBlock:(void (^)(int64_t rowid, NSUInteger index, BOOL *stop))block;

@end
