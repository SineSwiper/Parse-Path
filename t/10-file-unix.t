use Test::More tests => 30;

use lib 't/lib';
use PathTest;

use utf8;

# Suppressing the "Wide character" warnings from Test::Builder is harder than it sounds...
#no warnings 'utf8';
#binmode STDOUT, ':utf8';
#$ENV{PERL_UNICODE} = 'S';

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
   'Basic',
);
