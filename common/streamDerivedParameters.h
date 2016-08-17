// ----------------------------------------------------
// Derived parameters - common for host and device
// ----------------------------------------------------

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


//is this an OpenCL implementation or not (i.e. may be Maxeler)
#if (TARGET!=MAXELER) 
#define OCL
#endif