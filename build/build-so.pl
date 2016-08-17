#!/usr/bin/perl -w

use strict;
use warnings;
use Getopt::Long;   #for command line options
#use File::Slurp;
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
#use Time::HiRes qw( gettimeofday );
#use IO::Tee;
use IO::File;

my @start = localtime();

#----------------------------------------------------------
# default options, and list of possible command line options
#----------------------------------------------------------
our $target = 'CPU';
  #AOCL
  #SDACCEL
  #GPU
  #CPU
our $projectPrefix  = 'stream'; #the prefix to use for all project files, directories, etc
our $STREAM_ARRAY_SIZE_DIM1 = 1024;
our $ACCESS_PATTERN   = 'CONTIGUOUS';
  #our $ACCESS_PATTERN   = 'FIXED_STRIDE';
our $make = 'all'; #make all by default
  #our $make = 'run'; 
  #our $make = 'host'; 
  #our $make = 'aoclbin'; 
  #our $make = 'clean'; 
our $FLOW = 'cpu_emu'; ##no relevance for CPU/GPU --- all flows are the same
  #our $FLOW = 'hw';
  #our $FLOW = 'hw_emu';
our $vectorSize = 1; #scalar by default
our $help = '';
our $looping = 'API'; #looping managed by the opencl API by default
 #our $looping = 'kernel'; 
our $nesting = 'FLAT_LOOPING';#if KERNEL looping, then NESTED or FLAT?
  #our $nesting = 'FLAT_KERNEL_LOOPING'; 
  #our $nesting = 'NESTED_KERNEL_LOOPING'; 
our $testing = 'RW'; #testing both read and write by default
 #our $testing = 'RO'; 
 #our $testing = 'WO'; 
our $wordType = 'INT';
  #our $wordType = 'FLOAT';
  #our $wordType = 'DOUBLE';
our $batch = '';
our $kernel = 'COPY';
our $streamsFromTo = 'GMEM';
#[COPY*/MUL/ADD/TRIAD]
our $logresults = '';

#estimated by default
our $estimate = '';

#loop unroll
our $unrollFull= '';
our $unrollFactor = '';


#required work-group size
#our $reqWorkgroupSize = '1,0,0';
our $reqWorkgroupSize = '';

#AOCL specific?
our $numSimdItems = 1;
our $numComputeUnits = 1;
our $noInterleaving = '';


#SDACCEL specific
our $xclpipelineWorkitems='';
our $xclpipelineLoop='';
our $xclmaxmemoryports='';
our $xclmemportwidth='';

#-----------------------------
#get options from command line
#-----------------------------
GetOptions (
    'p=s'   =>  \$projectPrefix
  , 'tar=s' =>  \$target
  , 'sft=s' =>  \$streamsFromTo
  , 'k=s'   =>  \$kernel
  , 'd=s'   =>  \$STREAM_ARRAY_SIZE_DIM1               
  , 'w=s'   =>  \$wordType
  , 'l=s'   =>  \$looping
  , 'n=s'   =>  \$nesting
  , 'v=s'   =>  \$vectorSize
  , 't=s'   =>  \$testing
  , 'a=s'   =>  \$ACCESS_PATTERN
  , 'r=s'   =>  \$reqWorkgroupSize    
  , 'm=s'   =>  \$make
  , 'h'     =>  \$help
  , 'log'   =>  \$logresults
  , 'batch' =>  \$batch
  , 'f=s'   =>  \$FLOW                  #AOCL and SDACCEL only          
  , 'uf'    =>  \$unrollFull            #AOCL and SDACCEL only          
  , 'un=s'  =>  \$unrollFactor          #AOCL and SDACCEL only          
  , 's=s'   =>  \$numSimdItems          #AOCL only
  , 'c=s'   =>  \$numComputeUnits       #AOCL only
  , 'ni'    =>  \$noInterleaving        #AOCL only
  , 'e'     =>  \$estimate              #SDACCEL only
  , 'xpw'   =>  \$xclpipelineWorkitems  #SDACCEL only
  , 'xpl'   =>  \$xclpipelineLoop       #SDACCEL only
  , 'xmm'   =>  \$xclmaxmemoryports     #SDACCEL only
  , 'xmw=s' =>  \$xclmemportwidth       #SDACCEL only
  );

