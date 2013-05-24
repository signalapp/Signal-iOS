#import <Foundation/Foundation.h>
#import "YapAbstractDatabaseExtensionTransaction.h"


@interface YapDatabaseViewTransaction : YapAbstractDatabaseExtensionTransaction

- (NSUInteger)numberOfGroups;
- (NSArray *)allGroups;

- (NSUInteger)numberOfKeysInGroup:(NSString *)group;
- (NSUInteger)numberOfKeysInAllGroups;

- (NSString *)keyAtIndex:(NSUInteger)keyIndex inGroup:(NSString *)group;

- (NSString *)groupForKey:(NSString *)key;

- (BOOL)getGroup:(NSString **)groupPtr index:(NSUInteger *)indexPtr forKey:(NSString *)key;

- (id)objectAtIndex:(NSUInteger)keyIndex inGroup:(NSString *)group;

// Todo: Add enumerate methods...

@end
