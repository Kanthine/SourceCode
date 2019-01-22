/*
 * Copyright (c) 2000 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * The contents of this file constitute Original Code as defined in and
 * are subject to the Apple Public Source License Version 1.1 (the
 * "License").  You may not use this file except in compliance with the
 * License.  Please obtain a copy of the License at
 * http://www.apple.com/publicsource and read it before using this file.
 * 
 * This Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
#ifndef _MACHO_LOADER_H_
#define _MACHO_LOADER_H_

/* 编译器：把一种编程语言(原始语言)转换为另一种编程语言(目标语言)的程序叫做编译器
 *
 * 大多数编译器由两部分组成：前端和后端
 *      前端负责词法分析，语法分析，生成中间代码 IR；
 *      后端以中间代码 IR 作为输入，对与架构无关的代码优化，接着针对不同架构生成不同的机器码。
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
 *              动态库(.dylib)，Mach-O 类型的可执行文件，链接的时候只会绑定符号，动态库会被拷贝到app里，运行时加载
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

/* LC_SEGMENT / LC_SEGMENT_64 段的详解（Load command）
 *  常见段：
 *        _PAGEZERO: MH_EXECUTE 格式文件的空指针陷阱段
 *        _TEXT: 程序代码段
 *        __DATA: 程序数据段
 *        __RODATA: read only程序只读数据段
 *        __LINKEDIT: 链接器使用段
 *   段中节详解：
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


/* <mach/machine.h> 用于 cpu_type_t 和 cpu_subtype_t 类型，包含这些类型可能值的常量。
 */
#include <mach/machine.h>

/* <mach/vm_prot.h> 用于 vm_prot_t 类型，包含该类型可能值的常量。
 */
#include <mach/vm_prot.h>

/*
 * <machine/thread_status.h> is expected to define the flavors of the thread states and the structures of those flavors for each machine.
 */
#include <mach/machine/thread_status.h>
#include <architecture/byte_order.h>

/* Mach-O 文件的头部 ：mach_header 出现在目标文件的最开始;对于32位和64位架构都是一样的。
 */
struct mach_header {
    uint32_t	magic;// Mach-O 文件支持设备的CPU位数, 32位 oxFEEDFACE ; 64位xFEEDFACF
	cpu_type_t	cputype;// CPU类型
	cpu_subtype_t	cpusubtype;	// CPU 子类型
    uint32_t	filetype;	//文件类型，比如可执行文件、库文件、Dsym文件;
	uint32_t	ncmds;		//加载命令的数量
	uint32_t	sizeofcmds;	//所有加载命令的大小
	uint32_t	flags;		//dyld 加载所需的标记：MH_PIE 表示启动地址空间布局随机化
};

struct mach_header_64 {
	uint32_t	magic;// Mach-O 文件支持设备的CPU位数
	cpu_type_t	cputype;	// CPU类型
	cpu_subtype_t	cpusubtype;// CPU 子类型
	uint32_t	filetype;	//文件类型，比如可执行文件、库文件、Dsym文件;
	uint32_t	ncmds;		//加载命令的数量
	uint32_t	sizeofcmds;	//所有加载命令的大小
	uint32_t	flags;		//dyld 加载所需的标记：MH_PIE 表示启动地址空间布局随机化
	uint32_t	reserved;	//64 位的保留字段
};

// mach_header(32位) 的 magic 字段的常量
#define	MH_MAGIC	0xfeedface // 表示32位二进制
#define MH_CIGAM	NXSwapInt(MH_MAGIC)

//mach_header_64(64位) 的 magic 字段的常量
#define MH_MAGIC_64	0xfeedfacf //表示64位二进制
#define MH_CIGAM_64	NXSwapInt(MH_MAGIC_64)

// 新加载命令的 cmd 字段的常量
#define LC_SEGMENT_64	0x19 //定义一个段，加载后被映射到内存中，包括里面的节
#define LC_ROUTINES_64	0x1a // 64 位程序


/* 文件的布局取决于文件类型。对于除 MH_OBJECT 文件类型之外的所有文件类型，段被填充并在段对齐边界上对齐，以实现高效的需求分页。
 * MH_EXECUTE、MH_FVMLIB、MH_DYLIB、MH_DYLINKER和MH_BUNDLE文件类型的头文件也包含在它们的第一个段中。
 *
 * 文件类型MH_OBJECT是一种紧凑格式，用作汇编器的输出和链接编辑器的输入(.o格式)。所有节都在一个未命名的段中，没有段填充。当文件很小时，这种格式被用作可执行格式，段填充很大程度上增加了文件的大小。
 *
 * 文件类型MH_PRELOAD是一种可执行格式，用于内核下未执行的内容(proms、stand alones、kernels等)。该格式可以在内核下执行，但可能需要对其进行分页，而不是在执行前预加载。
 *
 * mach_header 的 filetype 字段的常量：
 * MH_DSYM   存储二进制文件符号信息的文件：.dYSM/Contents/Resources/DWARF/MyApp
 */
