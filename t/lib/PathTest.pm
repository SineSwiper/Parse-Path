package PathTest;

use Test::More;

use base 'Exporter';

our @EXPORT = qw(test_pathing);

sub test_pathing {
   my ($dso, $list, $expect_list, $name) = @_;

   for (my $i = 0; $i < @$list; $i++) {
      my ($path_str, $expect_str) = ($list->[$i], $expect_list->[$i]);

      my $path = $dso->path_class->new(
         %{ $dso->path_options },
         stash_obj => $dso,
         path => $path_str,
      ) // do {
         diag $dso->error;
         fail;
      };

      cmp_ok($path->as_string, 'eq', $expect_str, $name.' --> '.$path_str.' compare correctly');
   }
}
