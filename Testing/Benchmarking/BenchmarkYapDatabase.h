#import <Foundation/Foundation.h>


@interface BenchmarkYapDatabase : NSObject

+ (void)runTestsWithCompletion:(dispatch_block_t)completionBlock;

@end
