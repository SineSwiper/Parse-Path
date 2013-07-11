use Test::More tests => 18;

use lib 't/lib';
use PathTest;

my $opts = {
   style => 'PerlClass',
};

test_pathing($opts,
   [qw(
      Perl::Class
      overload::pragma
      K2P
      K2P'Foo'Bar'Baz
      K2P::Foo::Bar::Baz
      K2P'Class::Fun
   )],
   [qw(
      Perl::Class
      overload::pragma
      K2P
      K2P::Foo::Bar::Baz
      K2P::Foo::Bar::Baz
      K2P::Class::Fun
   )],
   'Basic',
);
