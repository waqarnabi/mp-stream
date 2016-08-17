#include "streamEnumerations.h"
// -------------------------------------
// Default Benchmark Paramters
// -------------------------------------

// We *must* ensure that we protect any 
// previous definitin of macros, which should
// override the following defaults

//What is the target board/flow?
//[AOCL*/SDACCEL/GPU/CPU]
#ifndef TARGET
  #define TARGET CPU
#endif

//What is the source/sink of streams?
//[GMEM* / HOST]
#ifndef STREAMSFROMTO
  #define STREAMSFROMTO GMEM
#endif

// Which benchmark kernel is being tested?
// [COPY*/ MUL / ADD / TRIAD]
#ifndef KERNELBENCH
  #define KERNELBENCH COPY
#endif

//The type of word used in the streaming experiments 
//[int* / float / double]
#ifndef WORD
  #define WORD INT
#endif

//The size of vector used in the kernel arguments 
//[1 / 2 / 4 / 8 / 16]
#ifndef VECTOR_SIZE
  #define VECTOR_SIZE 1
#endif

//The size of array(s) along one dimensions in a 2D square matrix
#ifndef STREAM_ARRAY_SIZE_DIM1
  #define STREAM_ARRAY_SIZE_DIM1 512
#endif

//The access pattern used to access array in the DRAM
//current:  [CONTIGUOUS / FIXED_STRIDE]
//future:   [CONSTANT / VARYING_PREDICTABLE_STRIDE / RANDOM_ACCESS]
#ifndef ACCESS_PATTERN
  #define ACCESS_PATTERN CONTIGUOUS
#endif

//"Testing" type, i.e. read only, write only, or both
//[RW / RO / WO]
#ifndef TESTING
  #define TESTING RW
#endif

//How is the looping managed? Kernel code or OpenCl API
//[KERNEL / API]
#ifndef LOOPING
  #define LOOPING KERNEL
#endif

//Is iterating through the 2D array done in a nested fashion or flat
//Only relevant if KERNEL looping enabled
//[FLAT_LOOPING / NESTED_LOOPING]
#ifndef NESTING
  #define NESTING NESTED_LOOPING
#endif

// -------------------------------------
// AOCL-specific Parameters
// -------------------------------------
//The value of AOCL optimization attribute NUM_SIMD_ITEMS
//[1 / 2 / 4 / 8 / 16] ??
#ifndef NUM_SIMD_ITEMS
  #define NUM_SIMD_ITEMS 1
#endif

//The value of AOCL optimziation attribute reqd_work_group_size
#ifndef REQ_WORKGROUP_SIZE
  #define REQ_WORKGROUP_SIZE 1,0,0
//  #define REQ_WORKGROUP_SIZE 1,1,1
#endif

//The value of AOCL optimziation attribute num_compute_units
#ifndef NUM_COMPUTE_UNITS
  #define NUM_COMPUTE_UNITS 1
#endif

// -------------------------------------
// SDACCEL-specific Parameters
// -------------------------------------

// -------------------------------------
// Derived parameters
// -------------------------------------

#if WORD==INT 
  #define stypeHost int
  #if   VECTOR_SIZE==1
    #define stypeDevice int
  #elif VECTOR_SIZE==2
    #define stypeDevice int2
  #elif VECTOR_SIZE==4
    #define stypeDevice int4
  #elif VECTOR_SIZE==8
    #define stypeDevice int8
  #elif VECTOR_SIZE==16
    #define stypeDevice int16
  #else
    #error Illegal VECTOR_SIZE
  #endif

#elif WORD==FLOAT
  #define stypeHost float
  #if   VECTOR_SIZE==1
    #define stypeDevice float
  #elif VECTOR_SIZE==2
    #define stypeDevice float2
  #elif VECTOR_SIZE==4
    #define stypeDevice float4
  #elif VECTOR_SIZE==8
    #define stypeDevice float8
  #elif VECTOR_SIZE==16
    #define stypeDevice float16
  #else
    #error Illegal VECTOR_SIZE
  #endif

#elif WORD==DOUBLE
  #define stypeHost double
  #if   VECTOR_SIZE==1
    #define stypeDevice double
  #elif VECTOR_SIZE==2
    #define stypeDevice double2
  #elif VECTOR_SIZE==4
    #define stypeDevice double4
  #elif VECTOR_SIZE==8
    #define stypeDevice double8
  #elif VECTOR_SIZE==16
    #define stypeDevice double16
  #else
    #error Illegal VECTOR_SIZE.
  #endif

#else
  #error Illegal data type used for WORD
#endif


#define STREAM_ARRAY_SIZE_DIM2   STREAM_ARRAY_SIZE_DIM1
#define STREAM_ARRAY_SIZE        (STREAM_ARRAY_SIZE_DIM1*STREAM_ARRAY_SIZE_DIM1)

// if strided access, then the default stride size
// is the size of DIM2, so that each STRIDE translates 
// to next element in the COLUMN
// (as C is ROW-MAJOR)
// TODO: this is not yet used... 
 #ifndef STRIDE_IN_WORDS
 #define STRIDE_IN_WORDS STREAM_ARRAY_SIZE_DIM2
 #endif
