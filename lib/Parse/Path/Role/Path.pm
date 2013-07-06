package Data::Path::Role::Path;

# VERSION
# ABSTRACT: Role for paths

#############################################################################
# Modules

use Moo::Role;
use MooX::Types::MooseLike 0.18;  # *Of support
use MooX::Types::MooseLike::Base qw(Bool Str ArrayRef HashRef InstanceOf);

use sanity;

use Scalar::Util qw( blessed );
use Storable qw( dclone );
use List::AllUtils qw( first all any );

use namespace::clean;
no warnings 'uninitialized';

#############################################################################
# Overloading

use overload
   # assign

   ### FIXME: assign subs shouldn't modify its assignment :(
   #'.='   => sub {
   #   my ($self, $thing) = @_;
   #   $self->push($thing);
   #},

   # 3way_comparison
   #'cmp'  ### TODO

   # conversion
   'bool' => sub { !!shift->step_count },
   '""'   => sub { shift->as_string    },
   '0+'   => sub { shift->step_count   },
   #'qr'  ### TODO

   # dereferencing
   '@{}'  => sub { @{ dclone(shift->_path) } },

   # special
   '='    => sub { shift->clone }
;

#############################################################################
# Requirements

requires 'blueprint';

# hash_step_regexp
# array_step_regexp
# delimiter_regexp
#
# unescape_sub
# unescape_quote_regexp
#
# delimiter_placement
# depth_translation
#
# array_step_sprintf
# hash_step_sprintf
# hash_step_sprintf_quoted
# quote_on_regexp
#
# escape_sub
# escape_on_regexp

#############################################################################
# Attributes

has _path => (
   is        => 'rw',
   isa       => ArrayRef[HashRef[Str]],
   predicate => 1,
);

has _tmp_path_thing => (
   is       => 'ro',
   init_arg => 'path',
   required => 1,
   clearer  => 1,
);

has auto_normalize => (
   is        => 'rw',
   isa       => Bool,
   default   => sub { 0 },
);

has auto_cleanup => (
   is        => 'rw',
   isa       => Bool,
   default   => sub { 0 },
);

#############################################################################
# Pre/post-BUILD

sub BUILD {
   my $self = $_[0];

   # Post-build coercion of path
   unless ($self->_has_path) {
      my $path_array = $self->_coerce_step( $self->_tmp_path_thing );

      $self->_path( $path_array );
      $self->cleanup if ($self->auto_cleanup and @$path_array);
   }
   $self->_clear_tmp_path_thing;  # ...and may it never return...

   return $self;
}

#############################################################################
# Methods

# XXX: The array-based methods makes internal CORE calls ambiguous
no warnings 'ambiguous';

sub depth {
   my $self = shift;
   $self->step_count ? $self->_path->[-1]{depth} : undef;
}
sub step_count { scalar @{shift->_path}; }

sub is_absolute {
   my $self = shift;
   $self->step_count ? $self->_path->[0]{depth} !~ /^X/ : undef;
}

sub shift   {   shift @{shift->_path}; }
sub pop     {     pop @{shift->_path}; }
sub unshift {
   my $self = shift;
   my $hash_steps = $self->_coerce_step([@_]);

   my $return = unshift @{$self->_path}, @$hash_steps;
   $self->cleanup if ($self->auto_cleanup and @$hash_steps);
   return $return;
}
sub push {
   my $self = shift;
   my $hash_steps = $self->_coerce_step([@_]);

   my $return = push @{$self->_path}, @$hash_steps;
   $self->cleanup if ($self->auto_cleanup and @$hash_steps);
   return $return;
}
sub splice {
   my ($self, $offset, $length) = (shift, shift, shift);
   my $hash_steps = $self->_coerce_step([@_]);

   # Perl syntax getting retardo here...
   my @params = ( $offset, defined $length ? ($length, @$hash_steps) : () );
   my @return = splice( @{$self->_path}, @params );
   #my $return = splice( @{$self->_path}, $offset, (defined $length ? ($length, @$hash_steps) : ()) );

   $self->cleanup if ($self->auto_cleanup and defined $length and @$hash_steps);
   return \@return;
}

sub clone {
   my $self = $_[0];

   $self->new(
      _path => dclone($self->_path),
      path  => '',  # ignored

      auto_normalize => $self->auto_normalize,
      auto_cleanup   => $self->auto_cleanup,
   );
}

sub normalize {
   my $self = $_[0];
   $self->_normalize( $self->_path );
   return $self;
}

