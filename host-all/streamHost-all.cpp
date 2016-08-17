// ======================================================
// Modified Stream benchmark for OpenCL Targets 
// Primary target is FPGA, but also meant to work with 
// GPUs and CPUs
// By: Syed Waqar Nabi, Glasgow
// 2015.12.15
//
// 
// This work is based on the following:
//
// ======================================================

#include "streamHost-all.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(int argc, char** argv) {
  using namespace std;

  // =============================================================================
  // Local variables
  // =============================================================================
  int       quantum, checktick();
  double    t;
  int       k;
  int       BytesPerWord = sizeof(stypeHost);
  ssize_t   i,j;

  //for timing profile
  double start_timer, end_timer;

#ifdef OCL
  //opencl variables
  cl_int            err = CL_SUCCESS;
  cl_context        context;        // compute context
  cl_command_queue  commands;       // compute command queue
  cl_program        program;        // compute program
  cl_kernel         kernel;         // compute kernel

  //device buffers
  cl_mem aBuffer, bBuffer, cBuffer;
#endif

  printf(SLINE); printf(HLINE);
  printf("STREAM *modified* version $Revision: 5.10.glasgow.1 $\n"); printf(HLINE);

  // =============================================================================
  // HOST DATA
  // =============================================================================
  stypeHost scalarval = (stypeHost)3.0;
  stypeHost *a2d = NULL;
  stypeHost *b2d = NULL;
  stypeHost *c2d = NULL;
  posix_memalign ((void**)&a2d, ALIGNMENT, STREAM_ARRAY_SIZE*BytesPerWord);
  posix_memalign ((void**)&b2d, ALIGNMENT, STREAM_ARRAY_SIZE*BytesPerWord);
  posix_memalign ((void**)&c2d, ALIGNMENT, STREAM_ARRAY_SIZE*BytesPerWord);

  //initialize data
  mps_init_data(a2d, b2d, c2d, BytesPerWord);

  // =============================================================================
  // Initialization helper functions calls
  // =============================================================================
  //checks clock precision etc 
  mps_timing_setup(a2d,  BytesPerWord);

  //display setup
  mps_display_setup();

#ifdef OCL
  //initialize opencl (create context, commansds, program, and kernel)
  mps_opencl_boilerplate(&context, &commands, &program, &kernel, argc, argv);

  //create buffers on device
  mps_create_cldevice_buffer(&aBuffer, &context);
  mps_create_cldevice_buffer(&cBuffer, &context);
#if (KERNELBENCH==ADD) || (KERNELBENCH==TRIAD)
  mps_create_cldevice_buffer(&bBuffer, &context);
#endif
#endif
//#ifdef OCL

  // =============================================================================
  // EXECUTION FOR HOST STREAMS (not yet defined for Maxeler)
  // =============================================================================
  //if we want to test bandwidth between host and device-DRAM
#if STREAMSFROMTO==HOST
#if TARGET==MAXELER 
#error Host streams not defined for Maxeler
#endif
  
  printf("HOST STREAMS :: Reported BW figures are for host<-->device-DRAM communication over PCIe\n");
     
  // Repeatedly write and read the data set into the device memory
  for (k=0; k<NTIMES; k++) {
    times[k] = mysecond(); 
    mps_blocking_write_cl_buffer(&commands, &aBuffer, a2d);
    mps_blocking_read_cl_buffer(&commands, &aBuffer, c2d);
    times[k] = mysecond() - times[0][k];
  }

  // =============================================================================
  // EXECUTION FOR GLOBAL-MEMORY STREAMS
  // =============================================================================
  // if we want to test bandwidth between device and device-DRAM
#else
    printf("GMEM STREAMS :: Reported BW figures are for device<-->device-DRAM communication\n");
    printf("NOTE: If 'TARGET' is the host itself, then GMEM is effectively still the HOST memmory\n");
     
    // Write our data set into the input array in device memory. Record times 
    start_timer = mysecond();
#if TARGET==MAXELER
    LMemExample_writeLMem(STREAM_ARRAY_SIZE, 0 , a2d);
#else    
    mps_blocking_write_cl_buffer(&commands, &aBuffer, a2d);
#endif    
    end_timer = mysecond();
    time_a2d_togpu = end_timer - start_timer;

#if (KERNELBENCH == ADD) || (KERNELBENCH == TRIAD)  
    start_timer = mysecond();
#if TARGET==MAXELER
    LMemExample_writeLMem(STREAM_ARRAY_SIZE, STREAM_ARRAY_SIZE  , b2d);
#else    
    mps_blocking_write_cl_buffer(&commands, &bBuffer, b2d);
#endif    
    end_timer = mysecond();
    time_b2d_togpu = end_timer - start_timer;
#endif

#ifdef OCL    
  //set the arguments 
  //bBuffer always exists, but is only initialized/set if needed
  mps_set_kernel_args(&kernel, &aBuffer, &bBuffer, &cBuffer, &scalarval);

  //set global and local sizes
  size_t globalSize[] = {0,0,0};
  size_t localSize[]  = {0,0,0};
  mps_get_global_local_sizes(globalSize, localSize);
#endif

  //launch kernel
  //-------------
  printf(SLINE); printf("Launching the Kernel\n"); printf(HLINE);
  start_timer = mysecond();

  // NTIMES loop over kernel call
  for (k=0; k<NTIMES; k++) {
    times[k] = mysecond();
#if TARGET==MAXELER    
    LMemExample(STREAM_ARRAY_SIZE);
#else    
    mps_enq_cl_kernel(&commands, &kernel, globalSize, localSize);
#endif    
    times[k] = mysecond() - times[k];
  }//for (k=0; k<NTIMES; k++)

  end_timer = mysecond();
  time_kernels = end_timer - start_timer;

  // Read back the results
  start_timer = mysecond();
#if TARGET==MAXELER    
  LMemExample_readLMem(STREAM_ARRAY_SIZE, 2 * STREAM_ARRAY_SIZE, c2d);
#else
  mps_blocking_read_cl_buffer(&commands, &cBuffer, c2d);
#endif
  end_timer = mysecond();
  time_c2d_tohost = end_timer - start_timer;
#endif    

  // =============================================================================
  // POST PROCESSING
  // =============================================================================   
  
  // Write output arrays 
#ifdef LOGRESULTS
  start_timer = mysecond();
  mps_log_results(a2d, b2d, c2d);
  end_timer = mysecond();
  time_write2file = end_timer - start_timer;
#endif

  //verify results
  start_timer = mysecond();
  mps_verify_results(a2d, b2d, c2d, scalarval);
  end_timer = mysecond();
  time_verify = end_timer - start_timer;

  // Calculate BW. Display and write to file
  mps_calculate_bandwidth();

  // Display overall timing profile 
  mps_disp_timing_profile();

// Shutdown and cleanup
// -----------------------------------------
  free(a2d);
  free(b2d);
  free(c2d);
#ifdef OCL  
  clReleaseMemObject(aBuffer);  
  #if (KERNELBENCH==ADD) || (KERNELBENCH==TRIAD)
    clReleaseMemObject(bBuffer);
  #endif
  clReleaseMemObject(cBuffer);
  clReleaseProgram(program);
  clReleaseKernel(kernel);
 
  clReleaseCommandQueue(commands);
  clReleaseContext(context);
#endif  
}

