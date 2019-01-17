/* objc-loadmethod.m
 *
 * 全局变量：
 * 结构数组 loadable_classes 中的每个元素都存储了类以及它的 +load 方法的 IMP；
 * 结构数组 loadable_categories 中的每个元素都存储了分类以及它的 +load 方法的 IMP；
 *
 * 功能函数：
 * add_class_to_loadable_list() 函数将一个类添加到数组 loadable_classes；
 * add_category_to_loadable_list() 函数将一个分类添加到数组 loadable_categories；
 * remove_class_from_loadable_list() 函数从数组 loadable_classes 中移除指定类；
 * remove_category_from_loadable_list() 函数从数组 loadable_categories 中移除指定分类；
 * call_class_loads() 函数遍历数组 loadable_classes 调用数组中所有挂起的类的 +load 方法；调用之后数组 loadable_classes 置为 nil
 * call_category_loads() 函数遍历数组 loadable_categories 调用分类挂起的 +load 方法；
 * call_load_methods() 函数调用所有挂起(未注册)的类和分类的 +load 方法。
 */

#include "objc-loadmethod.h"
#include "objc-private.h"

typedef void(*load_method_t)(id, SEL);

//存储了 +load 方法所属的Class和+load方法的IMP
struct loadable_class {
    Class cls;  //+load 方法所属的Class；可能为 nil
    IMP method;//+load方法的IMP
};

//存储了 +load 方法所属的 Category 和+load方法的IMP
struct loadable_category {
    Category cat;  //+load 方法所属的 Category；可能为 nil
    IMP method;//+load方法的IMP
};


/* loadable_classes 结构数组：存储着一个个结构元素 loadable_class
 * 静态变量 loadable_classes_used 用于记录 add_class_to_loadable_list() 函数的调用次数，也是 loadable_classes 数组的元素个数
 * @note 由于该数组的构造方式，要求总是先有父类
 */
static struct loadable_class *loadable_classes = nil;
static int loadable_classes_used = 0;
static int loadable_classes_allocated = 0;

/* loadable_categories 结构数组：存储着一个个结构元素 loadable_category
 * 静态变量 loadable_categories_used 用于记录 add_category_to_loadable_list() 函数的调用次数，也是 loadable_categories 数组的元素个数
 * @note 需要调用 +load 的 categories 列表(挂起父类+load)
 */
static struct loadable_category *loadable_categories = nil;
static int loadable_categories_used = 0;
static int loadable_categories_allocated = 0;


/* 将类添加到数组 loadable_classes 中
 * @param cls 要添加的类
 * @note 该函数每执行一次，loadable_classes_used 都会加 1 ；
 * @note loadable_classes_used 用于记录这个方法的调用次数，相当于数组 loadable_classes 的元素个数
 * @note 类cls刚刚连接起来：如果它实现了一个+load方法，那么为+load调用它。
 */
void add_class_to_loadable_list(Class cls)
{
    IMP method;

    loadMethodLock.assertLocked();
    
    method = cls->getLoadMethod();//获取类 cls 的 +load 方法的 IMP
    if (!method) return;  // 如果 cls 没有+load 方法，直接返回，不需要接着执行
    
    if (PrintLoading) {
        _objc_inform("LOAD: class '%s' scheduled for +load", cls->nameForLogging());
    }
    
    if (loadable_classes_used == loadable_classes_allocated) {
        // 如果已使用大小等于数组大小，对数组进行动态扩容
        loadable_classes_allocated = loadable_classes_allocated*2 + 16;
        loadable_classes = (struct loadable_class *)
            realloc(loadable_classes,
                              loadable_classes_allocated *
                              sizeof(struct loadable_class));
    }
    
    /* loadable_classes[loadable_classes_used] 取出数组中第 loadable_classes_used 个元素
     * 该元素是个结构体 loadable_class ，分别为它的成员赋值
     */
    loadable_classes[loadable_classes_used].cls = cls;//+load 方法所属的Class
    loadable_classes[loadable_classes_used].method = method;//+load方法的IMP
    loadable_classes_used++;//加 1，用于记录该函数的调用次数；相当于数组 loadable_classes 的元素个数
}


/* 将分类添加到数组 loadable_categories 中
 * @param cat 要添加的分类
 * @note 该函数每执行一次，loadable_categories_used 都会加 1 ；
 * @note loadable_categories_used 用于记录这个方法的调用次数，相当于数组 loadable_categories 的元素个数
 * @note 类cls刚刚连接起来：如果它实现了一个+load方法，那么为+load调用它。
 */
