#import <Foundation/Foundation.h>

@interface Queue : NSObject

- (instancetype)init;

- (void)enqueue:(id)item;
- (id)dequeue;
- (id)tryDequeue;
- (id)peek;
- (id)peekAt:(NSUInteger)offset;
- (NSUInteger)count;

@end
