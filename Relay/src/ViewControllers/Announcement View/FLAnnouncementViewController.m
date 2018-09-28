//
//  FLAnnouncementViewController.m
//  Forsta
//
//  Created by Mark Descalzo on 1/29/18.
//  Copyright © 2018 Forsta. All rights reserved.
//

@import WebKit;

#import "FLAnnouncementViewController.h"
#import "TSThread.h"
#import "TSIncomingMessage.h"
#import "TSDatabaseView.h"
#import "AnnouncementDetailViewController.h"

@interface FLAnnouncementViewController ()

@property (weak, nonatomic) IBOutlet UIView *titleContainerView;
@property (weak, nonatomic) IBOutlet UILabel *announcementTitleLabel;
@property (weak, nonatomic) IBOutlet UIScrollView *bodyContainerScrollView;
@property (weak, nonatomic) IBOutlet UIView *bodyContainerView;
@property (weak, nonatomic) IBOutlet UILabel *announcementBodyLabel;

@property (strong, nonatomic) TSMessage *announcementMessage;
@property (strong, nonatomic) NSString *htmlBodyString;
@property (strong, nonatomic) YapDatabaseConnection *dbConnection;

@property (nonatomic, strong) UIButton *infoButton;

@end

@implementation FLAnnouncementViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    UIBarButtonItem *infoItem = [[UIBarButtonItem alloc] initWithCustomView:self.infoButton];
    self.navigationItem.rightBarButtonItems = [NSArray arrayWithObject:infoItem];

    self.bodyContainerView.layer.masksToBounds = NO;
    self.bodyContainerView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.bodyContainerView.layer.shadowOffset = CGSizeMake(0.0f, 0.0f);
    self.bodyContainerView.layer.shadowOpacity = 0.5f;
    
    self.titleContainerView.layer.masksToBounds = NO;
    self.titleContainerView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.titleContainerView.layer.shadowOffset = CGSizeMake(0.0f, 0.0f);
    self.titleContainerView.layer.shadowOpacity = 0.5f;
}

-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self configureWithThread];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.thread markAllAsRead];
    });
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)configureWithThread
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.thread) {
            self.announcementTitleLabel.text = self.thread.displayName;
            self.announcementBodyLabel.attributedText = self.announcementMessage.attributedTextBody;
            [self updateTheShadows];
        }
    });
}

-(void)updateTheShadows
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.view bringSubviewToFront:self.titleContainerView];
        UIBezierPath *bodyShadowPath = [UIBezierPath bezierPathWithRect:self.titleContainerView.bounds];
        self.titleContainerView.layer.shadowPath = bodyShadowPath.CGPath;
        UIBezierPath *titleShadowPath = [UIBezierPath bezierPathWithRect:self.titleContainerView.bounds];
        self.titleContainerView.layer.shadowPath = titleShadowPath.CGPath;
    });
    
}


#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"showAnnouncementDetailSegue"]) {
        AnnouncementDetailViewController *destination = (AnnouncementDetailViewController *)segue.destinationViewController;
        destination.message = self.announcementMessage;
    }
}


-(void)didTapInfoButton
{
    [self performSegueWithIdentifier:@"showAnnouncementDetailSegue" sender:self];
}

-(void)setThread:(TSThread *)thread
{
    if (thread.uniqueId.length > 0) {
        _thread = thread;
        [self configureWithThread];
    }
}

-(TSMessage *)announcementMessage
{
        __block TSInteraction *last;
        [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
            last = [[transaction ext:TSMessageDatabaseViewExtensionName] lastObjectInGroup:self.thread.uniqueId];
        }];
        return (TSMessage *)last;

}

-(UIButton *)infoButton
{
    if (_infoButton == nil) {
        _infoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
        [_infoButton addTarget:self action:@selector(didTapInfoButton) forControlEvents:UIControlEventTouchUpInside];
    }
    return _infoButton;
}

-(YapDatabaseConnection *)dbConnection
{
    if (_dbConnection == nil) {
        _dbConnection = [TSStorageManager.sharedManager.database newConnection];
    }
    return _dbConnection;
}

@end
