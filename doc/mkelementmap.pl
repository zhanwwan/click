#!/usr/local/bin/perl

# mkelementmap.pl -- make map of element name to C++ class and file
# Eddie Kohler
#
# Copyright (c) 1999 Massachusetts Institute of Technology.
#
# This software is being provided by the copyright holders under the GNU
# General Public License, either version 2 or, at your discretion, any later
# version. For more information, see the `COPYRIGHT' file in the source
# distribution.

my(%processing_constants) =
    ('AGNOSTIC' => 'a/a', 'PUSH' => 'h/h', 'PULL' => 'l/l',
     'PUSH_TO_PULL' => 'h/l', 'PULL_TO_PUSH' => 'l/h');
my(@class_file, @click_name, @cxx_name,
   @parents, @processing, @flags, @requirements, @provisions,
   %click_name_to_id, %cxx_name_to_id);

sub process_file ($) {
  my($filename) = @_;
  my($headername) = $filename;
  $headername =~ s/\.cc$/\.hh/;
  if (!open(IN, $headername)) {
    print STDERR "$headername: $!\n";
    return;
  }
  my $text = <IN>;
  close IN;

  my $first;
  $first = @cxx_name;
  foreach $_ (split(m{^class(?=.*\{)}m, $text)) {
    my($cxx_class) = (/^\s*(\w+)(\s|:\s).*\{/);
    next if !$cxx_class;
    push @cxx_name, $cxx_class;
    push @class_file, $headername;
    $cxx_name_to_id{$cxx_class} = @cxx_name - 1;
    if (/\A\s*\w*\s*:\s*([\w\s,]+)/) {
      my $p = $1;
      $p =~ s/\bpublic\b//g;
      push @parents, [ split(/[\s,]+/, $p) ];
    } else {
      push @parents, [];
    }
    if (/class_name.*return\s*\"([^\"]+)\"/) {
      push @click_name, $1;
    } else {
      push @click_name, "";
    }
    if (/processing.*return\s*(.*?);/) {
      my $p = $1;
      $p = $processing_constants{$p} if exists($processing_constants{$p});
      $p =~ tr/\"\s//d;
      $p =~ s{\A([^/]+)\Z}{$1/$1};
      push @processing, $p;
    } else {
      push @processing, "";
    }
    if (/\bflags\(\).*return\s*"(.*?)";/) {
      push @flags, $1;
    } else {
      push @flags, undef;
    }
  }

  # process ELEMENT_REQUIRES and ELEMENT_PROVIDES
  if (!open(IN, $filename)) {
    print STDERR "$filename: $!\n";
    return;
  }
  $text = <IN>;
  close IN;

  my($req, $prov, $i) = ('', '');
  $req .= " " . $1 while $text =~ /^ELEMENT_REQUIRES\((.*)\)/mg;
  $prov .= " " . $1 while $text =~ /^ELEMENT_PROVIDES\((.*)\)/mg;
  $req =~ s/^\s+//;
  $req =~ s/"/\\"/g;
  $prov =~ s/^\s+//;
  $prov =~ s/"/\\"/g;
  for ($i = $first; $i < @processing; $i++) {
    push @requirements, $req;
    push @provisions, $prov;
    
    # check to see if overloading is valid
    if ($click_name[$i] && exists($click_name_to_id{$click_name[$i]})) {
      my($j) = $click_name_to_id{$click_name[$i]};
      if (($requirements[$i] =~ /\blinuxmodule\b/ && $requirements[$j] =~ /\buserlevel\b/)
	  || ($requirements[$i] =~ /\buserlevel\b/ && $requirements[$j] =~ /\blinuxmodule\b/)) {
	# ok
      } else {
	print STDERR "invalid multiple definition of element class \`$click_name[$i]'\n";
	print STDERR $class_file[$j], ": first definition here\n";
	print STDERR $class_file[$i], ": second definition here\n";
	print STDERR "(Two classes may share a name only if one of them is valid only at userlevel\nand the other is valid only in the Linux kernel module. Add explicit\nELEMENT_REQUIRES(linuxmodule) and ELEMENT_REQUIRES(userlevel) statements.)\n";
      }
    }
    $click_name_to_id{$click_name[$i]} = $i;
  }
}

sub parents_processing ($) {
  my($classid) = @_;
  if (!$processing[$classid]) {
    my($parent);
    foreach $parent (@{$parents[$classid]}) {
      if ($parent eq 'Element') {
	$processing[$classid] = 'a/a';
	last;
      } elsif ($parent ne '') {
	$processing[$classid] = parents_processing($cxx_name_to_id{$parent});
	last if $processing[$classid];
      }
    }
  }
  return $processing[$classid];
}

sub parents_flags ($) {
  my($classid) = @_;
  if (!defined $flags[$classid]) {
    my($parent);
    foreach $parent (@{$parents[$classid]}) {
      if ($parent eq 'Element') {
	last;
      } elsif ($parent ne '') {
	$flags[$classid] = parents_flags($cxx_name_to_id{$parent});
	last if defined $flags[$classid];
      }
    }
  }
  return $flags[$classid];
}

# main program: parse options
sub read_files_from ($) {
  my($fn) = @_;
  if (open(IN, ($fn eq '-' ? "<&STDIN" : $fn))) {
    my(@a, @b, $t);
    $t = <IN>;
    close IN;
    @a = split(/\s+/, $t);
    foreach $t (@a) {
      next if $t eq '';
      if ($t =~ /[*?\[]/) {
	push @b, glob($t);
      } else {
	push @b, $t;
      }
    }
    @b;
  } else {
    print STDERR "$fn: $!\n";
    ();
  }
}

undef $/;
my(@files, $fn, $prefix);
while (@ARGV) {
  $_ = shift @ARGV;
  if (/^-f$/ || /^--files$/) {
    die "not enough arguments" if !@ARGV;
    push @files, read_files_from(shift @ARGV);
  } elsif (/^--files=(.*)$/) {
    push @files, read_files_from($1);
  } elsif (/^-p$/ || /^--prefix$/) {
    die "not enough arguments" if !@ARGV;
    $prefix = shift @ARGV;
  } elsif (/^--prefix=(.*)$/) {
    $prefix = $1;
  } elsif (/^-./) {
    die "unknown option `$_'\n";
  } elsif (/^-$/) {
    push @files, "-";
  } else {
    push @files, glob($_);
  }
}
push @files, "-" if !@files;

foreach $fn (@files) {
  process_file($fn);
}

umask(022);
open(OUT, ">&STDOUT");
print OUT "# Click class name\tC++ class name\theader file\tprocessing code\tflag word\trequirements\tprovisions\n";
foreach $id (sort { $click_name[$a] cmp $click_name[$b] } 0..$#click_name) {
  my($n) = $click_name[$id];
  $n = '""' if !$n;
  
  my($f) = $class_file[$id];
  $f =~ s/^$prefix\/*//;

  my($p) = $processing[$id];
  $p = parents_processing($class) if !$p;

  my($flags) = $flags[$id];
  $flags = parents_flags($class) if !defined($flags);
  $flags = "" if !defined($flags);
  
  my($req) = $requirements[$id];
  my($prov) = $provisions[$id];
  
  print OUT $n, "\t", $cxx_name[$id], "\t", $f, "\t", $p, "\t\"", $flags, "\"",
  "\t\"", $req, "\"\t\"", $prov, "\"\n";
}
close OUT;
