package Parse::Path::Role::Path;

# VERSION
# ABSTRACT: Role for paths

#############################################################################
# Modules

use Moo::Role;
use MooX::ClassAttribute;
use Types::Standard qw(Dict Bool Str Int Enum ArrayRef HashRef RegexpRef CodeRef Maybe);

use sanity;

use Scalar::Util qw( blessed );
use Storable qw( dclone );
use List::AllUtils qw( first all any );
use Sub::Name;

use namespace::clean;
no warnings 'uninitialized';

#############################################################################
# Overloading

use overload
   # with_assign  (XXX: No idea why it can't use '0+')
   '+'  => subname(_overload_plus => sub {
      my ($self, $thing, $swap) = @_;
      $self->depth + $thing;
   }),
   '-'  => subname(_overload_minus => sub {
      my ($self, $thing, $swap) = @_;
      $swap ?
         $thing - $self->depth :
         $self->depth - $thing
      ;
   }),

   # assign
   '.='   => subname(_overload_concat => sub {
      my ($self, $thing) = @_;
      $self->push($thing);
      $self;
   }),

   # 3way_comparison
   '<=>'  => subname(_overload_cmp_num => sub {
      my ($self, $thing, $swap) = @_;
      $swap ?
         $thing <=> $self->depth :
         $self->depth <=> $thing
      ;
   }),
   'cmp'  => subname(_overload_cmp => sub {
      my ($self, $thing, $swap) = @_;

      # If both of these are Parse::Path objects, run through the key comparisons
      if (blessed $thing and $thing->does('Parse::Path::Role::Path')) {
         ($self, $thing) = ($thing, $self) if $swap;

         my ($cmp, $i) = (0, 0);
         for (; $i <= $#{$self->_path} and $i <= $#{$thing->_path}; $i++) {
            my ($stepA, $stepB) = ($self->_path->[$i], $thing->_path->[$i]);
            my $cmp = $stepA->{type} eq 'ARRAY' && $stepB->{type} eq 'ARRAY' ?
               $stepA->{key} <=> $stepB->{key} :
               $stepA->{key} cmp $stepB->{key}
            ;

            return $cmp if $cmp;
         }

         # Now it's down to step counts
         return $self->step_count <=> $thing->step_count;
      }

      # Fallback to string comparison
      return $swap ?
         $thing cmp $self->as_string :
         $self->as_string cmp $thing
      ;
   }),

   # conversion
   'bool' => subname(_overload_bool   => sub { !!shift->step_count }),
   '""'   => subname(_overload_string => sub { shift->as_string }),
   '0+'   => subname(_overload_numify => sub { shift->depth }),

   # dereferencing
   '${}'  => subname(_overload_scalar => sub { \(shift->as_string) }),
   '@{}'  => subname(_overload_array  => sub { shift->as_array }),

   # special
   '='    => subname(_overload_clone  => sub { shift->clone })
;

#############################################################################
# Requirements

requires '_build_blueprint';

# Mainly for validation of class's blueprint
class_has _blueprint => (
   is       => 'ro',
   builder  => '_build_blueprint',
   lazy     => 1,
   init_arg => undef,
   isa      => Dict[
      hash_step_regexp  => RegexpRef,
      array_step_regexp => RegexpRef,
      delimiter_regexp  => RegexpRef,

      unescape_sub          => Maybe[CodeRef],
      unescape_quote_regexp => RegexpRef,

      delimiter_placement => HashRef[Str],
      pos_translation     => HashRef[Str],

      array_step_sprintf       => Str,
      hash_step_sprintf        => Str,
      hash_step_sprintf_quoted => Str,
      quote_on_regexp          => RegexpRef,

      escape_sub       => Maybe[CodeRef],
      escape_on_regexp => RegexpRef,
   ],
);

#############################################################################
# Attributes