#define	MH_OBJECT	0x1 //可重定位目标文件：.o文件 .a/.framework静态库
#define	MH_EXECUTE	0x2	//请求分页的可执行文件: app/MyApp ; .out
#define	MH_FVMLIB	0x3 //固定VM共享库文件
#define	MH_CORE		0x4 //核心文件
#define	MH_PRELOAD	0x5 //预加载可执行文件
#define	MH_DYLIB	0x6 //动态库 .framework  .dylib
#define	MH_DYLINKER	0x7	//动态链接器 usr/lib/dyld
#define	MH_BUNDLE	0x8	//动态绑定 Bundle 文件

//mach_header 的 flags 字段的常量
#define	MH_NOUNDEFS	0x1	//目标文件没有未定义的引用，可以执行
#define	MH_INCRLINK	0x2  //目标文件是针对基本文件的增量链接的输出，不能再次链接编辑
#define MH_DYLDLINK	0x4	//目标文件是动态链接器的输入，不能再次静态链接编辑
#define MH_BINDATLOAD	0x8	//加载时，目标文件的未定义引用由动态链接器绑定。
#define MH_PREBOUND	0x10 //该文件具有预先绑定的动态未定义引用。

struct load_command {
	unsigned long cmd;	// load_command 的类型
	unsigned long cmdsize;	 //load_command 的总大小（以字节为单位）
};

// load_command 的类型常量(cmd 的值)
#define	LC_SEGMENT	0x1	//该文件被映射的段
#define	LC_SYMTAB	0x2	//为文件定义符号表和字符串表，在连接文件时被链接器使用，同时也用于调试器映射符号到源文件。符号表定义的本地符号仅用于本地测试，而已定义和未定义的 external 符号被链接器使用
#define	LC_SYMSEG	0x3 //符号表信息，符号表中详细说明了代码中所用符号的信息等(过时)
#define	LC_THREAD	0x4	//线程
#define	LC_UNIXTHREAD	0x5	//unix线程(包括堆栈)
#define	LC_LOADFVMLIB	0x6	//加载指定的固定VM共享库
#define	LC_IDFVMLIB	0x7	//固定VM共享库的标识
#define	LC_IDENT	0x8	//object 标识信息(已过时)
#define LC_FVMFILE	0x9	/* fixed VM file inclusion (internal use) */
#define LC_PREPAGE      0xa     //prepage 命令(内部使用)
#define	LC_DYSYMTAB	0xb	//将符号表中给出符号的额外符号信息提供给动态链接器
#define	LC_LOAD_DYLIB 	0xc	//依赖的动态库，包括动态库名称、当前版本号、兼容版本号，(可以使用 otool -L xxx 命令查看)
#define	LC_ID_DYLIB	0xd	//动态链接共享库的标识
#define LC_LOAD_DYLINKER 0xe //默认的加载器路径
#define LC_ID_DYLINKER	0xf	//动态链接器识别
#define	LC_PREBOUND_DYLIB 0x10	/* modules prebound for a dynamicly */
				/*  链接的共享库 */

/* load_command 中的可变长度字符串由 lc_str 联合类型表示。
 * 字符串存储在load_command之后，偏移量是从load_command结构的开始。
 * 字符串的大小反映在 load_command 的 cmdsize 字段中。
 * 同样，将 cmdsize 字段填充为 sizeof(long) 的倍数的任何字节都必须为零。
 */
union lc_str {
	unsigned long	offset;	//字符串偏移量
	char		*ptr;	//指向字符串的指针
};

/* 段的 load_command 指示将该文件的一部分映射到任务的地址空间。
 * 该段在内存中的大小 vmsize，可能等于或大于这个文件映射的大小 filesize。
 * 该文件从 fileoff 开始映射到内存中 segment 的开头vmaddr。
 * 如果该段还有空余内存，置为 nil。
 * 段的最大虚拟内存保护和初始虚拟内存保护由 maxprot 和 initprot 字段指定。
 * 如果段具有节，则section结构直接遵循segment_command ，其大小反映在cmdsize中。
 */
