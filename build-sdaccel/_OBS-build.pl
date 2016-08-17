#!/usr/bin/perl -w

# Usage example
#       ./build.pl -p stream -d 2000 -f cpu_emu -a CONTIGUOUS -m host -v
# OR perl build.pl -p stream -d 2000 -f cpu_emu -a CONTIGUOUS -m host -v
#

use strict;
use warnings;
use Getopt::Long;   #for command line options
use File::Slurp;
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
use Time::HiRes qw( usleep ualarm gettimeofday tv_interval nanosleep
          clock_gettime clock_getres clock_nanosleep clock
                      stat);
#use Text::CSV;

my $start = Time::HiRes::gettimeofday();

#===============================
our $target = 'SDACCEL';
#===============================

# default options, and list of possible command line options
#----------------------------------------------------------
our $projectPrefix  = 'stream'; #the prefix to use for all project files, directories, etc
our $STREAM_ARRAY_SIZE_DIM1 = 1024;
our $FLOW = 'cpu_emu';
  #our $FLOW = 'hw';
  #our $FLOW = 'hw_emu';

our $AP   = 'CONTIGUOUS';
  #our $AP   = 'FIXED_STRIDE';

our $make = 'all'; #make all by default
  #our $make = 'run'; 

our $vectorSize = 1; #scalar by default

our $help = '';

our $looping = 'API'; #looping managed by the opencl API by default
 #our $looping = 'kernel'; 

our $nesting = ''; #if KERNEL looping, then NESTED or FLAT?
  #our $nesting = 'FLAT_KERNEL_LOOPING'; 
  #our $nesting = 'NESTED_KERNEL_LOOPING'; 


our $testing = 'RW'; #testing both read and write by default
 #our $testing = 'RO'; 
 #our $testing = 'WO'; 

our $wordType = 'INT';
  #our $wordType = 'FLOAT';
  #our $wordType = 'DOUBLE';

#our $numSimdItems = 1;

#our $reqWorkgroupSize = '1,0,0';

#our $numComputeUnits = 1;

our $batch = '';

#our $noInterleaving = '';

our $kernel = 'COPY';

our $streamsFromTo = 'GMEM';
#[COPY*/MUL/ADD/TRIAD]


our $estimate = '';

#get options from command line
#-----------------------------
GetOptions (
    'p=s'   =>  \$projectPrefix
  , 'sft=s' =>  \$streamsFromTo
  , 'k=s'   =>  \$kernel
  , 'd=s'   =>  \$STREAM_ARRAY_SIZE_DIM1               
  , 'w=s'   =>  \$wordType
  , 'l=s'   =>  \$looping
  , 'n=s'   =>  \$nesting
  , 'v=s'   =>  \$vectorSize
  , 't=s'   =>  \$testing
  , 'f=s'   =>  \$FLOW  
  , 'e'     =>  \$estimate       
  , 'a=s'   =>  \$AP
  , 'm=s'   =>  \$make
  , 'h'     =>  \$help
  , 'batch' =>  \$batch
  );

