#! /bin/bash

EXECDIR=$(dirname $0)
DISTFILES='Artemis*-*.*.tar.gz '
$EXECDIR/../../Artemis/scripts/artemis_version_increment.pl $EXECDIR/../lib/Artemis/Reports/DPath.pm
cd $EXECDIR/..

if [[ -e MANIFEST ]]
then
  rm MANIFEST
fi

perl Makefile.PL || exit -1
make manifest || exit -1
make dist || exit -1

# -----------------------------------------------------------------
# It is important to not overwrite existing files.
# -----------------------------------------------------------------
# That guarantees that the version number is incremented so that we
# can be sure about version vs. functionality.
# -----------------------------------------------------------------

echo ""
echo '----- upload ---------------------------------------------------'
rsync -vv --progress --ignore-existing ${DISTFILES} artemis@wotan:/home/artemis/CPANSITE/CPAN/authors/id/A/AR/ARTEMIS/

echo ""
echo '----- re-index -------------------------------------------------'
ssh artemis@wotan /home/artemis/perl510/bin/cpansite -v --site=/home/artemis/CPANSITE/CPAN/ --cpan=ftp://ftp.fu-berlin.de/unix/languages/perl/ index
ssh artemis@wotan /home/artemis/perl510/bin/cpan Artemis::Reports::DPath
