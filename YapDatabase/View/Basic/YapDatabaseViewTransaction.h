#import <Foundation/Foundation.h>
#import "YapAbstractDatabaseViewTransaction.h"


@interface YapDatabaseViewTransaction : YapAbstractDatabaseViewTransaction

- (NSUInteger)numberOfSections;
- (NSUInteger)numberOfKeysInSection:(NSUInteger)section;

- (NSUInteger)numberOfKeysInAllSections;

- (NSString *)keyAtIndex:(NSUInteger)keyIndex inSection:(NSUInteger)sectionIndex;
- (NSString *)keyAtIndexPath:(NSIndexPath *)indexPath;

- (id)objectAtIndex:(NSUInteger)keyIndex inSection:(NSUInteger)sectionIndex;
- (id)objectAtIndexPath:(NSIndexPath *)indexPath;

- (NSIndexPath *)indexPathForKey:(NSString *)key;
- (void)getIndex:(NSUInteger *)indexPtr section:(NSUInteger *)sectionIndex forKey:(NSString *)key;

@end
