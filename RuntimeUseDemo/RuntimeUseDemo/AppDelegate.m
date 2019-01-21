//
//  AppDelegate.m
//  RuntimeUseDemo
//
//  Created by 苏沫离 on 2019/1/9.
//  Copyright © 2019 苏沫离. All rights reserved.
//

#import "AppDelegate.h"
#import "MainTableViewController.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    [self.window makeKeyAndVisible];
    
    MainTableViewController *mainVC = [[MainTableViewController alloc] initWithStyle:UITableViewStyleGrouped];
    self.window.rootViewController = mainVC;
    
    NSNumber *number =  @(0);
    NSNumber *number1 = @(1);
    NSNumber *number2 = @(2);
    NSNumber *number3 = @(9999999999999999999);
    NSString *string = [[@"a" mutableCopy] copy];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:0];
    
    NSLog(@"number ---- %@, %p", [number class], number);
    NSLog(@"number1 --- %@, %p", [number1 class], number1);
    NSLog(@"number2 --- %@, %p", [number2 class], number2);
    NSLog(@"number3 --- %@, %p", [number3 class], number3);
    NSLog(@"NSString -- %@, %p", [string class], string);
    NSLog(@"indexPath - %@, %p", indexPath.class,indexPath);

    return YES;
}


- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}


- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}


- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}


- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (void)sum:(CGFloat)_total :(CGFloat)_fund :(CGFloat)_special
{
    CGFloat total = _total - _fund - _special - 5000;//税前工资
    CGFloat totalTax = 0.0;
    CGFloat currentTax = 0.0;
    CGFloat total_sum = 0.0;
    NSLog(@"月份 |    该月纳税     |    累计纳税   |   该月净收入     |    累计净收入   |");
    for (int i = 1; i < 13; i ++) {
        
        CGFloat totalX = total * i;
        if (totalX <= 36000) {
            currentTax = totalX * 0.03 - totalTax;
        }else if (totalX <= 144000 ){
            currentTax = totalX * 0.1 - 2520 - totalTax;
        }else if (totalX <= 300000 ){
            currentTax = totalX * 0.2 - 16920 - totalTax;
        }
        totalTax = totalTax + currentTax;
        CGFloat per = total - currentTax + 5000;
        total_sum = total_sum + per;
        NSLog(@" %2d |  %11.2f  | %11.2f  |  %11.2f   |  %11.2f  |",i ,currentTax ,totalTax,per,total_sum);
    }
}

@end