void add_category_to_loadable_list(Category cat)
{
    IMP method;

    loadMethodLock.assertLocked();

    //获取分类实现的 +load 方法的 IMP；如果该分类没有实现+load 方法 ，则返回 nil
    method = _category_getLoadMethod(cat);

    if (!method) return;// 如果 cat 没有 +load 方法就不执行

    if (PrintLoading) {
        _objc_inform("LOAD: category '%s(%s)' scheduled for +load", 
                     _category_getClassName(cat), _category_getName(cat));
    }
    
    if (loadable_categories_used == loadable_categories_allocated) {
        // 如果已使用大小等于数组大小，对数组进行动态扩容
        loadable_categories_allocated = loadable_categories_allocated*2 + 16;
        loadable_categories = (struct loadable_category *)
            realloc(loadable_categories,
                              loadable_categories_allocated *
                              sizeof(struct loadable_category));
    }

    /* loadable_categories[loadable_categories_used] 取出数组中第 loadable_categories_used 个元素
     * 该元素是个结构体 loadable_class ，分别为它的成员赋值
     */
    loadable_categories[loadable_categories_used].cat = cat;//+load 方法所属的分类
    loadable_categories[loadable_categories_used].method = method;//+load方法的IMP
    loadable_categories_used++;//加 1，用于记录该函数的调用次数；相当于数组 loadable_categories 的元素个数
}


/* 从数组 loadable_classes 中移除指定类
 * @param cls 要移除的类
 * @note 类 cls 以前可能是可加载的，但现在它不再可加载(因为它的镜像是未映射的)。
 */
void remove_class_from_loadable_list(Class cls)
{
    loadMethodLock.assertLocked();

    if (loadable_classes) {
        int i;
        //遍历结构数组 loadable_classes，根据入参 cls 找到数组中指定的元素
        for (i = 0; i < loadable_classes_used; i++) {
            if (loadable_classes[i].cls == cls) {
                loadable_classes[i].cls = nil;//将成员 cls 置为 nil
                if (PrintLoading) {
                    _objc_inform("LOAD: class '%s' unscheduled for +load", 
                                 cls->nameForLogging());
                }
                return;
            }
        }
    }
}


/* 从数组 loadable_categories 中移除指定分类
 * @param cls 要移除的分类
 * @note 分类 cat 以前可能是可加载的，但现在它不再可加载(因为它的镜像是未映射的)。
 */
void remove_category_from_loadable_list(Category cat)
{
    loadMethodLock.assertLocked();

    if (loadable_categories) {
        int i;
        //遍历结构数组 loadable_categories，根据入参 cat 找到数组中指定的元素
        for (i = 0; i < loadable_categories_used; i++) {
            if (loadable_categories[i].cat == cat) {
                loadable_categories[i].cat = nil;//将成员 cat 置为 nil
                if (PrintLoading) {
                    _objc_inform("LOAD: category '%s(%s)' unscheduled for +load",
                                 _category_getClassName(cat), 
                                 _category_getName(cat));
                }
                return;
            }
        }
    }
}


/* 遍历数组 loadable_classes ，调用数组中所有挂起的类的 +load 方法
 * 调用之后，将 loadable_classes 置为 nil；
 * 如果新类变得可加载，则不调用它们的 +load。
 */
static void call_class_loads(void)
{
    int i;
    struct loadable_class *classes = loadable_classes;
    int used = loadable_classes_used;
    loadable_classes = nil;
    loadable_classes_allocated = 0;
    loadable_classes_used = 0;
    
    // 遍历列表中的所有 +load 方法
    for (i = 0; i < used; i++) {
        Class cls = classes[i].cls;//获取指定索引处的类
        load_method_t load_method = (load_method_t)classes[i].method;//获取 +load 方法的 IMP
        if (!cls) continue;  //如果该类为 nil ，则直接返回

        if (PrintLoading) {
            _objc_inform("LOAD: +[%s load]\n", cls->nameForLogging());
        }
        (*load_method)(cls, SEL_load);//通过函数指针执行指定类 cls 的 +load 方法
    }
    if (classes) free(classes);//释放列表
}


/* 该函数的主要功能是：
 * 1、遍历数组 loadable_categories 调用分类挂起的 +load 方法；
 * 2、将加载过 +load 方法的元素从数组 loadable_categories 中移除；
 * 3、假如数组 loadable_categories 中所有分类的 +load 方法 都已调用，则 loadable_categories 置为 nil；
 * @return 在遍历数组 loadable_categories 调用分类挂起的 +load 方法期间，假如有新的分类添加到数组 loadable_categories 中，则该函数会返回 true ，否则返回 false
 * @note 除非分类所属的类已连接，否则不要调用 +load。
 * @note The parent class of the +load-implementing categories has all of its categories attached, in case some are lazily waiting for +initalize.
 */
