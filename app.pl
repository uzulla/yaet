#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::RealBin/lib";
use Mojolicious::Commands;

$ENV{MOJO_HOME} = "$FindBin::RealBin";

# Start command line interface for application
Mojolicious::Commands->start_app('TailF');