my $arraySize = $STREAM_ARRAY_SIZE_DIM1*$STREAM_ARRAY_SIZE_DIM1;

if($help) {
  printHelp();
  exit;
}
#convenience boolean
my $FPGA = ( ($target eq 'SDACCEL') || ($target eq 'AOCL') );

#relevant for sdaccel; if flow is hardware, turn on estimation no matter what
#flag is passed
$estimate = 1 if ($FLOW eq 'hw');

#--------------------------------------------------
#Now move to build directory of appropriate target
#--------------------------------------------------
my $targetPlatformDirectory;
if    ($target eq 'AOCL')     {$targetPlatformDirectory = '../build-aocl';}
elsif ($target eq 'SDACCEL')  {$targetPlatformDirectory = '../build-sdaccel';}
elsif ($target eq 'GPU')      {$targetPlatformDirectory = '../build-nvidia-gpu';}
elsif ($target eq 'CPU')      {$targetPlatformDirectory = '../build-intel-cpu';}
else                          {die "Invalid target specificaion"};
print "Moving to build folder $targetPlatformDirectory for target: $target\n";
chdir $targetPlatformDirectory;

#--------------------------------------------------
#Create custom dirctory name for this build, 
#--------------------------------------------------
#get local time to create unique folder name
my $sec, my $min, my $hour, my $mday, my $mon, my $year, my $wday, my $yday, my $isdst;
($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
                                                localtime(time);

my $timeStamp =$yday.".".$hour.$min.$sec;

my $targetDir 
    = "build-".$target."-".$timeStamp."-".$projectPrefix."-".$kernel."-".$wordType.$vectorSize
    . "-".$looping."Looping-".$nesting."-".$testing."-".$STREAM_ARRAY_SIZE_DIM1."-".$ACCESS_PATTERN."-".$FLOW; 
#--------------------------------------------
# create target directory
#--------------------------------------------
print "\nBUILD.PL: Making target directory $targetDir...\n";
make_path($targetDir);

#----------------------------------------------------
#print pre-build messages and store them in LOG file
#----------------------------------------------------
my $buildparamlogfile = $targetPlatformDirectory."/".$targetDir."/build-parameters.log";
#open(my $bplfh, '>', $buildparamlogfile)
print "LOG FILE: $buildparamlogfile\n";
open my $tee , '>', $buildparamlogfile or die "BUILD.PL: Could not open file '$buildparamlogfile' $!";  
#my $tee = new IO::Tee(  \*STDOUT , $bplfh);

print $tee "Building with the following options...\n";
print $tee "--------------------------------------\n";
print $tee "TARGET                 = $target\n";
print $tee "STREAMSFROMTO          = $streamsFromTo\n";
print $tee "KERNELBENCH            = $kernel\n";
print $tee "WORD                   = $wordType\n";
print $tee "STREAM_ARRAY_SIZE_DIM1 = $STREAM_ARRAY_SIZE_DIM1\n";
print $tee "STREAM_ARRAY_SIZE      = $arraySize\n";
print $tee "VECTOR_SIZE            = $vectorSize\n";
print $tee "REQ_WORKGROUP_SIZE     = $reqWorkgroupSize\n" if($reqWorkgroupSize);
print $tee "LOOPING                = $looping\n";
print $tee "NESTING                = $nesting\n";
print $tee "TESTING                = $testing\n";
print $tee "ACCESS_PATTERN         = $ACCESS_PATTERN \n";
print $tee "Make                   = $make \n";
print $tee "projectPrefix          = $projectPrefix \n";
print $tee "targerDir              = $targetDir\n";
print $tee "timeStamp              = $timeStamp\n";
print $tee "LOGRESULTS             = ON\n" if($logresults);

#AOCL and SDACCEL only
print $tee "FLOW                   = [AOCLS and SDACCEL ONLY] $FLOW \n";
print $tee "UNROLL_FULL            = [AOCLS and SDACCEL ONLY] ON\n"             if($unrollFull);
print $tee "UNROLL_FACTOR          = [AOCLS and SDACCEL ONLY] $unrollFactor\n"  if($unrollFactor);

#AOCL only
print $tee "No-Interleaving?       = [AOCL ONLY] $noInterleaving\n";
print $tee "NUM_SIMD_ITEMS         = [AOCL ONLY] $numSimdItems\n";
print $tee "NUM_COMPUTE_UNITS      = [AOCL ONLY] $numComputeUnits\n";

#SDACCEL only
print $tee "XCL_PIPELINE_WORKITEMS = [SDACCEL ONLY] ON\n" if($xclpipelineWorkitems);
print $tee "XCL_PIPELINE_LOOP      = [SDACCEL ONLY] ON\n" if($xclpipelineLoop);
print $tee "max_memory_ports       = [SDACCEL ONLY] ON\n" if($xclmaxmemoryports);
print $tee "memory_port_data_width = [SDACCEL ONLY] $xclmemportwidth\n" if($xclmemportwidth);

close $tee;

#--------------------------------------------
#INVALID combination of experiment parameters
#--------------------------------------------
#vectors only work with contiguous data pattern
if (($vectorSize > 1) && ($ACCESS_PATTERN eq 'FIXED_STRIDE')) {
  die "BUILD.PL: Illegal setup. Vectors work only with contiguous data pattern.\n";
}
#Dimensions should be divisible by the vector size
if ( ($STREAM_ARRAY_SIZE_DIM1 % $vectorSize) !=0) {
  die "BUILD.PL: Illegal setup. Vector size must completely divide STREAM_ARRAY_SIZE_DIM1.\n";
}
#We can't have "NESTED" looping if we are using API looping; it can only be FLAT
if (($looping eq 'API') && ($nesting eq 'NESTED_KERNEL_LOOPING')) {
  die "BUILD.PL: Illegal setup. We can't have NESTED looping if we are using API looping; it can only be FLAT.\n";    
}

#We can't have UNROLL  if we are using API looping
if ( ($looping eq 'API') && (($unrollFull) || ($unrollFactor)) ) {
  die "BUILD.PL: Illegal setup. We can't have UNROLL defined for API looping\n";    
}

# --------------------------------------------
# >>>> Make a copy of soure files for logging
# --------------------------------------------
my $sourceFilesTarget = $targetDir."/srcCopy";
make_path($sourceFilesTarget);
#system ("cp ../common/streamHost-common.h   $sourceFilesTarget");
system ("cp ../device/streamKernel.cl       $sourceFilesTarget");
system ("cp ../host-all/streamHost-all.h    $sourceFilesTarget");
system ("cp ../host-all/streamHost-all.cpp  $sourceFilesTarget");
print "BUILD.PL: Backed up source files in $sourceFilesTarget\n";

#--------------------------------------------
# cd to target dir
#--------------------------------------------
print "BUILD.PL: Moving to target directory...\n";
chdir $targetDir;

# --------------------------------------------------------------------
# create custom .H file to pass macro definitions to kernel compiler 
# --------------------------------------------------------------------
print  "BUILD.PL: creating a custom include file for passing macro defintionst to kernel compiler\n";
my $kernelCompilerString  = "/*=========================================================================\n"
                          . "Custom kernel include file generated for this run:\n\t"
                          . $targetDir
                          . "\n=========================================================================*/\n"
                          ;
#first include all enumeration definitions defined in the common header file
#Note: obvious way would have been to simply include the common header file in the kernel code, if only!
# different opencl compilers seem to read relative paths to include files differently, so I have taken this route
my $handle;
my $enumerationsHeaderFile = "../../common/streamEnumerations.h";
open $handle, '<', $enumerationsHeaderFile;
chomp(my @lines = <$handle>);
close $handle;
$kernelCompilerString = $kernelCompilerString.join("\n", @lines);

#now append custom parameter definition for this run
$kernelCompilerString = $kernelCompilerString."\n\n"   
                 ." //===============================================\n"
                 ." // Custom parameter definitions for this run \n"
                 ." //===============================================\n"
                 ."#define TARGET                  $target     \n"
                 ."#define KERNELBENCH             $kernel     \n"
                 ."#define WORD                    $wordType   \n"
                 ."#define VECTOR_SIZE             $vectorSize \n"
                 ."#define LOOPING                 $looping    \n"
                 ."#define NESTING                 $nesting    \n"
                 ."#define TESTING                 $testing    \n"
                 ."#define ACCESS_PATTERN          $ACCESS_PATTERN         \n"    
                 ."#define STREAM_ARRAY_SIZE_DIM1  $STREAM_ARRAY_SIZE_DIM1 \n"
                 ."#define STRIDE_IN_WORDS         $STREAM_ARRAY_SIZE_DIM1 \n"
                 ."#define NUM_SIMD_ITEMS          $numSimdItems         \n"
                 ."#define NUM_COMPUTE_UNITS       $numComputeUnits      \n"
                 ." \n\n"
                 ;
#required workgroup size if defined
$kernelCompilerString = $kernelCompilerString."#define REQ_WORKGROUP_SIZE      $reqWorkgroupSize\n" if($reqWorkgroupSize);

#unroll factor append if relevant
$kernelCompilerString = $kernelCompilerString."#define UNROLL_FACTOR UNROLL_FULL\n"   if($unrollFull);
$kernelCompilerString = $kernelCompilerString."#define UNROLL_FACTOR $unrollFactor\n" if($unrollFactor);


#SDACCEL: Pipeline Workitems/loop
$kernelCompilerString = $kernelCompilerString."#define XCL_PIPELINE_WORKITEMS\n"  if($xclpipelineWorkitems);
$kernelCompilerString = $kernelCompilerString."#define XCL_PIPELINE_LOOP\n"       if($xclpipelineLoop);

#now append the derived parameter defintions from the common file used in both host and device
my $derivedParamsFile = "../../common/streamDerivedParameters.h";
open $handle, '<', $derivedParamsFile;
chomp(@lines = <$handle>);
close $handle;
$kernelCompilerString = $kernelCompilerString.join("\n", @lines);

#now write to file
my $kstringfile = "kernelCompilerInclude.h";
my $kstring;
unless (open $kstring, '>', $kstringfile) {
  die "\nUnable to create $kstringfile\n";    
}

print $kstring "$kernelCompilerString";
close $kstring;

#AOCL (SDACCEL?) are not able to find the include file when it is in the build folder.
#So we also make a copy of this file in the device folde where the kernel file is placed
system("cp -f kernelCompilerInclude.h ../../device");
#also store the genreated file in source code backup folder
print  "BUILD.PL: custom kernel include file created\n";

# =============================================================================================
# Pass KERNEL source through the pre-processor
# =============================================================================================
my $originalKernelFile = "../../device/streamKernel.source.cl";
my $preProcessedKernelFile = "../../device/streamKernel.cl";

#run pre-processor
system("cpp -I. -P $originalKernelFile > $preProcessedKernelFile");

#save generated kernel file in source code backup folder
system ("cp $preProcessedKernelFile ./srcCopy");

# =============================================================================================
# TARGET-SPECIFIC BUILD
# =============================================================================================

#-----------------------------------------------------------
# CPU-intel
#-----------------------------------------------------------
if ($target eq 'CPU') {
    my $makeString  = "make"
                    ." TARGET=$target"
                    ." STREAMSFROMTO=$streamsFromTo"
                    ." KERNELBENCH=$kernel"
                    ." WORD=$wordType"
                    ." VECTOR_SIZE=$vectorSize"
                    ." LOOPING=$looping"
                    ." NESTING=$nesting"
                    ." TESTING=$testing"
                    ." STREAM_ARRAY_SIZE_DIM1=$STREAM_ARRAY_SIZE_DIM1"
                    ." ACCESS_PATTERN=$ACCESS_PATTERN"
                    ." LOGRESULTS=$logresults"
                    ." $make"
                    ;

  #required workgroup size if defined
  $makeString = $makeString." REQ_WORKGROUP_SIZE=$reqWorkgroupSize" if($reqWorkgroupSize);

  print  "BUILD.PL: Calling makefile like this: ".$makeString."\n\n";
  system ("cp ../Makefile.template .");
  system ("mv Makefile.template Makefile");
  system  ($makeString);
}#if target eq CPU

#-----------------------------------------------------------
# GPU-nvidea
#-----------------------------------------------------------
elsif ($target eq 'GPU') {
    my $makeString  = "make"
                    ." TARGET=$target"
                    ." STREAMSFROMTO=$streamsFromTo"
                    ." KERNELBENCH=$kernel"
                    ." WORD=$wordType"
                    ." VECTOR_SIZE=$vectorSize"
                    ." LOOPING=$looping"
                    ." NESTING=$nesting"
                    ." TESTING=$testing"
                    ." STREAM_ARRAY_SIZE_DIM1=$STREAM_ARRAY_SIZE_DIM1"
                    ." ACCESS_PATTERN=$ACCESS_PATTERN"
                    ." LOGRESULTS=$logresults"
                    ." $make"
                    ;

  #required workgroup size if defined
  $makeString = $makeString." REQ_WORKGROUP_SIZE=$reqWorkgroupSize" if($reqWorkgroupSize);

  print  "BUILD.PL: Calling makefile like this: ".$makeString."\n\n";
  system ("cp ../Makefile.template .");
  system ("mv Makefile.template Makefile");
  system  ($makeString);
}#if target eq GPU

#-----------------------------------------------------------
# SDACCEL (TCL) target
#-----------------------------------------------------------
elsif ($target eq 'SDACCEL') {

  # >>>> GENERATE CUSTOM TCL
  # --------------------------------

  #note that unlike other targets, we call TCL file from ABOVE the
  #target build folder. Since we have cd'ed to it, we go one step up here...
  chdir("..");

  # temp string buffer used in file generation 
  my $strBuf = ""; 

  #target TCL file, same name as target build folder
  my $targetTclFilename = $targetDir.".tcl";  
  open(my $tclfh, '>', $targetTclFilename)
    or die "BUILD.PL: Could not open file '$targetTclFilename' $!";  
  
  # >>>> Load TCL build template file
  my $templateFileName = "perl-build.tcl.template"; 
  open (my $fhTemplate, '<', $templateFileName)
    or die "BUILD.PL: Could not open file '$templateFileName' $!"; 

  # >>>> Read template contents into string
  my $genCode = read_file ($fhTemplate);
  close $fhTemplate;

  # >>>>> Update parameter definitions
  $strBuf = "$strBuf"."set STREAM_ARRAY_SIZE_DIM1 $STREAM_ARRAY_SIZE_DIM1\n";
  $strBuf = "$strBuf"."set VECTOR_SIZE            $vectorSize\n";
  $strBuf = "$strBuf"."set TARGET                 \"$target\"\n";
  $strBuf = "$strBuf"."set STREAMSFROMTO          \"$streamsFromTo\"\n";
  $strBuf = "$strBuf"."set KERNELBENCH            \"$kernel\"\n";
  $strBuf = "$strBuf"."set WORD                   \"$wordType\"\n";
  $strBuf = "$strBuf"."set REQ_WORKGROUP_SIZE     \"$reqWorkgroupSize\"\n" if($reqWorkgroupSize);
  $strBuf = "$strBuf"."set LOOPING                \"$looping\"\n";
  $strBuf = "$strBuf"."set NESTING                \"$nesting\"\n";
  $strBuf = "$strBuf"."set TESTING                \"$testing\"\n";
  $strBuf = "$strBuf"."set FLOW                   \"$FLOW\"\n";
  $strBuf = "$strBuf"."set ACCESS_PATTERN         \"$ACCESS_PATTERN\"\n";
  $strBuf = "$strBuf"."set Make                   \"$make\"\n";
  $strBuf = "$strBuf"."set projectPrefix          \"$projectPrefix\"\n";
  $strBuf = "$strBuf"."set destDir                \"$targetDir\"\n";
  $strBuf = "$strBuf"."set timeStamp              \"$timeStamp\"\n";
  $genCode =~ s/<params>/$strBuf/g;

  #enable max_memory_ports=true or not
  $strBuf = "";
  $strBuf = "$strBuf"
          ."set_property max_memory_ports true [get_kernels \$kernel]\n" if($xclmaxmemoryports);

  #set memory_port_data_width if specified
  $strBuf = "$strBuf"
          ."set_property memory_port_data_width $xclmemportwidth [get_kernels \$kernel]\n\n" if($xclmemportwidth);


  $genCode =~ s/<max_memory_ports>/$strBuf/g;

  # report estimate or not
  $strBuf = "";
  if($estimate) {
    $strBuf = "$strBuf"."\n# ---------------------------------------------------------\n";
    $strBuf = "$strBuf"."# Generate the system estimate report\n";
    $strBuf = "$strBuf"."# ---------------------------------------------------------\n";
    $strBuf = "$strBuf"."report_estimate\n";
  }
  $genCode =~ s/<estimate>/$strBuf/g;

  # do HW build or not
  $strBuf = "";
  if ($FLOW eq 'hw') {
    $strBuf = "$strBuf"."\n# ---------------------------------------------------------\n";
    $strBuf = "$strBuf"."# Compile the application to run on the accelerator card\n";
    $strBuf = "$strBuf"."# ---------------------------------------------------------\n";
    $strBuf = "$strBuf"."build_system\n";
    $strBuf = "$strBuf"."\n";
    $strBuf = "$strBuf"."# ---------------------------------------------------------\n";
    $strBuf = "$strBuf"."# Package the application binaries\n";
    $strBuf = "$strBuf"."# ---------------------------------------------------------\n";
    $strBuf = "$strBuf"."package_system\n";
  }
  $genCode =~ s/<hw>/$strBuf/g;



  # >>>>> Write to file and make a backup copy
  $genCode =~ s/\r//g; #to remove the ^M  
  print $tclfh $genCode;
  print "BUILD.PL: Generated custom TCL file \n";
  close $tclfh;
  system ("cp $targetTclFilename $sourceFilesTarget");
  
  # call TCL
  # ---------
  system ("sdaccel $targetTclFilename");

  # run if asked
  # -------------
  my $execDir = $targetDir."/pkg/pcie/";
  my $executable = $targetDir.".exe";
  my $xclbin = "streamKernel.xclbin";

  if (($make eq 'run') && ($FLOW eq 'hw')) {
    print "BUILD.PL: Running HW \n";
    chdir "$execDir";
    print "BUILD.PL: cd to target directory $execDir\n";
    system ("./".$executable." ".$xclbin."\n");
    print "BUILD.PL: Running executable on hardware\n";
    chdir "../../../";
    print "BUILD.PL: cd back to parent directory\n";
  }#if
}#if target eq SDACCEL

#-----------------------------------------------------------
# AOCL target
#-----------------------------------------------------------
elsif ($target eq 'AOCL') {
  my $makeString = "make"
          ." TARGET=$target"
          ." STREAMSFROMTO=$streamsFromTo"
          ." KERNELBENCH=$kernel WORD=$wordType"
          ." VECTOR_SIZE=$vectorSize"
          ." NUM_SIMD_ITEMS=$numSimdItems"
          ." NUM_COMPUTE_UNITS=$numComputeUnits"
          ." LOOPING=$looping NESTING=$nesting"
          ." NO_INTERLEAVING=$noInterleaving"
          ." TESTING=$testing"
          ." STREAM_ARRAY_SIZE_DIM1=$STREAM_ARRAY_SIZE_DIM1"
          ." ACCESS_PATTERN=$ACCESS_PATTERN"
          ." FLOW=$FLOW"
          ." $make"
          ;

  #required workgroup size if defined
  $makeString = $makeString." REQ_WORKGROUP_SIZE=$reqWorkgroupSize" if($reqWorkgroupSize);

  print   "BUILD.PL: Calling makefile like this: ".$makeString."\n\n";
  system ("cp ../Makefile.template .");
  system ("mv Makefile.template Makefile");
  #system ("cp ../Makefile .");
  system ($makeString);
}#if target eq AOCL

#-----------------------------------------------------------
# DIE
#-----------------------------------------------------------
else
  {die "Invalid TARGET specification";}

# =============================================================================================
# POST PROCESSING
# =============================================================================================

  # store results in common database file if this was a make type "run"
  # also, if it was an FPGA run, then the FLOW must be HW
  # -----------------------------------------------------------------
  if  ( ($make eq 'run')  
        &&  (   ($FPGA && ($FLOW eq 'hw'))
            ||  (!($FPGA))
            )
      ) {

    my $handle;

    # SDACCEL SPECIFIC
    #-----------------
    my @linesSdaccelEstimateReport;
    #if sdaccel, go back down to BUILD folder
    chdir ($targetDir) if ($target eq 'SDACCEL');
    #name of input files containing estimates - only for SDACCEl for now
    my $estimateFile;
    $estimateFile = "/rpt/system_estimate.txt";
    if($target eq 'SDACCEL') {
      open $handle, '<', $estimateFile;
      chomp(@linesSdaccelEstimateReport = <$handle>);
      close $handle;
    }

    # AOCL SPECIFIC
    #-----------------
    #this is the dir where the build files are put by make for AOCL
    my $aocBuildDir =  "stream-opencl-".$STREAM_ARRAY_SIZE_DIM1."-".$ACCESS_PATTERN."-".$FLOW;
    
    #name of three relevant input files
    my $areaReportFile = $aocBuildDir."/area.rpt";
    my $quartusReportFile = $aocBuildDir."/acl_quartus_report.txt";
    
    my @linesAreaReport;
    my @linesQuartusReport;

    if ($target eq 'AOCL') {
      open $handle, '<', $areaReportFile;
      chomp(@linesAreaReport = <$handle>);
      close $handle;
  
      open $handle, '<', $quartusReportFile;
      chomp(@linesQuartusReport = <$handle>);
      close $handle;
    }

    # COMMON
    #-----------------
    #results of bandwidth
    my $bandwidthResultsFile  = "RESULTS.log";
    $bandwidthResultsFile     = "./pkg/pcie/RESULTS.log" if($target eq 'SDACCEL');
    open $handle, '<', $bandwidthResultsFile;
    chomp(my @linesBandwidthResults = <$handle>);
    close $handle;

    #name of master database file for writing extracted results
    my $masterFile = "../masterResults.log";
    my $master;
    open $master, '>>', $masterFile;



    #----------------------------------
    #print out the relevant lines
    #----------------------------------
    print $master "=======================================\n";
    print $master "  Experiment timestamp =  $timeStamp\n";
    print $master "=======================================\n";
    print $master "Parameters:\n";
    print $master "-----------\n";
    print $master "TARGET                 = $target\n";
    print $master "STREAMSFROMTO          = $streamsFromTo\n";
    print $master "KERNELBENCH            = $kernel\n";
    print $master "WORD                   = $wordType\n";
    print $master "STREAM_ARRAY_SIZE_DIM1 = $STREAM_ARRAY_SIZE_DIM1\n";
    print $master "VECTOR_SIZE            = $vectorSize\n";
    print $master "LOOPING                = $looping\n";
    print $master "NESTING                = $nesting\n";
    print $master "TESTING                = $testing\n";
    print $master "ACCESS_PATTERN         = $ACCESS_PATTERN \n";
    print $master "Make                   = $make \n";
    print $master "projectPrefix          = $projectPrefix \n";
    print $master "targerDir              = $targetDir\n";
    print $master "logresults             = $logresults\n";


    print $master "\nBandwidth Results:\n";
    print $master "-------------------\n";
    print $master $linesBandwidthResults[0];
    print $master "\n";
    print $master $linesBandwidthResults[1];
    print $master "\n\n\n\n";

    #SDACCEL specific results
    #-------------------------
    if($target eq 'SDACCEL'){
      print $master "\nSDACCEL: Resouce Results:\n";
      print $master "---------------------------\n";
      print $master "\n";
      print $master $linesSdaccelEstimateReport[45]."\n";
      print $master $linesSdaccelEstimateReport[46]."\n";
      print $master $linesSdaccelEstimateReport[47]."\n";
      print $master $linesSdaccelEstimateReport[48]."\n";
      print $master $linesSdaccelEstimateReport[49]."\n";
      print $master $linesSdaccelEstimateReport[50]."\n";
      print $master "\n";

      print $master "\nSDACCEL: Frequency:\n";
      print $master "-----------------------\n";
      print $master "\n";
      print $master $linesSdaccelEstimateReport[31]."\n";
      print $master $linesSdaccelEstimateReport[32]."\n";
      print $master $linesSdaccelEstimateReport[33]."\n";
      print $master $linesSdaccelEstimateReport[34]."\n";
      print $master $linesSdaccelEstimateReport[35]."\n";
      print $master $linesSdaccelEstimateReport[36]."\n";
      print $master "\n";
    }

    #AOCL specific results
    #-------------------------
    if ($target eq 'AOCL') {
      print $master "\nAOCL: Resouce Results:\n";
      print $master "------------------------\n";
      print $master "\n";
      print $master $linesAreaReport[0];
      print $master "\n";
      print $master $linesQuartusReport[7];
      print $master "\n";
    }
    close $master;

    printf("\nBUILD.PL: Written benchmark BW results to $masterFile\n");
  }

#my $end = Time::HiRes::gettimeofday();
my @end = localtime();
printf("\nBUILD.PL: The build type <%s> took %.2f seconds\n",$make,  $end[0]- $start[0]);
printf("\nBUILD.PL: Build files have been saved in $targetDir\n");
printf("==================================================================\n");
printf("BUILD.PL: ---- BUILD COMPLETE ----\n",$make,  $end[0] - $start[0]);
printf("==================================================================\n");
printf("\n\n\n\n");

# ----------------------------------------------------------------------------
#
# ----------------------------------------------------------------------------
sub printHelp {
  print "\nOpenCL stream Benchmark build script command line options and defaults (*)\n";
  print "--------------------------------------------------------------------------------------\n";
  print "-tar[AOCL/SDACCEL/GPU/CPU]      <*>: Target platform. MUST be specified.\n";
  print "-p  [stream]                       : the prefix to use for all project files, directories, etc\n";
  print "-sft[GMEM*/HOST]                   : Streams from/to host or Global Memory. Not relevant for CPU targets.\n";
  print "-k  [COPY*/MUL/ADD/TRIAD]          : which of the 4 benchmark kernels are we running?\n";
  print "-w  [INT*/FLOAT/DOUBLE]            : data-type of WORD used in the streams \n";
  print "-d  [1024]                         : size along one-dimension of the square 2D input matrix\n";
  print "-r  [NULL*]                        : Value for attribute <reqd_work_group_size>\n";
  print "-a  [CONTIGUOUS*/FIXED_STRIDE]     : access pattern \n";
  print "-v  [1]                            : size of vector for kernel streams (1 = scalar) \n";
  print "-l  [API*/KERNEL]                  : how is the looping over work-items handled\n";
  print "-n  [FLAT_LOOPING*/NESTED_LOOPING] : is the 2D looping nested or flat?\n";
  print "-t  [RW*/RO/WO]                    : testing read-write both, or only one (only for COPY kernel)\n";
  print "-m  [all*/host/aoclbin/run/clean]  : type of make\n";
  print "-log                               : do you want to log results to file?\n";
  print "-h                                 : print help \n";
  #print "\n";
  #print "-batch                             : Run a batch job. List of jobs ALWAYS picked from jobs.bat file in THIS folder.\n";
  #print "\n";

  print "\nAOCL+SDACCEL specific parameters\n";
  print "----------------------------------\n";
  print "-f  [cpu_emu*/hw_emu/hw]           : build flow\n";
  print "-uf [undefined]                    : should loop be FULLY  unrolled(only for -l = KERNEL)\n";
  print "-un N                              : should loop be unrolled by a factor of N? (only for -l = KERNEL)\n";
  
  print "\nAOCL specific parameters\n";
  print "--------------------------\n";
  print "-s  [1]                            : AOCL optimization attribute <num_simd_work_items>\n";
  print "-c  1                              : AOCL optimization attribute <num_compute_units>\n";
  print "-ni [undef]                        : No-Interleaving of (default) Global Memory?\n";

  print "\nSDACCEL specific parameters\n";
  print "-----------------------------\n";
  print "-e  [undef*]                       : include if you want to call \"report_estimate\".  \n";
  print "                                     turned in automatically if flow = hw              \n";
  print "-xpw [undef*]                      : turn on XCL_PIPELINE_WORKITEMS\n";
  print "-xpl [undef*]                      : turn on XCL_PIPELINE_LOOP\n";
  print "-xmm [undef*]                      : enable sdaccel optimization max_memory_ports\n";
  print "-xmw [undef*]                      : value for xcl opt' param' <memory_port_data_width>\n";

  print "\nGPU specific parameters\n";
  print "-------------------------\n";

  print "\nCPU specific parameters\n";
  print "-------------------------\n";


  print "\nUsage example\n";
  print "-------------\n";
  print "./build.pl -p stream -w int -d 1000 -a CONTIGUOUS -v 1 -l API -f hw -m host -v 1\tOR\n";
  print "perl build.pl <flags>\n";
  print "\nNotes\n";
  print "--------\n";
  print "1. If parameters not relevant to target are specified, they are ignored. No errors or warnings are raised\n";
  print "2. <*> indicated REQUIRED option \n";

}

sub read_file {
(my $fh) = @_;

my $res_str='';

while (my $str=<$fh>) {
$res_str.=$str;
}
#close $fh;
return $res_str;

}
