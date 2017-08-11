#!/usr/bin/perl
#
# Copyright 2017 Martijn Brekhof. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

use strict;
use warnings;
use Getopt::Std;
use File::Find;

sub usage()
{
    print "usage: run_instrumentation_tests.pl [OPTION]...\n\n";
    print "OPTIONS:\n";
    print "     -C <DIR>    location of test classes. (default: current directory)\n";
    print "     -m          create video of failed test. (default: screenshots)\n";
    print "     -d <DIR>    directory where screenshots/videos should be saved (default: /sdcard)\n";
    print "     -c <DIR>    copy screenshots/videos from device to local directory <DIR>. (default: current directory)\n";
    print "\n";
}

if(! (exists $ENV{'ANDROID_HOME'} && defined $ENV{'ANDROID_HOME'})) {
    die "ANDROID_HOME variable not defined\n";
}

my %opts = ('C' => '.', 'd' => '/sdcard/Pictures', 'c' => '.', 'm' => 0);

getopts('C:d:c:m', \%opts);

$ENV{'PATH'}="/bin/:/usr/bin:$ENV{'ANDROID_HOME'}/tools/bin:$ENV{'ANDROID_HOME'}/platform-tools";
my $SCREENSHOTDIR = $opts{'d'};

sub testScreenrecordingFunctionality() {
    system("adb shell ls " . $SCREENSHOTDIR . "/manage_screen_recording.sh > /dev/null 2>&1 ");
    if ($? != 0) {
        print STDERR "Could not find " . $SCREENSHOTDIR . "/manage_screen_recording.sh on device\n";
        print STDERR "Falling back to creating screenshots\n";
        $opts{'m'} = 0;
    }
}

sub createTestMethodsList($) {
    my $file = shift;
    open(FH, "$file") or return;
    my $test_annotation_found = 0;
    my $package = "";
    $file =~ /.*\/(.*)\.java/ or die "Error: couldn't get filename from $file\n";
    my $classname = $1;
    my @testmethods;
    while(my $line = <FH>) {
        if ($line =~ /\@Test/) {
            $test_annotation_found = 1;
        } elsif ($test_annotation_found == 1 && $line =~ /public\s+\w+\s+(\w+)/) {
            push @testmethods, "$package\#$1";
            $test_annotation_found = 0;
        } elsif ($line =~ /^\s*package\s+(.*);/) {
            $package = $1 . "." . $classname;
        }
    }
    return @testmethods;
}

=head2 startRecording

    startRecording( $testClassMethod )

Starts recording or takes a screenshot

=cut
sub startRecording($) {
    my $testClassMethod = shift;

    if ($opts{'m'} ne 0) {
        system("adb shell " . $SCREENSHOTDIR . "/manage_screen_recording.sh -s " . $SCREENSHOTDIR."/".$testClassMethod.".mp4")
    } else {
        system("adb shell screencap " . $SCREENSHOTDIR . "/before-" . $testClassMethod . ".png");
    }
}

=head2 stopRecording

   stopRecording( $testClassMethod, $testFailed )

Stops any running recording for $filename and if $testFailed == 0
remove the recording or screenshot

=cut
sub stopRecording($$) {
    my $testClassMethod = shift;
    my $testFailed = shift;

    if ($opts{'m'} ne 0) {
        system("adb shell " . $SCREENSHOTDIR . "/manage_screen_recording.sh -c " . $SCREENSHOTDIR."/".$testClassMethod.".mp4");
        ($testFailed == 0) && system("adb shell rm " . $SCREENSHOTDIR . "/" . $testClassMethod . ".mp4}");
    } else {
        system("adb shell screencap " . $SCREENSHOTDIR . "/after-" . $testClassMethod . ".png");
        ($testFailed == 0) && system("adb shell rm " . $SCREENSHOTDIR . "/*-" . $testClassMethod . ".png");
    }
}

sub runTest($) {
    my $testClassMethod = shift;

    print "Testing: $testClassMethod\n";

    startRecording($testClassMethod);

    open(FH, '-|', "adb shell am instrument --no-window-animation -r -w -e debug false -e class $testClassMethod org.xbmc.kore.instrumentationtest.test/android.support.test.runner.AndroidJUnitRunner");
    while (my $line = <FH>) {
        if ($line =~ /INSTRUMENTATION_STATUS_CODE:\s+(\d+)/) {
            if ($1 eq 0) {
                print "OK\n";
                stopRecording($testClassMethod, 0);
            } elsif ($1 ne 1) {
                print ("FAILED\n");
                stopRecording($testClassMethod, 1);
            }
        }
    }
    close FH;
}


testScreenrecordingFunctionality();

my @javafiles;

#Search for files with suffix .java
find(
    sub {
        push @javafiles, $File::Find::name if /.java$/;
    },
    $opts{'C'}
);

foreach my $file (@javafiles) {
    for my $testmethod (createTestMethodsList($file)) {
        runTest($testmethod) or die;
    }
}

system("adb pull $opts{'d'} $opts{'c'}");
