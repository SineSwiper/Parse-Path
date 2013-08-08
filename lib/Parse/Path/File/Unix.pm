package Parse::Path::File::Unix;

# VERSION
# ABSTRACT: /UNIX/file/path/support

#############################################################################
# Modules

use Moo;
use sanity;

use namespace::clean;
no warnings 'uninitialized';

#############################################################################
# Required Methods

with 'Parse::Path::Role::Path';

sub _build_blueprint { {
   hash_step_regexp => qr{
      # Illegal characters are a mere \0 and /
      (?<key>[^/\0]*)
   }x,

   array_step_regexp   => qr/\Z.\A/,  # no-op; arrays not supported
   delimiter_regexp    => qr{/+},     # + to capture repetitive slashes, like foo////bar

   # no support for escapes
   unescape_translation => [],

   pos_translation => [
      [qr{^/+$},     0],
      [qr{^\.\./*$}, 'X-1'],
      [qr{^\./*$},   'X-0'],
      [qr{.?},       'X+1'],
   ],

   delimiter_placement => {
      '0R' => '/',
      HH   => '/',
   },

   array_key_sprintf        => '',
   hash_key_stringification => [
      [qr/.?/, '%s'],
   ],
} }

42;

__END__

=begin wikidoc

= SYNOPSIS

   use v5.10;
   use Parse::Path;

   my $path = Parse::Path->new(
      path  => '/root/.cpan',
      style => 'File::Unix',
   );

   say $path->as_string;
   $path->push($path, 'FTPstats.yml');
   say $path->as_string;

= DESCRIPTION

This is a file-based path style for *nix paths.  Some examples:

   /etc/foobar.conf
   /home/bbyrd/foo/bar.txt
   ../..///.././aaa/.///bbb/ccc/../ddd
   foo/bar/../baz
   var/log/turnip.log

Arrays are, of course, not supported.  Neither is quoting, as that is a product of the shell, not the path itself.

Absolute paths will contain a blank first step, a la [Path::Class].  Though, it is recommended to use
[is_absolute|Parse::Path/is_absolute] for checking for path relativity.

=end wikidoc
