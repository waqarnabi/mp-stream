#!/usr/bin/perl -w

# Script to do a batch build of streamOCL for sdaccel-alphadata
# Uses the build.pl script for each build in the batch, 
# which in turn creates a custom TCL and calls sdaccel on it

# Created: Waqar Nabi, April 2016, Glasgow


# Usage example

use strict;
use warnings;
use Getopt::Long;   #for command line options
use Time::HiRes qw( usleep ualarm gettimeofday tv_interval nanosleep
                    clock_gettime clock_getres clock_nanosleep clock
                    stat);

my $start = Time::HiRes::gettimeofday();

#get options from command line
#-----------------------------
my $batchJobsFile;
GetOptions (
    'f=s'   =>  \$batchJobsFile
  );

# chomp lines, execute one by one
# --------------------------------
open my $handle, '<', $batchJobsFile;
chomp(my @batchCommands = <$handle>);
close $handle;
for my $oneCommand (@batchCommands) {
  system($oneCommand); 
}

#post
my $end = Time::HiRes::gettimeofday();
printf("\nThe BATCH build took %.2f seconds\n", $end - $start);

