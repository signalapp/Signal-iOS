#import <Foundation/Foundation.h>
#import "MyDatabaseObject.h"


@interface Car : MyDatabaseObject

@property (nonatomic, copy, readwrite) NSString *make;
@property (nonatomic, copy, readwrite) NSString *model;

@end
