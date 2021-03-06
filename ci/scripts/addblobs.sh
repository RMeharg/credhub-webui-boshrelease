#!/bin/bash
set -eu -o pipefail

header() {
	echo
	echo "###############################################"
	echo
	echo $*
	echo
}

echo "0+dev.1" > /tmp/version
if [[ -z ${VERSION_FROM} ]]; then
  VERSION_FROM=/tmp/version
fi
VERSION=$(cat ${VERSION_FROM})

cat > bosh-release/config/private.yml << EOF
---
blobstore:
  options:
    access_key_id: ${AWS_ACCESS_KEY}
    secret_access_key: ${AWS_SECRET_KEY}
    host: ${AWS_ENDPOINT}
EOF

pushd bosh-release
echo > config/blobs.yml
NEW_VERSION=credhub-webui-linux-$(cat ../credhub-webui-external/version).tar.gz
ls ../credhub-webui-external/
bosh add-blob ../credhub-webui-external/$NEW_VERSION credhub-webui/$NEW_VERSION
repo_changes=0; git status | grep -q "Changes not staged for commit" && repo_changes=1
if [ $repo_changes == 1 ]
then
  git config --global user.name "BaconBot"
  git config --global user.email "bacon@bot.local"
  git commit -am "Bump version(s) for $NEW_VERSION"
fi

export BOSH_CA_CERT=${BOSH_CA_CERT}
export BOSH_CLIENT=${BOSH_USERNAME}
export BOSH_CLIENT_SECRET=${BOSH_PASSWORD}

cat > ../releases.yml << EOF
---
- type: replace
  path: /releases
  value:
    - name: credhub-webui
      version: $VERSION
EOF

bosh create-release --force --version=$VERSION
bosh -n -e ${BOSH_TARGET} upload-release || echo "Continuing..."

# delete any failed previous tests
bosh -n -e ${BOSH_TARGET} -d ${BOSH_DEPLOYMENT} deld --force || echo "continuing on..."

bosh -n -e ${BOSH_TARGET} -d ${BOSH_DEPLOYMENT} d ./manifests/deployment.yml \
  -o ../releases.yml \
  -v credhub_webui_hostname=credhubwebui.local \
  -v credhub_client_id=credhub-admin \
  -v credhub_client_secret=${CREDHUB_ADMIN_SECRET} \
  -v credhub_server=https://${BOSH_TARGET}:8844

if [[ -n ${TEST_ERRAND} ]]; then
  header "Running '${TEST_ERRAND}' validation errand"
  bosh -n -e ${BOSH_TARGET} -d ${BOSH_DEPLOYMENT} run-errand ${TEST_ERRAND}
fi

header "Cleaning up..."
bosh -n -e ${BOSH_TARGET} -d ${BOSH_DEPLOYMENT} deld --force || echo "continuing on..."
bosh -n -e ${BOSH_TARGET} clean-up --client=${BOSH_USERNAME} || echo "continuing on..."

## Delete the release afterwards
bosh -n -e ${BOSH_TARGET} delete-release credhub-webui/$VERSION
popd

cp -a bosh-release pushgit

echo "finished uploading a new source blob"
exit 0
