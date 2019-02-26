#!/bin/bash
# This script only runs on circleci, just before the tests

if [ "$NODE_ENV" = "circleci" ]; then
  echo "Performing circleci e2e setup because NODE_ENV is '${NODE_ENV}'";
else
  echo "Skipping circleci e2e setup because NODE_ENV is '${NODE_ENV}'";
  exit;
fi

mkdir -p ~/cache
cd ~/cache

API_TARBALL_URL="https://codeload.github.com/opencollective/opencollective-api/tar.gz/";
if curl -s --head  --request GET "${API_TARBALL_URL}${CIRCLE_BRANCH}" | grep "200" > /dev/null
then
  BRANCH=$CIRCLE_BRANCH;
else
  BRANCH="master";
fi

# If we already have an archive of the branch locally (in ~/cache)
# Then we check to see if the size matches the online version
# If they do, we proceed to start the api server
# Otherwise we remove the local cache and install latest version of the branch

TARBALL_SIZE=$(curl -s --head  --request GET "${API_TARBALL_URL}${BRANCH}" | grep "Content-Length" | sed -E "s/.*: *([0-9]+).*/\1/")

if [ ! $TARBALL_SIZE ]; then
  # First request doesn't always provide the content length for some reason (it's probably added by their caching layer)
  TARBALL_SIZE=$(curl -s --head  --request GET "${API_TARBALL_URL}${BRANCH}" | grep "Content-Length" | sed -E "s/.*: *([0-9]+).*/\1/")
fi

if [ -e "${BRANCH}.tgz" ];
then
  LSIZE=$(wc -c ${BRANCH}.tgz | sed -E "s/ ?([0-9]+).*/\1/")
  test $TARBALL_SIZE = $LSIZE && echo "Size matches $BRANCH.tgz (${TARBALL_SIZE}:${LSIZE})" || (echo "> Removing old ${BRANCH}.tgz (size doesn't match: ${TARBALL_SIZE}:${LSIZE})"; rm "${BRANCH}.tgz"; echo "File removed";)
fi

if [ ! -e "${BRANCH}.tgz" ];
then
  echo "> Downloading tarball ${API_TARBALL_URL}${BRANCH}"
  curl  "${API_TARBALL_URL}${BRANCH}" -o "${BRANCH}.tgz"
  echo "> Extracting ${BRANCH}.tgz"
  tar -xzf "${BRANCH}.tgz"
  if [ -d "opencollective-api" ]; then
    rm -rf opencollective-api
  fi
  mv "opencollective-api-${BRANCH//\//-}" opencollective-api
  cd "opencollective-api"
  echo "> Running npm install for api"
  npm install
 echo "> Running build for api"
  npm run build
  cd ..
fi

cd "opencollective-api"
echo "> Restoring opencollective_dvl database for e2e testing";
export PGPORT=5432
export PGHOST=localhost
export PGUSER=ubuntu
npm run db:setup
./scripts/db_restore.sh -U ubuntu -d opencollective_dvl -f test/dbdumps/opencollective_dvl.pgsql
export PG_USERNAME=ubuntu
./scripts/sequelize.sh db:migrate
if [ $? -ne 0 ]; then
  echo "Error with restoring opencollective_dvl, exiting"
  exit 1;
else
  echo "✓ API is setup";
fi
