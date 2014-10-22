#line 1
package Any::Moose;
our $VERSION = '0.05';

# ABSTRACT: use Moose or Mouse modules

use strict;
use warnings;

our $PREFERRED = $ENV{'ANY_MOOSE'};

sub import {
    my $self = shift;
    my $pkg  = caller;

    # Any::Moose gives you strict and warnings (but only the first time, in case
    # you do something like: use Any::Moose; no strict 'refs')
    if (!defined(_backer_of($pkg))) {
        strict->import;
        warnings->import;
    }

    # first options are for Mo*se
    unshift @_, 'Moose' if !@_ || ref($_[0]);

    while (my $module = shift) {
        my $options = @_ && ref($_[0]) ? shift : [];

        $options = $self->_canonicalize_options(
            module  => $module,
            options => $options,
            package => $pkg,
        );

        $self->_install_module($options);
    }

    # give them any_moose too
    no strict 'refs';
    *{$pkg.'::any_moose'} = \&any_moose;
}

sub unimport {
    my $self = shift;
    my $pkg  = caller;

    my $backer = _backer_of($pkg);

    eval "package $pkg;\n"
       . '$backer->unimport(@_);';
}

sub _backer_of {
    my $pkg = shift;

    return 'Mouse' if $INC{'Mouse.pm'}
                   && Mouse::Meta::Class->_metaclass_cache($pkg);
    return 'Mouse::Role' if $INC{'Mouse/Role.pm'}
                         && Mouse::Meta::Role->_metaclass_cache($pkg);

    if (is_moose_loaded()) {
        my $meta = Class::MOP::get_metaclass_by_name($pkg);
        if ($meta) {
            return 'Moose::Role' if $meta->isa('Moose::Meta::Role');
            return 'Moose'       if $meta->isa('Moose::Meta::Class');
        }
    }

    return undef;
}

sub _canonicalize_options {
    my $self = shift;
    my %args = @_;

    my %options;
    if (ref($args{options}) eq 'HASH') {
        %options = %{ $args{options} };
    }
    else {
        %options = (
            imports => $args{options},
        );
    }

    $options{package} = $args{package};
    $options{module}  = any_moose($args{module}, $args{package});

    return \%options;
}

sub _install_module {
    my $self    = shift;
    my $options = shift;

    my $module = $options->{module};
    (my $file = $module . '.pm') =~ s{::}{/}g;

    require $file;

    eval "package $options->{package};\n"
       . '$module->import(@{ $options->{imports} });';
}

sub any_moose {
    my $fragment = _canonicalize_fragment(shift);
    my $package  = shift || caller;

    # Mouse gets first dibs because it doesn't introspect existing classes

    if ((_backer_of($package)||'') =~ /^Mouse/) {
        $fragment =~ s/^Moose/Mouse/;
        return $fragment;
    }

    return $fragment if (_backer_of($package)||'') =~ /^Moose/;

    # If we're loading up the backing class...
    if ($fragment eq 'Moose' || $fragment eq 'Moose::Role') {
        if (!$PREFERRED) {
            $PREFERRED = is_moose_loaded() ? 'Moose' : 'Mouse';

            (my $file = $PREFERRED . '.pm') =~ s{::}{/}g;
            require $file;
        }

        $fragment =~ s/^Moose/Mouse/ if $PREFERRED eq 'Mouse';
        return $fragment;
    }

    require Carp;
    Carp::croak("Neither Moose nor Mouse backs the '$package' package.");
}

sub load_class {
    my ($class_name) = @_;
    return Class::MOP::load_class($class_name)
        if is_moose_loaded();
    return Mouse::load_class($class_name);
}

sub is_moose_loaded { !!$INC{'Class/MOP.pm'} }

sub _canonicalize_fragment {
    my $fragment = shift;

    return 'Moose' if !defined($fragment);

    # any_moose("X::Types") -> any_moose("MooseX::Types")
    $fragment =~ s/^X::/MooseX::/;

    # any_moose("::Util") -> any_moose("Moose::Util")
    $fragment =~ s/^::/Moose::/;

    # any_moose("Mouse::Util") -> any_moose("Moose::Util")
    $fragment =~ s/^Mouse(X?)\b/Moose$1/;

    # any_moose("Util") -> any_moose("Moose::Util")
    $fragment =~ s/^(?!Moose)/Moose::/;

    # any_moose("Moose::") (via any_moose("")) -> any_moose("Moose")
    $fragment =~ s/^Moose::$/Moose/;

    return $fragment;
}

1;


__END__
