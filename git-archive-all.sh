#!/bin/bash -
#
# File:        git-archive-all.sh
#
# Description: A utility script that builds a single tarfile of all
#              git repositories and submodules in the current path.
#              Useful for creating a single tarfile of a git super-
#              project that contains other submodules.
#
# Examples:    Use git-archive-all.sh to create tarfile distributions
#              from git archives. To use, simply do:
#
#                  cd $GIT_DIR; git-archive-all.sh
#
#              where $GIT_DIR is the root of your git superproject.

# DEBUGGING
set -e
set -C # noclobber

# TRAP SIGNALS
trap 'cleanup' QUIT EXIT

# For security reasons, explicitly set the internal field separator
# to newline, space, tab
OLD_IFS=$IFS
IFS='
 	'

function cleanup () {
    if [ $FORMAT == 'zip' ]; then
        while read dir_to_clean; do
            if [ -e "$dir_to_clean" ]; then
                rmdir "$dir_to_clean"
            fi
        done < $TOCLEANFILE
    fi
    rm -f $TOCLEANFILE
    rm -f $TMPFILE
    rm -f $TOARCHIVE
    IFS="$OLD_IFS"
}

function usage () {
    echo "Usage is as follows:"
    echo
    echo "$PROGRAM <--version>"
    echo "    Prints the program version number on a line by itself and exits."
    echo
    echo "$PROGRAM [--format <fmt>] [--prefix <path>] [--separate|-s] [output_file]"
    echo "    Creates an archive for the entire git superproject, and its submodules"
    echo "    using the passed parameters, described below."
    echo
    echo "    If '--format' is specified, the archive is created with the named"
    echo "    git archiver backend. Obviously, this must be a backend that git-archive"
    echo "    understands. The format defaults to 'tar' if not specified."
    echo
    echo "    If '--prefix' is specified, the archive's superproject and all submodules"
    echo "    are created with the <path> prefix named. The default is to not use one."
    echo
    echo "    If '--separate' or '-s' is specified, individual archives will be created"
    echo "    for each of the superproject itself and its submodules. The default is to"
    echo "    concatenate individual archives into one larger archive."
    echo
    echo "    If 'output_file' is specified, the resulting archive is created as the"
    echo "    file named. This parameter is essentially a path that must be writeable."
    echo "    When combined with '--separate' ('-s') this path must refer to a directory."
    echo "    Without this parameter or when combined with '--separate' the resulting"
    echo "    archive(s) are named with the basename of the archived directory and a"
    echo "    file extension equal to their format (for instance, 'superproject.tar')."
}

function version () {
    echo "$PROGRAM version $VERSION"
}

# Internal variables and initializations.
readonly PROGRAM=`basename "$0"`
readonly PROGRAM_INVOCATION="$0" # for recursion in case $PROGRAM is not in $PATH
readonly VERSION=0.1.1

OLD_PWD="`pwd`"
TMPDIR=${TMPDIR:-/tmp}
TMPFILE=`mktemp $TMPDIR/$PROGRAM.XXXXXX` # Create a place to store our work's progress
TOCLEANFILE=`mktemp $TMPDIR/$PROGRAM.to_clean.XXXXXX` # Create a place to store what we need to clean
OUT_FILE=$OLD_PWD # assume "this directory" without a name change by default
SEPARATE=0

FORMAT=tar
PREFIX=
TREEISH=HEAD

# RETURN VALUES/EXIT STATUS CODES
readonly E_BAD_OPTION=254
readonly E_UNKNOWN=255

# Process command-line arguments.
while test $# -gt 0; do
    case $1 in
        --format )
            shift
            FORMAT="$1"
            shift
            ;;

        --prefix )
            shift
            PREFIX="$1"
            shift
            ;;

        --separate | -s )
            shift
            SEPARATE=1
            ;;

        --version )
            version
            exit
            ;;

        -* )
            echo "Unrecognized option: $1" >&2
            usage
            exit $E_BAD_OPTION
            ;;

        * )
            break
            ;;
    esac
done

if [ ! -z "$1" ]; then
    OUT_FILE="$1"
    shift
fi

# Validate parameters; error early, error often.
if [ $SEPARATE -eq 1 -a ! -d $OUT_FILE ]; then
    echo "When creating multiple archives, your destination must be a directory."
    echo "If it's not, you risk being surprised when your files are overwritten."
    exit
fi

# Create the superproject's git-archive
git-archive --format=$FORMAT --prefix="$PREFIX" $TREEISH > $TMPDIR/$(basename $(pwd)).$FORMAT
echo $TMPDIR/$(basename $(pwd)).$FORMAT >| $TMPFILE # clobber on purpose
superfile=`head -n 1 $TMPFILE`

# find all '.git' dirs, these show us the remaining to-be-archived dirs
TOARCHIVE=`mktemp "$TMPDIR/$PROGRAM.toarchive.XXXXXX"`
find . -name '.git' -type d -print | sed -e 's/^\.\///' -e 's/\.git$//' | grep -v '^$' >> $TOARCHIVE

while read path; do
    cd "$path"
    git-archive --format=$FORMAT --prefix="${PREFIX}$path" $TREEISH > "$TMPDIR"/"$(echo "$path" | sed -e 's/\//./g')"$FORMAT
    # we need to move the zip files around a bit so they will unzip cleanly
    if [ $FORMAT == 'zip' ]; then
        # delete the empty directory entry; zipped submodules won't unzip if we don't do this
        zip -d "$(tail -n 1 $TMPFILE)" "${PREFIX}${path%/}" >/dev/null # remove trailing '/'
    fi
    echo "$TMPDIR"/"$(echo "$path" | sed -e 's/\//./g')"$FORMAT >> $TMPFILE
    cd "$OLD_PWD"
done < $TOARCHIVE

# Concatenate archives into a super-archive.
if [ $SEPARATE -eq 0 ]; then
    if [ $FORMAT == 'tar' ]; then
        sed -e '1d' $TMPFILE | while read file; do
            tar --concatenate -f "$superfile" "$file" && rm -f "$file"
        done
    elif [ $FORMAT == 'zip' ]; then
        sed -e '1d' $TMPFILE | while read file; do
            # zip incorrectly stores the full path, so cd and then grow
            cd `dirname "$file"`
            zip -g "$superfile" `basename "$file"` && rm -f "$file"
        done
        cd "$OLD_PWD"
    fi

    echo "$superfile" >| $TMPFILE # clobber on purpose
fi

while read file; do
    mv "$file" "$OUT_FILE"
done < $TMPFILE
