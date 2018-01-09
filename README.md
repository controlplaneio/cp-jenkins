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
