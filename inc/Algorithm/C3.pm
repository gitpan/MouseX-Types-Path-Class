#line 1

package Algorithm::C3;

use strict;
use warnings;

use Carp 'confess';

our $VERSION = '0.07';

sub merge {
    my ($root, $parent_fetcher, $cache) = @_;

    $cache ||= {};

    my @STACK; # stack for simulating recursion

    my $pfetcher_is_coderef = ref($parent_fetcher) eq 'CODE';

    unless ($pfetcher_is_coderef or $root->can($parent_fetcher)) {
        confess "Could not find method $parent_fetcher in $root";
    }

    my $current_root = $root;
    my $current_parents = [ $root->$parent_fetcher ];
    my $recurse_mergeout = [];
    my $i = 0;
    my %seen = ( $root => 1 );

    my ($new_root, $mergeout, %tails);
    while(1) {
        if($i < @$current_parents) {
            $new_root = $current_parents->[$i++];

            if($seen{$new_root}) {
                my @isastack;
                my $reached;
                for(my $i = 0; $i < $#STACK; $i += 4) {
                    if($reached || ($reached = ($STACK[$i] eq $new_root))) {
                        push(@isastack, $STACK[$i]);
                    }
                }
                my $isastack = join(q{ -> }, @isastack, $current_root, $new_root);
                die "Infinite loop detected in parents of '$root': $isastack";
            }
            $seen{$new_root} = 1;

            unless ($pfetcher_is_coderef or $new_root->can($parent_fetcher)) {
                confess "Could not find method $parent_fetcher in $new_root";
            }

            push(@STACK, $current_root, $current_parents, $recurse_mergeout, $i);

            $current_root = $new_root;
            $current_parents = $cache->{pfetch}->{$current_root} ||= [ $current_root->$parent_fetcher ];
            $recurse_mergeout = [];
            $i = 0;
            next;
        }

        $seen{$current_root} = 0;

        $mergeout = $cache->{merge}->{$current_root} ||= do {

            # This do-block is the code formerly known as the function
            # that was a perl-port of the python code at
            # http://www.python.org/2.3/mro.html :)

            # Initial set (make sure everything is copied - it will be modded)
            my @seqs = map { [@$_] } @$recurse_mergeout;
            push(@seqs, [@$current_parents]) if @$current_parents;

            # Construct the tail-checking hash (actually, it's cheaper and still
            #   correct to re-use it throughout this function)
            foreach my $seq (@seqs) {
                $tails{$seq->[$_]}++ for (1..$#$seq);
            }

            my @res = ( $current_root );
            while (1) {
                my $cand;
                my $winner;
                foreach (@seqs) {
                    next if !@$_;
                    if(!$winner) {              # looking for a winner
                        $cand = $_->[0];        # seq head is candidate
                        next if $tails{$cand};  # he loses if in %tails
                        
                        # Handy warn to give a output like the ones on
                        # http://www.python.org/download/releases/2.3/mro/
                        #warn " = " . join(' + ', @res) . "  + merge([" . join('] [',  map { join(', ', @$_) } grep { @$_ } @seqs) . "])\n";
                        push @res => $winner = $cand;
                        shift @$_;                # strip off our winner
                        $tails{$_->[0]}-- if @$_; # keep %tails sane
                    }
                    elsif($_->[0] eq $winner) {
                        shift @$_;                # strip off our winner
                        $tails{$_->[0]}-- if @$_; # keep %tails sane
                    }
                }
                
                # Handy warn to give a output like the ones on
                # http://www.python.org/download/releases/2.3/mro/
                #warn " = " . join(' + ', @res) . "\n" if !$cand; 
                
                last if !$cand;
                die q{Inconsistent hierarchy found while merging '}
                    . $current_root . qq{':\n\t}
                    . qq{current merge results [\n\t\t}
                    . (join ",\n\t\t" => @res)
                    . qq{\n\t]\n\t} . qq{merging failed on '$cand'\n}
                  if !$winner;
            }
            \@res;
        };

        return @$mergeout if !@STACK;

        $i = pop(@STACK);
        $recurse_mergeout = pop(@STACK);
        $current_parents = pop(@STACK);
        $current_root = pop(@STACK);

        push(@$recurse_mergeout, $mergeout);
    }
}

1;

__END__

#line 339
