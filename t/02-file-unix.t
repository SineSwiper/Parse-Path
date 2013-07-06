use Parse::Path;
use Test::More tests => 11;

use lib 't/lib';
use PathTest;

use utf8;

my ($hash, $tree);
my $ppo = new_ok('Parse::Path', [ path_style => 'File::Unix' ]);

test_pathing($ppo,
   [qw(
      /
      ..
      .
      /etc/foobar.conf
      ../..///.././aaa/.///bbb/ccc/../ddd
      /home/bbyrd///foo/bar.txt
      foo/////bar
      ////root
      var/log/turnip.log
   ),
      '/root/FILENäME NIGHTMäRE…/…/ﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ.conf',
   ],
   [qw(
      /
      ..
      .
      /etc/foobar.conf
      ../../../aaa/bbb/ddd
      /home/bbyrd/foo/bar.txt
      foo/bar
      /root
      var/log/turnip.log
   ),
      '/root/FILENäME NIGHTMäRE…/…/ﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ.conf',
   ],
   'Basic UNIX path set',
);
