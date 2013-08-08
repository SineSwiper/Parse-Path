package Parse::Path::PerlClass;

# VERSION
# ABSTRACT: Perl::Class::path::support

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
      (?<key>[a-zA-Z_]\w*)
   }x,

   array_step_regexp   => qr/\Z.\A/,  # no-op; arrays not supported
   delimiter_regexp    => qr{::|'},
   delimiter_regexp    => qr{(?:\:\:|')(?=[a-zA-Z_])},  # no dangling delimiters

   # no support for escapes
   unescape_translation => [],

   pos_translation => [
      [qr/.?/, 'X+1'],
   ],

   delimiter_placement => {
      HH => '::',
   },

   array_key_sprintf        => '',
   hash_key_stringification => [
      [qr/.?/, '%s'],
   ],
} }

42;

__END__

= SYNOPSIS

   use v5.10;
   use Parse::Path;

   my $path = Parse::Path->new(
      path  => 'Parse::Path',
      style => 'PerlClass',
   );

   say $path->as_string;
   $path->push($step, 'Role::Path');
   say $path->as_string;

= DESCRIPTION

This is a path style for Perl classes.  Some examples:

   Perl::Class
   overload::pragma
   K2P'Foo'Bar'Baz
   K2P'Class::Fun

=end wikidoc
