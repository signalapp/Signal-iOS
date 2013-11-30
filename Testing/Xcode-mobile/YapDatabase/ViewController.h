//
//  ViewController.h
//  YapDatabase
//
//  Created by Robbie Hanson on 12/8/12.
//  Copyright (c) 2012 Robbie Hanson. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController

@property (nonatomic, strong, readwrite) IBOutlet UIButton *yapDatabaseBenchmarksButton;
@property (nonatomic, strong, readwrite) IBOutlet UIButton *cacheBenchmarksButton;

- (IBAction)runYapDatabaseBenchmarks;
- (IBAction)runCacheBenchmarks;

@end
