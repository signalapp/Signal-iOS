#import <Foundation/Foundation.h>


@interface YapDatabaseViewReadTransaction : NSObject

- (NSUInteger)numberOfSections;
- (NSUInteger)numberOfKeysInSection:(id)section;

- (NSUInteger)numberOfKeysInAllSections;

- (NSString *)keyAtIndex:(NSUInteger)keyIndex inSection:(NSUInteger)sectionIndex;
- (id)objectAtIndex:(NSUInteger)keyIndex inSection:(NSUInteger)sectionIndex;

- (NSString *)keyAtIndexPath:(NSIndexPath *)indexPath;
- (id)objectAtIndexPath:(NSIndexPath *)indexPath;

- (void)getIndex:(NSUInteger *)indexPtr section:(NSUInteger *)sectionIndex forKey:(NSString *)key;
- (NSIndexPath *)indexPathForKey:(NSString *)key;

@end

@interface YapDatabaseViewReadWriteTransaction : YapDatabaseViewReadTransaction

// YapDatabaseReadWriteTransaction needs a method to create a view.

@end