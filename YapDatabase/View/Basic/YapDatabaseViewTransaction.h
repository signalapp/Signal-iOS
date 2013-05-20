#import <Foundation/Foundation.h>
#import "YapAbstractDatabaseViewTransaction.h"


@interface YapDatabaseViewTransaction : YapAbstractDatabaseViewTransaction

- (NSUInteger)numberOfGroups;
- (NSArray *)allGroups;

- (NSUInteger)numberOfKeysInGroup:(NSString *)group;
- (NSUInteger)numberOfKeysInAllGroups;

- (NSString *)keyAtIndex:(NSUInteger)keyIndex inGroup:(NSString *)group;

- (id)objectAtIndex:(NSUInteger)keyIndex inGroup:(NSString *)group;

- (NSString *)groupForKey:(NSString *)key;

- (BOOL)getGroup:(NSString **)groupPtr index:(NSUInteger *)indexPtr forKey:(NSString *)key;

@end
