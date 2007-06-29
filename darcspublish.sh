#!/bin/sh

PROFILES=""

if [ ! -d _darcs ]; then
  echo "not a darcs working directory!" > /dev/stderr
  exit 1
fi

if [ $# -eq 0 ]; then
  for PROFILE in _darcs/prefs/darcspublish.*; do
    if [ -r $PROFILE ]; then
      PROFILE=`echo $PROFILE | sed -e 's/^.*darcspublish\.//'`
      PROFILES="$PROFILES$PROFILE "
    fi
  done
else
  PROFILES=$@
fi

PROFILECOUNT=0
if [ "x$PROFILES" != "x" ]; then
  for i in $PROFILES; do
    PROFILECOUNT=`expr $PROFILECOUNT + 1`
  done
fi

if [ $PROFILECOUNT -gt 1 ]; then
  for i in $PROFILES; do
    $0 $i
  done
  exit 0
fi

if [ $PROFILECOUNT -eq 1 ]; then
  PROFILE=$PROFILES
  PROFILECFG=_darcs/prefs/darcspublish.$PROFILE
  if [ ! -r $PROFILECFG ]; then
    echo "*** Profile '$PROFILE' not found." > /dev/stderr
    exit 1
  else
    echo "*** Using profile '$PROFILE'."
  fi
else
  PROFILE=
  PROFILECFG=
fi

unset SERVER USER DIR BASEDIR PASSWORD EXCLUDEPRISTINE PRISTINE EXCLUDE CAREFUL UPLOADSTATE

for config in $HOME/.darcspublish _darcs/prefs/ftpdata _darcs/prefs/darcspublish $PROFILECFG; do
  if [ -r $config ]; then
    . $config
  fi
done

if [ "x$UPLOADSTATE" != "x" -a "x$PASSWORD" != "x" ]; then
  echo "*** UPLOADSTATE currently only works if PASSWORD is specified in ~/.netrc" > /dev/stderr
  exit 1
fi

if [ "x$SERVER" = "x" -o "x$USER" = "x" -o\
     "x$BASEDIR" = "x" -a "x$DIR" = "x" ]; then
  echo "*** config not found." > /dev/stderr
  exit 1
fi

if [ "x$DIR" != "x" ]; then
  REMOTEDIR="$DIR"
else
  REMOTEDIR="$BASEDIR/$PROJECT"
fi

TMPDIR=`mktemp -d -t publish.XXXXXXXX` || exit 1
if [ "x$PRISTINE" = "x" ]; then
  if [ "x$EXCLUDEPRISTINE" != "x" ]; then
    PRISARG="--no-pristine-tree"
  else
    PRISARG=""
  fi
  echo -n "*** Creating clean working copy: "
  darcs put $PRISARG $TMPDIR/darcscopy >/dev/null && echo "ok." || exit 1
  if [ -r _darcs/prefs/email ]; then
    cp _darcs/prefs/email $TMPDIR/darcscopy/_darcs/prefs
  fi
fi
PROJECT=`pwd | xargs basename`


touch $TMPDIR/rc
chmod 0600 $TMPDIR/rc
echo "site darcspublish" >> $TMPDIR/rc
echo "  server $SERVER" >> $TMPDIR/rc
echo "  username $USER" >> $TMPDIR/rc
if [ "x$PASSWORD" != "x" ]; then
  echo "  password $PASSWORD" >> $TMPDIR/rc
fi
echo "  remote $REMOTEDIR" >> $TMPDIR/rc
if [ "x$PRISTINE" = "x" ]; then
  echo "  local $TMPDIR/darcscopy" >> $TMPDIR/rc
else
  echo "  local `pwd`/_darcs/pristine" >> $TMPDIR/rc
fi
echo "  protocol ftp" >> $TMPDIR/rc
echo "  state checksum" >> $TMPDIR/rc
echo "  permissions all" >> $TMPDIR/rc
echo "  symlinks ignore" >> $TMPDIR/rc
if [ "x$EXCLUDE" != "x" ]; then
  for i in $EXCLUDE; do
    echo "  exclude $i" >> $TMPDIR/rc
  done
fi

if [ ! -d _darcs/sitecopystate ]; then
  mkdir _darcs/sitecopystate
fi
chmod 0700 _darcs/sitecopystate

if [ "x$UPLOADSTATE" != "x" ]; then
  TMPSTATE=`mktemp` || exit 1
  echo -n "*** Looking for state file: "
  if `echo get $REMOTEDIR/.darcspublishstate $TMPSTATE | ftp -p $SERVER 2>&1 > /dev/null`; then
    mv $TMPSTATE _darcs/sitecopystate/darcspublish
    echo "found."
  else
    echo "not found."
  fi
  rm -f $TMPSTATE
fi

if [ ! -r _darcs/sitecopystate/darcspublish ]; then
  echo "*** publishing from here for the first time...."
  sitecopy -r $TMPDIR/rc -p _darcs/sitecopystate -i darcspublish
  sitecopy -r $TMPDIR/rc -p _darcs/sitecopystate -f darcspublish
fi

if [ "x$CAREFUL" != "x" ]; then
  sitecopy -r $TMPDIR/rc -p _darcs/sitecopystate -l darcspublish
  echo "press CTRL-C to cancel or ENTER to continue...."
  read bla
fi
sitecopy -r $TMPDIR/rc -p _darcs/sitecopystate -u darcspublish

if [ "x$UPLOADSTATE" != "x" ]; then
  echo -n "*** Uploading state file: "
  if `echo put _darcs/sitecopystate/darcspublish $REMOTEDIR/.darcspublishstate | ftp -p $SERVER 2>&1 > /dev/null`; then
    echo "success."
  else
    echo "error."
  fi
fi

rm -rf $TMPDIR
