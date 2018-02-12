# cp-jenkins

Repo for building a Jenkins container that works with our infra.

To build:

```
$ make build
```

To launch locally, once built:

```
$ JENKINS_HOME_MOUNT_DIR=~/jenkins_home make run # make sure this dir existS
```

Then go to `http://localhost:8080` in your browser.

If you don't care about persisting that data then you can use the following,
which uses a new `/tmp` directory each time.

```
$ make test-run
```

## local workflow

1. `make run`
  1. this mounts the `JENKINS_TESTING_REPO_MOUNT_DIR` to `/mnt/test-repo`
1. log in at http://localhost:8080
1. in security: disable script approval
1. in security: allow anyone to do anything (TODO: restrict this)
1. create a new pipeline job (or whatever you're testing)
  1. set the path to `file:///mnt/test-repo` (or a subdirectory thereof)
  1. disable shallow checkout
  1. set to build on all branches
1. trigger a build of the new job

In the repo under test:

1. `git branch jenkinsfile && git checkout jenkinsfile`
1. Update the repos, then
  1. `git add . && git commit -m "Auto commit $(date)"`

Optionally, trigger Jenkins via its API (you may need to retrieve your API token):

```bash
jenkins-trigger ()
{
    local JOB_NAME="${1:-maintenance-apply-dsl}";
    local USER='sublimino';
    local TOKEN="${LOCAL_JENKINS_TOKEN:-cbc47c7c3ee08ac33bdb8176a925ca7b}";
    local LAST_JOB_JSON=$(curl --silent http://${USER}:${TOKEN}@localhost:8080/job/${JOB_NAME}/lastBuild/api/json);
    local LAST_JOB=$(echo "${LAST_JOB_JSON}" | jq -r '"\(.id) \(.result) \(.url)"');
    if [[ "${LAST_JOB:-}" == "" ]]; then
        return 1;
    fi;
    local LAST_JOB_PARAMS=$(echo "${LAST_JOB_JSON}" \
      | jq -r '.actions? []? | select(."_class" == "hudson.model.ParametersAction") | .parameters? | .[] | "\(.name)=\(.value)"' \
      | tr '\n' '&' \
      | sed -E 's/(.*).$/\1/g');
    local BUILD_COMMAND='build';
    if [[ "${LAST_JOB_PARAMS:-}" != "" ]]; then
        BUILD_COMMAND="buildWithParameters?${LAST_JOB_PARAMS}";
    fi;
    curl -A --connect-timeout 5 -XPOST --silent "http://${USER}:${TOKEN}@localhost:8080/job/${JOB_NAME}/${BUILD_COMMAND}";
    printf "${JOB_NAME} triggered";
    local THIS_JOB=$(curl --silent http://${USER}:${TOKEN}@localhost:8080/job/${JOB_NAME}/lastBuild/api/json | jq -r '"\(.id) \(.result) \(.url)"');
    while [[ $(echo "${LAST_JOB}" | awk '{print $1}') == $(echo "${THIS_JOB}" | awk '{print $1}') ]]; do
        THIS_JOB=$(curl --silent http://${USER}:${TOKEN}@localhost:8080/job/${JOB_NAME}/lastBuild/api/json | jq -r '"\(.id) \(.result) \(.url)"');
        printf .;
        sleep 1;
    done;
    while [[ $(curl --silent http://${USER}:${TOKEN}@localhost:8080/job/${JOB_NAME}/lastBuild/api/json | jq -r '"\(.result)"') = 'null' ]]; do
        printf .;
        sleep 1;
    done;
    THIS_JOB=$(curl --silent http://${USER}:${TOKEN}@localhost:8080/job/${JOB_NAME}/lastBuild/api/json | jq -r '"\(.id) \(.result) \(.url)"');
    echo;
    echo "${THIS_JOB}console" | sed -E 's#(.*//)[0-9]+[^:/]*#\1localhost#' | highlight --stdlib;
    curl --connect-timeout 5 --silent http://${USER}:${TOKEN}@localhost:8080/job/${JOB_NAME}/lastBuild/consoleText | highlight
}

```

When work on the branch is complete:

```bash
git reset --soft $(git merge-base --fork-point master) && git add . && git commit
```