struct segment_command {// 32 位
	unsigned long	cmd;//load_command结构成员cmd的取值,取值 LC_SEGMENT 将文件中的段映射到进程地址空间
	unsigned long	cmdsize;//load_command结构大小
	char		segname[16];// 16字节的段名字
	unsigned long	vmaddr;	//映射到虚拟地址的偏移
	unsigned long	vmsize; //映射到虚拟地址的大小
	unsigned long	fileoff;//对应于当前架构文件的偏移（注意：是当前架构，不是整个 FAT 文件）
	unsigned long	filesize;//文件大小
	vm_prot_t	maxprot;//段里面的最高内存保护
	vm_prot_t	initprot;//初始内存保护
	unsigned long	nsects;//该段包含的节个数
	unsigned long	flags;//段页面标志
};

/* 64位段的 load_command 指示将该文件的一部分映射到64位任务的地址空间。如果64位段有节，那么section_64结构直接遵循segment_command_64，它们的大小反映在cmdsize中。
 *
 * LC_SEGMENT_64 定义一个64位的段，当文件加载后映射到地址空间（包括段里面节的定义）
 *
 * 系统将 fileoff 偏移处 filesize 大小的内容加载到虚拟内存的 vmaddr 处，大小为 vmsize，段页面的权限由 initprot 进行初始化。它的权限可以动态改变，但不能超过 maxprot 的值，例如 _TEXT 初始化和最大权限都是可读/可执行/不可写
 *
 * 上面的文件包括以下 4 种段：
 * __PAGEZERO  空指针陷阱段，映射到虚拟内存空间的第 1 页，用于捕捉对 NULL 指针的引用
 * __TEXT      代码段/只读数据段
 * __DATA      读取和写入数据的段
 * __LINKEDIT  动态链接器需要使用的信息，包括重定位信息、绑定信息、懒加载信息等
 */
struct segment_command_64 {	/* for 64-bit architectures */
	uint32_t	cmd;//load_command结构成员cmd的取值,取值 LC_SEGMENT 将文件中的段映射到进程地址空间
	uint32_t	cmdsize;//load_command结构大小
	char		segname[16];// 16字节的段名字
	uint64_t	vmaddr;	//映射到虚拟地址的偏移
	uint64_t	vmsize;	//映射到虚拟地址的大小
	uint64_t	fileoff;//对应于当前架构文件的偏移（注意：是当前架构，不是整个 FAT 文件）
	uint64_t	filesize;//文件大小
	vm_prot_t	maxprot;//段里面的最高内存保护
	vm_prot_t	initprot;//初始内存保护
	uint32_t	nsects;//该段包含的节个数
    uint32_t	flags;//段页面标志 : 表示节的标志
};

// segment_command 的 flags 字段的常量
#define	SG_HIGHVM	0x1	//该段的文件内容是VM空间的高内存部分，低内存部分是零填充(对于核心文件中的堆栈)
#define	SG_FVMLIB	0x2	//该段是由固定VM库分配的VM，用于在链接编辑器中进行重叠检查
#define	SG_NORELOC	0x4 // 该段可以在没有重新定位的情况下安全替换

/*
 * 段由零个或多个 section 组成。
 * 非 MH_OBJECT 类型文件的所有段中都有相应的节，并在链接编辑器生成时填充到指定的段对齐。
 * MH_EXECUTE 和 MH_FVMLIB 格式文件的第一个段包含对象填充部分的mach_header和 load_command ，在它们的段中(在所有格式中)总是最后一个。
 * 这允许将零段填充映射到可能为零填充节的内存中；
 * 具有S_GB_ZEROFILL类型的节，只能位于具有这种类型的节的段中。然后将这些段放在所有其他段之后。
 *
 * MH_OBJECT 格式在一个段中具有紧凑性的所有节。指定的段边界没有填充，并且 mach_header 和 load_command 不是段的一部分。
 *
 * 链接编辑器将具有相同节名 sectname 的节组合到相同的段名 segname 中；得到的节与组合节的最大对齐方式对齐，并且是新节的对齐方式。组合节与组合节中的原始对齐对齐。获得指定对齐的任何填充字节都归零。
 *
 * 头文件 <reloc.h> 中描述了mach对象文件的section结构的reloff和nreloc字段引用的重定位项的格式。
 *
 *  段里面可以包含不同的节 Section
 */
