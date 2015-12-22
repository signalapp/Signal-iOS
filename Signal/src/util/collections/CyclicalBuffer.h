#import <Foundation/Foundation.h>

/**
 *
 * Cyclic buffer is used to efficiently enqueue and dequeue blocks of data.
 *
 * Note that methods with 'volatile' in the name have results that can directly
 * reference the queue's internal buffer, instead of returning a safe copy.
 * The data returned by volatile methods must be used immediately and under the
 * constraints that more data is not being enqueued at the time.
 * Enqueueing data invalidates all previous volatile results, because the data they
 * reference may have been overwritten.
 *
 */
@interface CyclicalBuffer : NSObject {
   @private
    NSMutableData *buffer;
   @private
    uint32_t readOffset;
   @private
    uint32_t count;
}

/// Adds data to the buffer. The buffer will be resized if necessary.
- (void)enqueueData:(NSData *)data;

/// The number of bytes in the buffer.
- (NSUInteger)enqueuedLength;

/// Returns a view of the given length of bytes from the buffer.
/// Fails if there isn't enough enqueued data to satisfy the request.
- (NSData *)peekDataWithLength:(NSUInteger)length;

/// Extracts the given length of bytes from the buffer.
/// Fails if there isn't enough enqueued data to satisfy the request.
- (NSData *)dequeueDataWithLength:(NSUInteger)length;

/// Dequeues the given length of bytes from the buffer, without returning them.
/// Fails if there isn't enough enqueued data to satisfy the request.
- (void)discard:(NSUInteger)length;

/// Extracts the given length of bytes from the buffer, POTENTIALLY WITHOUT COPYING.
/// Fails if there isn't enough enqueued data to satisfy the request.
/// Consider result as invalid if more data is enqueued, because its contents may be overwritten.
- (NSData *)dequeuePotentialyVolatileDataWithLength:(NSUInteger)length;

/// Returns a volatile view of as much upcoming data-to-be-dequeued as possible, WITHOUT COPYING.
/// Consider result as invalid if more data is enqueued, because its contents may be overwritten.
- (NSData *)peekVolatileHeadOfData;

@end
