#!/bin/bash

urlbase="https://github.com/downloads/mapbox/tilemill/TileMill-==TAG==.zip"
changelogmd="../../CHANGELOG.md"
changeloghtml="./changelog.html"
changelogurl="http://tilemill.com/platforms/osx/changelog.html"
privatekeyname="TileMill Sparkle Private Key"
template="./appcast_template.xml"
appcast="./appcast.xml"

tag=$( git describe --tags --abbrev=0 )
version=$( echo $tag | sed -e s/^v// )
build=$( git rev-list $tag | grep -c ^ )
clear
echo
read -n 1 -p "Updating Sparkle for TileMill-$version ($build). Proceed? " proceed
if [ $proceed != "y" ] && [ $proceed != "Y" ]; then
  clear
  exit 1
fi
echo
echo

if [ -f $appcast -o -f $changeloghtml ]; then
  echo "Resetting $appcast and $changeloghtml to latest from repository."
  git checkout $appcast
  git checkout $changeloghtml
  echo
fi

grep $version $changelogmd > /dev/null
if [ $? != 0 ]; then
  echo "Unable to find entry for $version in $changelogmd. Aborting."
  exit 1
else
  echo -n "Found entry for $version in $changelogmd. Rendering to $changeloghtml... "
  node -e 'var fs = require("fs");
           var md = require("node-markdown").Markdown;
           fs.readFile("'$changelogmd'", "utf8", function (err, file) {
               console.log(md(file));
           });' | sed 1d > $changeloghtml
  echo "done."
fi
echo

zipurl=$( echo $urlbase | sed -e s/==TAG==/$version/ )
echo -n "Downloading $zipurl... "
curl -L -s $zipurl > /tmp/TileMill-$version.zip
if [ $? != 0 ]; then
  echo "Unable to download $zipurl. Aborting."
  exit 1
fi
echo "done."
echo

zipfile="/tmp/TileMill-$version.zip"
if [ ! -f $zipfile ]; then
  echo "Unable to stat downloaded $zipfile. Aborting."
  exit 1
fi
zipsize=$( stat -f %z $zipfile )
echo "Zip size is $zipsize bytes."
echo

timestamp=$( LC_TIME=en_US date +"%a, %d %b %G %T %z" )
echo "Timestamping appcast at $timestamp"
echo

echo -n "Generating DSA signature... "
privatekey=$( security find-generic-password -g -s "$privatekeyname" 2>&1 1>/dev/null | perl -pe '($_) = /"(.+)"/; s/\\012/\n/g' | perl -MXML::LibXML -e 'print XML::LibXML->new()->parse_file("-")->findvalue(q(//string[preceding-sibling::key[1] = "NOTE"]))' )
if [ -z "$privatekey" ]; then
  echo "Unable to find private key $privatekeyname in OS X keychain. Aborting."
  exit 1
fi
echo "$privatekey" > ./dsa_private.pem
signature=$( cat $zipfile | openssl dgst -sha1 -binary | openssl dgst -dss1 -sign ./dsa_private.pem | openssl enc -base64 )
rm -f ./dsa_private.pem
echo "done."
echo

echo -n "Outputting new appcast... "
if [ -f $appcast ]; then
  cat $appcast | grep -v "</channel>" | grep -v "</rss>" > $appcast.tmp && mv $appcast.tmp $appcast
else
  cat $template > $appcast
fi
echo "        <item>" >> $appcast
echo "            <title>TileMill $version</title>" >> $appcast
echo "            <sparkle:releaseNotesLink>$changelogurl</sparkle:releaseNotesLink>" >> $appcast
echo "            <pubDate>$timestamp</pubDate>" >> $appcast
echo "            <enclosure url=\"$zipurl\" sparkle:version=\"$build\" sparkle:shortVersionString=\"$version\" length=\"$zipsize\" type=\"application/octet-stream\" sparkle:dsaSignature=\"$signature\"/>" >> $appcast
echo "        </item>" >> $appcast
echo "    </channel>" >> $appcast
echo "</rss>" >> $appcast
echo "done."
echo

echo "Local appcast updated for TileMill $version ($build). Now do the following:"
echo
echo " 1. \`git add $appcast $changeloghtml\`"
echo " 2. \`git commit\`"
echo " 3. Merge & push to \`gh-pages\` branch."
echo
