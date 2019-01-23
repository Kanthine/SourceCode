/* 编译器：把一种编程语言(原始语言)转换为另一种编程语言(目标语言)的程序叫做编译器
 *
 * 大多数编译器由两部分组成：前端和后端
 *      前端负责词法分析，语法分析，生成中间代码 IR；
 *      后端以中间代码 IR 作为输入，进行行架构无关的代码优化，接着针对不同架构生成不同的机器码。
 * 前后端依赖统一格式的中间代码(IR)，使得前后端可以独立的变化。新增一门语言只需要修改前端，而新增一个CPU架构只需要修改后端即可。
 *
 * 注：Objective-C/C/C++使用的编译器前端是 clang，swift是swift，后端都是 LLVM。
 *
 * 从前端到后端 .m文件 编译的大致流程：
 * .m文件 -> 预处理器 -> 词法分析 -> 语法分析 -> CodeGen -> IR -> LLVM Optimizer -> 汇编器（.o）-> linker -> Mach-O 文件
 * 1、预处理器：预处理会替进行头文件引入，宏替换，注释处理，条件编译(#ifdef)等操作。
 * 2、词法分析：词法分析器读入源文件的字符流，将他们组织称有意义的词素(lexeme)序列，对于每个词素，此法分析器产生词法单元（token）作为输出。
 * 3、语法分析：词法分析的Token流会被解析成一颗抽象语法树(abstract syntax tree - AST)。有了抽象语法树，clang就可以对这个树进行分析，找出代码中的错误。比如类型不匹配，亦或Objective-C中向target发送了一个未实现的消息。
 * 4、CodeGen：CodeGen遍历语法树，生成LLVM IR代码。LLVM IR是前端的输出，后端的输入。
 *            Objective-C代码在这一步会进行runtime的桥接：property合成，ARC处理等。
 * 5、生成汇编代码：LLVM对IR进行优化后，会针对不同架构生成不同的目标代码，最后以汇编代码的格式输出：
 * 6、汇编器：汇编器以汇编代码作为输入，将汇编代码转换为机器代码，最后输出目标文件(object file)。
 * 7、链接：链接器会把编译器编译生成的多个文件（.o文件 .dylib文件 .a文件 .tbd文件等）链接成一个可执行文件 Mach-O。链接并不会产生新的代码，只是在现有代码的基础上做移动和补丁。
 *       链接器的输入可能是以下几种文件：
 *              object file(.o)，单个源文件的编辑结果，包含了由符号表示的代码和数据。
 *              动态库(.dylib)，mach o类型的可执行文件，链接的时候只会绑定符号，动态库会被拷贝到app里，运行时加载
 *              静态库(.a)，由ar命令打包的一组.o文件，链接的时候会把具体的代码拷贝到最后的Mach-O
 *              tbd，只包含符号 Symbols 的库文件
 *
 *
 * XCode编译的详细的步骤如下：
 * 创建Product.app的文件夹
 * 把Entitlements.plist写入到DerivedData里，处理打包的时候需要的信息（比如application-identifier）。
 * 创建一些辅助文件，比如各种.hmap，这是headermap文件，具体作用下文会讲解。
 * 执行CocoaPods的编译前脚本：检查Manifest.lock文件。
 * 编译.m文件，生成.o文件。
 * 链接动态库，.o文件，生成一个Mach-O格式的可执行文件。
 * 编译assets，编译storyboard，链接storyboard
 * 拷贝动态库Logger.framework，并且对其签名
 * 执行CocoaPods编译后脚本：拷贝CocoaPods Target生成的Framework
 * 对Demo.App签名，并验证（validate）
 * 生成Product.app
 */

/*
 *
 * LC_SEGMENT / LC_SEGMENT_64段的详解（Load command）
 *  常见段：
 *        _PAGEZERO: 空指针陷阱段
 *        _TEXT: 程序代码段
 *        __DATA: 程序数据段
 *        __RODATA: read only程序只读数据段
 *        __LINKEDIT: 链接器使用段
 *   段中区section详解：
 *       __text: 主程序代码
 *       __stubs, __stub_helper: 用于动态链接的桩
 *       __cstring: 程序中c语言字符串
 *       __const: 常量
 *       __RODATA,__objc_methname: OC方法名称
 *       __RODATA,__objc_methntype: OC方法类型
 *       __RODATA,__objc_classname: OC类名
 *       __DATA,__objc_classlist: OC类列表
 *       __DATA,__objc_protollist: OC原型列表
 *       __DATA,__objc_imageinfo: OC镜像信息
 *       __DATA,__objc_const: OC常量
 *       __DATA,__objc_selfrefs: OC类自引用(self)
 *       __DATA,__objc_superrefs: OC类超类引用(super)
 *       __DATA,__objc_protolrefs: OC原型引用
 *       __DATA, __bss: 没有初始化和初始化为0 的全局变量
 */


