//
//  MainTableViewController.m
//  RuntimeUseDemo
//
//  Created by 苏沫离 on 2019/1/9.
//  Copyright © 2019 苏沫离. All rights reserved.
//

#define CellIdentifer @"UITableViewCell"
#define HeaderIdentifer @"UITableViewHeaderFooterView"

#import "MainTableViewController.h"
#import "SonModel.h"

@interface MainTableViewController ()
@property (nonatomic ,strong) NSMutableArray<NSArray<NSString *> *> *daraArray;
@end

@implementation MainTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:CellIdentifer];
    [self.tableView registerClass:UITableViewHeaderFooterView.class forHeaderFooterViewReuseIdentifier:HeaderIdentifer];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.daraArray.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.daraArray[section].count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section{
    UITableViewHeaderFooterView *headerView = [tableView dequeueReusableHeaderFooterViewWithIdentifier:HeaderIdentifer];
    headerView.textLabel.text = @"Class";
    return headerView;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifer forIndexPath:indexPath];
    cell.textLabel.text = self.daraArray[indexPath.section][indexPath.row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *title = self.daraArray[indexPath.section][indexPath.row];
    
    if ([title isEqualToString:@"objc_getClass"]) {
        [FatherModel getClassWithName:@"SonModel_"];
    }else if ([title isEqualToString:@"objc_lookUpClass"]){
        [FatherModel lookUpClassWithName:@"SonModel_"];
    }else if ([title isEqualToString:@"objc_getRequiredClass"]){
        [FatherModel getRequiredClassWithName:@"SonModel_"];
    }else if ([title isEqualToString:@"objc_getClassList"]){
        [FatherModel getClassList];
    }else if ([title isEqualToString:@"objc_getMetaClass"]){
        [FatherModel getMetaClassWithName:@"SonModel"];
        [FatherModel getMetaClassWithName:@"SonModel_"];
    }else if ([title isEqualToString:@"objc_copyClassList"]){
        [FatherModel getAllRegisterClass];
    }else if ([title isEqualToString:@"获取指定数量的已注册类"]){
        [FatherModel getRandomClassListWithCount:9];
    }else if ([title isEqualToString:@"获取指定类的所有子类"]){
        [FatherModel getAllSubclassWithSupercalss:self.superclass];
    }else if ([title isEqualToString:@"class_getInstanceVariable"]){
        [FatherModel class_getInstanceVariable:@"_height"];
        [SonModel class_getInstanceVariable:@"_height"];
    }else if ([title isEqualToString:@"class_getClassVariable"]){
        [FatherModel class_getClassVariable:@"className"];
        [SonModel class_getClassVariable:@"classAge"];
    }else if ([title isEqualToString:@"class_copyIvarList"]){
        [FatherModel getAllIvarList];
        [SonModel getAllIvarList];
    }else if ([title isEqualToString:@""]){
    }else if ([title isEqualToString:@""]){
    }else if ([title isEqualToString:@""]){
    }else if ([title isEqualToString:@""]){
    }
}

- (NSMutableArray<NSArray<NSString *> *> *)daraArray{
    if (_daraArray == nil) {
        _daraArray = [NSMutableArray array];
        [_daraArray addObject:@[@"objc_getClass",@"objc_lookUpClass",
                                @"objc_getRequiredClass",@"objc_getMetaClass",
                                @"objc_getClassList",@"objc_copyClassList",
                                @"获取指定数量的已注册类",@"获取指定类的所有子类"]];
        [_daraArray addObject:@[@"class_getInstanceVariable",
                                @"class_getClassVariable",
                                @"class_copyIvarList"]];
    }
    return _daraArray;
}

@end
