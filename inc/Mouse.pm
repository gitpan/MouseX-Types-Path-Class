#line 1
package Mouse;
use strict;
use warnings;
use 5.006;
use base 'Exporter';

our $VERSION = '0.19';

use Carp 'confess';
use Scalar::Util 'blessed';
use Mouse::Util;

use Mouse::Meta::Attribute;
use Mouse::Meta::Class;
use Mouse::Object;
use Mouse::Util::TypeConstraints;

our @EXPORT = qw(extends has before after around override super blessed confess with);

sub extends { Mouse::Meta::Class->initialize(caller)->superclasses(@_) }

sub has {
    my $meta = Mouse::Meta::Class->initialize(caller);
    $meta->add_attribute(@_);
}

sub before {
    my $meta = Mouse::Meta::Class->initialize(caller);

    my $code = pop;

    for (@_) {
        $meta->add_before_method_modifier($_ => $code);
    }
}

sub after {
    my $meta = Mouse::Meta::Class->initialize(caller);

    my $code = pop;

    for (@_) {
        $meta->add_after_method_modifier($_ => $code);
    }
}

sub around {
    my $meta = Mouse::Meta::Class->initialize(caller);

    my $code = pop;

    for (@_) {
        $meta->add_around_method_modifier($_ => $code);
    }
}

sub with {
    Mouse::Util::apply_all_roles((caller)[0], @_);
}

our $SUPER_PACKAGE;
our $SUPER_BODY;
our @SUPER_ARGS;

sub super {
    # This check avoids a recursion loop - see
    # t/100_bugs/020_super_recursion.t
    return if defined $SUPER_PACKAGE && $SUPER_PACKAGE ne caller();
    return unless $SUPER_BODY; $SUPER_BODY->(@SUPER_ARGS);
}

sub override {
    my $meta = Mouse::Meta::Class->initialize(caller);
    my $pkg = $meta->name;

    my $name = shift;
    my $code = shift;

    my $body = $pkg->can($name)
        or confess "You cannot override '$name' because it has no super method";

    $meta->add_method($name => sub {
        local $SUPER_PACKAGE = $pkg;
        local @SUPER_ARGS = @_;
        local $SUPER_BODY = $body;

        $code->(@_);
    });
}

sub import {
    my $class = shift;

    strict->import;
    warnings->import;

    my $opts = do {
        if (ref($_[0]) && ref($_[0]) eq 'HASH') {
            shift @_;
        } else {
            +{ };
        }
    };
    my $level = delete $opts->{into_level};
       $level = 0 unless defined $level;
    my $caller = caller($level);

    # we should never export to main
    if ($caller eq 'main') {
        warn qq{$class does not export its sugar to the 'main' package.\n};
        return;
    }

    my $meta = Mouse::Meta::Class->initialize($caller);
    $meta->superclasses('Mouse::Object')
        unless $meta->superclasses;

    no strict 'refs';
    no warnings 'redefine';
    *{$caller.'::meta'} = sub { $meta };

    if (@_) {
        __PACKAGE__->export_to_level( $level+1, $class, @_);
    } else {
        # shortcut for the common case of no type character
        no strict 'refs';
        for my $keyword (@EXPORT) {
            *{ $caller . '::' . $keyword } = *{__PACKAGE__ . '::' . $keyword};
        }
    }
}

sub unimport {
    my $caller = caller;

    no strict 'refs';
    for my $keyword (@EXPORT) {
        delete ${ $caller . '::' }{$keyword};
    }
}

sub load_class {
    my $class = shift;

    if (ref($class) || !defined($class) || !length($class)) {
        my $display = defined($class) ? $class : 'undef';
        confess "Invalid class name ($display)";
    }

    return 1 if $class eq 'Mouse::Object';
    return 1 if is_class_loaded($class);

    (my $file = "$class.pm") =~ s{::}{/}g;

    eval { CORE::require($file) };
    confess "Could not load class ($class) because : $@" if $@;

    return 1;
}

sub is_class_loaded {
    my $class = shift;

    return 0 if ref($class) || !defined($class) || !length($class);

    # walk the symbol table tree to avoid autovififying
    # \*{${main::}{"Foo::"}} == \*main::Foo::

    my $pack = \*::;
    foreach my $part (split('::', $class)) {
        return 0 unless exists ${$$pack}{"${part}::"};
        $pack = \*{${$$pack}{"${part}::"}};
    }

    # check for $VERSION or @ISA
    return 1 if exists ${$$pack}{VERSION}
             && defined *{${$$pack}{VERSION}}{SCALAR};
    return 1 if exists ${$$pack}{ISA}
             && defined *{${$$pack}{ISA}}{ARRAY};

    # check for any method
    foreach ( keys %{$$pack} ) {
        next if substr($_, -2, 2) eq '::';
        return 1 if defined *{${$$pack}{$_}}{CODE};
    }

    # fail
    return 0;
}

1;

__END__

#line 447