sub _normalize {
   my ($self, $path_array) = @_;

   # For normalization, can't trust the original step, so we make new ones
   my $new_array = [];
   foreach my $item (@$path_array) {
      my $hash_step = $self->key2hash( @$item{qw(key type depth)} );
      push @$new_array, (ref $hash_step eq 'ARRAY') ? @$hash_step : $hash_step;
   }

   return $new_array;
}

sub cleanup {
   my $self = $_[0];
   my $path = $self->_path;
   my $new_path = [];

### FIXME: Rename depth to index or pos ###

   my ($old_depth, $old_type);
   foreach my $hash_step (@$path) {
      my $full_depth = $hash_step->{depth};

      # Process depth
      my ($depth, $type);
      if    ($full_depth =~ /^(\d+)$/)       { ($depth, $type) = ($1, 'A'); }  # absolute
      elsif ($full_depth =~ /^X([+\-]\d+)$/) { ($depth, $type) = ($1, 'R'); }  # relative
      else {                                                                   # WTF is this?
         die sprintf("During path cleanup, found unparsable depth: %s (step: %s)", $full_depth, $hash_step->{step});
      }
      $depth = int($depth);

      ### FIXME: Revisit this after plotting all of the path classes...
      ### We may not need this level of complexity if we are only using 0, 1, X-1, X-0, X+1

      my $new_hash_step = { %$hash_step };

      # The most important depth is the first one
      unless (defined $old_depth) {
         $old_depth = $depth;
         $old_type  = $type;

         push(@$new_path, $new_hash_step);
         $new_hash_step->{depth} = $hash_step->{depth};
         next;
      }

      # Relative is going to continue the status quo
      if ($type eq 'R') {
         $old_depth += $depth;
         $new_hash_step->{depth} = $old_type eq 'A' ? $old_depth : sprintf 'X%+d', $depth;

         # Don't use the depth for placement.  Follow the chain of the index, using the array offset.
         # IOW, if it started out with something like X+3, we won't end up with a bunch of starter blanks.
         my $array_index = $#$new_path + $depth;

         # If the index ends up in the negative, we can't clean it up yet.
         if ($array_index < 0) {
            if ($old_type eq 'A') {
               # FIXME: Solve for C:\.. (which should error sooner)

               # An absolute path should never go into the negative index (ie: /..)
               die sprintf("During path cleanup, an absolute path dropped into a negative depth (full path: %s)", $self->as_string);
            }

            push(@$new_path, $new_hash_step);
         }
         # Backtracking
         elsif ($depth <= 0) {
            # If the slicing would carve off past the end, just append and move on...
            if (@$new_path < abs($depth)) {
               push(@$new_path, $new_hash_step);
               next;
            }

            # Just ignore zero-depth (ie: /./)
            next unless $depth;

            # Carve off a slice of the $new_path
            my @back_path = splice(@$new_path, $depth);

            # If any of the steps in the path are a relative negative, we have to keep all of them.
            if (any { $_->{depth} =~ /^X-/ } @back_path) { push(@$new_path, @back_path, $new_hash_step); }

            # Otherwise, we won't save this virtual step, and trash the slice.
         }
         # Moving ahead
         else {
            $new_path->[$array_index] = $new_hash_step;
         }
      }
      # Absolute is a bit more error prone...
      elsif ($type eq 'A') {
         if ($old_type eq 'R') {
            # What the hell is ..\C:\ ?
            die sprintf("During path cleanup, a relative path found an illegal absolute step (full path: %s)", $self->as_string);
         }

         # Now this is just A/A, which is rarer, but may happen with volumes
         $new_hash_step->{depth} = $old_depth = $depth;
         $new_path->[$depth] = $new_hash_step;
      }
   }

   # Replace
   $self->_path( $new_path );

   return $self;
}

