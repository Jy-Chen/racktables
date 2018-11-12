#!/bin/sh

THISDIR=`dirname $0`
BASEDIR=`readlink -f "$THISDIR/.."`
: ${PHPUNIT_BIN:=phpunit}

case `"$PHPUNIT_BIN" --version` in
	'PHPUnit 4.'*|'PHPUnit 5.'*)
		BOOTSTRAP_FILE=bootstrap_v4v5.php
		;;
	'PHPUnit 6.'*|'PHPUnit 7.'*)
		BOOTSTRAP_FILE=bootstrap_v6v7.php
		;;
	*)
		echo 'ERROR: failed to find a known version of PHPUnit'
		"$PHPUNIT_BIN" --version
		exit 5
esac

echo "Running express tests using the base directory '$BASEDIR'"
echo "and PHPUnit bootstrap file '$BOOTSTRAP_FILE'."

testPHPSyntaxOnly()
{
	local FORMAT="${1:?}"
	local INPUT="${2:?}"

	if php --syntax-check "$INPUT" >/dev/null 2>&1; then
		printf "$FORMAT" "$INPUT" 'OK (syntax only)'
		return 0
	else
		printf "$FORMAT" "$INPUT" "ERROR: PHP syntax check failed"
		return 1
	fi
}

testPHPExitCodeAndOutput()
{
	local FORMAT="${1:?}"
	local INPUT="${2:?}"
	local TEMPFILE="${3:?}"
	local fname rc curdir

	fname=`basename "$INPUT"`
	curdir=`pwd`
	cd `dirname "$INPUT"`
	php "$fname" > "$TEMPFILE"
	rc=$?
	cd "$curdir"
	if [ $rc -eq 0 -a ! -s "$TEMPFILE" ]; then
		printf "$FORMAT" "$INPUT" 'OK'
		return 0
	else
		[ $rc -ne 0 ] && printf "$FORMAT" "$INPUT" "ERROR: PHP interpreter returned code $rc"
		[ -s "$TEMPFILE" ] && printf "$FORMAT" "$f" 'ERROR: produces output when parsed'
		return 1
	fi
}

# Every file in wwwroot/inc/ must be a valid PHP input file and must not
# produce any output when parsed by PHP (because, for instance, a plain text
# file is a valid PHP input file).
echo
cd "$BASEDIR"
files=0
errors=0
TEMPFILE=`mktemp /tmp/racktables_unittest.XXXXXX`
FORMAT='%-50s : %s\n'
for f in wwwroot/inc/*.php plugins/*/plugin.php; do
	if [ "$f" = "wwwroot/inc/init.php" ]; then
		testPHPSyntaxOnly "$FORMAT" "$f" || errors=`expr $errors + 1`
	else
		testPHPExitCodeAndOutput "$FORMAT" "$f" "$TEMPFILE" || errors=`expr $errors + 1`
	fi
	files=`expr $files + 1`
done
for f in tests/*.php; do
	[ -h "$f" ] && continue
	testPHPSyntaxOnly "$FORMAT" "$f" || errors=`expr $errors + 1`
	files=`expr $files + 1`
done
echo '---------------------------------------------------'
echo "Files parsed: $files, failed: $errors"
rm -f "$TEMPFILE"
[ $errors -eq 0 ] || exit 1

# The command-line scripts among other things prove that init.php actually works.
echo
cd "$BASEDIR/wwwroot"
echo 'Testing syncdomain.php'; ../scripts/syncdomain.php --help || exit 1
echo 'Testing cleanup_ldap_cache.php'; ../scripts/cleanup_ldap_cache.php || exit 1
echo 'Testing reload_dictionary.php'; ../scripts/reload_dictionary.php || exit 1

# At this point it makes sense to test specific functions.
echo
cd "$BASEDIR/tests"
"$PHPUNIT_BIN" --group small --bootstrap $BOOTSTRAP_FILE || exit 1
