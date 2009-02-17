#! perl

use Test::More;

BEGIN {
        use Class::C3;
        use MRO::Compat;
}

use Artemis::Reports::DPath::Mason 'render';
use Artemis::Schema::TestTools;
use Test::Fixture::DBIC::Schema;
use Data::Dumper;


print "TAP Version 13\n";
plan tests => 1;

# -------------------- path division --------------------

my $mason = new Artemis::Reports::DPath::Mason;
my $result;
my $template;
my $path;

# -----------------------------------------------------------------------------------------------------------------
construct_fixture( schema  => reportsdb_schema, fixture => 't/fixtures/reportsdb/report.yml' );
# -----------------------------------------------------------------------------------------------------------------

$mason->render(file     => "SOME_FILE");
$mason->render(template => "SOME_TEMPLATE");
ok(1);
