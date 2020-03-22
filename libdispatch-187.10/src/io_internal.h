#ifndef __DISPATCH_IO_INTERNAL__
#define __DISPATCH_IO_INTERNAL__

#ifndef __DISPATCH_INDIRECT__
#error "Please #include <dispatch/dispatch.h> instead of this file directly."
#include <dispatch/base.h> // for HeaderDoc
#endif

#define _DISPATCH_IO_LABEL_SIZE 16

#ifndef DISPATCH_IO_DEBUG
#define DISPATCH_IO_DEBUG 0
#endif

#if TARGET_OS_EMBEDDED // rdar://problem/9032036
#define DIO_MAX_CHUNK_PAGES				128u //  512kB chunk size
#else
#define DIO_MAX_CHUNK_PAGES				256u // 1024kB chunk size
#endif

#define DIO_DEFAULT_LOW_WATER_CHUNKS	  1u // default low-water mark
#define DIO_MAX_PENDING_IO_REQS			  6u // Pending I/O read advises

typedef unsigned int dispatch_op_direction_t;
enum {
	DOP_DIR_READ = 0,
	DOP_DIR_WRITE,
	DOP_DIR_MAX,
	DOP_DIR_IGNORE = UINT_MAX,
};

typedef unsigned int dispatch_op_flags_t;
#define DOP_DEFAULT		0u // check conditions to determine delivery
#define DOP_DELIVER		1u // always deliver operation
#define DOP_DONE		2u // operation is done (implies deliver)
#define DOP_STOP		4u // operation interrupted by chan stop (implies done)
#define DOP_NO_EMPTY	8u // don't deliver empty data

// dispatch_io_t atomic_flags
#define DIO_CLOSED		1u // channel has been closed
#define DIO_STOPPED		2u // channel has been stopped (implies closed)

#define _dispatch_io_data_retain(x) dispatch_retain(x)
#define _dispatch_io_data_release(x) dispatch_release(x)

#if DISPATCH_IO_DEBUG
#define _dispatch_io_debug(msg, fd, args...) \
	_dispatch_debug("fd %d: " msg, (fd), ##args)
#else
#define _dispatch_io_debug(msg, fd, args...)
#endif

DISPATCH_DECL(dispatch_operation);
DISPATCH_DECL(dispatch_disk);

struct dispatch_stream_s {
	dispatch_queue_t dq;
	dispatch_source_t source;
	dispatch_operation_t op;
	bool source_running;
	TAILQ_HEAD(, dispatch_operation_s) operations[2];
};

typedef struct dispatch_stream_s *dispatch_stream_t;

struct dispatch_io_path_data_s {
	dispatch_io_t channel;
	int oflag;
	mode_t mode;
	size_t pathlen;
	char path[];
};

typedef struct dispatch_io_path_data_s *dispatch_io_path_data_t;

struct dispatch_stat_s {
	dev_t dev;
	mode_t mode;
};

struct dispatch_disk_vtable_s {
	DISPATCH_VTABLE_HEADER(dispatch_disk_s);
};

struct dispatch_disk_s {
	DISPATCH_STRUCT_HEADER(dispatch_disk_s, dispatch_disk_vtable_s);
	dev_t dev;
	TAILQ_HEAD(dispatch_disk_operations_s, dispatch_operation_s) operations;
	dispatch_operation_t cur_rq;
	dispatch_queue_t pick_queue;

	size_t free_idx;
	size_t req_idx;
	size_t advise_idx;
	bool io_active;
	int err;
	TAILQ_ENTRY(dispatch_disk_s) disk_list;
	size_t advise_list_depth;
	dispatch_operation_t advise_list[];
};

struct dispatch_fd_entry_s {
	dispatch_fd_t fd;
	dispatch_io_path_data_t path_data;
	int orig_flags, orig_nosigpipe, err;
	struct dispatch_stat_s stat;
	dispatch_stream_t streams[2];
	dispatch_disk_t disk;
	dispatch_queue_t close_queue, barrier_queue;
	dispatch_group_t barrier_group;
	dispatch_io_t convenience_channel;
	TAILQ_HEAD(, dispatch_operation_s) stream_ops;
	TAILQ_ENTRY(dispatch_fd_entry_s) fd_list;
};

typedef struct dispatch_fd_entry_s *dispatch_fd_entry_t;

typedef struct dispatch_io_param_s {
	dispatch_io_type_t type; // STREAM OR RANDOM
	size_t low;
	size_t high;
	uint64_t interval;
	unsigned long interval_flags;
} dispatch_io_param_s;

struct dispatch_operation_vtable_s {
	DISPATCH_VTABLE_HEADER(dispatch_operation_s);
};

struct dispatch_operation_s {
	DISPATCH_STRUCT_HEADER(dispatch_operation_s, dispatch_operation_vtable_s);
	dispatch_queue_t op_q;
	dispatch_op_direction_t direction; // READ OR WRITE
	dispatch_io_param_s params;
	off_t offset;
	size_t length;
	int err;
	dispatch_io_handler_t handler;
	dispatch_io_t channel;
	dispatch_fd_entry_t fd_entry;
	dispatch_source_t timer;
	bool active;
	int count;
	off_t advise_offset;
	void* buf;
	dispatch_op_flags_t flags;
	size_t buf_siz, buf_len, undelivered, total;
	dispatch_data_t buf_data, data;
	TAILQ_ENTRY(dispatch_operation_s) operation_list;
	// the request list in the fd_entry stream_ops
	TAILQ_ENTRY(dispatch_operation_s) stream_list;
};

struct dispatch_io_vtable_s {
	DISPATCH_VTABLE_HEADER(dispatch_io_s);
};

struct dispatch_io_s {
	DISPATCH_STRUCT_HEADER(dispatch_io_s, dispatch_io_vtable_s);
	dispatch_queue_t queue, barrier_queue;
	dispatch_group_t barrier_group;
	dispatch_io_param_s params;
	dispatch_fd_entry_t fd_entry;
	unsigned int atomic_flags;
	dispatch_fd_t fd, fd_actual;
	off_t f_ptr;
	int err; // contains creation errors only
};

void _dispatch_io_set_target_queue(dispatch_io_t channel, dispatch_queue_t dq);

#endif // __DISPATCH_IO_INTERNAL__