sub _coerce_step {
   my ($self, $thing) = @_;

   # A string step/path to be converted to a HASH step
   unless (ref $thing) {
      my $path_array = $self->path_str2array($thing);
      return $path_array unless $self->auto_normalize;
      return $self->_normalize($path_array);
   }

   # Another DP path object
   elsif (blessed $thing and $thing->does('Parse::Path::Role::Path')) {
      # At the very least, we need to make sure our depths are cleaned up.
      $self ->cleanup;
      $thing->cleanup;

      # If the class is the same, it's the same type of path and we can do a
      # direct transfer.  And only if the path is normalized, or we don't care
      # about it.
      return dclone($thing->_path) if (
         $thing->isa($self) and
         $thing->auto_normalize || !$self->auto_normalize
      );

      return $self->_normalize($thing->_path);
   }

   # WTF is this?
   elsif (blessed $thing) {
      die sprintf( "Found incoercible %s step (blessed)", blessed $thing );
   }

   # A potential HASH step
   elsif (ref $thing eq 'HASH') {
      die 'Found incoercible HASH step with ref values'
         if (grep { ref $_ } values %$thing);

      if ( all { exists $thing->{$_} } qw(key type step depth) ) {
         # We have no idea what data is in $thing, so we just soft clone it into
         # something else.  Our own methods will bypass the validation if we
         # pass the right thing, by accessing _path directly.
         return [{
            type  => $thing->{type},
            key   => $thing->{key},
            step  => $thing->{step},
            depth => $thing->{depth},
         }];
      }

      # It's better to have a key/type pair than a step
      if (exists $thing->{key} and exists $thing->{type}) {
         my $hash_step = $self->key2hash( @$thing{qw(key type depth)} );
         return [ $hash_step ];
      }

      return $self->path_str2array( $thing->{step} ) if (exists $thing->{step});

      die 'Found incoercible HASH step with wrong keys/data';
   }

   # A collection of HASH steps?
   elsif (ref $thing eq 'ARRAY') {
      my $path_array = [];
      foreach my $item (@$thing) {
         my $hash_step = $self->_coerce_step($item);
         push @$path_array, (ref $hash_step eq 'ARRAY') ? @$hash_step : $hash_step;
      }

      return $path_array;
   }

   # WTF is this?
   else {
      die sprintf( "Found incoercible %s step", ref $thing );
   }
}

