# ControlPlane: Jenkins

## Quickstart

Repo for building a Jenkins container that works with our infra.

To build:

```
$ make build
```

Before you can run it you should do a `git-crypt unlock` as there is an encrypted secret.
If you are not in the git-crypt send your public gpg-key to a person who is and have them add you.

To launch locally, once built:

Make sure `JENKINS_HOME_MOUNT_DIR` exists, and is an absolute path. If you don't
specify it, it will default to `/mnt/jenkins_home`.

```
$ JENKINS_HOME_MOUNT_DIR=${HOME}/jenkins_home make run
```

Then go to `http://localhost:8080` in your browser.

If you don't care about persisting that data then you can use the following,
which uses a new `/tmp/foo` directory each time, and runs on `TEST_PORT` in the Makefile (default is `8090`).

```
$ make test-run
```

## Configuration

1. Jenkins requires a manual `ssh git@github.com` from the command line to accept `github.com`'s public key
    ```bash
    docker exec -it CONTAINER_ID su jenkins -c -- bash -c 'mkdir -p ~/.ssh && ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts'
    ```
   (Successful output looks something like `# github.com:22 SSH-2.0-libssh_0.7.0`, and there is a github.com entry in `/var/jenkins_home/.ssh/known_hosts`)
1. Credentials need to be added to clone repositories
1. In-process script approval is required to allow the initial DSL scripts

## Local Workflow

Building in a local Jenkins instance avoids the long feedback loop associated with remote Jenkins builds. It's particuarly useful for Jenkinsfile and Job DSL development.

1. checkout a git repo to your host machine (laptop, etc)
1. mount the git repo from your host to the local Jenkins container at startup
1. make a commit to your local git repo (Jenkins will alway build from the last commit)
1. trigger a build job in the local Jenkins

### Steps

1. `JENKINS_HOME_MOUNT_DIR=${HOME}/jenkins_home JENKINS_TESTING_REPO_MOUNT_DIR=${HOME}/test-repo make run`
    1. replace `JENKINS_HOME_MOUNT_DIR` and `JENKINS_TESTING_REPO_MOUNT_DIR` with the directories you want to mount for the Jenkins home directory and the repository you are building.
    1. this mounts the `JENKINS_TESTING_REPO_MOUNT_DIR` to `/mnt/test-repo`
1. Log in at [http://localhost:8080](http://localhost:8080) (or `TEST_PORT` if running `make test-run`, default `8090`)
1. Disable security in the UI, or exec into the running container and disable security in the config file in order to access all the settings. 
   (you should ONLY DO THIS LOCALLY):
  ```
  sed -i 's/<useSecurity>true<\/useSecurity>/<useSecurity>false<\/useSecurity>/' /var/jenkins_home/config.xml
  ```
  You will need to restart the container for the new config to take place.
1. create a new pipeline job (or whatever you're testing)
    1. set the path to `file:///mnt/test-repo` (or a subdirectory thereof). If you are building a pipeline job, you will need to set `Pipeline > Definition` to "Pipeline script from SCM" and specify the path in "Repository URL", e.g file:///mnt/test-repo/my-repo/
    1. untick "Lightweight checkout"
 
1. trigger a build of the new job. In the repo under test, switch to a new branch to commit small chunks to test in Jenkins. These commits should be squashed or rebased onto another branch when complete:
  1. `git branch local-jenkins-dev && git checkout local-jenkins-dev`
  1. Make changes to the code in the repo
  1. `git add . && git commit -m "Auto commit $(date)"`
  1. Trigger a Jenkins build (see next section, or do manually through UI)
  1. Iterate
  1. When complete, rebase changes onto another branch for commit or PR
  
## Trigger Build via API

Instead of triggering builds through the UI, the Jenkins can be used (unless security is off you will need to retrieve your API token)

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
