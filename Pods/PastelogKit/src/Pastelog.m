//
//  LogSubmit.m
//  Signal
//
//  Created by Frederic Jacobs on 02/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "Pastelog.h"
#include <sys/types.h>
#include <sys/sysctl.h>

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

@interface Pastelog ()

@property (nonatomic)NSMutableData *responseData;
@property (nonatomic, copy)successBlock block;

@end

@implementation Pastelog

+(void)submitLogsWithCompletion:(successBlock)block{
  [self submitLogsWithCompletion:(successBlock)block forFileLogger:[[DDFileLogger alloc] init]];
}

+(void)submitLogsWithCompletion:(successBlock)block forFileLogger:(DDFileLogger*)fileLogger{

    NSArray *fileNames = fileLogger.logFileManager.sortedLogFileNames;
    NSArray *filePaths = fileLogger.logFileManager.sortedLogFilePaths;

    NSMutableDictionary *gistFiles = [@{} mutableCopy];

    NSError *error;

    for (unsigned int i = 0; i < [filePaths count]; i++) {
        [gistFiles setObject:@{@"content":[NSString stringWithContentsOfFile:[filePaths objectAtIndex:i] encoding:NSUTF8StringEncoding error:&error]} forKey:[fileNames objectAtIndex:i]];
    }

    if (error) {
    }

    NSDictionary *gistDict = @{@"description":[self gistDescription], @"files":gistFiles};

    NSData *postData = [NSJSONSerialization dataWithJSONObject:gistDict options:0 error:nil];

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[[NSURL alloc] initWithString:@"https://api.github.com/gists"] cachePolicy:NSURLCacheStorageNotAllowed timeoutInterval:30];

    [[self sharedManager] setResponseData:[NSMutableData data]];
    [[self sharedManager] setBlock:block];

    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:postData];

    NSURLConnection *connection = [NSURLConnection connectionWithRequest:request delegate:[self sharedManager]];

    [connection start];

}

+ (id)sharedManager {
    static Pastelog *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] init];
    });
    return sharedMyManager;
}

- (id)init {
    if (self = [super init]) {
        self.responseData = [NSMutableData data];
    }
    return self;
}

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data{
    [self.responseData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection{
    NSError *error;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:self.responseData options:0 error:&error];
    if (!error) {
        self.block(nil, [dict objectForKey:@"html_url"]);
    } else{
        DDLogError(@"Error on debug response: %@", error);
        self.block(error, nil);
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error{
    DDLogError(@"Uploading logs failed with error: %@", error);
    self.block(error,nil);
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response{

    NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;

    if ( [httpResponse statusCode] != 201) {
        DDLogError(@"Failed to submit debug log: %@", httpResponse.debugDescription);
        self.block([NSError errorWithDomain:@"PastelogKit" code:10001 userInfo:@{}],nil);
    }
}

+(NSString*)gistDescription{
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *platform = [NSString stringWithUTF8String:machine];
    free(machine);

    NSString *gistDesc = [NSString stringWithFormat:@"iPhone Version: %@, iOS Version: %@", platform,[UIDevice currentDevice].systemVersion];

    return gistDesc;
}

@end
