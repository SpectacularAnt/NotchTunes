# Runs NotchTunes' Now Playing helper.
#
# macOS keeps its Now Playing service (MediaRemote) for Apple's own programs.
# perl is one of them, and it will load a library it's handed — so this script
# loads NotchTunes' helper library into perl and calls one function in it:
#
#   perl NowPlayingHelper.pl <path to NowPlayingHelper.dylib> stream
#       prints a line of JSON each time what's playing changes, until stopped
#   perl NowPlayingHelper.pl <path to NowPlayingHelper.dylib> send <command>
#       sends one command: toggle, next, previous, or seek:<seconds>
use strict;
use warnings;
use DynaLoader;

my ($library, $function, $argument) = @ARGV;
$ENV{NOTCHTUNES_ARGUMENT} = $argument // '';

my $handle = DynaLoader::dl_load_file($library, 0)
    or die "can't load $library: " . DynaLoader::dl_error() . "\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "notchtunes_$function")
    or die "no function $function\n";
DynaLoader::dl_install_xsub("main::run", $symbol);
main::run();