struct section {// 32 位
	char		sectname[16];//节的名字
	char		segname[16];//节所在段的名字
	unsigned long	addr;//映射到虚拟地址的偏移
	unsigned long	size;//节的大小
	unsigned long	offset;//节在当前架构文件中的偏移
	unsigned long	align;//节的字节对齐大小 n ，计算结果为 2^n
	unsigned long	reloff;//重定位入口的文件偏移
	unsigned long	nreloc;	//重定位入口的个数
	unsigned long	flags;//节的类型和属性
	unsigned long	reserved1;	//保留位
	unsigned long	reserved2;	//保留位
};

//段里面可以包含不同的节 Section
struct section_64 { // 64 位
	char		sectname[16];//节的名字
	char		segname[16];//节所在段的名字
	uint64_t	addr;//映射到虚拟地址的偏移
	uint64_t	size;//节的大小
	uint32_t	offset;//节在当前架构文件中的偏移
	uint32_t	align;	//节的字节对齐大小 n ，计算结果为 2^n
	uint32_t	reloff;//重定位入口的文件偏移
	uint32_t	nreloc;	//重定位入口的个数
	uint32_t	flags;//节的类型和属性
	uint32_t	reserved1;	//用于偏移量或索引
	uint32_t	reserved2;	//数量或大小
	uint32_t	reserved3;//保留位
};


/* section_64 结构的flags字段分为两个部分:
 * section_64 类型: 类型是互斥的,它只能有一种类型
 * section_64 属性: 可能有多个属性
 */
#define SECTION_TYPE		 0x000000ff	//256 section_64 类型
#define SECTION_ATTRIBUTES	 0xffffff00	//24 section_64 属性

//section_64 类型的常量
#define	S_REGULAR		0x0	//一般的节section_64
#define	S_ZEROFILL		0x1	//使用 0 填充的 section_64
#define	S_CSTRING_LITERALS	0x2	//只有C字符串的节
#define	S_4BYTE_LITERALS	0x3	//只有4字节文字的节
#define	S_8BYTE_LITERALS	0x4	//只有8字节文字的节
#define	S_LITERAL_POINTERS	0x5	//只有指向文字的指针的节

/* 符号指针节和符号stubs节这两种类型，它们有间接符号表项。
 * 间接符号表中节的每个项，按照间接符号表中相应的顺序，从section结构的reserved1字段中存储的索引开始。
 * 由于间接符号表项对应于节中的项，所以间接符号表项的数量是由节的大小除以节中的项得出。
 * 对于符号指针节，节中的项大小为4字节，对于符号stubs节，stubs的大小存储在section结构的reserved2字段中。
 */
#define	S_NON_LAZY_SYMBOL_POINTERS	0x6	// 只有非懒加载符号指针的节
#define	S_LAZY_SYMBOL_POINTERS		0x7	// 只有懒加载符号指针的节
#define	S_SYMBOL_STUBS			0x8 //只有符号stubs的节，reserved2字段中 stub的大小
#define	S_MOD_INIT_FUNC_POINTERS	0x9 //仅用于初始化函数指针的节

/* section_64 结构的flags字段表示属性部分的常量
 */
#define SECTION_ATTRIBUTES_USR	 0xff000000	/* User setable attributes */
#define S_ATTR_PURE_INSTRUCTIONS 0x80000000	/* section contains only true machine instructions */
#define SECTION_ATTRIBUTES_SYS	 0x00ffff00	/* system setable attributes */
#define S_ATTR_SOME_INSTRUCTIONS 0x00000400	/* section contains some machine instructions */
#define S_ATTR_EXT_RELOC	 0x00000200	/* section has external relocation entries */
#define S_ATTR_LOC_RELOC	 0x00000100	/* section has local relocation entries */


/* 段和节的名称对链接编辑器来说几乎没有意义。但是支持传统 UNIX 可执行文件的东西很少，传统 UNIX 可执行文件要求链接编辑器和汇编器使用约定的一些名称。
 *
 * __TEXT 段 不可写
 * 链接编辑器将在 __DATA 段的 __common 节的末尾分配公共符号。如果需要，它将创建节和段。
 */

// 目前已知的段名和这些段中的节名
#define	SEG_PAGEZERO "__PAGEZERO" //pagezero 段没有保护，它捕获 MH_EXECUTE 文件的空引用

#define	SEG_TEXT	"__TEXT" //传统UNIX文本段
#define	SECT_TEXT	"__text" // 文本节的真实文本部分没有headers，也没有填充
#define SECT_FVMLIB_INIT0 "__fvmlib_init0"	//fvmlib初始化节
#define SECT_FVMLIB_INIT1 "__fvmlib_init1"	//fvmlib初始化节之后的节

