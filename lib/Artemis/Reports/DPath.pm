use MooseX::Declare;

use 5.010;

class Artemis::Reports::DPath is dirty {

        use Artemis::Model 'model';
        use Text::Balanced 'extract_codeblock';
        use Data::DPath::Path;
        use Data::Dumper;
        use Cache::FileCache;

        use Sub::Exporter -setup => { exports =>           [ 'reportdata' ],
                                      groups  => { all  => [ 'reportdata' ] },
                                    };

        sub _extract_condition_and_part {
                my ($reports_path) = @_;
                my ($condition, $path) = extract_codeblock($reports_path, '{}');
                $path =~ s/^\s*::\s*//;
                return ($condition, $path);
        }

        # better use alias
        sub rds($) { reports_dpath_search(@_) }

        # better use alias
        sub reportdata($) { reports_dpath_search(@_) }

        # allow trivial better readable column names
        # - foo => 23           ... mapped to "me.foo" => 23
        # - "report.foo" => 23  ... mapped to "me.foo" => 23
        # - suite_name => "bar" ... mapped to "suite.name" => "bar"
        # - -and => ...         ... mapped to "-and" => ...            # just to ensure that it doesn't produce: "me.-and" => ...
        sub _fix_condition
        {
                no warnings 'uninitialized';
                my ($condition) = @_;
                $condition      =~ s/(['"])?\bsuite_name\b(['"])?\s*=>/"suite.name" =>/;        # ';
                $condition      =~ s/([^-\w])(['"])?((report|me)\.)?(?<!suite\.)(\w+)\b(['"])?(\s*)=>/$1"me.$5" =>/;        # ';
                return $condition;

        }

        # ===== CACHE =====

        # ----- cache complete Artemis::Reports::DPath queries -----

        sub _cachekey_whole_dpath {
                my ($reports_path) = @_;
                my $key = ($ENV{ARTEMIS_DEVELOPMENT} || "0") . '::' . $reports_path;
                #say STDERR "  . $key";
                return $key;
        }

        sub cache_whole_dpath  {
                my ($reports_path, $rs_count, $res) = @_;

                return if $ENV{HARNESS_ACTIVE};

                my $cache = new Cache::FileCache;

                # we cache on the dpath
                # but need count to verify and maintain cache validity

                say STDERR "  -> set whole: $reports_path ($rs_count)";
                $cache->set( _cachekey_whole_dpath($reports_path),
                             {
                              count => $rs_count,
                              res   => $res,
                             });
        }

        sub cached_whole_dpath {
                my ($reports_path, $rs_count) = @_;

                return if $ENV{HARNESS_ACTIVE};

                my $cache      = new Cache::FileCache;
                my $cached_res = $cache->get(  _cachekey_whole_dpath($reports_path) );

                say STDERR "  <- get whole: $reports_path ($rs_count vs. ".($cached_res->{count}||'').")";
                return undef              if not defined $cached_res;

                if ($cached_res->{count} and $cached_res->{count} == $rs_count) {
                        say STDERR "  Gotcha!";
                        return $cached_res->{res}
                }
                
                # clean up when matching report count changed
                $cache->remove( $reports_path );
                return undef;
        }

        # ----- cache single report dpaths queries -----

        sub _cachekey_single_dpath {
                my ($path, $reports_id) = @_;
                my $key = ($ENV{ARTEMIS_DEVELOPMENT} || "0") . '::' . $reports_id."::".$path;
                #say STDERR "  . $key";
                return $key;
        }

        sub cache_single_dpath {
                my ($path, $reports_id, $res) = @_;

                return if $ENV{HARNESS_ACTIVE};

                my $cache = new Cache::FileCache;
                say STDERR "  -> set single: $reports_id -- $path";
                $cache->set( _cachekey_single_dpath( $path, $reports_id ),
                             $res
                           );
        }

        sub cached_single_dpath {
                my ($path, $reports_id) = @_;

                return if $ENV{HARNESS_ACTIVE};

                my $cache      = new Cache::FileCache;
                my $cached_res = $cache->get( _cachekey_single_dpath( $path, $reports_id ));

                print STDERR "  <- get single: $reports_id -- $path: ".Dumper($cached_res);
                return $cached_res;
        }

        # ===== the query search =====

        sub reports_dpath_search($) {
                my ($reports_path) = @_;

                my ($condition, $path) = _extract_condition_and_part($reports_path);
                my $dpath              = new Data::DPath::Path( path => $path );
                $condition             = _fix_condition($condition);
                #say STDERR "condition: ".($condition || '');
                my %condition          = $condition ? %{ eval $condition } : ();
                my $rs = model('ReportsDB')->resultset('Report')->search
                    (
                     {
                      %condition
                     },
                     {
                      order_by  => 'me.id asc',
                      columns   => [ qw(
                                               id
                                               suite_id
                                               suite_version
                                               reportername
                                               peeraddr
                                               peerport
                                               peerhost
                                               successgrade
                                               reviewed_successgrade
                                               total
                                               failed
                                               parse_errors
                                               passed
                                               skipped
                                               todo
                                               todo_passed
                                               wait
                                               exit
                                               success_ratio
                                               starttime_test_program
                                               endtime_test_program
                                               machine_name
                                               machine_description
                                               created_at
                                               updated_at
                                      )],
                      join      => [ 'suite',      ],
                      '+select' => [ 'suite.name', ],
                      '+as'     => [ 'suite.name', ],
                     }
                    );
                my $rs_count = $rs->count();
                my @res = ();

                # layer 2 cache
                my $cached_res = cached_whole_dpath( $reports_path, $rs_count );
                return @$cached_res if defined $cached_res;

                while (my $row = $rs->next)
                {
                        my $report_id = $row->id;
                        # layer 1 cache

                        my $cached_row_res = cached_single_dpath( $path, $report_id );

                        if (defined $cached_row_res) {
                                push @res, @$cached_row_res;
                                next;
                        }

                        my $data = _as_data($row);
                        my @row_res = $dpath->match( $data );

                        cache_single_dpath($path, $report_id, \@row_res);

                        push @res, @row_res;
                }

                cache_whole_dpath($reports_path, $rs_count, \@res);

                return @res;
        }

        sub _dummy_needed_for_tests {
                # once there were problems with eval
                return eval "12345";
        }

        sub _as_data
        {
                my ($report) = @_;

                my $simple_hash = {
                                   report => {
                                              $report->get_columns,
                                              suite_name         => $report->suite ? $report->suite->name : 'unknown',
                                              machine_name       => $report->machine_name || 'unknown',
                                              created_at_ymd_hms => $report->created_at->ymd('-')." ".$report->created_at->hms(':'),
                                              created_at_ymd     => $report->created_at->ymd('-'),
                                             },
                                   results => $report->get_cached_tapdom,
                                  };
                return $simple_hash;
        }

}

package Artemis::Reports::DPath;
our $VERSION = '2.010013';

1;

__END__

=head1 NAME

Artemis::Reports::DPath - Extended DPath access to Artemis reports.

=head1 SYNOPSIS

    use Artemis::Reports::DPath 'reports_dpath_search';
    # the first bogomips entry of math sections:
    @resultlist = reportdata (
                     '{ suite_name => "TestSuite-LmBench" } :: /tap/section/math/*/bogomips[0]'
                  );
    # all report IDs of suite_id 17 that FAILed:
    @resultlist = reportdata (
                     '{ suite_name => "TestSuite-LmBench" } :: /suite_id[value == 17]/../successgrade[value eq 'FAIL']/../id'
                  );

This searches all reports of the test suite "TestSuite-LmBench" and
furthermore in them for a TAP section "math" with the particular
subtest "bogomips" and takes the first array entry of them.

The part before the '::' selects reports to search in a DBIx::Class
search query, the second part is a normal L<Data::DPath|Data::DPath>
expression that matches against the datastructure that is build from
the DB.

=head1 API FUNCTIONS

=head2 reports_dpath_search

Takes an extended DPath expression, applies it to an Artemis Reports
with TAP::DOM structure and returns the matching results in an array.

=head2 rds

Alias for reports_dpath_search.

=head2 reportdata

Alias for reports_dpath_search.


=head1 UTILITY FUNCTIONS

=head2 cache_single_dpath

Cache a result for a raw dpath on a report id.

=head2 cached_single_dpath

Return cached result for a raw dpath on a report id.

=head2 cache_whole_dpath

Cache a result for a complete artemis::dpath on all reports.

=head2 cached_whole_dpath

Return cached result for a complete artemis::dpath on all reports.

=head1 AUTHOR

OSRC SysInt Team, C<< <osrc-sysint at elbe.amd.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 OSRC SysInt Team, all rights reserved.

This program is released under the following license: proprietary


=cut

