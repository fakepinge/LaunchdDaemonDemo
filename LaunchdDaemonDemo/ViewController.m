//
//  ViewController.m
//  LaunchdDaemonDemo
//
//  Created by fakepinge on 2023/6/30.
//

#import "ViewController.h"
#import "LaunchdDaemonDemo-Swift.h"

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
}


- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}
- (IBAction)test:(id)sender {
    [[PrivilegedHelperManager shared] checkInstall];
}


@end
