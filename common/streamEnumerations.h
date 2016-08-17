// -------------------------------------
// Enumerated types 
// -------------------------------------

// for DATA pattern
// Data pattern should be specified in the command line, otherwise
// the default patterns is contiguous
// Since C stores arrays in ROW_MAJOR format, so that means row-wise
// iteration over the array
// Allowed patterns are all defined following, but commented out
#define CONSTANT                    0
#define CONTIGUOUS                  1
#define FIXED_STRIDE                2
#define VARYING_PREDICTABLE_STRIDE  3
#define RANDOM_ACCESS               4

//for TESTING type (only relevant for COPY kernel)
#define RW 0
#define RO 1
#define WO 2

//for LOOPING
#define API     0
#define KERNEL  1

//for NESTING (only applies when KERNEL looping)
#define FLAT_LOOPING   0
#define NESTED_LOOPING 1

//for WORD
#define INT     0
#define FLOAT   1
#define DOUBLE  2

//for KERNEL BENCHMARK
#define COPY  0
#define MUL   1
#define ADD   2
#define TRIAD 3

//for stream source/sink
#define GMEM 0
#define HOST 1

//target boards/flows
#define AOCL    0
#define SDACCEL 1
#define GPU     2
#define CPU     3
#define MAXELER 4

//for loop unroll
//since we can expect UNROLL never to be 
//explicitly defined as 0, we use this value to 
//indicate FULL unroll
#define UNROLL_FULL 0
