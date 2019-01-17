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
    
    
    NSMutableString *muStr2 = [NSMutableString stringWithString:@"1"];
    for(int i=0; i<20; i+=1){
        NSNumber *number = @([muStr2 longLongValue]);
        NSLog(@"NSNumber -- %@, %p", [number class], number);
        [muStr2 appendString:@"1"];
    }
    
    NSString *string = [[@"a" mutableCopy] copy];
    NSLog(@"NSString -- %@, %p", [string class], string);
    
    int int1 = 1;
    long long long1 = 1;
    float float1 = 1.0;
    double double1 = 1.0;
    NSNumber *intNumber1 = @(int1);
    NSNumber *longNumber1 = @(long1);
    NSNumber *floatNumber1 = @(float1);
    NSNumber *doubleNumber1 = @(double1);
    NSLog(@"intNumber1 %p %@", intNumber1, [intNumber1 class]);
    NSLog(@"longNumber1 %p %@", longNumber1, [longNumber1 class]);
    NSLog(@"floatNumber1 %p %@", floatNumber1, [floatNumber1 class]);
    NSLog(@"doubleNumber1 %p %@", doubleNumber1, [doubleNumber1 class]);

    
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


@end
