//
//  main.m
//  YLTest
//
//  Created by long on 2021/2/3.
//

#import <Foundation/Foundation.h>






void taggedPointerTest(void){
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
}




int main(int argc, const char * argv[]) {
    @autoreleasepool {
        taggedPointerTest();
    }
    return 0;
}
