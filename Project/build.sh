#!/bin/bash
DIR=`dirname "$0"`
DIR=`realpath "$DIR"`
NAME=`basename "$0" | sed 's/[.].*$//'`
OWNER=`ls -ld "$DIR" | awk '{print $3}'`
CDIR=`pwd`
export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
if [ -f "$DIR/pom.xml" ] ; then
  cd "$DIR"
else
  if [ ! -f "pom.xml" ] ; then
    echo "No build script found"
    exit 1
  fi
fi
if [ "$OWNER" != "$USER" ] ; then
  echo "This script must be run as $OWNER"
  exit 1
fi

INIT=`grep "^[#][[:space:]]*$DIR[/]*$" /etc/softco/maven* | head -n 1 | awk -F ':' '{print $1}'`
if [ -f "$INIT" ] ; then
  echo "Using maven settings in $INIT"
  . "$INIT"
else
  CFG=""
  TMP="$DIR"
  while [ -d "$TMP" -a "$TMP" != "/" -a -z "$CFG" ] ; do
    CFG="$TMP/.mavenrc"
    if [ -e "$CFG" ] ; then
      if [ ! -x "$CFG" ] ; then
        echo "$CFG is not executable"
        exit 1
      fi
      echo "Using maven settings in $CFG"
      . "$CFG"
    else
      CFG=""
    fi
    TMP=`dirname "$TMP"`
  done
  if [ -z "$CFG" ] ; then
    echo "Using maven defaults"
  fi
fi
if [ ! -z "$JAVA_HOME" ] ; then
  echo "Using java in $JAVA_HOME"
else
  echo "Using default java"
fi

function options {
  FILE="$1"
  shift
  DEFAULTS="$*"
  RESULT=""
  if [ -f "${FILE}" ] ; then
    RESULT=`cat "${FILE}" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | head -n 1`
  fi
  if [ -z "${RESULT}" ] ; then
    echo "${DEFAULTS}"
  else
    echo "${RESULT}"
  fi
}

OPTS=""
GOALS="compile package install"
REAL=`realpath "$DIR"`
#echo "Folder: $REAL"
#echo "Script: $NAME"
OPTS=`options "../defaults/${NAME}.opt" "$OPTS"`
OPTS=`options "${NAME}.opt" "$OPTS"`
GOALS=`options "../defaults/${NAME}.goal" "$GOALS"`
GOALS=`options "${NAME}.goal" "$GOALS"`

TESTS=0
NODEPS=0
REBUILD=0
READY=""
PARAM="$1"
while [ ! -z "$PARAM" ] ; do
  case "$PARAM" in
     --fast)
       NODEPS=1
       ;;
     --nodeps)
       NODEPS=1
       ;;
     --no-deps)
       NODEPS=1
       ;;
     --no-dependencies)
       NODEPS=1
       ;;
     --test)
       TESTS=1
       ;;
     --tests)
       TESTS=1
       ;;
     --with-tests)
       TESTS=1
       ;;
     --rebuild)
       REBUILD=1
       ;;
     -f)
       NODEPS=1
       ;;
     -n)
       NODEPS=1
       ;;
     -t)
       TESTS=1
       ;;
     -r)
       REBUILD=1
       ;;
     -D*)
       OPTS="$OPTS $PARAM"
       ;;
     -*)
       echo "Invalid option: $PARAM"
       exit 1
       ;;
     *)
       READY="$READY $PARAM"
  esac
  shift
  PARAM="$1"
done
 
if [ $TESTS -eq 0 ] ; then
  TMP=`echo "$OPTS" | grep "[-]DskipTests"`
  if [ -z "$TMP" ] ; then
    OPTS="$OPTS -DskipTests"
  fi
else
  OPTS=`echo "$OPTS" | sed 's/[-]DskipTests//'`
fi
if [ $REBUILD -eq 1 ] ; then
  OPTS="$OPTS -Dbuildnumber.phase=none"
fi

# ECHO

if [ -f "pom.xml" ] ; then
  ARTIFACT=`grep "[<]artifactId[>].*[<][/]artifactId[>]" pom.xml | head -n 1  | grep -o "[>].*[<][/]" | sed 's/[>]//' | sed 's/[<].*$//'`
  DEPS=`grep -A 2 "<dependency>" pom.xml | grep -A 1 "[<]groupId[>]za[.]co[.]softco[<][/]groupId[>]" | grep "[<]artifactId[>].*[<][/]artifactId[>]" | grep -o "[>].*[<][/]" | sed 's/[>]//' | sed 's/[<].*$//'`
  if [ $NODEPS -ne 0 ] ; then
    DEPS=""
  fi
  for DEP in $DEPS ; do
    SKIP=`echo "$READY" | grep -o "$DEP"`
    if [ -z "$SKIP" ] ; then
      if [ -f "../$DEP/build.sh" ] ; then
        #echo "Building dependency: $DEP"
        OUT=`"../$DEP/build.sh" "$READY"`
        echo "$OUT" | grep -v "^ARTIFACT[:]"
        DONE=`echo "$OUT" | grep '^ARTIFACT[:]' | awk '{print $2}'`
        for A in $DONE ; do
          READY="$READY $A"
        done
        #echo "READY: $READY"
      fi
    #else
      #echo "Skipping dependency: $DEP"
    fi
  done
  if [ -z "$OPTS" ] ; then
    OPTS="-o -U -q -DskipTests"
  fi
  
  JAVAFILE=`find src/main/java/ | grep '[.]java$' | head -n 1`
  if [ ! -z "$JAVAFILE" ] ; then
    echo "Touching $JAVAFILE ..."
    touch "$JAVAFILE"
  fi

  #echo ""
  echo "Building $ARTIFACT ( $REAL ) with Maven..."
  #echo "mvn ${GOALS} ${OPTS}"
  mvn ${GOALS} ${OPTS}
  RESULT=$?
  if [ $RESULT -eq 0 ] ; then
    READY="$READY $ARTIFACT"
    echo "ARTIFACT: $ARTIFACT"
  fi
  exit $RESULT
fi
if [ -f "build.xml" ] ; then
  echo "Building $REAL with Ant..."
  ant ${OPTS}
  exit $?
fi 
echo "No build script found"
exit 1
