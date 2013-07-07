use Test::More tests => 11;

use lib 't/lib';
use PathTest;

use utf8;

my $opts = {
   style => 'File::Unix',
   auto_normalize => 1,
   auto_cleanup   => 1,
};

test_pathing($opts,
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
