#line 1
package Mouse::Object;
use strict;
use warnings;

use Scalar::Util 'weaken';
use Carp 'confess';

sub new {
    my $class = shift;

    my $args = $class->BUILDARGS(@_);

    my $instance = bless {}, $class;

    for my $attribute ($class->meta->compute_all_applicable_attributes) {
        my $from = $attribute->init_arg;
        my $key  = $attribute->name;

        if (defined($from) && exists($args->{$from})) {
            $args->{$from} = $attribute->coerce_constraint($args->{$from})
                if $attribute->should_coerce;
            $attribute->verify_against_type_constraint($args->{$from});

            $instance->{$key} = $args->{$from};

            weaken($instance->{$key})
                if ref($instance->{$key}) && $attribute->is_weak_ref;

            if ($attribute->has_trigger) {
                $attribute->trigger->($instance, $args->{$from}, $attribute);
            }
        }
        else {
            if ($attribute->has_default || $attribute->has_builder) {
                unless ($attribute->is_lazy) {
                    my $default = $attribute->default;
                    my $builder = $attribute->builder;
                    my $value = $attribute->has_builder
                              ? $instance->$builder
                              : ref($default) eq 'CODE'
                                  ? $default->($instance)
                                  : $default;

                    $value = $attribute->coerce_constraint($value)
                        if $attribute->should_coerce;
                    $attribute->verify_against_type_constraint($value);

                    $instance->{$key} = $value;

                    weaken($instance->{$key})
                        if ref($instance->{$key}) && $attribute->is_weak_ref;
                }
            }
            else {
                if ($attribute->is_required) {
                    confess "Attribute (".$attribute->name.") is required";
                }
            }
        }
    }

    $instance->BUILDALL($args);

    return $instance;
}

sub BUILDARGS {
    my $class = shift;

    if (scalar @_ == 1) {
        if (defined $_[0]) {
            (ref($_[0]) eq 'HASH')
                || confess "Single parameters to new() must be a HASH ref";
            return {%{$_[0]}};
        } else {
            return {};
        }
    }
    else {
        return {@_};
    }
}

sub DESTROY { shift->DEMOLISHALL }

sub BUILDALL {
    my $self = shift;

    # short circuit
    return unless $self->can('BUILD');

    for my $class (reverse $self->meta->linearized_isa) {
        no strict 'refs';
        no warnings 'once';
        my $code = *{ $class . '::BUILD' }{CODE}
            or next;
        $code->($self, @_);
    }
}

sub DEMOLISHALL {
    my $self = shift;

    # short circuit
    return unless $self->can('DEMOLISH');

    no strict 'refs';

    for my $class ($self->meta->linearized_isa) {
        my $code = *{ $class . '::DEMOLISH' }{CODE}
            or next;
        $code->($self, @_);
    }
}

sub dump { 
    my $self = shift;
    require Data::Dumper;
    local $Data::Dumper::Maxdepth = shift if @_;
    Data::Dumper::Dumper $self;
}

1;

__END__

#line 176


