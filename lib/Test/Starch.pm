package Test::Starch;

=head1 NAME

Test::Starch - Test core features of starch.

=head1 SYNOPSIS

    use Test::More;
    
    my $tester = Test::Starch->new(
        plugins => [ ... ],
        store => ...,
        ...,
    );
    $tester->test();
    
    done_testing;

=head1 DESCRIPTION

This class runs the core L<Starch> test suite by testing public
interfaces of L<Starch::Manager>, L<Starch::State>, and
L<Starch::Store>.  These are the same tests that Starch runs
when you install it from CPAN.

This module is used by stores and plugins to ensure that they have
not broken any of the core features of Starch.  All store and plugin
authors are highly encouraged to run these tests as part of their
test suite.

Along the same lines, it is recommended that if you use Starch that
you make a test in your in-house test-suite which runs these tests
against your configuration.

This class takes all the same arguments as L<Starch> and saves them
to be used when L</new_manager> is called by the tests.  Unlike L<Starch>,
if the C<store> argument is not passed it will defailt to a Memory store.

=cut

use Types::Standard -types;
use Types::Common::String -types;

use Starch;
use Starch::Manager;
use Test::More;
use Test::Fatal;

use Moo;
use strictures 2;
use namespace::clean;

around BUILDARGS => sub{
    my $orig = shift;
    my $class = shift;

    my $args = $class->$orig( @_ );

    return {
        args => {
            store => { class=>'::Memory' },
            %$args,
        },
    };
};

has args => (
    is       => 'ro',
    isa      => HashRef,
    required => 1,
);

=head1 METHODS

=head2 new_manager

Creates a new L<Starch::Manager> object and returns it.  Any arguments
you specify to this method will override those specified when creating
the L<Test::Starch> object.

=cut

sub new_manager {
    my $self = shift;

    my $extra_args = Starch::Manager->BUILDARGS( @_ );

    return Starch->new(
        %{ $self->args() },
        %{ $extra_args },
    );
}

=head2 test

Calls L</test_manager>, L</test_state>, and L</test_store>.

=cut

sub test {
    my ($self) = @_;
    $self->test_manager();
    $self->test_state();
    $self->test_store();
    return;
}

=head2 test_manager

Tests L<Starch>.

=cut

sub test_manager {
    my ($self) = @_;

    my $starch = $self->new_manager();

    subtest 'core tests for ' . ref($starch) => sub{
        subtest clone_data => sub{
            my $old_data = { foo=>32, bar=>[1,2,3] };
            my $new_data = $starch->clone_data( $old_data );

            is_deeply( $new_data, $old_data, 'cloned data matches source data' );

            isnt( "$old_data->{bar}", "$new_data->{bar}", 'clone data structure has different reference' );
        };
    };


    return;
}

=head2 test_state

Test L<Starch::State>.

=cut

