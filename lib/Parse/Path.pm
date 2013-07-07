package Parse::Path;

# VERSION
# ABSTRACT: Parser for paths

#############################################################################
# Modules

use sanity;

use Scalar::Util qw( blessed );
use Module::Runtime qw( use_module );

use namespace::clean;
no warnings 'uninitialized';

#############################################################################
# Dispatcher

sub new {
   my $class = shift;
   my %opts;

   if (@_ == 1) {
      # XXX: Many of these forms are purposely undocumented and experimental
      my $arg = pop;
      if (blessed $arg) {
         if   ($arg->does('Parse::Path::Role::Path')) { return $arg->clone; }
         else                                         { $opts{path} = "$arg"; }
      }
      elsif (ref $arg eq 'ARRAY') { %opts = @$arg; }
      elsif (ref $arg eq 'HASH')  { %opts = %$arg; }
      else                        { $opts{path} = $arg; }
   }
   # NOTE: if @_ == 0, it gets passed to DZIL and fails with its own isa error
   else { %opts = @_; }

   my $style = delete $opts{style} // 'DZIL';
   $style = "Parse::Path::$style" unless ($style =~ s/^\=//);  # NOTE: kill two birds with one stone

   # Load+create the path class
   return use_module($style)->new(%opts);
}

42;

__END__

=begin wikidoc

= SYNOPSIS

   use v5.10;
   use Parse::Path;

   my $path = Parse::Path->new(
      path  => 'gophers[0].food.count',
      style => 'DZIL',  # default
   );

   my $step = $path->shift;  # { key => 'count', ... }
   say $path->as_string;
   $path->push($step, '[2]');

   foreach my $p (@$path) {
      say sprintf('%-6s %s --> %s', @$p{qw(type step key)});
   }

= DESCRIPTION

Parse::Path is, well, a parser for paths.  File paths, object paths, URLs...  A path is whatever string that can be translated into
hash/array keys.  Unlike modules like [File::Spec] or [File::Basename], which are designed for interacting with file systems paths in
a portable manner, Parse::Path is designed for interacting with ~any~ path, filesystem or otherwise, at the lowest level possible.

Paths are split out into steps.  Internally, these are stored as "step hashes".  However, there is some exposure to these hashes as
both input and output, so we'll describe them here:

   {
      type => 'HASH',       # must be either HASH or ARRAY
      key  => 'foo bar',    # as it would be represented as a key
      step => '"foo bar"',  # as it would be represented in a path
      pos  => 'X+1',        # used to determine depth
   }

For the purposes of this manual, a "step" is usually referring to a step hash, unless specified.

= CONSTRUCTOR

   my $path = Parse::Path->new(
      path  => $path,   # required
      style => 'DZIL',  # default
   );

Creates a new path object.  Parse::Path is really just a dispatcher to other Parse::Path modules, but it serves as a common API for
all of them.

Accepts the following arguments:

== path

   path => 'gophers[0].food.count'

String used to create path.  Can also be another Parse::Path object, a step, an array of step hashes, an array of paths, or whatever
makes sense.

This parameter is required.

== style

   style => 'File::Unix'
   style => '=MyApp::Parse::Path::Foobar'

Class used to create the new path object.  With a {=} prefix, it will use that as the full class.  Otherwise, the class will be
intepreted as {Parse::Path::$class}.

Default is [DZIL|Parse::Path::DZIL].

== auto_normalize

   auto_normalize => 1

   my $will_normalize = $path->auto_normalize;
   $path->auto_normalize(1);

If on, calls [/normalize] after any new step has been added (ie: [new|/CONSTRUCTOR], [/unshift], [/push], [/splice]).

Default is off.  This attribute is read-write.

== auto_cleanup

   auto_cleanup => 1

   my $will_cleanup = $path->auto_cleanup;
   $path->auto_cleanup(1);

If on, calls [/cleanup] after any new step has been added (ie: [new|/CONSTRUCTOR], [/unshift], [/push], [/splice]).

Default is off.  This attribute is read-write.

= METHODS

== depth

   my $depth = $path->depth;

Returns path depth.  In most cases, this is the number of steps to the path, a la [/step_count].  However, relative paths might make
this lower, or even negative.  For example:

   my $path = Parse::Path->new(
      path => '../../../foo/bar.txt',
      path_style => 'File::Unix',
   );

   say $path->step_count;  # 5
   say $path->depth;       # -1

Despite the similarity to the pos value of a step hash, this method doesn't tell you whether it's relative or absolute.  Use
[/is_absolute] for that.

== step_count

   my $count = $path->step_count;

Returns the number of steps in the path.  Unlike [/depth], negative-seeking steps (like {..} for most file-based paths) will not lower
the step count.

== is_absolute

   my $is_absolute = $path->is_absolute;

Returns a true value if this path is absolute.  Hint: most paths are relative.  For example, if the following paths were
[File::Unix|Parse::Path::File::Unix] paths:

   foo/bar.txt        # relative
   ../bar.txt         # relative
   bar.txt            # relative
   /home/foo/bar.txt  # absolute
   /home/../bar.txt   # absolute (even prior to cleanup)

== shift

   my $step_hash = $path->shift;

Works just like the Perl version.  Removes a step from the beginning of the path and returns it.

== pop

   my $step_hash = $path->pop;

Works just like the Perl version.  Removes a step from the end of the path and returns it.

== unshift

   my $count = $path->unshift($step_or_path);

Works just like the Perl version.  Adds a step (or other path-like thingy) to the beginning of the path and returns the number of new
steps prepended.  Will also call [/cleanup] afterwards, if [/auto_cleanup] is enabled.

== push

   my $count = $path->push($step_or_path);

Works just like the Perl version.  Adds a step (or other path-like thingy) to the end of the path and returns the number of new steps
appended.  Will also call [/cleanup] afterwards, if [/auto_cleanup] is enabled.

== splice

   my @step_hashes = $path->splice($offset, $length, $step_or_path);
   my @step_hashes = $path->splice($offset, $length);
   my @step_hashes = $path->splice($offset);

   my $last_step_hash = $path->splice($offset);

Works just like the Perl version.  Removes elements designated by the offset and length, and replaces them with the new step/path.
Returns the steps removed in list context, or the last step removed in scalar context.  Will also call [/cleanup] afterwards, if
[/auto_cleanup] is enabled.

== clone

   my $same_path = $path->clone;

Clones the path.  Returns the same type of object.

== normalize

   $path->normalize;

Normalizes the steps in the path.  This ensures that the keys of the step hash and the steps will be the same thing.  Or to put it
another way, this will make a "round trip" of string-to-path-to-string work commutatively.  For example, if the following paths were
[DZIL|Parse::Path::DZIL] paths:

   '"Oh, but it can..." said the spider'.[0].value   # Before normalize
   "\"Oh, but it can...\" said the spider"[0].value  # After normalize

   a.b...c[0].""."".''      # Before normalize
   a.b.""."".c[0].""."".""  # After normalize

== cleanup

   $path->cleanup;

Cleans up the path.  Think of this in terms of {cleanup} within [Path::Class].  This will remove unnecessary relative steps, and
try as best as possible to present an absolute path, or at least one that progresses in a sequential manner.  For example, if the
following paths were [File::Unix|Parse::Path::File::Unix] paths:

   /foo/baz/../foo.txt   # /foo/foo.txt
   /foo//baz/./foo.txt   # /foo/baz/foo.txt
   ../../foo/../bar.txt  # ../../bar.txt
   ./command             # command

Returns itself for chaining.

== as_string

   my $path_str = $path->as_string;

Returns the string form of the path.  This involves taking the individual step strings of the path and placing the delimiters in the
right place.

= UTILITY METHODS

These step conversion methods are available to use, but are somewhat internal, so they might be subject to change.  In most cases,
you can use the more public methods to achieve the same goals.

== key2hash

   my $step_hash = $path->key2hash($key, $type, $pos);
   my $step_hash = $path->key2hash($key, $type);

Figures out the missing pieces of a key/type pair, and returns a complete four-key step hash.  The [/normalize] method works by
throwing away the existing step and using this method.

Since pos translation works by using both step+delimiter, and {key2hash} doesn't have access to the delimiter, it's more accurate to
pass the pos value than leave it out.

== path_str2array

   my $path_array = $path->path_str2array($path_str);

Converts a path string into a path array (of step hashes).

== shift_path_str

   my $step_hash = $self->shift_path_str(\$path_str);

Removes a step from the beginning of the path string, and returns a complete four-key step hash.  This is the workhorse for most of
Parse::Path's use cases.

== blueprint

   my $data = $self->blueprint->{$blueprint_key};

Provides access to the blueprint for parsing the path style.  More informaton about what this hashref contains in the [role
documentation|Parse::Path::Role::Path].

Technically, the blueprint hashref is editable, but changing it is highly discouraged, and may break other paths!  Create your own
Path class if you need to change the specs.

= OVERLOADS

= MAKING YOUR OWN

= CAVEATS

== Absolute paths and step removal

== Normalization of splits

== Playing with two different Path styles

== Sparse arrays and memory usage

= SEE ALSO

### Ruler ########################################################################################################################12345

Other modules...

=end wikidoc