#define	SEG_DATA	"__DATA"	//传统UNIX数据段
#define	SECT_DATA	"__data" // 真正初始化的数据节没有填充，没有bss重叠
#define	SECT_BSS	"__bss"	 // 真正的未初始化数据节没有填充
#define SECT_COMMON	"__common"	//链接编辑器在节中分配公共符号

#define	SEG_OBJC	"__OBJC"	//objective-C runtime segment
#define SECT_OBJC_SYMBOLS "__symbol_table"	//符号表
#define SECT_OBJC_MODULES "__module_info"	//module 信息
#define SECT_OBJC_STRINGS "__selector_strs"	/* string table */
#define SECT_OBJC_REFS "__selector_refs"	/* string table */

#define	SEG_ICON	 "__ICON"	//icon segment
#define	SECT_ICON_HEADER "__header"	//the icon headers
#define	SECT_ICON_TIFF   "__tiff"	//tiff格式的 icon

#define	SEG_LINKEDIT	"__LINKEDIT" //由链接编辑器创建和维护的所有结构的段，仅为 MH_EXECUTE 和 FVMLIB 类型的文件使用 ld(1) 的- seglinkedit 选项创建

#define SEG_UNIXSTACK	"__UNIXSTACK" //unix堆段

/* 固定虚拟内存共享库有两个标识： 目标路径名(找到要执行的库的名称)和次要版本号。头文件加载的地址在 header_addr 中。
 */
struct fvmlib {
	union lc_str	name; //库的目标路径名
	unsigned long	minor_version;	//库的次要版本号
	unsigned long	header_addr;	//库的头地址
};

/* 一个固定的虚拟共享库(mach_header_64 结构成员 filetype == MH_FVMLIB)包含一个 fvmlib_command (cmd == LC_IDFVMLIB)来标识库。
 * 使用固定虚拟共享库的对象还为其使用的每个库包含 fvmlib_command (cmd == LC_LOADFVMLIB)。
 */
struct fvmlib_command {
	unsigned long	cmd;		//LC_IDFVMLIB 或者 LC_LOADFVMLIB
	unsigned long	cmdsize;	//包括路径名
	struct fvmlib	fvmlib;		//库的标识
};

/*
 *
 * 动态链接的共享库有两个标识。路径名(找到要执行的库的名称)和兼容性版本号。路径名必须匹配，库必须兼容。
 * timestamp 用于记录构建库并将其复制的时间，因此可以使用它来确定运行时使用的库是否与构建程序所用的库完全相同。
 */
struct dylib {
    union lc_str  name;			//路径名
    unsigned long timestamp;    //构建时间
    unsigned long current_version;	//当前版本号
    unsigned long compatibility_version;//兼容的版本号
};

/* 动态链接的共享库(mach_header_64 结构成员 filetype == MH_DYLIB)包含一个 dylib_command (cmd == LC_ID_DYLIB)来标识库。
 * 使用动态链接共享库的对象还为其使用的每个库包含一个 dylib_command (cmd == LC_LOAD_DYLIB)。
 */
struct dylib_command {
	unsigned long	cmd;    //LC_ID_DYLIB or LC_LOAD_DYLIB
	unsigned long	cmdsize;//包括路径名
	struct dylib	dylib;	//库的标识
};

/*
 *
 * 预先绑定到其动态库的程序（filetype == MH_EXECUTE）或bundle（filetype == MH_BUNDLE）具有静态链接器在预绑定中使用的每个库中的一个。
 * 它包含库中modules的位向量。这些位表示哪些modules被绑定（1），哪些不是（0）来自库。
 * modules 0的位是第一个字节的低位。 因此第N个modules块的位是：（linked_modules [N / 8] >> N％8）＆1
 */
struct prebound_dylib_command {
	unsigned long	cmd;		//LC_PREBOUND_DYLIB
	unsigned long	cmdsize;	//includes strings
	union lc_str	name;		//路径名
	unsigned long	nmodules;	//库中的nmodules数
	union lc_str	linked_modules;	//链接nmodules的位向量
};

/* 使用动态链接器的程序包含一个 dylinker_command 来标识动态链接器的名称(LC_LOAD_DYLINKER)。
 * 动态链接器包含一个 dylinker_command 来标识动态链接器(LC_ID_DYLINKER)。
 * 一个文件最多可以包含其中一个。
 */
