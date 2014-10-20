#import <Foundation/Foundation.h>
#import "MyDatabaseObject.h"


@interface MyTodo : MyDatabaseObject <NSCoding, NSCopying>

- (instancetype)init;
- (instancetype)initWithUUID:(NSString *)uuid;

@property (nonatomic, copy, readonly) NSString *uuid;

@property (nonatomic, copy, readwrite) NSString *title;
@property (nonatomic, copy, readwrite) NSString *notes;

@property (nonatomic, assign, readwrite) BOOL isDone;

@property (nonatomic, strong, readwrite) NSDate *created;
@property (nonatomic, strong, readwrite) NSDate *lastModified;

@end