static bool call_category_loads(void)
{
    int i, shift;
    bool new_categories_added = NO;//该函数返回值
    
    struct loadable_category *cats = loadable_categories;
    int used = loadable_categories_used;
    int allocated = loadable_categories_allocated;
    loadable_categories = nil;
    loadable_categories_allocated = 0;
    loadable_categories_used = 0;

    // 遍历列表中的所有 +load 方法
    for (i = 0; i < used; i++) {
        Category cat = cats[i].cat;//获取指定索引处的分类
        load_method_t load_method = (load_method_t)cats[i].method;//获取 +load 方法的 IMP
        Class cls;
        if (!cat) continue;//如果该分类为 nil ，则直接返回

        cls = _category_getClass(cat);//获取分类所属的类
        if (cls  &&  cls->isLoadable()) {//要求该类可加载
            if (PrintLoading) {
                _objc_inform("LOAD: +[%s(%s) load]\n", 
                             cls->nameForLogging(), 
                             _category_getName(cat));
            }
#pragma mark - 调用的是分类的 +load 方法 还是该类的 +load 方法 ？
            (*load_method)(cls, SEL_load);//通过函数指针执行指定分类所属类 cls 的 +load 方法
            cats[i].cat = nil;
        }
    }

    //将所有加载过的分类移除 cats 数组
    shift = 0;
    for (i = 0; i < used; i++) {
        if (cats[i].cat) {
            cats[i-shift] = cats[i];
        } else {
            shift++;
        }
    }
    used -= shift;

    //为数组 cats 重新分配内存，并重新设置它的值：将新添加到数组loadable_categories的分类存储到数组 cats 上
    new_categories_added = (loadable_categories_used > 0);//是否有新的分类添加到数组 loadable_categories
    for (i = 0; i < loadable_categories_used; i++) {
        if (used == allocated) {
            allocated = allocated*2 + 16;
            cats = (struct loadable_category *)
                realloc(cats, allocated *
                                  sizeof(struct loadable_category));
        }
        cats[used++] = loadable_categories[i];
    }

    if (loadable_categories) free(loadable_categories);//释放数组 loadable_categories

    // Reattach the (now augmented) detached list. 
    // But if there's nothing left to load, destroy the list.
    if (used) {
        loadable_categories = cats;
        loadable_categories_used = used;
        loadable_categories_allocated = allocated;
    } else {//如果没有要加载的分类，则销毁列表。
        if (cats) free(cats);
        loadable_categories = nil;
        loadable_categories_used = 0;
        loadable_categories_allocated = 0;
    }

    if (PrintLoading) {
        if (loadable_categories_used != 0) {
            _objc_inform("LOAD: %d categories still waiting for +load\n",
                         loadable_categories_used);
        }
    }

    return new_categories_added;
}

/* call_load_methods
 * 调用所有挂起(未注册)的类和分类+load方法。
 * 父类优先调用 类方法 +load
 * 父类调用 +load 之后，Category 调用 +load
 *
 * 此方法必须是可重入的，因为 +load 可能触发更多的图像映射。此外，在面对可重入调用时，必须遵循父类优先顺序。因此，只有该函数的最外层调用才会执行任何操作，而该调用将处理所有可加载类，即使是在运行时生成的类。
 * 下面的顺序在 +load 期间保存图像加载时的 +load 排序，并确保不会因为在 +load 调用期间添加了+load方法而忘记 +load 方法。
 * 顺序:
 * 1. 重复调用class +load，直到不再有其他类为止
 * 2. 调用category +load一次。
 * 3. 运行更多 +loads ，如果:
 *    (a) 有更多的类要加载，或
 *    (b) 有些潜在的 category +load 还从未尝试过。
 * Category +load 只运行一次，以确保“父类优先”排序，即使 Category +load 触发了一个新的可加载类，以及一个附加到该类的可加载类别。
 * 锁定:loadMethodLock 必须由调用方持有，其他所有锁都不能持有。
 */
void call_load_methods(void)
{
    static bool loading = NO;
    bool more_categories;

    loadMethodLock.assertLocked();

    // Re-entrant calls do nothing; the outermost call will finish the job.
    if (loading) return;
    loading = YES;

    void *pool = objc_autoreleasePoolPush();

    do {
        // 1. 重复调用 loadable_classes 数组上的 +load，直到不再有其他类为止
        while (loadable_classes_used > 0) {
            //遍历数组 loadable_classes ，调用数组中所有挂起的类的 +load 方法; 调用之后，将 loadable_classes_used 置为 0；
            call_class_loads();
        }

        // 2. 调用 loadable_categories 数组中的 +load 一次
        //调用该函数期间，是否有新的分类添加到数组 loadable_categories
        more_categories = call_category_loads();

        // 3. Run more +loads if there are classes OR more untried categories
    } while (loadable_classes_used > 0  ||  more_categories);

    objc_autoreleasePoolPop(pool);

    loading = NO;
}