struct dylinker_command {
	unsigned long	cmd;	//LC_ID_DYLINKER or LC_LOAD_DYLINKER
	unsigned long	cmdsize;//包含路径名
	union lc_str    name;	//路径名
};

/*
 * thread_command 包含适用于线程状态原语的机器特定数据结构。机器特定的数据结构遵循 thread_command 。
 * 机器特定数据结构的每种风格前面都有一个用于该数据结构风格的无符号长常量，一个无符号长整数，它是状态数据结构大小的长整数，然后是状态数据结构。
 * triple 可以重复很多次。
 *
 *
 * The constants for the flavors, counts and state data structure definitions are expected to be in the header file <machine/thread_status.h>.
 * These machine specific data structures sizes must be multiples of sizeof(long).
 * The cmdsize reflects the total size of the thread_command and all of the sizes of the constants for the flavors, counts and state data structures.
 *
 * For executable objects that are unix processes there will be one thread_command (cmd == LC_UNIXTHREAD) created for it by the link-editor.
 * This is the same as a LC_THREAD, except that a stack is automatically created (based on the shell's limit for the stack size).  Command arguments and environment variables are copied onto that stack.
 */
struct thread_command {
	unsigned long	cmd;		/* LC_THREAD or  LC_UNIXTHREAD */
	unsigned long	cmdsize;	/* total size of this command */
	/* unsigned long flavor		   flavor of thread state */
	/* unsigned long count		   count of longs in thread state */
	/* struct XXX_thread_state state   thread state for this flavor */
	/* ... */
};

/*
 * The symtab_command contains the offsets and sizes of the link-edit 4.3BSD
 * "stab" style symbol table information as described in the header files
 * <nlist.h> and <stab.h>.
 */
struct symtab_command {
	unsigned long	cmd;		/* LC_SYMTAB */
	unsigned long	cmdsize;	/* sizeof(struct symtab_command) */
	unsigned long	symoff;		/* symbol table offset */
	unsigned long	nsyms;		/* number of symbol table entries */
	unsigned long	stroff;		/* string table offset */
	unsigned long	strsize;	/* string table size in bytes */
};

/*
 * This is the second set of the symbolic information which is used to support
 * the data structures for the dynamicly link editor.
 *
 * The original set of symbolic information in the symtab_command which contains
 * the symbol and string tables must also be present when this load command is
 * present.  When this load command is present the symbol table is organized
 * into three groups of symbols:
 *	local symbols (static and debugging symbols) - grouped by module
 *	defined external symbols - grouped by module (sorted by name if not lib)
 *	undefined external symbols (sorted by name)
 * In this load command there are offsets and counts to each of the three groups
 * of symbols.
 *
 * This load command contains a the offsets and sizes of the following new
 * symbolic information tables:
 *	table of contents
 *	module table
 *	reference symbol table
 *	indirect symbol table
 * The first three tables above (the table of contents, module table and
 * reference symbol table) are only present if the file is a dynamicly linked
 * shared library.  For executable and object modules, which are files
 * containing only one module, the information that would be in these three
 * tables is determined as follows:
 * 	table of contents - the defined external symbols are sorted by name
 *	module table - the file contains only one module so everything in the
 *		       file is part of the module.
 *	reference symbol table - is the defined and undefined external symbols
 *
 * For dynamicly linked shared library files this load command also contains
 * offsets and sizes to the pool of relocation entries for all sections
 * separated into two groups:
 *	external relocation entries
 *	local relocation entries
 * For executable and object modules the relocation entries continue to hang
 * off the section structures.
 */
struct dysymtab_command {
    unsigned long cmd;		/* LC_DYSYMTAB */
    unsigned long cmdsize;	/* sizeof(struct dysymtab_command) */

    /*
     * The symbols indicated by symoff and nsyms of the LC_SYMTAB load command
     * are grouped into the following three groups:
     *    local symbols (further grouped by the module they are from)
     *    defined external symbols (further grouped by the module they are from)
     *    undefined symbols
     *
     * The local symbols are used only for debugging.  The dynamic binding
     * process may have to use them to indicate to the debugger the local
     * symbols for a module that is being bound.
     *
     * The last two groups are used by the dynamic binding process to do the
     * binding (indirectly through the module table and the reference symbol
     * table when this is a dynamicly linked shared library file).
     */
    unsigned long ilocalsym;	/* index to local symbols */
    unsigned long nlocalsym;	/* number of local symbols */

