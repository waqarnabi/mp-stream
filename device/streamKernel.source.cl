// Waqar Nabi, Dec 1 2015
//

// include the custom header file generated for this run
#include "kernelCompilerInclude.h"

//needed if we want to work with double
#if WORD==DOUBLE
#pragma OPENCL EXTENSION cl_khr_fp64 : enable
#endif

// -------------------------------
// AOCL specific
// -------------------------------
#if TARGET==AOCL
#if NUM_COMPUTE_UNITS>1 
  __attribute__((num_compute_units(NUM_COMPUTE_UNITS)))
#endif
  
#if NUM_SIMD_ITEMS>1
  __attribute__((num_simd_work_items(NUM_SIMD_ITEMS)))
#endif
  
  //#ifdef REQ_WORKGROUP_SIZE
  //  __attribute__((reqd_work_group_size(REQ_WORKGROUP_SIZE)))
  //#endif
#endif

// -------------------------------
// SDACCEL specific
// -------------------------------
#if TARGET==SDACCEL
#endif    

// -------------------------------
// GENERIC attributes/opimizations
// -------------------------------
#ifdef REQ_WORKGROUPIZE
    __attribute__((reqd_work_group_size(REQ_WORKGROUP_SIZE)))
#endif


// -------------------------------
// STREAM KERNEL
// -------------------------------
__kernel void streamKernel(
    __global const  stypeDevice * restrict a
  , __global        stypeDevice * restrict c
#if KERNELBENCH == ADD
  ,  __global const  stypeDevice * restrict b
#elif KERNELBENCH == MUL
  , const  stypeDevice  scalar
#elif KERNELBENCH == TRIAD
  , __global const  stypeDevice * restrict b
  , const  stypeHost  scalar
#elif KERNELBENCH == COPY
  //nothing unique
#else
#error Invalid KERNELBENCH defined.
#endif
)  {  
  __local stypeDevice c_local;
  int i, j, index, indexCounter;
  //--------------------------------------------------------------------
  // ** API-looping **  (aka NDrange kernel)
  // looping over work-items handled by enquing multiple work-items
  //--------------------------------------------------------------------
#if LOOPING == API    
    
    // SDACCEL OPT: pipeline work items
    //----------------------------------
#if TARGET==SDACCEL
#ifdef XCL_PIPELINE_WORKITEMS
        __attribute__((xcl_pipeline_workitems))
#endif
#endif

    //get the current work-item ID
    indexCounter = get_global_id(0); 

    //recover the i and j coordinate from it
    //the reason we dont use indexCounter directly is that we may
    //want a non-contiguous access to memory
    i = indexCounter /  (STREAM_ARRAY_SIZE_DIM2/VECTOR_SIZE); //recover i (row)
    j = indexCounter % (STREAM_ARRAY_SIZE_DIM2/VECTOR_SIZE); //recover j (col)

  //--------------------------------------------------------------------
  // * Kernel-looping*   (aka "1 work-item kernel")
  //  Single work-item launched via API, looping here
  //--------------------------------------------------------------------
  //NOTE: Strided and vector do not go together?
#elif LOOPING == KERNEL
    
    // FLAT LOOPING 
    //---------------------------------
#if NESTING == FLAT_LOOPING
      
      // LOOP UNROLL HINT (for FLAT)
      //---------------------------------
#ifdef UNROLL_FACTOR
        //unroll pragma for SDACCEL
#if TARGET==SDACCEL
#if UNROLL_FACTOR == UNROLL_FULL
            __attribute__ ((opencl_unroll_hint))
#else
            __attribute__ ((opencl_unroll_hint(UNROLL_FACTOR)))
#endif
        //unroll pragma for AOCL
#elif TARGET==AOCL
#if UNROLL_FACTOR == UNROLL_FULL
#pragma unroll
#else
#pragma unroll UNROLL_FACTOR
#endif
#else
          //unroll pragma for CPU/GPU has no effect??
#endif
#endif

      // XCL PIPELINE LOOP
      //---------------------------------
#if TARGET==SDACCEL
#ifdef XCL_PIPELINE_LOOP
          __attribute__((xcl_pipeline_loop))
#endif
#endif

      // THE LOOP
      //---------------------------------
      for (indexCounter=0; indexCounter<(STREAM_ARRAY_SIZE/VECTOR_SIZE); indexCounter++)  {   
      //recover the i and j coordinate from it
      i = indexCounter / (STREAM_ARRAY_SIZE_DIM2/VECTOR_SIZE); //recover i (row)
      j = indexCounter % (STREAM_ARRAY_SIZE_DIM2/VECTOR_SIZE); //recover j (col)
  
    // NESTED LOOPING 
    //---------------------------------
#elif NESTING == NESTED_LOOPING
      for (i=0; i<STREAM_ARRAY_SIZE_DIM1; i++) 
        // LOOP UNROLL HINT (For nested, only inner)
        //------------------------------------------
#ifdef UNROLL_FACTOR
          //unroll pragma for SDACCEL
#if TARGET==SDACCEL
#if UNROLL_FACTOR == UNROLL_FULL
              __attribute__ ((opencl_unroll_hint))
#else
              __attribute__ ((opencl_unroll_hint(UNROLL_FACTOR)))
#endif
          //unroll pragma for AOCL
#elif TARGET==AOCL
#if UNROLL_FACTOR == UNROLL_FULL
#pragma unroll
#else
#pragma unroll UNROLL_FACTOR
#endif
#else
            //unroll pragma for CPU/GPU has no effect
#endif
#endif

        // XCL PIPELINE LOOP
        //---------------------------------
#if TARGET==SDACCEL
#ifdef XCL_PIPELINE_LOOP
            __attribute__((xcl_pipeline_loop))
#endif
#endif

        // THE (INNER) LOOP
        //---------------------------------
        for (j=0; j<STREAM_ARRAY_SIZE_DIM2/VECTOR_SIZE; j++) {
#else
#error Invalid value for NESTING macro.
#endif
#else
#error Invalid LOOPING macro definition.
#endif
    //if LOOPING == API

  //--------------------------------------------------------------------
  // CREATE LINEAR INDEX
  //--------------------------------------------------------------------
  
    //the DIM2 is effectively scaled down by vector-size
    //but only applies in the case of contig data, as we 
    //dont allow vector+strided access
#if (ACCESS_PATTERN==CONTIGUOUS)
      index = j + i*(STREAM_ARRAY_SIZE_DIM2/VECTOR_SIZE);
#elif (ACCESS_PATTERN==FIXED_STRIDE)
      index = i + j*STREAM_ARRAY_SIZE_DIM2;
#else
#error Only CONTIGUOUS or FIXED_STRIDE allowed.
#endif  

  //--------------------------------------------------------------------
  // Run the Kernel
  //--------------------------------------------------------------------
  // ----------- COPY KERNEL -------------------------------------
#if KERNELBENCH==COPY
    //check for RW, RO, and WO
#if   TESTING==RW
      c[index] = a[index];
#elif TESTING==WO
      c[index] = index; //don't read
#elif TESTING==RO 
      c_local += a[index];
#endif      
#endif
  // ----------- MUL KERNEL -------------------------------------
#if KERNELBENCH==MUL
      c[index] = scalar * a[index];
#endif

  // ----------- ADD KERNEL -------------------------------------
#if KERNELBENCH==ADD
      c[index] =  a[index] + b[index];
#endif

  // ----------- TRIAD KERNEL -------------------------------------
#if KERNELBENCH==TRIAD
      c[index] = a[index] + scalar * b[index];
#endif

  // if KERNEL looping, then we need to close the for loop.
#if LOOPING == KERNEL
    }//for
#endif
    
  //a[index]=c_local;
  
  return;
}//__kerneL