# NOTE: hot attr; bypass isa
has _path => (
   is        => 'rw',
   #isa       => ArrayRef[Dict[
   #   type => Enum[qw( ARRAY HASH )],
   #   key  => Str,
   #   step => Str,
   #   pos  => Int,
   #]],
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

sub step_count { scalar @{shift->_path}; }

sub depth {
   my $self = shift;

   my $depth;
   foreach my $step_hash (@{$self->_path}) {
      my $pos = $step_hash->{pos};

      # Process depth
      if    ($pos =~ /^(\d+)$/)       { $depth  = $1; }  # absolute
      elsif ($pos =~ /^X([+\-]\d+)$/) { $depth += $1; }  # relative
      else {                                             # WTF is this?
         die sprintf("Found unparsable pos: %s (step: %s)", $pos, $step_hash->{step});
      }
   }

   return $depth;
}

sub is_absolute {
   my $self = shift;
   $self->step_count ? $self->_path->[0]{pos} !~ /^X/ : undef;
}

sub as_array  { dclone(shift->_path) }
sub blueprint { dclone(shift->_blueprint) }

sub shift   { {%{ shift @{shift->_path} }} }
sub pop     { {%{   pop @{shift->_path} }} }
sub unshift {
   my $self = shift;
   my $step_hashs = $self->_coerce_step([@_]);

   my $return = unshift @{$self->_path}, @$step_hashs;
   $self->cleanup if ($self->auto_cleanup and @$step_hashs);
   return $return;
}
sub push {
   my $self = shift;
   my $step_hashs = $self->_coerce_step([@_]);

   my $return = push @{$self->_path}, @$step_hashs;
   $self->cleanup if ($self->auto_cleanup and @$step_hashs);
   return $return;
}
sub splice {
   my ($self, $offset, $length) = (shift, shift, shift);
   my $step_hashs = $self->_coerce_step([@_]);

   # Perl syntax getting retardo here...
   my @params = ( $offset, defined $length ? ($length, @$step_hashs) : () );
   my @return = splice( @{$self->_path}, @params );
   #my $return = splice( @{$self->_path}, $offset, (defined $length ? ($length, @$step_hashs) : ()) );

   $self->cleanup if ($self->auto_cleanup and defined $length and @$step_hashs);
   return (wantarray ? {%{ $return[-1] }} : @{ dclone(\@return) });
}

sub clear {
   my $self = shift;
   $self->_path([]);
   return $self;
}
sub replace {
   my $self = shift;
   $self->clear->push(@_);
}

sub clone {
   my $self = shift;

   # if an argument is passed, assume it's a path
   my %path_args = @_ ? (
      path  => shift,
   ) : (
      _path => dclone($self->_path),
      path  => '',  # ignored
   );

   $self->new(
      %path_args,
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
      push @$new_array, $self->key2hash( @$item{qw(key type pos)} );
   }

   return $new_array;
}

sub cleanup {
   my $self = $_[0];
   my $path = $self->_path;
   my $new_path = [];

   my ($old_pos, $old_type);
   foreach my $step_hash (@$path) {
      my $full_pos = $step_hash->{pos};

      # Process pos
      my ($pos, $type);
      if    ($full_pos =~ /^(\d+)$/)       { ($pos, $type) = ($1, 'A'); }  # absolute
      elsif ($full_pos =~ /^X([+\-]\d+)$/) { ($pos, $type) = ($1, 'R'); }  # relative
      else {                                                               # WTF is this?
         die sprintf("During path cleanup, found unparsable pos: %s (step: %s)", $full_pos, $step_hash->{step});
      }
      $pos = int($pos);

      ### XXX: We may not need this level of complexity if we are only using 0, 1, X-1, X-0, X+1

      my $new_step_hash = { %$step_hash };

      # The most important pos is the first one
      unless (defined $old_pos) {
         $old_pos = $pos;
         $old_type  = $type;

         push(@$new_path, $new_step_hash);
         $new_step_hash->{pos} = $step_hash->{pos};
         next;
      }

      # Relative is going to continue the status quo
      if ($type eq 'R') {
         $old_pos += $pos;
         $new_step_hash->{pos} = $old_type eq 'A' ? $old_pos : sprintf 'X%+d', $pos;

         # Don't use the pos for placement.  Follow the chain of the index, using the array offset.
         # IOW, if it started out with something like X+3, we won't end up with a bunch of starter blanks.
         my $array_index = $#$new_path + $pos;

         # If the index ends up in the negative, we can't clean it up yet.
         if ($array_index < 0) {
            if ($old_type eq 'A') {
               # An absolute path should never go into the negative index (ie: /..)
               die sprintf("During path cleanup, an absolute path dropped into a negative depth (full path: %s)", $self->as_string);
            }

            push(@$new_path, $new_step_hash);
         }
         # Backtracking
         elsif ($pos <= 0) {
            # If the slicing would carve off past the end, just append and move on...
            if (@$new_path < abs($pos)) {
               push(@$new_path, $new_step_hash);
               next;
            }

            # Just ignore zero-pos (ie: /./)
            next unless $pos;

            # Carve off a slice of the $new_path
            my @back_path = splice(@$new_path, $pos);

            # If any of the steps in the path are a relative negative, we have to keep all of them.
            if (any { $_->{pos} =~ /^X-/ } @back_path) { push(@$new_path, @back_path, $new_step_hash); }

            # Otherwise, we won't save this virtual step, and trash the slice.
         }
         # Moving ahead
         else {
            $new_path->[$array_index] = $new_step_hash;
         }
      }
      # Absolute is a bit more error prone...
      elsif ($type eq 'A') {
         if ($old_type eq 'R') {
            # What the hell is ..\C:\ ?
            die sprintf("During path cleanup, a relative path found an illegal absolute step (full path: %s)", $self->as_string);
         }

         # Now this is just A/A, which is rarer, but still legal
         $new_step_hash->{pos} = $old_pos = $pos;
         $new_path->[$pos] = $new_step_hash;
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

      if ( all { exists $thing->{$_} } qw(key type step pos) ) {
         # We have no idea what data is in $thing, so we just soft clone it into
         # something else.  Our own methods will bypass the validation if we
         # pass the right thing, by accessing _path directly.
         return [{
            type => $thing->{type},
            key  => $thing->{key},
            step => $thing->{step},
            pos  => $thing->{pos},
         }];
      }

      # It's better to have a key/type pair than a step
      if (exists $thing->{key} and exists $thing->{type}) {
         my $step_hash = $self->key2hash( @$thing{qw(key type pos)} );
         return [ $step_hash ];
      }

      return $self->path_str2array( $thing->{step} ) if (exists $thing->{step});

      die 'Found incoercible HASH step with wrong keys/data';
   }

   # A collection of HASH steps?
   elsif (ref $thing eq 'ARRAY') {
      my $path_array = [];
      foreach my $item (@$thing) {
         my $step_hash = $self->_coerce_step($item);
         push @$path_array, (ref $step_hash eq 'ARRAY') ? @$step_hash : $step_hash;
      }

      return $path_array;
   }

   # WTF is this?
   else {
      die sprintf( "Found incoercible %s step", ref $thing );
   }
}

sub key2hash {
   my ($self, $key, $type, $pos) = @_;

   # Sanity checks
   die sprintf( "type not HASH or ARRAY (found %s)", $type )
      unless ($type =~ /^HASH$|^ARRAY$/);

   my $bp = $self->_blueprint;
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
      die sprintf( "Found %s key than didn't validate against regexp: '%s' --> '%s' (pos: %s)", $type, $key, $step, $pos // '???' );
   }

   return {
      type => $type,
      key  => $key,
      step => $step,
      ### XXX: No +delimiter in latter case.  Not our fault; doing the best we can with the data we've got! ###
      pos  => $pos // $self->_find_pos($step),
   };
}

sub path_str2array {
   my ($self, $path) = @_;
   my $path_array = [];

   while (length $path) {
      my $step_hash = $self->shift_path_str(\$path);

      push(@$path_array, $step_hash);
      die sprintf( "In path '%s', too deep down the rabbit hole, stopped at '%s'", $_[1], $path )
         if (@$path_array > 255);
   };

   return $path_array;
}

sub _find_pos {
   my ($self, $step_plus_delimiter) = @_;

   # Find a matching pos key
   my $dt = $self->_blueprint->{pos_translation};
   my $re = first { $_ ne '#DEFAULT#' && $step_plus_delimiter =~ /$_/; } (keys %$dt);
   $re //= '#DEFAULT#';

   return $dt->{$re};
}

sub shift_path_str {
   my ($self, $pathref) = @_;

   my $orig_path = $$pathref;

   my $bp = $self->_blueprint;
   my $hash_re  = $bp->{hash_step_regexp};
   my $array_re = $bp->{array_step_regexp};
   my $delim_re = $bp->{delimiter_regexp};

   my $step_hash;
   # Array first because hash could have zero-length string
   if ($$pathref =~ s/^(?<step>$array_re)//) {
      $step_hash = {
         type => 'ARRAY',
         key  => $+{key},
         step => $+{step},
      };
   }
   elsif ($$pathref =~ s/^(?<step>$hash_re)//) {
      $step_hash = {
         type => 'HASH',
         key  => $+{key},
         step => $+{step},
      };

      # Support escaping via double quotes
      $step_hash->{key} = $bp->{unescape_sub}->($step_hash->{key})
         if ($bp->{unescape_sub} and $+{quote} =~ $bp->{unescape_quote_regexp});
   }
   else {
      die sprintf( "Found unparsable step: '%s'", $$pathref );
   }

   $$pathref =~ s/^($delim_re)//;

   # Re-piece the step + delimiter to use with _find_pos
   $step_hash->{pos} = $self->_find_pos( $step_hash->{step}.$1 );

   # If the path is not shifting at all, then something is wrong with REs
   if (length $$pathref == length $orig_path) {
      die sprintf( "Found unshiftable step: '%s'", $$pathref );
   }

   return $step_hash;
}

sub as_string {
   my $self = $_[0];

   my $dlp = $self->_blueprint->{delimiter_placement};

   my $str = '';
   for my $i (0 .. $self->step_count - 1) {
      my $step_hash = $self->_path->[$i];
      my $next_step = ($i == $self->step_count - 1) ? undef : $self->_path->[$i+1];

      my $d = $step_hash->{pos};

      ### Left side delimiter placement
      if    (                   exists $dlp->{$d.'L'}) { $str .= $dlp->{$d.'L'};  }  # pos-specific
      elsif (not $next_step and exists $dlp->{'-1L'} ) { $str .= $dlp->{'-1L'};   }  # ending pos

      # Add the step
      $str .= $step_hash->{step};

      ### Right side delimiter placement
      my $L = substr($step_hash->{type}, 0, 1);
      if (exists $dlp->{$d.'R'}) {  # pos-specific (supercedes other right side options)
         $str .= $dlp->{$d.'R'};
      }
      elsif ($next_step) {          # ref-specific
         my $R = substr($next_step->{type}, 0, 1);
         $str .= $dlp->{$L.$R} if (exists $dlp->{$L.$R});
      }
      else {                        # ending pos
         if    (exists $dlp->{'-1R'}) { $str .= $dlp->{'-1R'}; }  # pos-specific
         elsif (exists $dlp->{$L})    { $str .= $dlp->{$L};    }  # ref-specific
      }
   }

   return $str;
}

42;

__END__

=begin wikidoc

= SYNOPSIS

   package Parse::Path::MyNewPath;

   use Moo;

   with 'Parse::Path::Role::Path';

   sub _build_blueprint { {
      hash_step_regexp  => qr/(?<key>\w+)|(?<quote>")(?<key>[^"]+)(?<quote>")/,
      array_step_regexp => qr/\[(?<key>\d{1,5})\]/,
      delimiter_regexp  => qr/(?:\.|(?=\[))/,

      unescape_sub          => undef,
      unescape_quote_regexp => qr/\Z.\A/,

      delimiter_placement => {
         HH => '.',
         AH => '.',
      },

      pos_translation => {
         '#DEFAULT#' => 'X+1',
      },

      array_step_sprintf       => '[%u]',
      hash_step_sprintf        => '%s',
      hash_step_sprintf_quoted => '"%s"',
      quote_on_regexp          => qr/\W|^$/,

      escape_sub       => undef,
      escape_on_regexp => qr/\Z.\A/,
   } }

= DESCRIPTION

This is the base role for [Parse::Path] and contains 95% of the code.  The idea behind the path classes is that they should be able to
get by with a single blueprint and little to no changes to the main methods.

= BLUEPRINT

The blueprint [class attribute|MooX::ClassAttribute] is a hashref of various properties that detail how the path is parsed and put
back together.  All properties are required, though some can be turned off.

== hash_step_regexp

   hash_step_regexp => qr/(?<key>\w+)|(?<quote>")(?<key>[^"]+)(?<quote>")/

== array_step_regexp

   array_step_regexp => qr/\[(?<key>\d{1,5})\]/
   array_step_regexp => qr/\Z.\A/   # no-op; turn off array support

== delimiter_regexp

   delimiter_regexp => qr/(?:\.|(?=\[))/

== unescape_sub

   unescape_sub => \&String::Escape::unbackslash
   unescape_sub => undef  # turn off unescape support

== unescape_quote_regexp

   unescape_quote_regexp => qr/\"/
   unescape_quote_regexp => qr/\Z.\A/  # no-op; turn off unescape support

== delimiter_placement

   delimiter_placement => {
      '0R' => '/',
      HH   => '.',
      AH   => '.',
   },

== pos_translation

   pos_translation => {
      qr{^/+$}     => 0,
      qr{^\.\./*$} => 'X-1',
      qr{^\./*$}   => 'X-0',
      '#DEFAULT#'  => 'X+1',
   },

== array_step_sprintf

   array_step_sprintf => '[%u]'
   array_step_sprintf => ''  # turn off array support

== hash_step_sprintf

   hash_step_sprintf => '%s'

== hash_step_sprintf_quoted

   hash_step_sprintf_quoted => '"%s"'
   hash_step_sprintf_quoted => '%s'  # no quoting

== quote_on_regexp

   quote_on_regexp => qr/\W|^$/
   quote_on_regexp => qr/\Z.\A/  # no-op; turn off quoting

== escape_sub

   escape_sub => \&String::Escape::backslash
   escape_sub => undef  # turn off escape support

== escape_on_regexp

   escape_on_regexp => qr/\W|^$/
   escape_on_regexp => qr/\Z.\A/  # no-op; turn off escape support

= CAVEATS


= SEE ALSO

### Ruler ########################################################################################################################12345

Other modules...

=end wikidoc