sub key2hash {
   my ($self, $key, $type, $depth) = @_;

   # Sanity checks
   die sprintf( "type not HASH or ARRAY (found %s)", $type )
      unless ($type =~ /^HASH$|^ARRAY$/);

   my $bp = $self->blueprint;
   my $hash_re  = $bp->{hash_step_regexp};
   my $array_re = $bp->{array_step_regexp};

   # Transform the key to a string step
   my $step = $key;
   if ($type eq 'HASH') {
      $step = $bp->{escape_sub}->($step) if ($bp->{escape_sub} and $step =~ $bp->{escape_on_regexp});
      $step = sprintf ($bp->{
         'hash_step_sprintf'.($step =~ $bp->{quote_on_regexp} ? '_quoted' : '')
      }, $step);
   }
   else {
      $step = sprintf ($bp->{array_step_sprintf}, $step);
   }

   # Validate the new step
   if (
      $type eq 'HASH'  and $step !~ /^$hash_re$/ ||
      $type eq 'ARRAY' and $step !~ /^$array_re$/
   ) {
      die sprintf( "Found %s key than didn't validate against regexp: '%s' --> '%s' (depth: %s)", $type, $key, $step, $depth // '???' );
   }

   return {
      type  => $type,
      key   => $key,
      step  => $step,
      ### XXX: No +delimiter in latter case.  Not our fault; doing the best we can with the data we've got! ###
      depth => $depth // $self->_find_depth($step),
   };
}

sub path_str2array {
   my ($self, $path) = @_;
   my $path_array = [];

   while (length $path) {
      my $hash_step = $self->shift_path_str(\$path, scalar @$path_array);

      push(@$path_array, $hash_step);
      die sprintf( "In path '%s', too deep down the rabbit hole, stopped at '%s'", $_[1], $path )
         if (@$path_array > 255);
   };

   return $path_array;
}

sub _find_depth {
   my ($self, $step_plus_delimiter) = @_;

   # Find a matching depth key
   my $dt = $self->blueprint->{depth_translation};
   my $re = first { $_ ne '#DEFAULT#' && $step_plus_delimiter =~ /$_/; } (keys %$dt);
   $re //= '#DEFAULT#';

   return $dt->{$re};
}

sub shift_path_str {
   my ($self, $pathref, $depth) = @_;

   my $orig_path = $$pathref;

   my $bp = $self->blueprint;
   my $hash_re  = $bp->{hash_step_regexp};
   my $array_re = $bp->{array_step_regexp};
   my $delim_re = $bp->{delimiter_regexp};

   my $hash_step;
   # Array first because hash could have zero-length string
   if ($$pathref =~ s/^(?<step>$array_re)//) {
      $hash_step = {
         type => 'ARRAY',
         key  => $+{key},
         step => $+{step},
      };
   }
   elsif ($$pathref =~ s/^(?<step>$hash_re)//) {
      $hash_step = {
         type => 'HASH',
         key  => $+{key},
         step => $+{step},
      };

      # Support escaping via double quotes
      $hash_step->{key} = $bp->{unescape_sub}->($hash_step->{key})
         if ($bp->{unescape_sub} and $+{quote} =~ $bp->{unescape_quote_regexp});
   }
   else {
      die sprintf( "Found unparsable step: '%s'", $_[1], $$pathref );
   }

   $$pathref =~ s/^($delim_re)//;

   # Re-piece the step + delimiter to use with _find_depth
   $hash_step->{depth} = $self->_find_depth( $hash_step->{step}.$1 );

   # If the path is not shifting at all, then something is wrong with REs
   if (length $$pathref == length $orig_path) {
      die sprintf( "Found unshiftable step: '%s'", $$pathref );
   }

   return $hash_step;
}

sub as_string {
   my $self = $_[0];

   my $dlp = $self->blueprint->{delimiter_placement};

   my $str = '';
   for my $i (0 .. $self->step_count - 1) {
      my $hash_step = $self->_path->[$i];
      my $next_step = ($i == $self->step_count - 1) ? undef : $self->_path->[$i+1];

      my $d = $hash_step->{depth};

      ### Left side delimiter placement
      if    (                   exists $dlp->{$d.'L'}) { $str .= $dlp->{$d.'L'};  }  # depth-specific
      elsif (not $next_step and exists $dlp->{'-1L'} ) { $str .= $dlp->{'-1L'};   }  # ending depth

      # Add the step
      $str .= $hash_step->{step};

      ### Right side delimiter placement
      my $L = substr($hash_step->{type}, 0, 1);
      if (exists $dlp->{$d.'R'}) {  # depth-specific (supercedes other right side options)
         $str .= $dlp->{$d.'R'};
      }
      elsif ($next_step) {          # ref-specific
         my $R = substr($next_step->{type}, 0, 1);
         $str .= $dlp->{$L.$R} if (exists $dlp->{$L.$R});
      }
      else {                        # ending depth
         if    (exists $dlp->{'-1R'}) { $str .= $dlp->{'-1R'}; }  # depth-specific
         elsif (exists $dlp->{$L})    { $str .= $dlp->{$L};    }  # ref-specific
      }
   }

   return $str;
}

42;

__END__

=begin wikidoc

= SYNOPSIS

   use v5.10;
   use Parse::Path;

   my $path = Parse::Path->new(
      path => 'gophers[0].food.count',
      path_style => 'DZIL',  # default
   );

   my $step = $path->shift;  # { key => 'count', ... }
   say $path->as_string;
   $path->push($step, '[2]');

   foreach my $p (@$path) {
      say sprintf('%-6s %s --> %s', @$p{qw(type step key)});
   }

= DESCRIPTION

Parse::Path is, well, a parser for paths.  File paths, object paths, URLs...  A path is whatever string that can be translated into
hash/array keys.

### FIXME: Examples of usage with other Paths, step keys, etc. ###

= CONSTRUCTOR

   my $path = Parse::Path->new(
      path => $path,         # required
      path_style => 'DZIL',  # default
   );

Creates a new path object.  Parse::Path is really just a dispatcher to other Parse::Path modules, but it serves as a common API for
all of them.

Accepts the following arguments:

== path

   path => 'gophers[0].food.count'

String used to create path.  Can also be another Parse::Path object, a step, an array of steps, an array of paths, or whatever makes
sense.

This parameter is required.

== path_style

   path_style => 'File::Unix'
   path_style => '=MyApp::Parse::Path::Foobar'

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

   my $step = $path->shift;

Works just like the Perl version.  Removes a step from the beginning of the path and returns it.

== pop

   my $step = $path->pop;

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

   my @steps = $path->splice($offset, $length, $step_or_path);
   my @steps = $path->splice($offset, $length);
   my @steps = $path->splice($offset);

   my $last_step = $path->splice($offset);

Works just like the Perl version.  Removes elements designated by the offset and length, and replaces them with the new step/path.
Returns the steps removed in list context, or the last step removed in scalar context.  Will also call [/cleanup] afterwards, if
[/auto_cleanup] is enabled.

== clone

   my $same_path = $path->clone;

Clones the path.  Returns the same type of object.

== normalize

== cleanup

== key2hash

== path_str2array

== shift_path_str

== as_string
### NOTE: basically the opposite of path_str2array ###

== blueprint

= OVERLOADS

= MAKING YOUR OWN

= CAVEATS

== Absolute paths and step removal

= SEE ALSO

### Ruler ########################################################################################################################12345

Other modules...

=end wikidoc
