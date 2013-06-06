#import <Foundation/Foundation.h>
#import "YapAbstractDatabaseExtensionTransaction.h"


@interface YapCollectionsDatabaseViewTransaction : YapAbstractDatabaseExtensionTransaction

- (NSUInteger)numberOfGroups;
- (NSArray *)allGroups;

- (NSUInteger)numberOfKeysInGroup:(NSString *)group;
- (NSUInteger)numberOfKeysInAllGroups;

- (BOOL)getKey:(NSString **)keyPtr
    collection:(NSString **)collectionPtr
       atIndex:(NSUInteger)index
       inGroup:(NSString *)group;

- (NSString *)groupForKey:(NSString *)key inCollection:(NSString *)collection;

- (BOOL)getGroup:(NSString **)groupPtr
           index:(NSUInteger *)indexPtr
          forKey:(NSString *)key
    inCollection:(NSString *)collection;

//- (NSArray *)keysInRange:(NSRange)range group:(NSString *)group;
//
//- (void)enumerateKeysInGroup:(NSString *)group
//                  usingBlock:(void (^)(NSUInteger index, NSString *key, BOOL *stop))block;
//
//- (void)enumerateKeysInGroup:(NSString *)group
//                 withOptions:(NSEnumerationOptions)options
//                  usingBlock:(void (^)(NSUInteger index, NSString *key, BOOL *stop))block;
//
//- (void)enumerateKeysInGroup:(NSString *)group
//                 withOptions:(NSEnumerationOptions)options
//                       range:(NSRange)range
//                  usingBlock:(void (^)(NSUInteger index, NSString *key, BOOL *stop))block;

@end
