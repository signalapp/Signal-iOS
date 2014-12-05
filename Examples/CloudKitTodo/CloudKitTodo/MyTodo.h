#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>
#import "MyDatabaseObject.h"

typedef NS_ENUM(NSInteger, TodoPriority) {
	TodoPriorityLow     = -1,
	TodoPriorityNormal  =  0,
	TodoPriorityHigh    =  1,
};

@interface MyTodo : MyDatabaseObject <NSCoding, NSCopying>

- (instancetype)init;
- (instancetype)initWithUUID:(NSString *)uuid;

- (instancetype)initWithRecord:(CKRecord *)record;

@property (nonatomic, copy, readonly) NSString *uuid;

@property (nonatomic, copy, readwrite) NSString *title;
@property (nonatomic, assign, readwrite) TodoPriority priority;
@property (nonatomic, assign, readwrite) BOOL isDone;

@property (nonatomic, strong, readwrite) NSDate *creationDate;
@property (nonatomic, strong, readwrite) NSDate *lastModified;

@end
