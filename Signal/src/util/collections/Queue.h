#import <Foundation/Foundation.h>

@interface Queue : NSObject
- (void)enqueue:(id)item;
- (id)dequeue;
- (id)tryDequeue;
- (id)peek;
- (id)peekAt:(NSUInteger)offset;
- (NSUInteger)count;
@end