    unsigned long iextdefsym;	/* index to externally defined symbols */
    unsigned long nextdefsym;	/* number of externally defined symbols */

    unsigned long iundefsym;	/* index to undefined symbols */
    unsigned long nundefsym;	/* number of undefined symbols */

    /*
     * For the for the dynamic binding process to find which module a symbol
     * is defined in the table of contents is used (analogous to the ranlib
     * structure in an archive) which maps defined external symbols to modules
     * they are defined in.  This exists only in a dynamicly linked shared
     * library file.  For executable and object modules the defined external
     * symbols are sorted by name and is use as the table of contents.
     */
    unsigned long tocoff;	/* file offset to table of contents */
    unsigned long ntoc;		/* number of entries in table of contents */

    /*
     * To support dynamic binding of "modules" (whole object files) the symbol
     * table must reflect the modules that the file was created from.  This is
     * done by having a module table that has indexes and counts into the merged
     * tables for each module.  The module structure that these two entries
     * refer to is described below.  This exists only in a dynamicly linked
     * shared library file.  For executable and object modules the file only
     * contains one module so everything in the file belongs to the module.
     */
    unsigned long modtaboff;	/* file offset to module table */
    unsigned long nmodtab;	/* number of module table entries */

    /*
     * To support dynamic module binding the module structure for each module
     * indicates the external references (defined and undefined) each module
     * makes.  For each module there is an offset and a count into the
     * reference symbol table for the symbols that the module references.
     * This exists only in a dynamicly linked shared library file.  For
     * executable and object modules the defined external symbols and the
     * undefined external symbols indicates the external references.
     */
    unsigned long extrefsymoff;  /* offset to referenced symbol table */
    unsigned long nextrefsyms;	 /* number of referenced symbol table entries */

    /*
     * The sections that contain "symbol pointers" and "routine stubs" have
     * indexes and (implied counts based on the size of the section and fixed
     * size of the entry) into the "indirect symbol" table for each pointer
     * and stub.  For every section of these two types the index into the
     * indirect symbol table is stored in the section header in the field
     * reserved1.  An indirect symbol table entry is simply a 32bit index into
     * the symbol table to the symbol that the pointer or stub is referring to.
     * The indirect symbol table is ordered to match the entries in the section.
     */
    unsigned long indirectsymoff; /* file offset to the indirect symbol table */
    unsigned long nindirectsyms;  /* number of indirect symbol table entries */

    /*
     * To support relocating an individual module in a library file quickly the
     * external relocation entries for each module in the library need to be
     * accessed efficiently.  Since the relocation entries can't be accessed
     * through the section headers for a library file they are separated into
     * groups of local and external entries further grouped by module.  In this
     * case the presents of this load command who's extreloff, nextrel,
     * locreloff and nlocrel fields are non-zero indicates that the relocation
     * entries of non-merged sections are not referenced through the section
     * structures (and the reloff and nreloc fields in the section headers are
     * set to zero).
     *
     * Since the relocation entries are not accessed through the section headers
     * this requires the r_address field to be something other than a section
     * offset to identify the item to be relocated.  In this case r_address is
     * set to the offset from the vmaddr of the first LC_SEGMENT command.
     *
     * The relocation entries are grouped by module and the module table
     * entries have indexes and counts into them for the group of external
     * relocation entries for that the module.
     *
     * For sections that are merged across modules there must not be any
     * remaining external relocation entries for them (for merged sections
     * remaining relocation entries must be local).
     */
    unsigned long extreloff;	/* offset to external relocation entries */
    unsigned long nextrel;	/* number of external relocation entries */

    /*
     * All the local relocation entries are grouped together (they are not
     * grouped by their module since they are only used if the object is moved
     * from it staticly link edited address).
     */
    unsigned long locreloff;	/* offset to local relocation entries */
    unsigned long nlocrel;	/* number of local relocation entries */

};	

/*
 * An indirect symbol table entry is simply a 32bit index into the symbol table 
 * to the symbol that the pointer or stub is refering to.  Unless it is for a
 * non-lazy symbol pointer section for a defined symbol which strip(1) as 
 * removed.  In which case it has the value INDIRECT_SYMBOL_LOCAL.  If the
 * symbol was also absolute INDIRECT_SYMBOL_ABS is or'ed with that.
 */
#define INDIRECT_SYMBOL_LOCAL	0x80000000
#define INDIRECT_SYMBOL_ABS	0x40000000


