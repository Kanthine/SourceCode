typedef struct dispatch_object_s *dispatch_object_t;
typedef struct dispatch_queue_s *dispatch_queue_t;
typedef void (*dispatch_function_t)(void *);

provider dispatch {
	probe queue__push(dispatch_queue_t queue, const char *label,
			dispatch_object_t item, const char *kind,
			dispatch_function_t function, void *context);
	probe queue__pop(dispatch_queue_t queue, const char *label,
			dispatch_object_t item, const char *kind,
			dispatch_function_t function, void *context);
	probe callout__entry(dispatch_queue_t queue, const char *label,
			dispatch_function_t function, void *context);
	probe callout__return(dispatch_queue_t queue, const char *label,
			dispatch_function_t function, void *context);
};

#pragma D attributes Evolving/Evolving/Common provider dispatch provider
#pragma D attributes Private/Private/Common provider dispatch module
#pragma D attributes Private/Private/Common provider dispatch function
#pragma D attributes Evolving/Evolving/Common provider dispatch name
#pragma D attributes Evolving/Evolving/Common provider dispatch args
