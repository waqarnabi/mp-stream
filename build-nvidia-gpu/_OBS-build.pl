#!/usr/bin/perl -w

# Usage example
#       ./build.pl -p stream -d 2000 -f cpu_emu -a CONTIGUOUS -m host -v
# OR perl build.pl -p stream -d 2000 -f cpu_emu -a CONTIGUOUS -m host -v
#

use strict;
use warnings;
use Getopt::Long;   #for command line options
use File::Path qw(make_path remove_tree);
use Time::HiRes qw( usleep ualarm gettimeofday tv_interval nanosleep
          clock_gettime clock_getres clock_nanosleep clock
                      stat);
#use Text::CSV;

#----------------------------------------------------------
our $target = 'GPU';
#----------------------------------------------------------

my $start = Time::HiRes::gettimeofday();
# default options, and list of possible command line options
#----------------------------------------------------------
our $projectPrefix  = 'stream'; #the prefix to use for all project files, directories, etc
our $DIM1 = 1024;

our $AP   = 'CONTIGUOUS';
  #our $AP   = 'FIXED_STRIDE';

our $make = 'all'; #make all by default
  #our $make = 'run'; 
  #our $make = 'host'; 
  #our $make = 'aoclbin'; 
  #our $make = 'clean'; 

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

#get options from command line
#-----------------------------
GetOptions (
    'p=s'   =>  \$projectPrefix
  , 'sft=s' =>  \$streamsFromTo
  , 'k=s'   =>  \$kernel
  , 'd=s'   =>  \$DIM1               
  , 'w=s'   =>  \$wordType
  , 'l=s'   =>  \$looping
  , 'n=s'   =>  \$nesting
  , 'v=s'   =>  \$vectorSize
  , 't=s'   =>  \$testing
  , 'a=s'   =>  \$AP
  , 'm=s'   =>  \$make
  , 'h'     =>  \$help
  , 'log'   =>  \$logresults
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

  my $targetDir 
    = "build-".$timeStamp."-".$projectPrefix."-".$kernel."-".$wordType.$vectorSize
    . "-".$looping."Looping-".$nesting."-".$testing."-".$DIM1."-".$AP;
  
  #print pre-build messages
  #--------------------------
  print "Building with the following options...\n";
  print "--------------------------------------\n";
  print "TARGET             = $target\n";
  print "STREAMSFROMTO      = $streamsFromTo\n";
  print "KERNELBENCH        = $kernel\n";
  print "WORD               = $wordType\n";
  print "DIM1               = $DIM1\n";
  print "VECTOR_SIZE        = $vectorSize\n";
  print "LOOPING            = $looping\n";
  print "NESTING            = $nesting\n";
  print "TESTING            = $testing\n";
  print "AP                 = $AP \n";
  print "Make               = $make \n";
  print "projectPrefix      = $projectPrefix \n";
  print "targerDir          = $targetDir\n";
  print "timeStamp          = $timeStamp\n";
  print "LOGRESULTS         = ON\n" if($logresults);


  #INVALID combination of experiment parameters
  #--------------------------------------------
  #vectors only work with contiguous data pattern
  if (($vectorSize > 1) && ($AP eq 'FIXED_STRIDE')) {
    die "BUILD.PL: Illegal setup. Vectors work only with contiguous data pattern.\n";
  }

  #Dimensions should be divisible by the vector size
  if ( ($DIM1 % $vectorSize) !=0) {
    die "BUILD.PL: Illegal setup. Vector size must completely divide DIM1.\n";
  }

  #We can't have "NESTED" looping if we are using API looping; it can only be FLAT
  if (($looping eq 'API') && ($nesting eq 'NESTED_KERNEL_LOOPING')) {
    die "BUILD.PL: Illegal setup. We can't have NESTED looping if we are using API looping; it can only be FLAT.\n";    
  }

  # >>>> Make a copy of soure files for logging
  # --------------------------------------------
  my $sourceFilesTarget = $targetDir."/srcCopy";
  make_path($sourceFilesTarget);

  system ("cp ../common/streamHost-common.h   $sourceFilesTarget");
  system ("cp ../device/streamKernel.cl       $sourceFilesTarget");
  system ("cp ../host-all/streamHost-all.h    $sourceFilesTarget");
  system ("cp ../host-all/streamHost-all.cpp  $sourceFilesTarget");

  print "BUILD.PL: Backed up source files in $sourceFilesTarget\n";


  # create target directory, cd to it
  # -----------------------
  print "\nBUILD.PL: Making target directory $targetDir...\n";
  make_path($targetDir);
  print "BUILD.PL: Moving to target directory...\n";
  chdir $targetDir;
  
  # create custom .H file to pass macro definitions to kernel compiler 
  # --------------------------------------------------------------------
  print  " BUILD.PL: creating a custom include file for passing macro defintionst to kernel compiler\n";
  my $openclcompilerstring = ""   
                   ." #define TARGET                  $target     \n"
                   ." #define KERNELBENCH             $kernel     \n"
                   ." #define WORD                    $wordType   \n"
                   ." #define VECTOR_SIZE             $vectorSize \n"
                   ." #define LOOPING                 $looping    \n"
                   ." #define NESTING                 $nesting    \n"
                   ." #define TESTING                 $testing    \n"
                   ." #define STREAM_ARRAY_SIZE_DIM1  $DIM1       \n"
                   ." #define ACCESS_PATTERN          $AP         \n"    
                   ;
  my $cstringfile = "openclcompilerstring.h";
  my $cstring;
  unless (open $cstring, '>', $cstringfile) {
    die "\nUnable to create $cstringfile\n";    
  }

  print $cstring "$openclcompilerstring";
  close $cstring;

  # call make
  # --------
  print  " BUILD.PL: Calling makefile like this: make"
        ." TARGET=$target"
        ." STREAMSFROMTO=$streamsFromTo"
        ." KERNELBENCH=$kernel"
        ." WORD=$wordType"
        ." VECTOR_SIZE=$vectorSize"
        ." LOOPING=$looping"
        ." NESTING=$nesting"
        ." TESTING=$testing"
        ." DIM1=$DIM1"
        ." AP=$AP"
        ." LOGRESULTS=$logresults"
        ." $make"
        ." n\n"
        ;
  system ("cp ../Makefile .");
  system  ("make TARGET=$target"
          ." STREAMSFROMTO=$streamsFromTo"
          ." KERNELBENCH=$kernel"
          ." WORD=$wordType"
          ." VECTOR_SIZE=$vectorSize"
          ." LOOPING=$looping"
          ." NESTING=$nesting"
          ." TESTING=$testing"
          ." DIM1=$DIM1"
          ." AP=$AP"
          ." LOGRESULTS=$logresults"
          ." $make"
          );
  my $end = Time::HiRes::gettimeofday();
  printf("\nBUILD.PL: The build type <%s> took %.2f seconds\n",$make,  $end - $start);
  printf("==================================================================\n");
  printf("BUILD.PL: ---- BUILD COMPLETE ----\n",$make,  $end - $start);
  printf("==================================================================\n");
  printf("\n\n\n\n");

# store results in common database file if this was a make type "run"s
  # --------------------------------------------------------------------------------------
  if($make eq 'run') {
    my $bandwidthResultsFile = "RESULTS.log";

    #name of master database file for writing extracted results
    my $masterFile = "../masterResults.log";
    my $master;
    open $master, '>>', $masterFile;

    my $handle;
    open $handle, '<', $bandwidthResultsFile;
    chomp(my @linesBandwidthResults = <$handle>);
    close $handle;

    #open $handle, '<', $quartusReportFile;
    #chomp(my @linesQuartusReport = <$handle>);
    #close $handle;

    #print out the relevant lines
    print $master "=======================================\n";
    print $master "  Experiment timestamp =  $timeStamp\n";
    print $master "=======================================\n";
    print $master "Parameters:\n";
    print $master "-----------\n";
    print $master "TARGET             = $target\n";
    print $master "STREAMSFROMTO      = $streamsFromTo\n";
    print $master "KERNELBENCH        = $kernel\n";
    print $master "WORD               = $wordType\n";
    print $master "DIM1               = $DIM1\n";
    print $master "VECTOR_SIZE        = $vectorSize\n";
    print $master "LOOPING            = $looping\n";
    print $master "NESTING            = $nesting\n";
    print $master "TESTING            = $testing\n";
    print $master "AP                 = $AP \n";
    print $master "Make               = $make \n";
    print $master "projectPrefix      = $projectPrefix \n";
    print $master "targerDir          = $targetDir\n";
    print $master "logresults         = $logresults\n";

    print $master "\nBandwidth Results:\n";
    print $master "-------------------\n";
    print $master $linesBandwidthResults[0];
    print $master "\n";
    print $master $linesBandwidthResults[1];
    print $master "\n\n\n\n";
    close $master;
  }

#cleanup
#============
#delete the temporary .h file

 
# ----------------------------------------------------------------------------
#
# ----------------------------------------------------------------------------
sub printHelp {
  print "\nOpenCL NVIDIA GPU Stream Benchmark build script command line options and defaults (*)\n";
  print "--------------------------------------------------------------------------------------\n";
  print "-p  [stream]                       : the prefix to use for all project files, directories, etc\n";
  print "-sft[GMEM*/HOST]                   : Streams from/to host or Global Memory\n";
  print "-k  [COPY*/MUL/ADD/TRIAD]          : which of the 4 benchmark kernels are we running?\n";
  print "-w  [INT*/FLOAT/DOUBLE]            : data-type of WORD used in the streams \n";
  print "-d  [1024]                         : size along one-dimension of the square 2D input matrix\n";
  print "-a  [CONTIGUOUS*/FIXED_STRIDE]     : access pattern \n";
  print "-v  [1]                            : size of vector for kernel streams (1 = scalar) \n";
  print "-l  [API*/KERNEL]                  : how is the looping over work-items handled\n";
  print "-n  [FLAT_LOOPING*/NESTED_LOOPING] : is the 2D looping nested or flat?\n";
  print "-t  [RW*/RO/WO]                    : testing read-write both, or only one\n";
  print "-m  [all*/host/aoclbin/run/clean]  : type of make\n";
  print "-log                               : do you want to log results to file?\n";
  print "-h                                 : print help \n";
  print "\n";
  print "-batch                             : Run a batch job. List of jobs ALWAYS picked from jobs.bat file in THIS folder.\n";
  print "\n";
  print "Usage example\n";
  print "-------------\n";
  print "./build.pl -p stream -w int -d 1000 -a CONTIGUOUS -v 1 -l API -f hw -m host -v 1\tOR\n";
  print "perl build.pl <flags>\n";
  print "\n";
}
