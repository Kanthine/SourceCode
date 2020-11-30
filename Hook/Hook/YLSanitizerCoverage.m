//
//  YLSanitizerCoverage.m
//  Hook
//
//  Created by 苏沫离 on 2020/11/30.
//

#import "YLSanitizerCoverage.h"
#import <dlfcn.h>
#import <libkern/OSAtomic.h>


@implementation YLSanitizerCoverage


void __sanitizer_cov_trace_pc_guard_init(uint32_t *start,uint32_t *stop) {
    static uint32_t N;  // Counter for the guards.
    if (start == stop || *start) return;  // Initialize only once.
    printf("INIT: %p %p\n", start, stop);
    for (uint32_t *x = start; x < stop; x++)
        *x = ++N;// Guards should start from 1.
}

+ (void)getDataOrder{
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"data.order"];
    [YLSanitizerCoverage getDataOrderFilePath:filePath];
}

+ (void)getDataOrderFilePath:(NSString *)filePath{
    NSMutableArray<NSString *> * symbolNames = [NSMutableArray array];
    while (true) {
        //offsetof 就是针对某个结构体找到某个属性相对这个结构体的偏移量
        SymbolNode * node = OSAtomicDequeue(&symboList, offsetof(SymbolNode, next));
        if (node == NULL) break;
        Dl_info info;
        dladdr(node->pc, &info);
         
        NSString * name = @(info.dli_sname);
         
        // 添加 _
        BOOL isObjc = [name hasPrefix:@"+["] || [name hasPrefix:@"-["];
        NSString * symbolName = isObjc ? name : [@"_" stringByAppendingString:name];
         
        //去重
        if (![symbolNames containsObject:symbolName]) {
            [symbolNames addObject:symbolName];
        }
    }
    
    //取反
    NSArray * symbolAry = [[symbolNames reverseObjectEnumerator] allObjects];
    NSLog(@"%@",symbolAry);
     
    //将结果写入到文件
    NSString * funcString = [symbolAry componentsJoinedByString:@"\n"];
    NSData * fileContents = [funcString dataUsingEncoding:NSUTF8StringEncoding];
    BOOL result = [[NSFileManager defaultManager] createFileAtPath:filePath contents:fileContents attributes:nil];
    if (result) {
        NSLog(@".order filePath ===== %@",filePath);
    }else{
        NSLog(@".order 文件写入出错");
    }
}



//原子队列
static OSQueueHead symboList = OS_ATOMIC_QUEUE_INIT;
//定义符号结构体
typedef struct{
    void * pc;
    void * next;
}SymbolNode;
 
void __sanitizer_cov_trace_pc_guard(uint32_t *guard) {
    //if (!*guard) return;  // Duplicate the guard check.
    void *PC = __builtin_return_address(0);
    SymbolNode * node = malloc(sizeof(SymbolNode));
    *node = (SymbolNode){PC,NULL};
    //入队
    // offsetof 用在这里是为了入队添加下一个节点找到 前一个节点next指针的位置
    OSAtomicEnqueue(&symboList, node, offsetof(SymbolNode, next));
    
    Dl_info info;
    dladdr(node->pc, &info);
    NSString *name = @(info.dli_sname);
    NSLog(@"name==%@",name);
}



@end
