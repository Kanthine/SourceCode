#ifndef __DISPATCH_SHIMS_MALLOC_ZONE__
#define __DISPATCH_SHIMS_MALLOC_ZONE__

#include <sys/types.h>

#include <stdlib.h>

/* 将 malloc 区域实现为不支持它们的系统上的 malloc(3) 的简单包装。
 * Implement malloc zones as a simple wrapper around malloc(3) on systems
 * that don't support them.
 */
#if !HAVE_MALLOC_CREATE_ZONE
typedef void * malloc_zone_t;

static inline malloc_zone_t *
malloc_create_zone(size_t start_size, unsigned flags){
	return ((void *)(-1));
}

static inline void
malloc_destroy_zone(malloc_zone_t *zone){

}

static inline malloc_zone_t *
malloc_default_zone(void){
	return ((void *)(-1));
}

static inline malloc_zone_t *
malloc_zone_from_ptr(const void *ptr){
	return ((void *)(-1));
}

static inline void *
malloc_zone_malloc(malloc_zone_t *zone, size_t size){
	return (malloc(size));
}

static inline void *
malloc_zone_calloc(malloc_zone_t *zone, size_t num_items, size_t size){
	return (calloc(num_items, size));
}

static inline void *
malloc_zone_realloc(malloc_zone_t *zone, void *ptr, size_t size){
	return (realloc(ptr, size));
}

static inline void
malloc_zone_free(malloc_zone_t *zone, void *ptr){
	free(ptr);
}

static inline void
malloc_set_zone_name(malloc_zone_t *zone, const char *name){
	/* No-op. */
}
#endif

#endif /* __DISPATCH_SHIMS_MALLOC_ZONE__ */