sub test_state {
    my ($self) = @_;

    my $starch = $self->new_manager();

    subtest 'core tests for ' . ref($starch->state()) => sub{
        subtest id => sub{
            my $state1 = $starch->state();
            my $state2 = $starch->state();
            my $state3 = $starch->state( '1234' );

            like( $state1->id(), qr{^\S+$}, 'ID looks good' );
            isnt( $state1->id(), $state2->id(), 'two generated state IDs are not the same' );
            is( $state3->id(), '1234', 'custom ID was used' );
        };

        subtest expires => sub{
            my $state = $starch->state();
            is( $state->expires(), $starch->expires(), 'state expires inherited the global expires' );
        };

        subtest modified => sub{
            my $state = $starch->state();
            is( $state->modified(), $state->created(), 'modfied is same as created in new state' );
            sleep 2;
            $state->force_save();
            $state = $starch->state( $state->id() );
            cmp_ok( $state->modified(), '>', $state->created(), 'modified was updated with save' );
        };

        subtest created => sub{
            my $start_time = time();
            my $state = $starch->state();
            my $created_time = $state->created();
            cmp_ok( $created_time, '>=', $start_time, 'state created on or after test start' );
            cmp_ok( $created_time, '<=', $start_time+1, 'state created is on or just after test start' );
            sleep 2;
            $state->force_save();
            $state = $starch->state( $state->id() );
            is( $state->created(), $created_time, 'created was updated with save' );
        };

        subtest in_store => sub{
            my $state1 = $starch->state();
            my $state2 = $starch->state( $state1->id() );

            is( $state1->in_store(), 0, 'new state is_new' );
            is( $state2->in_store(), 1, 'existing state is not is_new' );
        };

        subtest is_deleted => sub{
            my $state = $starch->state();
            is( $state->is_deleted(), 0, 'new state is not deleted' );
            $state->force_save();
            $state->delete();
            is( $state->is_deleted(), 1, 'deleted state is deleted' );
        };

        subtest is_dirty => sub{
            my $state = $starch->state();
            is( $state->is_dirty(), 0, 'new state is not is_dirty' );
            $state->data->{foo} = 543;
            is( $state->is_dirty(), 1, 'modified state is_dirty' );
        };

        subtest is_loaded => sub{
            my $state = $starch->state();
            ok( (!$state->is_loaded()), 'state is not loaded' );
            $state->data();
            ok( $state->is_loaded(), 'state is loaded' );
        };

        subtest is_saved => sub{
            my $state = $starch->state();
            ok( (!$state->is_saved()), 'state is not saved' );
            $state->force_save();
            ok( $state->is_saved(), 'state is saved' );
        };

        subtest save => sub{
            my $state1 = $starch->state();

            $state1->data->{foo} = 789;
            my $state2 = $starch->state( $state1->id() );
            is( $state2->data->{foo}, undef, 'new state did not receive data from old' );

            is( $state1->is_dirty(), 1, 'is dirty before save' );
            $state1->save();
            is( $state1->is_dirty(), 0, 'is not dirty after save' );
            $state2 = $starch->state( $state1->id() );
            is( $state2->data->{foo}, 789, 'new state did receive data from old' );
        };

        subtest force_save => sub{
            my $state = $starch->state();

            $state->data->{foo} = 931;
            $state->save();

            $state = $starch->state( $state->id() );
            $state->data();

            $starch->state( $state->id() )->delete();

            $state->save();
            is(
                $starch->state( $state->id() )->data->{foo},
                undef,
                'save did not save',
            );

            $state->force_save();
            is(
                $starch->state( $state->id() )->data->{foo},
                931,
                'force_save did save',
            );
        };

        subtest reload => sub{
            my $state = $starch->state();
            is( exception { $state->reload() }, undef, 'reloading a non-dirty state did not fail' );
            $state->data->{foo} = 2;
            like( exception { $state->reload() }, qr{dirty}, 'reloading a dirty state failed' );
        };

        subtest force_reload => sub{
            my $state1 = $starch->state();
            $state1->data->{foo} = 91;
            $state1->save();
            my $state2 = $starch->state( $state1->id() );
            $state2->data->{foo} = 19;
            $state2->save();
            $state1->reload();
            is( $state1->data->{foo}, 19, 'reload worked' );
        };

        subtest mark_clean => sub{
            my $state = $starch->state();
            $state->data->{foo} = 6934;
            is( $state->is_dirty(), 1, 'is dirty' );
            $state->mark_clean();
            is( $state->is_dirty(), 0, 'is clean' );
            is( $state->data->{foo}, 6934, 'data is intact' );
        };

        subtest rollback => sub{
            my $state = $starch->state();
            $state->data->{foo} = 6934;
            is( $state->is_dirty(), 1, 'is dirty' );
            $state->rollback();
            is( $state->is_dirty(), 0, 'is clean' );
            is( $state->data->{foo}, undef, 'data is rolled back' );

            $state->data->{foo} = 23;
            $state->mark_clean();
            $state->data->{foo} = 95;
            $state->rollback();
            is( $state->data->{foo}, 23, 'rollback to previous mark_clean' );
        };

        subtest delete => sub{
            my $state = $starch->state();
            like( exception { $state->delete() }, qr{stored}, 'calling delete on un-stored state fails' );
            $state->force_save();
            is( exception { $state->delete() }, undef, 'deleting a stored state does not fail' );
        };

        subtest force_delete => sub{
            my $state = $starch->state();
            $state->data->{foo} = 39;
            $state->save();

            $state = $starch->state( $state->id() );
            is( $state->data->{foo}, 39, 'state persists' );

            $state->delete();
            $state = $starch->state( $state->id() );
            is( $state->data->{foo}, undef, 'state was deleted' );
        };

        subtest set_expires => sub{
            my $state = $starch->state();
            is( $state->expires(), $starch->expires(), 'double check a new state gets the global expires' );
            $state->set_expires( 111 );
            $state->save();
            $state = $starch->state( $state->id() );
            is( $state->expires(), 111, 'custom expires was saved' );
        };

        subtest hash_seed => sub{
            my $state = $starch->state();
            isnt( $state->hash_seed(), $state->hash_seed(), 'two hash seeds are not the same' );
        };

        subtest generate_id => sub{
            my $state = $starch->state();

            isnt(
                $state->generate_id(),
                $state->generate_id(),
                'two generated ids are not the same',
            );
        };

        subtest reset_id => sub{
            my $state = $starch->state();

            $state->data->{foo} = 54;
            ok( $state->is_dirty(), 'state is dirty before save' );
            $state->save();
            ok( (!$state->is_dirty()), 'state is not dirty after save' );
            ok( $state->is_saved(), 'state is marked saved after save' );

            my $old_id = $state->id();
            $state->reset_id();
            ok( (!$state->is_saved()), 'state is not marked saved after reset_id' );
            ok( $state->is_dirty(), 'state is marked dirty after reset_id' );
            isnt( $state->id(), $old_id, 'state has new id after reset_id' );
            $state->save();

            my $old_state = $starch->state( $old_id );
            is( $old_state->data->{foo}, undef, 'old state data was deleted' );
        };
    };

    return;
}

=head2 test_store

Tests the L<Starch::Store>.

=cut

sub test_store {
    my ($self) = @_;

    my $starch = $self->new_manager();
    my $store = $starch->store();

    subtest 'core tests for ' . ref($store) => sub{

        subtest 'set, get, and remove' => sub{
            my $key = 'starch-test-key';
            $store->remove( $key, [] );

            is( $store->get( $key, [] ), undef, 'no data before set' );

            $store->set( $key, [], {foo=>6}, 10 );
            is( $store->get( $key, [] )->{foo}, 6, 'has data after set' );

            $store->remove( $key, [] );

            is( $store->get( $key, [] ), undef, 'no data after remove' );
        };

        subtest max_expires => sub{
            my $starch = $self->new_manager(
                expires => 89,
            );
            is( $starch->store->max_expires(), undef, 'store max_expires left at undef' );

            $starch = $self->new_manager(
                store=>{ class=>'::Memory', max_expires=>67 },
                expires => 89,
            );
            is( $starch->store->max_expires(), 67, 'store max_expires explicitly set' );
        };
    };

    return;
}

1;
__END__

=head1 AUTHORS AND LICENSE

See L<Starch/AUTHOR>, L<Starch/CONTRIBUTORS>, and L<Starch/LICENSE>.

=cut

