use Parse::Path;
use Test::More tests => 11;

use lib 't/lib';
use PathTest;

my ($hash, $tree);
my $ppo = new_ok('Parse::Path');

test_pathing($ppo,
   [qw(
      a[4]
      a[1].b.c.d
      a[3].turnip
      a[0][1][1][1][1].[2].too.long
   )],
   [qw(
      a[4]
      a[1].b.c.d
      a[3].turnip
      a[0][1][1][1][1][2].too.long
   )],
   'Basic',
);

test_pathing($ppo,
   [qw(
      '[4]' => 2,
      '[1].b.c.d' => 3,
      '[3].turnip' => 4,
      '[0][1][1][1][1].[2].too.long
   )],
   [qw(
      [4]
      [1].b.c.d
      [3].turnip
      [0][1][1][1][1][2].too.long
   )],
   'Array-is-first',
);

test_pathing($ppo,
   [
      q{"This can't be a terrible mistake"[0].value},
      q{'"Oh, but it can..." said the spider'.[0].value},
   ],
   [
      q{"This can't be a terrible mistake"[0].value},
      q{"\"Oh, but it can...\" said the spider"[0].value},
   ],
   'Quoted',
);

test_both_ways($ppo,
   [
      'a.b...c[0].""."".' . "''",
   ],
   [
      'a.b.""."".c[0].""."".""',
   ],
   'Zero-length keys',
);
