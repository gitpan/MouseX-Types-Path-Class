#line 1

package Class::C3;

use strict;
use warnings;

our $VERSION = '0.20';

our $C3_IN_CORE;
our $C3_XS;

BEGIN {
    if($] > 5.009_004) {
        $C3_IN_CORE = 1;
        require mro;
    }
    else {
        eval "require Class::C3::XS";
        my $error = $@;
        if(!$error) {
            $C3_XS = 1;
        }
        else {
            die $error if $error !~ /\blocate\b/;
            require Algorithm::C3;
            require Class::C3::next;
        }
    }
}

# this is our global stash of both 
# MRO's and method dispatch tables
# the structure basically looks like
# this:
#
#   $MRO{$class} = {
#      MRO => [ <class precendence list> ],
#      methods => {
#          orig => <original location of method>,
#          code => \&<ref to original method>
#      },
#      has_overload_fallback => (1 | 0)
#   }
#
our %MRO;

# use these for debugging ...
sub _dump_MRO_table { %MRO }
our $TURN_OFF_C3 = 0;

# state tracking for initialize()/uninitialize()
our $_initialized = 0;

sub import {
    my $class = caller();
    # skip if the caller is main::
    # since that is clearly not relevant
    return if $class eq 'main';

    return if $TURN_OFF_C3;
    mro::set_mro($class, 'c3') if $C3_IN_CORE;

    # make a note to calculate $class 
    # during INIT phase
    $MRO{$class} = undef unless exists $MRO{$class};
}

## initializers

# This prevents silly warnings when Class::C3 is
#  used explicitly along with MRO::Compat under 5.9.5+

{ no warnings 'redefine';

sub initialize {
    %next::METHOD_CACHE = ();
    # why bother if we don't have anything ...
    return unless keys %MRO;
    if($C3_IN_CORE) {
        mro::set_mro($_, 'c3') for keys %MRO;
    }
    else {
        if($_initialized) {
            uninitialize();
            $MRO{$_} = undef foreach keys %MRO;
        }
        _calculate_method_dispatch_tables();
        _apply_method_dispatch_tables();
        $_initialized = 1;
    }
}

sub uninitialize {
    # why bother if we don't have anything ...
    %next::METHOD_CACHE = ();
    return unless keys %MRO;    
    if($C3_IN_CORE) {
        mro::set_mro($_, 'dfs') for keys %MRO;
    }
    else {
        _remove_method_dispatch_tables();    
        $_initialized = 0;
    }
}

sub reinitialize { goto &initialize }

} # end of "no warnings 'redefine'"

## functions for applying C3 to classes

sub _calculate_method_dispatch_tables {
    return if $C3_IN_CORE;
    my %merge_cache;
    foreach my $class (keys %MRO) {
        _calculate_method_dispatch_table($class, \%merge_cache);
    }
}

sub _calculate_method_dispatch_table {
    return if $C3_IN_CORE;
    my ($class, $merge_cache) = @_;
    no strict 'refs';
    my @MRO = calculateMRO($class, $merge_cache);
    $MRO{$class} = { MRO => \@MRO };
    my $has_overload_fallback;
    my %methods;
    # NOTE: 
    # we do @MRO[1 .. $#MRO] here because it
    # makes no sense to interogate the class
    # which you are calculating for. 
    foreach my $local (@MRO[1 .. $#MRO]) {
        # if overload has tagged this module to 
        # have use "fallback", then we want to
        # grab that value 
        $has_overload_fallback = ${"${local}::()"} 
            if !defined $has_overload_fallback && defined ${"${local}::()"};
        foreach my $method (grep { defined &{"${local}::$_"} } keys %{"${local}::"}) {
            # skip if already overriden in local class
            next unless !defined *{"${class}::$method"}{CODE};
            $methods{$method} = {
                orig => "${local}::$method",
                code => \&{"${local}::$method"}
            } unless exists $methods{$method};
        }
    }    
    # now stash them in our %MRO table
    $MRO{$class}->{methods} = \%methods; 
    $MRO{$class}->{has_overload_fallback} = $has_overload_fallback;        
}

sub _apply_method_dispatch_tables {
    return if $C3_IN_CORE;
    foreach my $class (keys %MRO) {
        _apply_method_dispatch_table($class);
    }     
}

sub _apply_method_dispatch_table {
    return if $C3_IN_CORE;
    my $class = shift;
    no strict 'refs';
    ${"${class}::()"} = $MRO{$class}->{has_overload_fallback}
        if !defined &{"${class}::()"}
           && defined $MRO{$class}->{has_overload_fallback};
    foreach my $method (keys %{$MRO{$class}->{methods}}) {
        if ( $method =~ /^\(/ ) {
            my $orig = $MRO{$class}->{methods}->{$method}->{orig};
            ${"${class}::$method"} = $$orig if defined $$orig;
        }
        *{"${class}::$method"} = $MRO{$class}->{methods}->{$method}->{code};
    }    
}

sub _remove_method_dispatch_tables {
    return if $C3_IN_CORE;
    foreach my $class (keys %MRO) {
        _remove_method_dispatch_table($class);
    }
}

sub _remove_method_dispatch_table {
    return if $C3_IN_CORE;
    my $class = shift;
    no strict 'refs';
    delete ${"${class}::"}{"()"} if $MRO{$class}->{has_overload_fallback};    
    foreach my $method (keys %{$MRO{$class}->{methods}}) {
        delete ${"${class}::"}{$method}
            if defined *{"${class}::${method}"}{CODE} && 
               (*{"${class}::${method}"}{CODE} eq $MRO{$class}->{methods}->{$method}->{code});       
    }
}

sub calculateMRO {
    my ($class, $merge_cache) = @_;

    return Algorithm::C3::merge($class, sub { 
        no strict 'refs'; 
        @{$_[0] . '::ISA'};
    }, $merge_cache);
}

# Method overrides to support 5.9.5+ or Class::C3::XS

sub _core_calculateMRO { @{mro::get_linear_isa($_[0], 'c3')} }

if($C3_IN_CORE) {
    no warnings 'redefine';
    *Class::C3::calculateMRO = \&_core_calculateMRO;
}
elsif($C3_XS) {
    no warnings 'redefine';
    *Class::C3::calculateMRO = \&Class::C3::XS::calculateMRO;
    *Class::C3::_calculate_method_dispatch_table
        = \&Class::C3::XS::_calculate_method_dispatch_table;
}

1;

__END__

#line 576
