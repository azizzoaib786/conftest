#!/usr/bin/env bash

set -euf -o pipefail

export DIR="conftest-policy-as-code"
export COMMIT_ID=$(git rev-parse HEAD)
export POLICY_TYPE="terraform"
export POLICY_DIR="$DIR/$POLICY_TYPE"

[ ! -d "$DIR" ] && git clone $github_org/$DIR

export POLICY_RESULT=""

policy_dir_exist() {
  if [ ! -e "$POLICY_DIR" ]; then
      echo "No OPA files (*.rego) present, skipping OPA check!"
      exit 0;
  fi
}

eval_policy_name() {
  for policy in $POLICY_DIR; do
    policy_name=$(basename $policy)
    echo "evaluating $policy_name"
    update_github_status "pending" $policy_name
  done
}

run_policy_check() {
  if POLICY_RESULT=$(conftest test --update $github_conftest_policies_repo --no-color -p $POLICY_DIR $PLANFILE.json)
  then
      state="success"
  else
      state="failure"
  fi
  POLICY_RESULT=$(echo $POLICY_RESULT | sed -e 's/\\"/'\''/g')
  echo $POLICY_RESULT > /dev/null 2>&1 >/proc/1/fd/1
  update_github_status $state $POLICY_TYPE
  update_github_comment $POLICY_TYPE $POLICY_RESULT
}

update_github_status() {
  curl --header "Authorization: token $ATLANTIS_GH_TOKEN" \
      --header "Content-Type: application/json" \
      --data \
      '{"state": "'$1'", "context": "'open-policy-agent/$2'", "description": "'"Conftest Policy Check for PR#$PULL_NUM"'"}' \
      --request POST \
      "https://api.github.com/repos/$BASE_REPO_OWNER/$BASE_REPO_NAME/statuses/$COMMIT_ID" \
      > /dev/null 2>&1 >/proc/1/fd/1
}

update_github_comment() {
  POLICY_RESULT=$(echo ${POLICY_RESULT//$'"'/'*'})
  curl -H "Authorization: token $ATLANTIS_GH_TOKEN" \
       -H "Accept: application/vnd.github.v3+json" \
       -d \
       '{"body": "'"${POLICY_RESULT//$'FAIL'/'\n FAIL'}"'"}' \
       -X POST \
       "https://api.github.com/repos/$BASE_REPO_OWNER/$BASE_REPO_NAME/issues/$PULL_NUM/comments" \
       > /dev/null 2>&1 >/proc/1/fd/1
}

policy_dir_exist
eval_policy_name
run_policy_check