#get local time to create unique folder name
my $sec, my $min, my $hour, my $mday, my $mon, my $year, my $wday, my $yday, my $isdst;
($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
                                                localtime(time);

if($help) {
  printHelp();
  exit;
}

my $timeStamp =$yday.".".$hour.$min.$sec;



#Build instance if not Batch job
#---------------------------------

my $targetDir 
  = "build-".$timeStamp."-".$projectPrefix."-".$kernel."-".$wordType.$vectorSize
  . "-".$looping."Looping-".$nesting."-".$testing."-".$FLOW."-".$STREAM_ARRAY_SIZE_DIM1."-".$AP;
    

  #print pre-build messages
  #--------------------------
  print "BUILD.PL: Building with the following options...\n";
  print "------------------------------------------------\n";
  print "TARGET                 = $target\n";
  print "STREAMSFROMTO          = $streamsFromTo\n";
  print "KERNELBENCH            = $kernel\n";
  print "WORD                   = $wordType\n";
  print "STREAM_ARRAY_SIZE_DIM1 = $STREAM_ARRAY_SIZE_DIM1\n";
  print "VECTOR_SIZE            = $vectorSize\n";
  print "LOOPING                = $looping\n";
  print "NESTING                = $nesting\n";
  print "TESTING                = $testing\n";
  print "FLOW                   = $FLOW\n";
  print "ACCESS_PATTERN         = $AP \n";
  print "Make                   = $make \n";
  print "projectPrefix          = $projectPrefix \n";
  print "targerDir              = $targetDir\n";
  print "timeStamp              = $timeStamp\n";

  #INVALID combination of experiment parameters
  #--------------------------------------------
  #vectors only work with contiguous data pattern
  if (($vectorSize > 1) && ($AP eq 'FIXED_STRIDE')) {
    die "BUILD.PL: Illegal setup. Vectors work only with contiguous data pattern.\n";
  }

  #Dimensions should be divisible by the vector size
  if ( ($STREAM_ARRAY_SIZE_DIM1 % $vectorSize) !=0) {
    die "BUILD.PL: Illegal setup. Vector size must completely divide DIM1.\n";
  }

  #We can't have "NESTED" looping if we are using API looping; it can only be FLAT
  if (($looping eq 'API') && ($nesting eq 'NESTED_KERNEL_LOOPING')) {
    die "BUILD.PL: Illegal setup. We can't have NESTED looping if we are using API looping; it can only be FLAT.\n";    
  }

  
  # ---------------------------------------------
  # >>>> Make a copy of soure files for logging
  # --------------------------------------------
  my $sourceFilesTarget = $targetDir."/srcCopy";
  make_path($sourceFilesTarget);

  system ("cp ../common/streamHost-common.h   $sourceFilesTarget");
  system ("cp ../device/streamKernel.cl       $sourceFilesTarget");
  system ("cp ../host-all/streamHost-all.h    $sourceFilesTarget");
  system ("cp ../host-all/streamHost-all.cpp  $sourceFilesTarget");

  print "BUILD.PL: Backed up source files in $sourceFilesTarget\n";

  # --------------------------------
  # >>>> GENERATE CUSTOM TCL
  # --------------------------------

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
  $strBuf = "$strBuf"."set LOOPING                \"$looping\"\n";
  $strBuf = "$strBuf"."set NESTING                \"$nesting\"\n";
  $strBuf = "$strBuf"."set TESTING                \"$testing\"\n";
  $strBuf = "$strBuf"."set FLOW                   \"$FLOW\"\n";
  $strBuf = "$strBuf"."set ACCESS_PATTERN         \"$AP\"\n";
  $strBuf = "$strBuf"."set Make                   \"$make\"\n";
  $strBuf = "$strBuf"."set projectPrefix          \"$projectPrefix\"\n";
  $strBuf = "$strBuf"."set destDir                \"$targetDir\"\n";
  $strBuf = "$strBuf"."set timeStamp              \"$timeStamp\"\n";
  $genCode =~ s/<params>/$strBuf/g;

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

  # >>>>> Write to file
  $genCode =~ s/\r//g; #to remove the ^M  
  print $tclfh $genCode;
  print "BUILD.PL: Generated custom TCL file \n";
  close $tclfh;
  
  # call TCL
  # ---------
  system ("sdaccel $targetTclFilename");

  # run if asked
  # -------------
  my $execDir = $targetDir."/pkg/pcie/";
  my $executable = $targetDir.".exe";
  my $xclbin = "streamKernel.xclbin";

  if ($make eq 'run') {
    print "BUILD.PL: Running HW \n";

    #system ("cd $execDir\n");
    chdir "$execDir";
    print "BUILD.PL: cd to target directory $execDir\n";

    system ("./".$executable." ".$xclbin."\n");
    print "BUILD.PL: Running executable on hardware\n";

    chdir "../../../";
    #system ("cd ../../..\n");
    print "BUILD.PL: cd back to parent directory\n";
  }

  # ========================
  # Post processing
  # ========================
  my $end = Time::HiRes::gettimeofday();
  printf("\nBUILD.PL: The build type <%s> took %.2f seconds\n",$make,  $end - $start);
  printf("BUILD.PL: ---- BUILD COMPLETE ----\n\n\n",$make,  $end - $start);

  
  # store results in common database file if this was a make type "run" for hardware flow
  # --------------------------------------------------------------------------------------
  if(($make eq 'run') && ($FLOW eq 'hw')) {
  
  #name of input files containing estimates
  my $estimateFile = $targetDir."/rpt/system_estimate.txt";

  #name of master database file for writing extracted results
  my $masterFile = "masterResults.csv";
  my $master;
  open $master, '>>', $masterFile;

  #read estimate file contents into array
  my $handle;
  open $handle, '<', $estimateFile;
  chomp(my @linesReport = <$handle>);
  close $handle;

  print "BUILD.PL: storing results in $masterFile\n";

  #print out the relevant lines
  print $master "\n\nExperiment timestamp =  $timeStamp\n";
  print $master     "=======================================\n";
  print $master "Parameters:\n";
  print $master "-----------\n";
  print $master "STREAMSFROMTO          = $streamsFromTo\n";
  print $master "KERNELBENCH            = $kernel\n";
  print $master "WORD                   = $wordType\n";
  print $master "STREAM_ARRAY_SIZE_DIM1 = $STREAM_ARRAY_SIZE_DIM1\n";
  print $master "VECTOR_SIZE            = $vectorSize\n";
  print $master "LOOPING                = $looping\n";
  print $master "NESTING                = $nesting\n";
  print $master "TESTING                = $testing\n";
  print $master "FLOW                   = $FLOW\n";
  print $master "ACCESS_PATTERN         = $AP \n";
  print $master "Make                   = $make \n";
  print $master "projectPrefix          = $projectPrefix \n";
  print $master "targerDir              = $targetDir\n";

  print $master "\nResouce Results:\n";
  print $master "------------------\n";
  print $master "\n";
  print $master $linesReport[45]."\n";
  print $master $linesReport[46]."\n";
  print $master $linesReport[47]."\n";
  print $master $linesReport[48]."\n";
  print $master $linesReport[49]."\n";
  print $master $linesReport[50]."\n";
  print $master "\n";

 print $master "\nFrequency:\n";
 print $master "-------------------\n";
 print $master "\n";
 print $master $linesReport[31]."\n";
 print $master $linesReport[32]."\n";
 print $master $linesReport[33]."\n";
 print $master $linesReport[34]."\n";
 print $master $linesReport[35]."\n";
 print $master $linesReport[36]."\n";
 print $master "\n";
 close $master;
}#if results need to be logged
 
# ----------------------------------------------------------------------------
#
# ----------------------------------------------------------------------------
sub printHelp {
  print "\nSDACCEL Stream Benchmark build script command line options and defaults (*)\n";
  print "----------------------------------------------------------------------\n";
  print "-p  [stream]                       : the prefix to use for all project files, directories, etc\n";
  print "-sft[GMEM*/HOST]                   : Streams from/to host or device-DRAM (Global Memory)\n";
  print "-k  [COPY*/MUL/ADD/TRIAD]          : which of the 4 benchmark kernels are we running?\n";
  print "-w  [INT*/FLOAT/DOUBLE]            : data-type of WORD used in the streams \n";
  print "-d  [1024]                         : size along one-dimension of the square 2D input matrix\n";
  print "-a  [CONTIGUOUS*/FIXED_STRIDE]     : access pattern \n";
  print "-v  [1]                            : size of vector for kernel streams (1 = scalar) \n";
  print "-l  [API*/KERNEL]                  : how is the looping over work-items handled\n";
  print "-t  [RW*/RO/WO]                    : testing read-write both, or only one\n";
  print "-m  [all*/run]                     : type of make (use of TCL limits to these two)\n";
  print "-f  [cpu_emu*/hw_emu/hw]           : build flow  \n";
  print "-e  [undefined*]                   : include if you want to call \"report_estimate\"  \n";
  print "-h                                 : print help \n";
  #print "\n";
  #print "-batch                             : Run a batch job. List of jobs ALWAYS picked from jobs.bat file in THIS folder.\n";
  print "\n";
  print "Usage example\n";
  print "-------------\n";
  print "./build.pl -p stream -w int -d 1000 -a CONTIGUOUS -v 1 -l API -f hw -m host -v 1\tOR\n";
  print "perl build.pl <flags>\n";
  print "\n";
}
