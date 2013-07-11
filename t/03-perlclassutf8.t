use Test::More;

if ($] < v5.14) { plan skip_all => 'Perl 5.14 or higher required'; }
else            { plan tests => 21; }

use lib 't/lib';
use PathTest;

use utf8;

# Suppressing the "Wide character" warnings from Test::Builder is harder than it sounds...
#no warnings 'utf8';
#binmode STDOUT, ':utf8';
#$ENV{PERL_UNICODE} = 'S';

my $opts = {
   style => 'PerlClassUTF8',
};

test_pathing($opts,
   [qw(
      Perl::Class
      overload::pragma
      K2P
      K2P'Foo'Bar'Baz
      K2P::Foo::Bar::Baz
      K2P'Class::Fun
      ʻNIGHTMäREʼ::ʺ'ﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ
   )],
   [qw(
      Perl::Class
      overload::pragma
      K2P
      K2P::Foo::Bar::Baz
      K2P::Foo::Bar::Baz
      K2P::Class::Fun
      ʻNIGHTMäREʼ::ʺ::ﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ
   )],
   'Basic',
);
