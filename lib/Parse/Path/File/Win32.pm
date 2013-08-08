package Parse::Path::File::Win32;

# VERSION
# ABSTRACT: C:\Windows\file\path\support

#############################################################################
# Modules

use Moo;
use sanity;

use Types::Standard qw(StrMatch);

use namespace::clean;
no warnings 'uninitialized';

#############################################################################
# Attributes

has volume => (
   is      => 'rw',
   isa     => StrMatch[ qr/^[A-Za-z]?$/ ],
   default => sub { '' },
);

#############################################################################
# Required Methods

with 'Parse::Path::Role::Path';

sub _build_blueprint { {
   hash_step_regexp => qr{
      # Illegal characters: http://msdn.microsoft.com/en-us/library/windows/desktop/aa365247(v=vs.85).aspx
      (?<key>[^\x00-\x1F<>:"/\\|?*]*)
   }x,

   array_step_regexp   => qr/\Z.\A/,  # no-op; arrays not supported
   delimiter_regexp    => qr{\\+},    # + to capture repetitive slashes, like foo\\\\\bar

   # no support for escapes
   unescape_translation => [],

   pos_translation => [
      [qr{^\\+$},     0],
      [qr{^\.\.\\*$}, 'X-1'],
      [qr{^\.\\*$},   'X-0'],
      [qr{.?},        'X+1'],
   ],

   delimiter_placement => {
      '0R' => "\\",
      HH   => "\\",
   },

   array_key_sprintf        => '',
   hash_key_stringification => [
      [qr/.?/, '%s'],
   ],
} }

#############################################################################
# Modified Methods

# Remove volume to the path
around path_str2array => sub {
   my ($orig, $self, $path) = (shift, shift, shift);

   $self->volume($1) if ($path =~ s/^([A-Za-z])\://);

   return $self->$orig($path, @_);
};

# Uppercase volume on normalize
around _normalize => sub {
   my ($orig, $self) = (shift, shift);

   $self->volume(uc $self->volume);

   return $self->$orig(@_);
};

# Add volume to the path
around as_string => sub {
   my ($orig, $self) = (shift, shift);

   my $path_str = $self->$orig(@_);
   my $V = $self->volume;

   return ($V ? "$V:" : '').$path_str;
};

42;

__END__

=begin wikidoc

= SYNOPSIS

   use v5.10;
   use Parse::Path;

   my $path = Parse::Path->new(
      path  => 'C:\WINDOWS\SYSTEM32',
      style => 'File::Win32',
   );

   say $path->as_string;
   $path->push($path, 'DRIVERS');
   say $path->as_string;

   $path->volume('D');
   say $path->as_string;

= DESCRIPTION

This is a file-based path style for Windows paths.  Some examples:

   C:\WINDOWS
   c:\windows
   \Users
   C:foo\bar.txt
   ..\..\..\.\aaa\.\\\\\\bbb\ccc\..\ddd

Arrays are, of course, not supported.  Neither is quoting, as that is a product of the shell, not the path itself.

Absolute paths will contain a blank first step, a la [Path::Class].  Though, it is recommended to use
[is_absolute|Parse::Path/is_absolute] for checking for path relativity.

= EXTRA ATTRIBUTES

== volume

   my $volume = $path->volume;
   $path->volume('Z');
   $path->volume('');  # removes the volume

Returns or sets the volume.  This must be a single letter, or a blank string to remove it.

Volumes are automatically extracted and put into this attribute when passed as a path string.  If transformed back into a string, it
will show the volume again.  Normalization will capitalize the volume, as there is no difference between {C:} and {c:}.

= CAVEATS

* Though Windows isn't case-sensitive, it does support upper and lowercase letters.  Thus, there is no logic to force case on the
paths (except for volume), and is left as an exercise to the user.
* UNC paths are not supported.  This would be a different path style, anyway.

=end wikidoc