/* a table of contents entry */
struct dylib_table_of_contents {
    unsigned long symbol_index;	/* the defined external symbol
				   (index into the symbol table) */
    unsigned long module_index;	/* index into the module table this symbol
				   is defined in */
};	

/* a module table entry */
struct dylib_module {
    unsigned long module_name;	/* the module name (index into string table) */

    unsigned long iextdefsym;	/* index into externally defined symbols */
    unsigned long nextdefsym;	/* number of externally defined symbols */
    unsigned long irefsym;		/* index into reference symbol table */
    unsigned long nrefsym;	/* number of reference symbol table entries */
    unsigned long ilocalsym;	/* index into symbols for local symbols */
    unsigned long nlocalsym;	/* number of local symbols */

    unsigned long iextrel;	/* index into external relocation entries */
    unsigned long nextrel;	/* number of external relocation entries */

    unsigned long iinit;	/* index into the init section */
    unsigned long ninit;	/* number of init section entries */

    unsigned long		/* for this module address of the start of */
	objc_module_info_addr;  /*  the (__OBJC,__module_info) section */
    unsigned long		/* for this module size of */
	objc_module_info_size;	/*  the (__OBJC,__module_info) section */
};	

/* a 64-bit module table entry */
struct dylib_module_64 {
	uint32_t module_name;	/* the module name (index into string table) */

	uint32_t iextdefsym;	/* index into externally defined symbols */
	uint32_t nextdefsym;	/* number of externally defined symbols */
	uint32_t irefsym;	/* index into reference symbol table */
	uint32_t nrefsym;	/* number of reference symbol table entries */
	uint32_t ilocalsym;	/* index into symbols for local symbols */
	uint32_t nlocalsym;	/* number of local symbols */

	uint32_t iextrel;	/* index into external relocation entries */
	uint32_t nextrel;	/* number of external relocation entries */

	uint32_t iinit_iterm;	/* low 16 bits are the index into the init
				   section, high 16 bits are the index into
				   the term section */
	uint32_t ninit_nterm;	/* low 16 bits are the number of init section
				   entries, high 16 bits are the number of
				   term section entries */

	uint32_t		/* for this module size of the */
		objc_module_info_size;	/* (__OBJC,__module_info) section */
	uint64_t		/* for this module address of the start of */
		objc_module_info_addr;	/* the (__OBJC,__module_info) section */
};


/* 
 * The entries in the reference symbol table are used when loading the module
 * (both by the static and dynamic link editors) and if the module is unloaded
 * or replaced.  Therefore all external symbols (defined and undefined) are
 * listed in the module's reference table.  The flags describe the type of
 * reference that is being made.  The constants for the flags are defined in
 * <mach-o/nlist.h> as they are also used for symbol table entries.
 */
struct dylib_reference {
    unsigned long isym:24,	/* index into the symbol table */
    		  flags:8;	/* flags to indicate the type of reference */
};

/*
 * The symseg_command contains the offset and size of the GNU style
 * symbol table information as described in the header file <symseg.h>.
 * The symbol roots of the symbol segments must also be aligned properly
 * in the file.  So the requirement of keeping the offsets aligned to a
 * multiple of a sizeof(long) translates to the length field of the symbol
 * roots also being a multiple of a long.  Also the padding must again be
 * zeroed. (THIS IS OBSOLETE and no longer supported).
 */
struct symseg_command {
	unsigned long	cmd;		/* LC_SYMSEG */
	unsigned long	cmdsize;	/* sizeof(struct symseg_command) */
	unsigned long	offset;		/* symbol segment offset */
	unsigned long	size;		/* symbol segment size in bytes */
};

/*
 * The ident_command contains a free format string table following the
 * ident_command structure.  The strings are null terminated and the size of
 * the command is padded out with zero bytes to a multiple of sizeof(long).
 * (THIS IS OBSOLETE and no longer supported).
 */
struct ident_command {
	unsigned long cmd;		/* LC_IDENT */
	unsigned long cmdsize;		/* strings that follow this command */
};

/*
 * The fvmfile_command contains a reference to a file to be loaded at the
 * specified virtual address.  (Presently, this command is reserved for NeXT
 * internal use.  The kernel ignores this command when loading a program into
 * memory).
 */
struct fvmfile_command {
	unsigned long cmd;		/* LC_FVMFILE */
	unsigned long cmdsize;		/* includes pathname string */
	union lc_str	name;		/* files pathname */
	unsigned long	header_addr;	/* files virtual address */
};

#endif /* _MACHO_LOADER_H_ */
