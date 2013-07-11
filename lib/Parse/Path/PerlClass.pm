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

   # no support for escapes
   unescape_sub          => undef,
   unescape_quote_regexp => qr/\Z.\A/,

   delimiter_placement => {
      HH => '::',
   },

   pos_translation => {
      '#DEFAULT#' => 'X+1',
   },

   array_step_sprintf       => '',
   hash_step_sprintf        => '%s',
   hash_step_sprintf_quoted => '%s',
   quote_on_regexp          => qr/\Z.\A/,  # no-op; quoting not supported

   escape_sub       => undef,
   escape_on_regexp => qr/\Z.\A/,
} }

42;

__END__

=begin wikidoc

= SYNOPSIS

   # code

= DESCRIPTION

### Ruler ##################################################################################################################################12345

Insert description here...

= CAVEATS

### Ruler ##################################################################################################################################12345

Bad stuff...

= SEE ALSO

### Ruler ##################################################################################################################################12345

Other modules...

= ACKNOWLEDGEMENTS

### Ruler ##################################################################################################################################12345

Thanks and stuff...

=end wikidoc
