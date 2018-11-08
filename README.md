# ControlPlane: Jenkins

Opinionated YAML-driven Jenkins.

## Quickstart

1. Edit `setup.yml` to point to a seed job, if one is desired, or remove the contents of the `seed_jobdsl` block. Change:
    ```
    properties {
        githubProjectUrl('https://github.com/controlplaneio/jenkins-dsl')
    }
    ```
    and  
    ```
    remote {
        url('git@github.com:controlplaneio/jenkins-dsl.git')
        credentials('ssh-key-jenkins-bot')
    }
    ```
1. Update the secrets and admin configuration for the deployment:

    ```
    $ cp setup-secret-example.yml setup-secret.yml
    ```
    
    Edit `setup-secret.yml` and fill in the configuration values. Update:
    ```
    org_name: github organisation name
    admin_user: github username
    admin_emai: email of github user
    client_id/client_secret: OAuth secrets from Github for login
    ```
    
    > Client secrets for github/github_test are used for make run/test-run respectively

1. Build the Docker image:
    ```
    $ make build
    ```

1. Once built, launch locally:
    
    > Make sure `JENKINS_HOME_MOUNT_DIR` exists, and is an absolute path. If you don't
    > specify it, it will default to `/mnt/jenkins_home`.
    
    ```
    $ JENKINS_HOME_MOUNT_DIR=${HOME}/jenkins_home make run-local
    ```
    
    Navigate go to `http://localhost:8080` in your browser.

    > For a local development workflow, see below

1. If you don't care about persisting that data then you can use the `test-run` command, which uses a new `/tmp/foo`
directory each invocation, and runs on `TEST_PORT` in the Makefile (default is `8090`).
    
    ```
    $ make test-run
    ```

## Configuration

Once Jenkins is up:
1. Credentials need to be added to clone repositories via SSH
1. In-process script approval is required to allow the initial DSL scripts

## Local Workflow

Building in a local Jenkins instance avoids the long feedback loop associated with remote Jenkins builds. It's
particuarly useful for Jenkinsfile and Job DSL development.

1. checkout a git repo to your host machine (laptop, etc)
1. mount the git repo from your host to the local Jenkins container at startup
1. make a commit to your local git repo (Jenkins will alway build from the last commit)
1. trigger a build job in the local Jenkins

### Steps

1. Invoke the container:
    ```bash
    JENKINS_HOME_MOUNT_DIR=${HOME}/jenkins_home \
      JENKINS_TESTING_REPO_MOUNT_DIR=${HOME}/test-repo \
      CONTAINER_TAG=latest \
      make run-local
     ```
    1. add the directories you want to mount for the Jenkins home directory and the repository you are building to the environment variables `JENKINS_HOME_MOUNT_DIR` and `JENKINS_TESTING_REPO_MOUNT_DIR`.
    1. this mounts the `JENKINS_TESTING_REPO_MOUNT_DIR` to `/mnt/test-repo`
1. Log in at [http://localhost:8080](http://localhost:8080) (or `TEST_PORT` if running `make test-run`, default `8090`)
1. Exec into the running container and disable security in the config file in order to access all the settings.
   (you should ONLY DO THIS LOCALLY):
  ```
  $ docker exec -it CONTAINER_ID su jenkins -c bash
  jenkins@CONTAINER_ID:/$ sed -i 's/<useSecurity>true<\/useSecurity>/<useSecurity>false<\/useSecurity>/' /var/jenkins_home/config.xml
  jenkins@CONTAINER_ID:/$ exit
  $ docker container restart CONTAINER_ID
  ```
  You will need to restart the container for the new config to take effect.
1. create a new pipeline job (or whatever you're testing)
    1. set the path to `file:///mnt/test-repo` (or a subdirectory thereof). If you are building a pipeline job,
    you will need to set `Pipeline > Definition` to "Pipeline script from SCM" and specify the path in "Repository URL",
    e.g file:///mnt/test-repo/my-repo/
    1. untick "Lightweight checkout"

1. trigger a build of the new job. In the repo under test, switch to a new branch to commit small chunks to test in
Jenkins. These commits should be squashed or rebased onto another branch when complete:
  1. `git branch local-jenkins-dev && git checkout local-jenkins-dev`
  1. Make changes to the code in the repo
  1. `git add . && git commit -m "Auto commit $(date)"`
  1. Trigger a Jenkins build (see next section, or do manually through UI)
  1. Iterate
  1. When complete, rebase changes onto another branch for commit or PR

> Jenkins checks out the local git repo to build the job, so changes must be committed locally for Jenkins to build
> them.

# Migrating between hosts

1. Stop the Jenkins container
1. Compress the data directories
  ```
  tar czvf mount-jenkins.tar.gz /mnt/jenkins_home/ /mnt/certs/
  ```
1. Copy the file to the new host (either via ssh ForwardAgent [which should only be [enabled when required](https://heipei.github.io/2015/02/26/SSH-Agent-Forwarding-considered-harmful/) or bounced through a secure intermediate host/workstation)
1. Untar the tarball into the same directories on the new host
1. Run the Makefile from this repo on the new host
  ```
  make run-prod \
    CONTAINER_TAG=latest \
    VIRTUAL_HOST=myhost.example.com \
    LETSENCRYPT_EMAIL=my@example.com
  ```
> To run the image by itself (without nginx or letencrypt), use `make run` instead of `make run-prod`


# Prior Art

- https://github.com/cfpb/jenkins-automation
- https://github.com/fabric8io/fabric8-jenkinsfile-library
- https://github.com/fabric8io/jenkins-docker
- https://github.com/sudo-bmitch/jenkins-docker

## Further reading

- https://github.com/forj-oss/jenkins-install-inits
- https://github.com/jenkins-x/jx
- https://github.com/samrocketman/jenkins-bootstrap-shared
