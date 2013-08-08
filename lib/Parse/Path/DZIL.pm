package Parse::Path::DZIL;

# VERSION
# ABSTRACT: "dist.ini-style".paths.for.DZIL[0]

#############################################################################
# Modules

use Moo;
use sanity;

use String::Escape;

use namespace::clean;
no warnings 'uninitialized';

#############################################################################
# Required Methods

with 'Parse::Path::Role::Path';

sub _build_blueprint { {
   hash_step_regexp => qr/
      # Standard character (or a zero-length with a delimiter)
      (?<key>\w+|(?=\.))|

      # Quoted key
      (?<quote>['"])(?<key> (?:

         # The (?!) is a fancy way of saying ([^\"\\]*) with a variable quote character
         (?>(?: (?! \\|\g{quote}). )*) |  # Most stuff (no backtracking)
         \\ \g{quote}                  |  # Escaped quotes
         \\ (?! \g{quote})                # Any other escaped character

      )* )\g{quote}|

      # Zero-length step (with a single blank key)
      (?<key>^$)
   /x,

   array_step_regexp   => qr/\[(?<key>\d{1,5})\]/,
   delimiter_regexp    => qr/(?:\.|(?=\[))/,

   unescape_translation => [
      [qr/\"/ => \&String::Escape::unbackslash],
      [qr/\'/ => sub { my $str = $_[0]; $str =~ s|\\([\'\\])|$1|g; $str; }],
   ],
   pos_translation => [
      [qr/.?/, 'X+1'],
   ],

   delimiter_placement => {
      HH => '.',
      AH => '.',
   },

   array_key_sprintf        => '[%u]',
   hash_key_stringification => [
      [qr/[\x00-\x1f\']/,
                  '"%s"' => \&String::Escape::backslash],
      [qr/\W|^$/, "'%s'" => sub { my $str = $_[0]; $str =~ s|([\'\\])|\\$1|g; $str; }],
      [qr/.?/,    '%s'],
   ],
} }

42;

__END__

=begin wikidoc

= SYNOPSIS

   use v5.10;
   use Parse::Path;

   my $path = Parse::Path->new(
      path  => 'gophers[0].food.count',
      style => 'DZIL',
   );

   say $path->as_string;
   $path->push($path, '[2]');
   say $path->as_string;

= DESCRIPTION

This path style is used for advanced [Dist::Zilla] INI parsing.  It's the reason why this distribution (and related modules) were
created.

Support is available for both hash and array steps, including quoted hash steps.  Some examples:

   gophers[0].food.type
   "Drink more milk".[3][0][0]."and enjoy it!"
   'foo bar baz'[0]."\"Escaping works, too\""

DZIL paths do not have relativity.  They are all relative.

=end wikidoc
