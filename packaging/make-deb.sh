#!/bin/sh
# make-deb.sh - builds meeships-n9_<VER>_armel.deb from build/meeships-n9 + qml/ + packaging/
set -e
D=$(cd "$(dirname "$0")/.." && pwd)
VER=${VER:-0.1.2}
OUTDIR=${OUTDIR:-$D/dist}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
P=$T/data; mkdir -p $P/opt/meeships-n9/bin $P/opt/meeships-n9/qml $P/usr/share/applications $P/usr/share/icons/hicolor/80x80/apps $P/usr/share/doc/meeships-n9 $T/ctl
install -m 755 $D/build/meeships-n9 $P/opt/meeships-n9/bin/
install -m 644 $D/qml/*.qml $D/qml/*.js $D/qml/*.png $P/opt/meeships-n9/qml/
mkdir -p $P/opt/meeships-n9/qml/fonts
install -m 644 $D/qml/fonts/* $P/opt/meeships-n9/qml/fonts/
mkdir -p $P/opt/meeships-n9/qml/sounds
install -m 644 $D/qml/sounds/*.wav $P/opt/meeships-n9/qml/sounds/
install -m 644 $D/packaging/meeships-n9.desktop $P/usr/share/applications/
install -m 644 $D/qml/meeships80.png $P/usr/share/icons/hicolor/80x80/apps/
install -m 644 $D/LICENSE $P/usr/share/doc/meeships-n9/copyright
SIZE=$(du -sk $P | cut -f1)
cat > $T/ctl/control <<CTL
Package: meeships-n9
Version: $VER
Architecture: armel
Maintainer: smyhu <smyhu@users.noreply.github.com>
Installed-Size: $SIZE
Depends: libc6 (>= 2.10), libqtcore4 (>= 4.7.4~), libqtgui4 (>= 4.7.4~), libqt4-declarative (>= 4.7.4~), libqt4-network (>= 4.7.4~), libqtm-systeminfo (>= 1.2.1), libqtm-multimedia (>= 1.2.1), qt-components (>= 1.0)
Section: user/games
Priority: optional
Description: Battleships in raw 8-bit style
 Battleships for the Nokia N9: place your fleet (one ship of four squares,
 two of three, three of two, four of one; ships never touch) and sink the
 enemy fleet. Play against the computer (easy, normal, hard) or against a
 friend on another N9 over Wi-Fi: phones find each other automatically.
 Simple 8-bit sounds (can be switched off). Languages: en, pl.
 Designed and written by Claude (Anthropic) together with smyhu for the Nokia N9.
Maemo-Display-Name: MeeShips
Maemo-Flags: visible
CTL
printf 'Maemo-Icon-26: %s\n' "$(base64 -w0 $D/qml/meeships80.png)" >> $T/ctl/control
(cd $P && find . -type f | sed 's#^\./##' | sort | xargs md5sum) > $T/ctl/md5sums
wpis() { printf 'S 15 com.nokia.maemo H 40 %s R %d %s\n' "$1" "${#2}" "$2"; }
(cd $P && find . -type f | sed 's#^\./##' | grep -v '^usr/share/' | sort | while read -r f; do wpis "$(sha1sum "$f" | cut -d' ' -f1)" "$f"; done) > $T/ctl/digsigsums
(cd $T/ctl && tar czf ../control.tar.gz --owner=0 --group=0 --numeric-owner --format=gnu ./control ./md5sums ./digsigsums)
(cd $P && tar czf ../data.tar.gz --owner=0 --group=0 --numeric-owner --format=gnu .)
echo 2.0 > $T/debian-binary
mkdir -p $OUTDIR; DEB=$OUTDIR/meeships-n9_${VER}_armel.deb; rm -f $DEB
(cd $T && ar rc $DEB debian-binary control.tar.gz data.tar.gz)
md5sum $DEB
