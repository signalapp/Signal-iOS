#import <Foundation/Foundation.h>


@interface Person : NSObject <NSCoding>

- (id)initWithName:(NSString *)name uuid:(NSString *)uuid;

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *uuid;

@end
