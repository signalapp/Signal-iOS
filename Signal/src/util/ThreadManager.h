#import <Foundation/Foundation.h>

@interface RunningThreadRunLoopPair : NSObject

@property (nonatomic, readonly) NSThread *thread;
@property (nonatomic, readonly) NSRunLoop *runLoop;

+ (RunningThreadRunLoopPair *)startNewWithThreadName:(NSString *)name;
- (void)terminate;

@end

/**
 *
 * The thread manager is responsible for starting and exposing the low/normal/high latency threads.
 *
 * Low latency:
 * - Includes: Audio encoding/decoding, communicating audio data, advancing zrtp handshake, etc.
 * - Operations on this thread should complete at human-interaction speeds (<30ms) and avoid swamping.
 * - If an operation must be low latency but takes too long, split it into parts that can be interleaved.
 *
 * Normal latency:
 * - Includes: Registration
 * - Operations on this thread should complete at human-reaction speeds (<250ms).
 *
 * High latency:
 * - Includes: DNS CNAME lookup (due to gethostbyname blocking and being non-reentrant and non-threadsafe)
 * - Operations on this thread should complete at human-patience speeds (<10s).
 *
 */

@interface ThreadManager : NSObject {
   @private
    RunningThreadRunLoopPair *low;
   @private
    RunningThreadRunLoopPair *normal;
   @private
    RunningThreadRunLoopPair *high;
}

+ (NSThread *)lowLatencyThread;
+ (NSRunLoop *)lowLatencyThreadRunLoop;

+ (NSThread *)normalLatencyThread;
+ (NSRunLoop *)normalLatencyThreadRunLoop;

+ (NSThread *)highLatencyThread;
+ (NSRunLoop *)highLatencyThreadRunLoop;

+ (void)terminate;

@end
