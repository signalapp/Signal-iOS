//
//  LogSubmit.m
//  Signal
//
//  Created by Frederic Jacobs on 02/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "LogSubmit.h"
#import "AppDelegate.h"
#include <sys/types.h>
#include <sys/sysctl.h>

@interface LogSubmit ()


@property (nonatomic, copy)successBlock block;

@end

@implementation LogSubmit

+(void)submitLogsWithCompletion:(successBlock)block{
    AppDelegate *delegate = [[UIApplication sharedApplication]delegate];
    
    NSArray *fileNames = delegate.fileLogger.logFileManager.sortedLogFileNames;
    NSArray *filePaths = delegate.fileLogger.logFileManager.sortedLogFilePaths;
    
    NSMutableDictionary *gistFiles = [@{} mutableCopy];
    
    for (unsigned int i = 0; i < [filePaths count]; i++) {
        [gistFiles setObject:@{@"content":[NSString stringWithContentsOfFile:[filePaths objectAtIndex:i] encoding:NSUTF8StringEncoding error:nil]} forKey:[fileNames objectAtIndex:i]];
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
    static LogSubmit *sharedMyManager = nil;
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
        self.block(true, [dict objectForKey:@"html_url"]);
    } else{
        DDLogError(@"Error on debug response: %@", error);
        self.block(false, nil);
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error{
    DDLogError(@"Uploading logs failed with error: %@", error);
    self.block(false,nil);
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response{
    
    NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
    
    if ( [httpResponse statusCode] != 201) {
        DDLogError(@"Failed to submit debug log: %@", httpResponse.debugDescription);
        self.block(false,nil);
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
