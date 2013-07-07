package PathTest;

use Parse::Path;
use Test::More;

use base 'Exporter';

our @EXPORT = qw(test_pathing);

sub test_pathing {
   my ($pp_opts, $list, $expect_list, $name) = @_;

   my $style = $pp_opts->{style} // 'DZIL';
   $style = "Parse::Path::$style" unless ($style =~ s/^\=//);

   for (my $i = 0; $i < @$list; $i++) {
      my ($path_str, $expect_str) = ($list->[$i], $expect_list->[$i]);

      my $path = Parse::Path->new(
         %$pp_opts,
         path => $path_str,
      );
      isa_ok $path, $style;

      cmp_ok($path->as_string, 'eq', $expect_str, $name.' --> '.$path_str.' compare correctly');
   }
}
