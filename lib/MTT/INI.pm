lib/MTT/Values.pm                                                                                   0000644 0476523 0000012 00000014234 10513261660 0014402 0                                                                                                    ustar 00em162155                        staff                           0000434 0051460                                                                                                                                                                        #!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Values;

use strict;
use MTT::Messages;
use MTT::Values::Functions;
use Config::IniFiles;
use vars qw(@EXPORT);
use base qw(Exporter);
@EXPORT = qw(EvaluateString Value Logical ProcessEnvKeys);

#--------------------------------------------------------------------------

sub EvaluateString {
    my ($str) = @_;
    Debug("Evaluating: $str\n");

    # Loop until there are no more &functions(...)
    while ($str =~ /\&(\w+)\(([^&\(]*?)\)/) {
        my $func_name = $1;
        my $func_args = $2;
        Debug("Got name: $func_name\n");
        Debug("Got args: $func_args\n");

        # Since we used a non-greedy regexp above, there cannot be any
        # &functions(...) in the $func_args, so just evaluate it.

        my $ret;
        my $eval_str = "\$ret = MTT::Values::Functions::$func_name($func_args)";
        Debug("_do: $eval_str\n");
        eval $eval_str;
        if ($@) {
            Error("Could not evaluate: $eval_str: $@\n");
        }

        # If we get a string back, just handle it.
        if (ref($ret) eq "") {
            # Substitute in the $ret in place of the &function(...)
            $str =~ s/(\&\w+\([^&\(]*?\))/$ret/;
            Debug("String now: $str\n");

            # Now loop around and see if there are any more
            # &function(...)s
            next;
        }

        # Otherwise, we get an array back, recursively call back
        # through for each item in the array.  Not efficient, but it
        # gets the job done.  However, we may have gotten an *empty*
        # array back, in which case we still need to substitute in
        # nothing into the string and continue looping around.

        if ($#{@$ret} < 0) {
            # Put an empty string in the return value's place in the
            # original string
            $str =~ s/(\&\w+\([^&\(]*?\))/""/;
            Debug("String now: $str\n");

            # Now loop around and see if there are any more
            # &function(...)s
            next;
        }

        # Now we handle all the array values that came back.

        # --- If you're trying to figure out the logic here, note that
        # --- beyond this point, we're not looping any more -- we'll
        # --- simply return.

        my @ret;
        foreach my $s (@$ret) {
            my $tmp = $str;
            # Substitute in the $s in place of the &function(...)
            $tmp =~ s/(\&\w+\([^&\(]*?\))/$s/;
            $ret = EvaluateString($tmp);
            if (ref($ret) eq "") {
                push(@ret, $ret);
            } else {
                push(@ret, @$ret);
            }
        }
        return \@ret;
    }

#    Debug("No more functions left; final: $str\n");
    return $str;
}

#--------------------------------------------------------------------------

# Get a value from an INI file and call all the functions that it may
# have invoked
sub Value {
    my ($ini, $section, $name) = @_;

    my $val = $ini->val($section, $name);
    return undef
        if (!defined($val));
    return EvaluateString($val);
}

#--------------------------------------------------------------------------

# Get a Value and evaluate it as either true or false; return value
# will be 0 or 1.
sub Logical {
    my ($ini, $section, $name) = @_;

    my $val = Value($ini, $section, $name);
    return undef
        if (!defined($val));
    if (!$val || 
        $val == 0 || 
        $val eq "0" ||
        lc($val) eq "no" ||
        lc($val) eq "false" ||
        lc($val) eq "off") {
        return 0;
    } elsif ($val == 1 ||
             $val eq "1" ||
             lc($val) eq "yes" ||
             lc($val) eq "true" ||
             lc($val) eq "on") {
        return 1;
    }

    # Assume true

    return 1;
}

#--------------------------------------------------------------------------

sub ProcessEnvKeys {
    my ($config, $save) = @_;

    # setenv
    my $val = $config->{setenv};
    if ($val) {
        my @vals = split(/\n/, $val);
        foreach my $v (@vals) {
            my $name = $v;
            $name =~ s/(\w+)\W.+/\1/;
            my $str = $v;
            $str =~ s/\w+\W+(.+)\W*/\1/;
            $ENV{$name} = $str;

            $str = "setenv $name $str";
            push(@$save, $str);
            Debug("$str\n");
        }
    }
    
    # unsetenv
    $val = $config->{unsetenv};
    if ($val) {
        my @vals = split(/\n/, $val);
        foreach my $v (@vals) {
            delete $ENV{$v};

            my $str = "unsetenv $v";
            push(@$save, $str);
            Debug("$str\n");
        }
    }
    
    # prepend_path
    $val = $config->{prepend_path};
    if ($val) {
        my @vals = split(/\n/, $val);
        foreach my $v (@vals) {
            my $name = $v;
            $name =~ s/(\w+)\W.+/\1/;
            my $str = $v;
            $str =~ s/\w+\W+(.+)\W*/\1/;
            
            if (exists($ENV{$name})) {
                $ENV{$name} = "${str}:" . $ENV{$name};
            } else {
                $ENV{$name} = $str;
            }

            $str = "prepend_path $name $str";
            push(@$save, $str);
            Debug("$str\n");
        }
    }
    
    # append_path
    $val = $config->{append_path};
    if ($val) {
        my @vals = split(/\n/, $val);
        foreach my $v (@vals) {
            my $name = $v;
            $name =~ s/(\w+)\W.+/\1/;
            my $str = $v;
            $str =~ s/\w+\W+(.+)\W*/\1/;
            
            if (exists($ENV{$name})) {
                $ENV{$name} = $ENV{$name} . ":$str";
            } else {
                $ENV{$name} = $str;
            }

            $str = "append_path $name $str";
            push(@$save, $str);
            Debug("$str\n");
        }
    }
}

# This function generates random strings of a given length
sub RandomString {

    # length of the random string to generate
    my $length_of_randomstring = shift;
    my @chars = ('a'..'z','A'..'Z','0'..'9','_');
    my $random_string;

    foreach (1..$length_of_randomstring) {
        $random_string .= $chars[rand @chars];
    }
    return $random_string;
}

1;
                                                                                                                                                                                                                                                                                                                                                                    lib/MTT/Files.pm                                                                                    0000644 0476523 0000012 00000024633 10513263057 0014213 0                                                                                                    ustar 00em162155                        staff                           0000434 0051460                                                                                                                                                                        #!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Files;

use strict;
use Cwd;
use File::Basename;
use File::Find;
use MTT::Messages;
use MTT::DoCommand;
use MTT::FindProgram;
use MTT::Defaults;
use MTT::Values;
use Data::Dumper;

# How many old builds to keep
my $keep_builds = 3;

# the download program to use
my $http_agent;

#--------------------------------------------------------------------------

sub make_safe_filename {
    my ($filename) = @_;

    $filename =~ s/[ :\/\\\*\&\$\#\@\!\t]/_/g;
    return $filename;
}

#--------------------------------------------------------------------------

sub mkdir {
    my ($dir) = @_;

    my $c = cwd();
    Debug("Making dir: $dir (cwd: $c)\n");
    my @parts = split(/\//, $dir);

    my $str;
    if (substr($dir, 0, 1) eq "/") {
        $str = "/";
        shift(@parts);
    }

    # Test and make

    foreach my $p (@parts) {
        next if (! $p);

        $str .= "$p";
        if (! -d $str) {
            Debug("$str does not exist -- creating\n");
            mkdir($str, 0777);
            if (! -d $str) {
                Error("Could not make directory $p\n");
            }
        }
        $str .= "/";
    }

    # Return an absolute version of the created directory

    my $orig = cwd();
    chdir($str);
    my $newdir = cwd();
    chdir($orig);
    $newdir;
} 

#--------------------------------------------------------------------------

# Trim old build directories
sub trim_builds {
    my ($base_dir) = @_;

    # Get all the directory entries in the top of the build tree.
    # Currently determining trim by a simple sort; may need to do
    # something better (like mtime?) in the futre...?
    opendir(DIR, $base_dir);
    my @entries = sort(grep { ! /^\./ && -d "$base_dir/$_" } readdir(DIR));
    closedir(DIR);
    print Dumper(@entries);

    # Discard the last $keep_builds entries
    my $len = $#entries - $keep_builds;
    return if ($len < 0);

    my $old_cwd = cwd();
    chdir($base_dir);

    my $i = 0;
    while ($i <= $len) {
        my $trim = 1;
        my $e = $entries[$i];
        foreach my $tarball (@MTT::Download::tarballs) {
            my $b = basename($tarball->{tarball});
            if ($e eq $b) {
                $trim = 0;
                last;
            }
        }

        if ($trim) {
            Debug("Trimming build tree: $e\n");
            MTT::DoCommand::Cmd(1, "rm -rf $e");
        } else {
            Debug("NOT trimming build tree: $e\n");
        }
        ++$i;
    }
    chdir($old_cwd);
}

#--------------------------------------------------------------------------

# unpack a tarball in the cwd and figure out what directory it
# unpacked into
sub unpack_tarball {
    my ($tarball, $delete_first) = @_;

    Debug("Unpacking tarball: $tarball\n");

    if (! -f $tarball) {
        Warning("Tarball does not exist: $tarball\n");
        return undef;
    }

    # Decide which unpacker to use

    my $unpacker;
    if ($tarball =~ /.*\.bz2$/) {
        $unpacker="bunzip2";
    } elsif ($tarball =~ /.*\.gz$/) {
        $unpacker="gunzip";
    } else {
        Warning("Unrecognized tarball extension ($tarball); don't know how to uncompress -- skipped\n");
        return undef;
    }

    # Examine the tarball and see what it puts in the cwd

    open(TAR, "$unpacker -c $tarball | tar tf - |");
    my @entries = <TAR>;
    close(TAR);
    my $dirs;
    my $files;
    foreach my $e (@entries) {
        chomp($e);
        # If no /'s, then it's possibly a file in the top-level dir --
        # save for later analysis.
        if ($e !~ /\//) {
            $files->{$e} = 1;
        } else {
            # If there's a / anywhere in the name, then save the
            # top-level dir name
            $e =~ s/(.+?)\/.*/\1/;
            $dirs->{$e} = 1;
        }
    }

    # Check all the "files" and ensure that they weren't just entries
    # in the tarball to make a directory (this shouldn't happen, but
    # just in case...)

    foreach my $f (keys(%$files)) {
        if (exists($dirs->{$f})) {
            delete $files->{$f};
        }
    }

    # Any top-level files left?

    my $tarball_dir;
    if (keys(%$files)) {
        my $b = basename($tarball);
        Debug("GOT FILES IN TARBALL\n");
        $tarball_dir = MTT::Files::mkdir("slimy_tarball_$b");
        chdir($tarball_dir);
    } else {
        my @k = keys(%$dirs);
        if ($#k != 0) {
            my $b = basename($tarball);
            Debug("GOT MULTI DIRS IN TARBALL\n");
            print Dumper($dirs);
            $tarball_dir = MTT::Files::mkdir("slimy_tarball_$b");
            chdir($tarball_dir);
        } else {
            $tarball_dir = $k[0];
        }
    }
    Debug("Tarball dir is: $tarball_dir\n");

    # Remove the tree first if requested
    MTT::DoCommand::Cmd(1, "rm -rf $tarball_dir")
        if ($delete_first);

    # Untar the tarball.  Do not use DoCommand here
    # because we don't want the stdout intercepted.

    system("$unpacker -c $tarball | tar xf -");
    my $ret = $? >> 8;
    if ($ret != 0) {
        Warning("Failed to unpack tarball successfully: $tarball: $@\n");
        return undef;
    }
    
    return $tarball_dir;
}

#--------------------------------------------------------------------------

# do a svn checkout
sub svn_checkout {
    my ($url, $username, $pw, $pw_cache, $delete_first, $export) = @_;

    Debug("SVN checkout: $url\n");

    my $b = basename($url);
    MTT::DoCommand::Cmd(1, "rm -rf $b")
        if ($delete_first);

    my $str = "svn ";
    if ($export) {
        $str .= "export "
    } else {
        $str .= "co "
    }
    if ($username) {
        $str .= "--username $username ";
    }
    if ($pw) {
        $str .= "--password $pw ";
    }
    if ("0" eq $pw_cache) {
        $str .= "--no-auth-cache ";
    }
    $str .= $url;
    my $ret = MTT::DoCommand::Cmd(1, $str);
    if (0 != $ret->{status}) {
        Warning("Could not SVN checkout $url: $@\n");
        return undef;
    }
    my $r = undef;
    if ($ret->{stdout} =~ m/Exported revision (\d+)\.\n$/) {
        $r = $1;
    }

    return ($b, $r);
}

#--------------------------------------------------------------------------

# Copy and entire file tree
sub copy_tree {
    my ($srcdir, $delete_first) = @_;

    Debug("Copying directory: $srcdir\n");

    if (! -d $srcdir) {
        Warning("Directory does not exist: $srcdir\n");
        return undef;
    }

    my $b = basename($srcdir);
    MTT::DoCommand::Cmd(1, "rm -rf $b")
        if ($delete_first);

    my $ret = MTT::DoCommand::Cmd(1, "cp -r $srcdir .");
    if (0 != $ret->{status}) {
        Warning("Could not copy file tree $srcdir: $@\n");
        return undef;
    }

    return $b;
}

#--------------------------------------------------------------------------

my $md5sum_path;
my $md5sum_searched;

sub _find_md5sum {
    # Search
    $md5sum_path = FindProgram(qw(md5sum gmd5sum));
    $md5sum_searched = 1;
    if (!$md5sum_path) {
        Warning("Could not find md5sum executable, so I will not be able to check the validity of downloaded executables against their known MD5 checksums.  Proceeding anyway...\n");
    }
}

sub md5sum {
    my ($file) = @_;

    _find_md5sum()
        if (!$md5sum_searched);
    # If we already searched and didn't find then, then just return undef
    return undef
        if (!$md5sum_path && $md5sum_searched);
    return undef
        if (! -f $file);

    my $x = MTT::DoCommand::Cmd(1, "$md5sum_path $file");
    if (0 != $x->{status}) {
        Warning("md5sum unable to run properly\n");
        return undef;
    }
    $x->{stdout} =~ m/^(\w{32})/;
    return $1;
}

#--------------------------------------------------------------------------

my $sha1sum_path;
my $sha1sum_searched;

sub sha1sum {
    my ($file) = @_;

    # Setup if we haven't already
    if (!$sha1sum_path) {
        # If we already searched and didn't find then, then just return undef
        return undef
            if ($sha1sum_searched);

        # Search
        $sha1sum_path = FindProgram(qw(sha1sum gsha1sum));
        $sha1sum_searched = 1;
        if (!$sha1sum_path) {
            Warning("Could not find sha1sum executable, so I will not be able to check the validity of downloaded executables against their known SHA1 checksums.  Proceeding anyway...\n");
            return undef;
        }
    }

    my $x = MTT::DoCommand::Cmd(1, "$sha1sum_path $file");
    if (0 != $x->{status}) {
        Warning("sha1sum unable to run properly\n");
        return undef;
    }
    $x->{stdout} =~ m/^(\w{40})/;
    return $1;
}

#--------------------------------------------------------------------------

my $mtime_max;

sub _do_mtime {
    # don't process special directories or links, and dont' recurse
    # down "special" directories
    if ( -l $_ ) { return; }
    if ( -d $_  && 
         ((/\.svn/) || (/\.deps/) || (/\.libs/))) {
        $File::Find::prune = 1;
        return;
    }

    # $File::Find::name is the path relative to the starting point.
    # $_ contains the file's basename.  The code automatically changes
    # to the processed directory, so we want to open / close $_.
    my @stat_info = stat($_);
    $mtime_max = $stat_info[9]
        if ($stat_info[9] > $mtime_max);
}

sub mtime_tree {
    my ($dir) = @_;

    $mtime_max = -1;
    find(\&_do_mtime, $dir);

    return $mtime_max;
}

#--------------------------------------------------------------------------

sub http_get {
    my ($url) = @_;

    # figure out what download command to use
    if (!$http_agent) {
        my @agents = split(/ /, $MTT::Defaults::System_config->{http_agents});
        $http_agent = FindProgram(@agents);
    }
    Abort("Cannot find downloading program -- aborting in despair\n")
        if (!defined($http_agent));

    my $x = MTT::DoCommand::Cmd(1, "$http_agent $url");
    if (0 != $x->{status}) {
        return undef;
    }
    return 1;
}

# Copy infile or stdin to a unique file in /tmp
sub copyfile {

    my($infile) = @_;
    my($opener);
    my($outfile) = "/tmp/" . MTT::Values::RandomString(10) . ".ini";

    # stdin
    if (ref($infile) =~ /glob/i) {
        $infile = "stdin";
        $opener = "-";
    }
    # file
    else {
        $opener = "< $infile";
    }
    open(in, $opener);
    open(out, "> $outfile");

    Debug("Copying: $infile to $outfile\n");

    while (<in>) {
        print out;
    }
    close(in);
    close(out);

    return $outfile;
}
1;


                                                                                                     client/mtt                                                                                          0000755 0476523 0000012 00000035363 10513263257 0013415 0                                                                                                    ustar 00em162155                        staff                           0000434 0051460                                                                                                                                                                        #!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

use strict;

use Data::Dumper;
use Getopt::Long;
use File::Basename;
use Cwd;
use POSIX qw(strftime);

# Try to find the MTT files.  Assume that mtt executable is in the
# base directory for the MTT files.  Try three methods:

# 1. With no effort; see if we can just "require" and find MTT files.
# 2. If $0 is a path, try adding that do @INC and try "require" again.
# 3. Otherwise, search $ENV[PATH] for mtt, and when you find it, add
#    that directory to @INC and try again.

use lib cwd() . "/lib";

my $ret;
eval "\$ret = require MTT::Version";
if (1 != $ret) {
    my $dir = dirname($0);
    my @INC_save = @INC;

    # Change to the dir of $0 (because it might be a relative
    # directory) and add the cwd() to @INC
    my $start_dir = cwd();
    chdir($dir);
    chdir("..");
    push(@INC, cwd() . "/lib");
    chdir($start_dir);
    eval "\$ret = require MTT::Version";

    # If it didn't work, restore @INC and try looking for mtt in the
    # path

    if (1 != $ret) {
        @INC = @INC_save;
        my @dirs = split(/:/, $ENV{PATH});
        my $mtt = basename($0);
        foreach my $dir (@dirs) {

            # If we found the mtt executable, add the dir to @INC and
            # see if we can "require".  If require fails, restore @INC
            # and keep trying.
            if (-x "$dir/$mtt") {
                chdir($dir);
                chdir("..");
                push(@INC, cwd() . "/lib");
                chdir($start_dir);
                eval "\$ret = require MTT::Version";
                if (1 == $ret) {
                    last;
                } else {
                    @INC = @INC_save;
                }
            }
        }
    }

    # If we didn't find them, die.
    die "Unable to find MTT support libraries"
        if (0 == $ret);
}

# Must use "require" (run-time) for all of these, not "use"
# (compile-time)

require Config::IniFiles;
require MTT::Version;
require MTT::MPI;
require MTT::Test;
require MTT::Files;
require MTT::Messages;
require MTT::INI;
require MTT::Reporter;
require MTT::Defaults;
require MTT::Globals;
require MTT::FindProgram;
require MTT::Trim;

my @file_arg;
my $stdin_arg;
my $scratch_arg;
my $help_arg;
my $debug_arg;
my $verbose_arg;
my $force_arg;
my $mpi_get_arg;
my $mpi_install_arg;
my $test_get_arg;
my $test_build_arg;
my $test_run_arg;
my @section_arg;
my @no_section_arg;
my $trim_arg;
my $version_arg;
my $ini_args;
my $time_arg;

my @SAVE_ARGV = @ARGV;

&Getopt::Long::Configure("bundling");
my $ok = Getopt::Long::GetOptions("file|f=s" => \@file_arg,
                                  "" => \$stdin_arg,
                                  "scratch|s=s" => \$scratch_arg,
                                  "help|h" => \$help_arg,
                                  "debug|d" => \$debug_arg,
                                  "verbose|v" => \$verbose_arg,
                                  "force" => \$force_arg,
                                  "mpi-get!" => \$mpi_get_arg,
                                  "mpi-install!" => \$mpi_install_arg,
                                  "test-get!" => \$test_get_arg,
                                  "test-build!" => \$test_build_arg,
                                  "test-run!" => \$test_run_arg,
                                  "section=s" => \@section_arg,
                                  "no-section=s" => \@no_section_arg,
                                  "trim!" => \$trim_arg,
                                  "version" => \$version_arg,
                                  "print-time|p" => \$time_arg,
                                  );
# Everything ok?

if ($version_arg) {
    print "MTT Version $MTT::Version::Major.$MTT::Version::Minor\n";
    exit(0);
}

foreach my $file (@ARGV) {
    push(@file_arg, $file) 
        if (-T $file and $file =~ /\.ini\s*$/);
}

# Get command-line overridden ini params
my $key_val_regexp = '([^=]+)\=(.*)';
foreach my $arg (@ARGV) {
    if ($arg =~ /([^:]+)\:$key_val_regexp$/) {
        $ini_args->{$2}->{value} = $3; 
        $ini_args->{$2}->{match} = $1; 
    }
    elsif ($arg =~ /$key_val_regexp$/) {
        $ini_args->{$1}->{value} = $2; 
        $ini_args->{$1}->{match} = '.'; 
    }
}
if (! @file_arg and ! $stdin_arg) {
    print "Must specify at least one --file argument or '-' for stdin.\n";
    $ok = 0;
}
if ($file_arg[0] eq "-" or $stdin_arg) {
    $stdin_arg = 1;
    $file_arg[0] = undef;
    open($file_arg[0], "-");
}

if (!$ok || $help_arg) {
    print("Command line error\n") 
        if (!$ok);
    print "Options:
--file|-f <config_file>       Specify the configuration file
--scratch|-s <dir_name>       Scratch directory (where all work is done)
--help|-h                     This message
--debug|-d                    Output lots of debug messages
--verbose|-v                  Output some status / verbose messages
                              while processing
--print-time|-p               Display the amount of time taken in each phase
--force                       Do steps even if they would not normally
                              be executed
--[no-]mpi-get                Do the \"MPI get\" phase
--[no-]mpi-install            Do the \"MPI install\" phase
--[no-]test-get               Do the \"Test get\" phase
--[no-]test-build             Do the \"Test build\" phase
--[no-]test-run               Do the \"Test run\" phase
--[no-]trim                   Do the \"Trim\" phase
--[no-]section                Do a specific section(s)
field=value                   Replace parameter \"foo\" from the INI file
                              with the value \"bar\" (i.e., override the
                              INI file value)

If no options other than --file, -f, or '-' are specified, the MTT
will default to trying to make as much progress as possible (i.e.,
running each of the phases as necessary).  For example, to set
'save_stdout_on_success' in every section:

    \$ client/mtt [...] save_stdout_on_success=1

To set 'intel_ompi_tests_fflags' in only the [test build: intel]
section (note the shell quoting to include the spaces in the value):

    \$ client/mtt [...] 'build,intel:intel_ompi_tests_fflags=-g -odd_ball_flag'

The phases can be specified in positive or negative form.  You can
only specify positive or negative phases in a run; you cannot mix both
positive and negative phases in a single MTT run.

* If any phases are specified in the positive form, then only those
  phases will be run (e.g., \"--mpi-get --mpi-install\").
* If negative phases are specified, then thoses phases will *not* be
  run.
  
Use --section to run sections matching a pattern.  For example, the
following command will perform any section matching the
case-insensitive patttern \"intel\":

    \$ client/mtt [...] --section intel

The following performs only sections whose name matches the
case-insensitive pattterns \"run\" AND \"intel\" (so only the [Test
run: intel] section):

    \$ client/mtt [...] --section 'run;intel'

To perform sections NOT matching \"intel\" OR \"ibm\":

    \$ client/mtt [...] --no-section intel --no-section ibm

\n";

    exit($ok);
}

# Check debug

my $debug = ($debug_arg ? 1 : 0);
my $verbose = ($verbose_arg ? 1 : $debug);
MTT::Messages::Messages($debug, $verbose);
MTT::Messages::Debug("Debug is $debug, Verbose is $verbose\n");
MTT::Messages::Verbose("*** MTT: $0 @SAVE_ARGV\n");

MTT::FindProgram::FindZeroDir();

########################################################################
# Params
########################################################################

# See if we got a scratch root
if (! $scratch_arg) {
    $scratch_arg = ".";
}
MTT::Messages::Debug("Scratch: $scratch_arg\n");
if (! -d $scratch_arg) {
    MTT::Files::mkdir($scratch_arg, 0777);
}
if (! -d $scratch_arg) {
    MTT::Messages::Abort("Could not make scratch dir: $scratch_arg\n");
}
chdir($scratch_arg);
$scratch_arg = cwd();
MTT::Messages::Debug("Scratch resolved: $scratch_arg\n");

# If any of the --get-mpi, --install-mpi, --build-tests, or
# --run-tests are specified, then their defaults all go to 0.
# Otherwise, if none are specified, they all default to 1.

my $mpi_get = 1;
my $mpi_install = 1;
my $test_get = 1;
my $test_build = 1;
my $test_run = 1;
my $trim = 1;

if (defined($mpi_get_arg) || defined($mpi_install_arg) ||
    defined($test_get_arg) || defined($test_build_arg) || 
    defined($test_run_arg) || defined($trim_arg)) {

    # If anything is defined as "yes", then only do those

    if ($mpi_get_arg || $mpi_install_arg || 
        $test_get_arg || $test_build_arg || $test_run_arg ||
        $trim_arg) {

        $mpi_get = $mpi_install = $test_get = $test_build = $test_run = $trim = 0;

        $mpi_get = 1 if defined($mpi_get_arg) && $mpi_get_arg;
        $mpi_install = 1 if defined($mpi_install_arg) && $mpi_install_arg;
        $test_get = 1 if defined($test_get_arg) && $test_get_arg;
        $test_build = 1 if defined($test_build_arg) && $test_build_arg;
        $test_run = 1 if defined($test_run_arg) && $test_run_arg;
        $trim = 1 if defined($trim_arg) && $trim_arg;
    } 

    # Otherwise, just negate whatever option was negated

    else {
        $mpi_get = 0 if defined($mpi_get_arg) && !$mpi_get_arg;
        $mpi_install = 0 if defined($mpi_install_arg) && !$mpi_install_arg;
        $test_get = 0 if defined($test_get_arg) && !$test_get_arg;
        $test_build = 0 if defined($test_build_arg) && !$test_build_arg;
        $test_run = 0 if defined($test_run_arg) && !$test_run_arg;
        $trim = 0 if defined($trim_arg) && !$trim_arg;
    }
}

########################################################################
# Load up all old data
########################################################################

# Make directories
my $source_dir = 
    MTT::Files::mkdir("$scratch_arg/$MTT::Defaults::System_config->{source_subdir}");
my $install_dir = 
    MTT::Files::mkdir("$scratch_arg/$MTT::Defaults::System_config->{install_subdir}");

# Load up all the MPI sources that this system has previously obtained
MTT::MPI::LoadSources($source_dir)
    if ($mpi_get || $mpi_install || $trim);

# Load up all the installs of the MPI sources
MTT::MPI::LoadInstalls($install_dir)
    if ($mpi_install || $test_build || $test_run || $trim);

# Load up the test sources for each install
MTT::Test::LoadSources($source_dir)
    if ($test_get || $test_build || $test_run || $trim);

# Load up the built tests for each install
MTT::Test::LoadBuilds($install_dir)
    if ($test_build || $test_run || $trim);

# Load up the run tests for each install
MTT::Test::LoadRuns($install_dir)
    if ($test_run || $trim);


########################################################################
# Timekeeping
########################################################################

my $start_timestamp_string;
my $start_timestamp_data;
my $start_timestamp_first_string;
my $start_timestamp_first_data;
sub start_time {
    if (!defined($start_timestamp_string)) {
        $start_timestamp_first_string = $start_timestamp_string = localtime;
        $start_timestamp_first_data = $start_timestamp_data = time;
    } else {
        $start_timestamp_string = localtime;
        $start_timestamp_data = time;
    }
}

sub timestamp_sub {
    my ($start, $stop) = @_;
    my ($days, $hours, $mins, $secs);

    # Constants
    my $m = 60;
    my $h = $m * 60;
    my $d = $h * 24;

    # Baseline difference
    my $elapsed = $stop - $start;

    # Individual components
    if ($elapsed > $d) {
        use integer;
        $days = $elapsed / $d;
        $elapsed -= $days * $d;
    } else {
        $days = 0;
    }

    if ($elapsed > $h) {
        use integer;
        $hours = $elapsed / $h;
        $elapsed -= $hours * $h;
    } else {
        $hours = 0;
    }

    if ($elapsed > $m) {
        use integer;
        $mins = $elapsed / $m;
        $elapsed -= $mins * $m;
    } else {
        $mins = 0;
    }

    my $secs = $elapsed;

    my $elapsed_string = sprintf("%02d:%02d:%02d", $hours, $mins, $secs);
    if ($days > 0) {
        $elapsed_string = "$days days, $elapsed_string";
    }
    return $elapsed_string;
}

sub stop_time {
    my $name = shift;
    if ($time_arg) {
        my $stop_timestamp_string = localtime;
        my $stop_timestamp_data = time;

        my $elapsed_string = timestamp_sub($start_timestamp_data, 
                                           $stop_timestamp_data);
        my $total_elapsed_string = timestamp_sub($start_timestamp_first_data,
                                                 $stop_timestamp_data);

        print ">> Phase: $name
   Started:       $start_timestamp_string
   Stopped:       $stop_timestamp_string
   Elapsed:       $elapsed_string
   Total elapsed: $total_elapsed_string\n";
    }
}

########################################################################
# Read the ini file(s)
########################################################################

foreach my $file (@file_arg) {

    my $orig_file = $file;
    my $temp_file = MTT::Files::copyfile($file);

    # Load up the ini file
    MTT::Messages::Debug("Reading ini file: " . (($stdin_arg) ? "stdin" : $orig_file) . "\n");
    my $ini = new Config::IniFiles(-file => $temp_file, 
                                   -nocase => 1,
                                   -allowcontinue => 1);

    # Check for problems in the ini file
    MTT::INI::ValidateINI($temp_file);
    MTT::DoCommand::Cmd(1, "rm $temp_file");

    # Override ini file params with those supplied at command-line
    $ini = MTT::INI::OverrideINIParams($ini, $ini_args);

    # Filter ini sections at command line
    $ini = MTT::INI::FilterINISections($ini, \@section_arg, \@no_section_arg);

    if (! $ini) {
        MTT::Messages::Warning("Could not read INI file: $file; skipping\n");
        next;
    }

    # Examine the [MTT] global defaults section

    MTT::Globals::load($ini);

    # Run the phases

    MTT::Reporter::Init($ini);

    if ($mpi_get) {
        start_time();
        MTT::MPI::Get($ini, $source_dir, $force_arg);
        stop_time("MPI Get");
    }
    if ($mpi_install) {
        start_time();
        MTT::MPI::Install($ini, $install_dir, $force_arg);
        stop_time("MPI Install");
    }
    if ($test_get) {
        start_time();
        MTT::Test::Get($ini, $source_dir, $force_arg);
        stop_time("Test Get");
    }
    if ($test_build) {
        start_time();
        MTT::Test::Build($ini, $install_dir, $force_arg);
        stop_time("Test Build");
    }
    if ($test_run) {
        start_time();
        MTT::Test::Run($ini, $install_dir, $force_arg);
        stop_time("Test Run");
    }

    # Remove old sources, installs, and builds

    if ($trim) {
        start_time();
        MTT::Trim::Trim($ini);
        stop_time("Trim");
    }

    # Shutdown the reporter

    MTT::Reporter::Finalize();
}

# That's it!

exit(0);
y (where all work is done)
--help|-h                     This message
--debug|-d                    Output lots of debug messages
--verbose|-v                  Output some status / verbose messages
                              while processing
--print-time|-p                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         