#if __OBJC2__

#include "objc-private.h"
#include "objc-file.h"


/* Mach-O 程序的 Runtime 接口：getsectiondata() 函数从 Mach-O 文件获取某个区段数据
 * @param mhp 头信息，文件类型, 目标架构
 * @param segname 段名
 * @param sectname 段中区的名称
 * @param size 函数内部赋值所获取数据的字节数
 * @return uint8_t 返回的数据
 */

/* 获取 __DATA区段 或 __DATA_CONST区段 或 __DATA_DIRTY区段 的指定数据
 * @param mhp 头信息，文件类型, 目标架构
 * @param sectname 段中区的名称
 * @param outCount 获取列表中元素的数量
 */
template <typename T> T* getDataSection(const headerType *mhdr, const char *sectname,
                  size_t *outBytes, size_t *outCount){
    unsigned long byteCount = 0;//所获取数据的字节数
    T* data = (T*)getsectiondata(mhdr, "__DATA", sectname, &byteCount);//首先从程序数据段获取数据
    if (!data) {
        data = (T*)getsectiondata(mhdr, "__DATA_CONST", sectname, &byteCount);
    }
    if (!data) {
        data = (T*)getsectiondata(mhdr, "__DATA_DIRTY", sectname, &byteCount);
    }
    if (outBytes) *outBytes = byteCount;
    
    //列表中元素的数量 = 所获取数据的字节数 / sizeof(T)
    if (outCount) *outCount = byteCount / sizeof(T);
    return data;
}

//宏函数：用于获取 Mach-O 文件的某些数据
#define GETSECT(name, type, sectname)                                   \
    type *name(const headerType *mhdr, size_t *outCount) {              \
        return getDataSection<type>(mhdr, sectname, nil, outCount);     \
    }                                                                   \
    type *name(const header_info *hi, size_t *outCount) {               \
        return getDataSection<type>(hi->mhdr(), sectname, nil, outCount); \
    }

//          函数名字                 函数返回值类型            section name
GETSECT(_getObjc2SelectorRefs,        SEL,             "__objc_selrefs"); //获取哪些SEL对应的字符串被引用
GETSECT(_getObjc2MessageRefs,         message_ref_t,   "__objc_msgrefs"); //
GETSECT(_getObjc2ClassRefs,           Class,           "__objc_classrefs");//获取被引用的 OC 类
GETSECT(_getObjc2SuperRefs,           Class,           "__objc_superrefs");//获取被引用的 OC 类的父类
GETSECT(_getObjc2ClassList,           classref_t,      "__objc_classlist");//获取所有的Class
GETSECT(_getObjc2NonlazyClassList,    classref_t,      "__objc_nlclslist");//获取非懒加载的所有的类的列表
GETSECT(_getObjc2CategoryList,        category_t *,    "__objc_catlist");//获取所有的 category
GETSECT(_getObjc2NonlazyCategoryList, category_t *,    "__objc_nlcatlist");//获取非懒加载的所有的分类的列表
GETSECT(_getObjc2ProtocolList,        protocol_t *,    "__objc_protolist");//获取所有的 Protocol
GETSECT(_getObjc2ProtocolRefs,        protocol_t *,    "__objc_protorefs");//OC 协议引用
GETSECT(getLibobjcInitializers,       UnsignedInitializer, "__objc_init_func");


objc_image_info *_getObjcImageInfo(const headerType *mhdr, size_t *outBytes){
    //__objc_imageinfo OC镜像信息
    return getDataSection<objc_image_info>(mhdr, "__objc_imageinfo", outBytes, nil);
}

// Look for an __objc* section other than __objc_imageinfo
static bool segmentHasObjcContents(const segmentType *seg)
{
    for (uint32_t i = 0; i < seg->nsects; i++) {
        const sectionType *sect = ((const sectionType *)(seg+1))+i;
        if (sectnameStartsWith(sect->sectname, "__objc_")  &&
            !sectnameEquals(sect->sectname, "__objc_imageinfo"))
        {
            return true;
        }
    }

    return false;
}

// Look for an __objc* section other than __objc_imageinfo
bool
_hasObjcContents(const header_info *hi)
{
    bool foundObjC = false;

    foreach_data_segment(hi->mhdr(), [&](const segmentType *seg, intptr_t slide)
    {
        if (segmentHasObjcContents(seg)) foundObjC = true;
    });

    return foundObjC;
    
}


// OBJC2
#endif
