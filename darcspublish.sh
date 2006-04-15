#!/bin/sh

if [ ! -d _darcs ]; then
  echo "not a darcs working directory!" > /dev/stderr
  exit 1
fi

unset SERVER USER DIR BASEDIR PASSWORD

for config in _darcs/prefs/ftpdata $HOME/.darcspublish; do
  if [ -r $config ]; then
    . $config
  fi
done

if [ "x$SERVER" = "x" -o "x$USER" = "x" -o\
     "x$BASEDIR" = "x" -a "x$DIR" = "x" ]; then
  echo "*** config not found." > /dev/stderr
  exit 1
fi  

TMPDIR=`mktemp -d -t publish` || exit 1
PROJECT=`pwd | xargs basename`

#echo $PROJECT

darcs put $TMPDIR/darcscopy

# hmm
#cp _darcs/prefs/author $TMPDIR/darcscopy/_darcs/prefs

touch $TMPDIR/rc
chmod 0600 $TMPDIR/rc
echo "site darcspublish" >> $TMPDIR/rc
echo "  server $SERVER" >> $TMPDIR/rc
echo "  username $USER" >> $TMPDIR/rc
if [ "x$PASSWORD" != "x" ]; then
  echo "  password $PASSWORD" >> $TMPDIR/rc
fi
if [ "x$DIR" != "x" ]; then
  echo "  remote $DIR" >> $TMPDIR/rc
else
  echo "  remote $BASEDIR/$PROJECT" >> $TMPDIR/rc
fi
echo "  local $TMPDIR/darcscopy" >> $TMPDIR/rc
echo "  protocol ftp" >> $TMPDIR/rc
echo "  state checksum" >> $TMPDIR/rc
echo "  permissions all" >> $TMPDIR/rc
echo "  symlinks ignore" >> $TMPDIR/rc

if [ ! -r _darcs/sitecopystate/darcspublish ]; then
  echo "*** publishing from here for the first time...."
  mkdir _darcs/sitecopystate
  chmod 0700 _darcs/sitecopystate
  sitecopy -r $TMPDIR/rc -p _darcs/sitecopystate -i darcspublish
  sitecopy -r $TMPDIR/rc -p _darcs/sitecopystate -f darcspublish
fi

sitecopy -r $TMPDIR/rc -p _darcs/sitecopystate -u darcspublish
rm -rf $TMPDIR
