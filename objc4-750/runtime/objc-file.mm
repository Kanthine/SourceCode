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
GETSECT(_getObjc2SelectorRefs,        SEL,             "__objc_selrefs"); //被引用SEL对应的字符串
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
