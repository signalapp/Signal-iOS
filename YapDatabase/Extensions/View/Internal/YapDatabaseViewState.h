#import <Foundation/Foundation.h>
#import "YapDatabaseViewPageMetadata.h"


@interface YapDatabaseViewState : NSObject <NSCopying, NSMutableCopying>

@property (nonatomic, readonly) BOOL isImmutable;

#pragma mark Access

- (NSArray *)pagesMetadataForGroup:(NSString *)group;
- (NSString *)groupForPageKey:(NSString *)pageKey;

- (NSUInteger)numberOfGroups;

- (void)enumerateGroupsWithBlock:(void (^)(NSString *group, BOOL *stop))block;
- (void)enumerateWithBlock:(void (^)(NSString *group, NSArray *pagesMetadataForGroup, BOOL *stop))block;

#pragma mark Mutation

- (NSArray *)createGroup:(NSString *)group;
- (NSArray *)createGroup:(NSString *)group withCapacity:(NSUInteger)capacity;

- (NSArray *)addPageMetadata:(YapDatabaseViewPageMetadata *)pageMetadata
                     toGroup:(NSString *)group;

- (NSArray *)insertPageMetadata:(YapDatabaseViewPageMetadata *)pageMetadata
                        atIndex:(NSUInteger)index
                        inGroup:(NSString *)group;

- (NSArray *)removePageMetadataAtIndex:(NSUInteger)index inGroup:(NSString *)group;

- (void)removeGroup:(NSString *)group;
- (void)removeAllGroups;

@end
