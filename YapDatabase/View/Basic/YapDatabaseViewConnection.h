#import <Foundation/Foundation.h>


@interface YapDatabaseViewConnection : NSObject

- (void)prepare;
- (BOOL)isPrepared;

- (void)mergeChangeset:(NSDictionary *)changeset;

@end
