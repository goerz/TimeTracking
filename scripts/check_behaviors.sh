#!/bin/sh
# Checks that every numbered testable behavior has a test and every test
# identifier names a behavior (spec_architecture.md §3.2).
#
#   scripts/check_behaviors.sh [--root DIR] [--only PREFIX[,PREFIX...]]
#
# Specs: every spec/spec_*.md has one "Testable behaviors" section, numbered
# continuously from 1, either "1. ..." or "- TW-1. ...". Tests carry the
# identifier in a Swift Testing display name (@Test("TW-1 ...")), an XCTest
# method name (func testTW1_...), or a shell test (behavior "ARCH-2 ...").
# One test may name several identifiers. With --only, missing tests of other
# prefixes are reported but do not fail; malformed lists and unknown
# identifiers always fail.
exec /usr/bin/perl -x "$0" "$@"

#!perl
use strict;
use warnings;
use File::Find;

my %PREFIX = (
    'spec_architecture.md'       => 'ARCH',
    'spec_data_and_sync.md'      => 'DATA',
    'spec_timer_window.md'       => 'TW',
    'spec_menubar.md'            => 'MB',
    'spec_planner_projects.md'   => 'PP',
    'spec_planner_calendar.md'   => 'PC',
    'spec_planner_reports.md'    => 'PR',
    'spec_planner_activity.md'   => 'PA',
    'spec_activity_tracking.md'  => 'TRK',
    'spec_ios.md'                => 'IOS',
    'spec_automation.md'         => 'AUTO',
);
# Specs without testable behaviors of their own (the design language is
# checked through the component specs' behaviors).
my %NO_BEHAVIORS = ('spec_design.md' => 1);
my $PREFIXES = join '|', sort { length($b) <=> length($a) } values %PREFIX;

my $root = '.';
my %only;
while (@ARGV) {
    my $arg = shift @ARGV;
    if ($arg eq '--root') { $root = shift @ARGV; }
    elsif ($arg eq '--only') { $only{$_} = 1 for split /,/, shift @ARGV; }
    else { die "usage: check_behaviors.sh [--root DIR] [--only PREFIX[,PREFIX...]]\n"; }
}

my @errors;
my %defined;    # id -> spec file
my %count;      # prefix -> number of behaviors

# --- Specs
opendir(my $dh, "$root/spec") or die "check_behaviors: no spec/ folder under $root\n";
for my $file (sort grep { /^spec_.*\.md$/ } readdir $dh) {
    next if $NO_BEHAVIORS{$file};
    my $prefix = $PREFIX{$file};
    unless ($prefix) {
        push @errors, "spec/$file: no behavior prefix known for this spec (add it to scripts/check_behaviors.sh)";
        next;
    }
    open(my $fh, '<', "$root/spec/$file") or die "check_behaviors: cannot read spec/$file\n";
    my ($in, $seen, $expected) = (0, 0, 1);
    while (my $line = <$fh>) {
        if ($line =~ /^#+\s.*Testable behaviors/i) { $in = 1; $seen = 1; next; }
        if ($in && $line =~ /^#/) { $in = 0; next; }
        next unless $in;
        my ($p, $n);
        if ($line =~ /^- ([A-Z]+)-(\d+)\.\s/) { ($p, $n) = ($1, $2); }
        elsif ($line =~ /^(\d+)\.\s/) { ($p, $n) = ($prefix, $1); }
        else { next; }
        if ($p ne $prefix) {
            push @errors, "spec/$file:$.: item $p-$n has the wrong prefix (expected $prefix)";
            next;
        }
        if ($n != $expected) {
            push @errors, "spec/$file:$.: behavior list is not continuous: expected $prefix-$expected, found $prefix-$n";
        }
        $expected = $n + 1;
        $defined{"$prefix-$n"} = $file;
        $count{$prefix}++;
    }
    close $fh;
    push @errors, "spec/$file: no \"Testable behaviors\" section" unless $seen;
}
closedir $dh;

# --- Tests
my %tested;     # id -> first location
my @test_files;
find({ no_chdir => 1, wanted => sub {
    if (-d $_ && m{/(?:\.build|\.git|build\.noindex|DerivedData|node_modules|spec)$}) { $File::Find::prune = 1; return; }
    push @test_files, $_ if -f $_ && (m{Tests/.*\.swift$} || m{/scripts/test_[^/]*\.sh$});
} }, $root);

sub record {
    my ($text, $where) = @_;
    while ($text =~ /\b($PREFIXES)-(\d+)\b/g) {
        my $id = "$1-$2";
        $tested{$id} //= $where;
    }
}

for my $path (sort @test_files) {
    open(my $fh, '<', $path) or next;
    local $/;
    my $text = <$fh>;
    close $fh;
    (my $rel = $path) =~ s{^\Q$root\E/}{};
    if ($path =~ /\.swift$/) {
        while ($text =~ /\@Test\s*\(\s*"((?:[^"\\]|\\.)*)"/g) {
            my $name = $1;
            my $line = 1 + (() = substr($text, 0, pos($text)) =~ /\n/g);
            record($name, "$rel:$line");
        }
        while ($text =~ /\bfunc\s+test((?:(?:$PREFIXES)\d+_?)+)/g) {
            my $ids = $1;
            my $line = 1 + (() = substr($text, 0, pos($text)) =~ /\n/g);
            $ids =~ s/_/ /g;
            $ids =~ s/($PREFIXES)(\d+)/$1-$2 /g;
            record($ids, "$rel:$line");
        }
    } else {
        while ($text =~ /(?:^|\|\||&&)[ \t]*behavior[ \t]+"([^"]*)"/mg) {
            my $name = $1;
            my $line = 1 + (() = substr($text, 0, pos($text)) =~ /\n/g);
            record($name, "$rel:$line");
        }
    }
}

for my $id (sort keys %tested) {
    push @errors, "$tested{$id}: test identifier $id is defined by no spec" unless $defined{$id};
}

my %missing;
for my $id (keys %defined) {
    next if $tested{$id};
    my ($p) = $id =~ /^([A-Z]+)-/;
    push @{ $missing{$p} }, $id;
}

my $fail = @errors ? 1 : 0;
print STDERR "error: $_\n" for @errors;
for my $p (sort keys %count) {
    my @m = sort { ($a =~ /(\d+)$/)[0] <=> ($b =~ /(\d+)$/)[0] } @{ $missing{$p} // [] };
    my $done = $count{$p} - @m;
    my $line = sprintf "%-5s %3d/%-3d", $p, $done, $count{$p};
    if (@m) {
        my $counts = !%only || $only{$p};
        $fail = 1 if $counts;
        $line .= ($counts ? '  missing: ' : '  (not checked) missing: ') . join(' ', @m);
    }
    print "$line\n";
}
exit $fail;
