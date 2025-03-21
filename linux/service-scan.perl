#!/usr/bin/env perl

use strict;
use warnings;
use threads;

my @service_lines = `systemctl show '*.service' --property=Id,FragmentPath,ExecStart,Slice`;
my @blocklist;

my $IS_RHEL = `test -f /etc/redhat-release && echo "true"`;

{
    my @exe;
    my $id;
    my $fragmentPath;

    foreach (@service_lines) {
        my $line = $_;
        if ($line ne "\n") {
            if ($line =~ m/^Id=(.*)$/) {
                $id = $1;
            } elsif ($line =~ m/^ExecStart=\{ path=([^;]*).*$/) {
                push(@exe, $1);
            } elsif ($line =~ m/^FragmentPath=(.*)$/) {
                $fragmentPath = $1;
            }
        } elsif (defined $id) {
            push(@blocklist, { exe => [ @exe ],
                               id => $id,
                               path => $fragmentPath,
                 });
            @exe = ();
        }
    }
}

END {
    foreach my $block (@blocklist) {
        threads->create(\&checkService, $block);
    }

    for my $thread (threads->list()) {
        my @returnVal = $thread->join();
        print join("\n", @returnVal);
    }
}


sub checkService {
    my @output;
    my $id = $_[0]->{"id"};
    my $path = $_[0]->{"path"};
    #        my $id = $_.{"id"};
    #        print $id . "\n";
    my $flag = 0;
    #        print $_.{"id"};

    foreach my $e (@{$_[0]->{"exe"}}) {
        push(@output, "$e");
        if(!belongsToPackage($e)) {
            push(@output, "executable does not belong to package: $e");
            $flag = 1;
        } else {
            for my $validstring (validate($e)) {
                if( defined $validstring ) {
                    push(@output, "Altered file: $validstring");
                    $flag = 1;
                }
            }
        }
    }

    if (defined $path) {
        if (!belongsToPackage($path)) {
            push(@output, "service file does not belong to package: $path");
            $flag = 1;
        } else {
            for my $validstring (validate($path)) {
                if( defined $validstring ) {
                    push(@output, "Altered service file ${path}: $validstring");
                }
            }
        }
    }
    return @output;
}


sub belongsToPackage {
    my $file = $_[0];

    if ( defined $file && defined findPackage($file)) {
        return 1;
    } else {
        return 0;
    }
}

sub validate {
    my $file = $_[0];
    my @output;
    if ( defined $file ) {
        if ($IS_RHEL) {
            @output = `rpm -Vf $file`
        } else {
            my $package = findPackage($file);
            @output = `dpkg -V $package 2>/dev/null`
        }
    }
    for my $line (@output) {
        if ($line =~ m/^missing.*$/) {
            undef $line;
        }
    }
    return @output;
}

sub findPackage {
    my $file = $_[0];
    my $output = "";
    if ($IS_RHEL) {
        $output=`rpm -qf $file`
    } else {
        $output=`dpkg -S $file | cut -d: -f1`
    }
    if( defined $output || $output =~ m/.*not owned by.*/ || $output =~ m/.*no path found/) {
        return "";
    } else {
        return $output;
    }
}
