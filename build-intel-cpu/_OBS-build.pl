#!/usr/bin/perl -w
  system ("cp ../build-common/build-template.pl ./build-compiletime-temp.pl");
  system ("perl build-compiletime-temp.pl");
  system ("rm build-compiletime-temp.pl");