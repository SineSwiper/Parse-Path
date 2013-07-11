package PathTest;

use Parse::Path;
use Test::Most;
use base 'Exporter';

our @EXPORT = qw(test_pathing);

sub test_pathing {
   my ($pp_opts, $list, $expect_list, $name) = @_;

   my $style = $pp_opts->{style} // 'DZIL';
   $style = "Parse::Path::$style" unless ($style =~ s/^\=//);

   SKIP: for (my $i = 0; $i < @$list; $i++) {
      my ($path_str, $expect_str) = ($list->[$i], $expect_list->[$i]);
      my $test_name = $name.' --> '.$path_str;

      my $path;
      lives_ok {
         $path = Parse::Path->new(
            %$pp_opts,
            path => $path_str,
         );
      } "$test_name construction didn't die" or skip '$path died', 2;
      isa_ok $path, $style, "$test_name path";

      cmp_ok($path->as_string, 'eq', $expect_str, "$test_name compared correctly");
   }
}
