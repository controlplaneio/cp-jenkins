# ControlPlane: Jenkins

## Quickstart

Repo for building a Jenkins container that works with our infra.

To build:

```
$ make build
```

Before you can run it you should do a `git-crypt unlock` as there is an encrypted secret.

To launch locally, once built:

```
$ JENKINS_HOME_MOUNT_DIR=${HOME}/jenkins_home make run
```

Make sure `JENKINS_HOME_MOUNT_DIR` exists, and is an absolute path. If you don't
specify it, it will default to `/mnt/jenkins_home`.

Then go to `http://localhost:8080` in your browser.

If you don't care about persisting that data then you can use the following,
which uses a new `/tmp/foo` directory each time.

```
$ make test-run
```

## Configuration

1. Jenkins requires a manual `ssh git@github.com` from the command line to accept `github.com`'s public key
    ```bash
    docker exec -it CONTAINER_ID bash -c 'mkdir -p ~/.ssh && ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts'
    ```
   (Successful output looks something like `# github.com:22 SSH-2.0-libssh_0.7.0`, and there is a github.com entry in `/root/.ssh/known_hosts`)
1. Credentials need to be added to clone repositories
1. In-process script approval is required to allow the initial DSL scripts

## Local Workflow

To iterate quickly on a Jenkinsfile without having to commit to a remote repostiory, a local directory can be mounted into the Jenkins container.

1. `make run`
    1. this mounts the `JENKINS_TESTING_REPO_MOUNT_DIR` to `/mnt/test-repo`
1. log in at [http://localhost:8080](http://localhost:8080)
1. in security: disable script approval
1. in security: allow anyone to do anything (this replaces the GitHub auth strategy - ONLY USE LOCALLY)
1. create a new pipeline job (or whatever you're testing)
    1. set the path to `file:///mnt/test-repo` (or a subdirectory thereof)
    1. disable shallow checkout
    1. set to build on all branches
1. trigger a build of the new job

In the repo under test:

1. `git branch jenkinsfile && git checkout jenkinsfile`
1. Update the repos, then
1. `git add . && git commit -m "Auto commit $(date)"`

## Trigger Build via API

Optionally, trigger Jenkins via its API (you may need to retrieve your API token):

```bash
jenkins-trigger ()
{
    local JOB_NAME="${1:-maintenance-apply-dsl}";
    local USER='sublimino';
    local TOKEN="${LOCAL_JENKINS_TOKEN:-}";
    local LAST_JOB_JSON=$(curl --silent http://${USER}:${TOKEN}@localhost:8080/job/${JOB_NAME}/lastBuild/api/json);
    local LAST_JOB=$(echo "${LAST_JOB_JSON}" \
      | jq -r '"\(.id) \(.result) \(.url)"');

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

    curl -A --connect-timeout 5 -XPOST --silent \
      "http://${USER}:${TOKEN}@localhost:8080/job/${JOB_NAME}/${BUILD_COMMAND}";
    printf "${JOB_NAME} triggered";

    local THIS_JOB=$(curl --silent http://${USER}:${TOKEN}@localhost:8080/job/${JOB_NAME}/lastBuild/api/json | jq -r '"\(.id) \(.result) \(.url)"');

    while [[ $(echo "${LAST_JOB}" | awk '{print $1}') == $(echo "${THIS_JOB}" | awk '{print $1}') ]]; do
        THIS_JOB=$(curl --silent http://${USER}:${TOKEN}@localhost:8080/job/${JOB_NAME}/lastBuild/api/json | jq -r '"\(.id) \(.result) \(.url)"');
        printf .;
        sleep 1;
    done;

    while [[ $(curl --silent \
      http://${USER}:${TOKEN}@localhost:8080/job/${JOB_NAME}/lastBuild/api/json \
        | jq -r '"\(.result)"') = 'null' ]]; do
        printf .;
        sleep 1;
    done;

    THIS_JOB=$(curl --silent \
      http://${USER}:${TOKEN}@localhost:8080/job/${JOB_NAME}/lastBuild/api/json \
      | jq -r '"\(.id) \(.result) \(.url)"');
    echo;
    echo "${THIS_JOB}console" | sed -E 's#(.*//)[0-9]+[^:/]*#\1localhost#' | highlight --stdlib;
    curl --connect-timeout 5 --silent \
      http://${USER}:${TOKEN}@localhost:8080/job/${JOB_NAME}/lastBuild/consoleText
}

```

When work on the branch is complete:

```bash
git reset --soft \
    $(git merge-base --fork-point master) \
  && git add . \
  && git commit
```

# Prior Art

- https://github.com/cfpb/jenkins-automation
- https://github.com/fabric8io/fabric8-jenkinsfile-library
- https://github.com/fabric8io/jenkins-docker
- https://github.com/sudo-bmitch/jenkins-docker

## Further reading

- https://github.com/forj-oss/jenkins-install-inits
- https://github.com/jenkins-x/jx
