### To use lxd vm's:

1. run `tests/bin/lx_setup.sh`. This only needs to be run once.

2. run `tests/lxd/preloaded/create_preloaded.sh`. Run this anytime a new base image is updated (usually when ubuntu updates would require a system reboot).


### To bring up a vm:

1. It's helpful to have `vlx` in your path. vlx is a tool that makes `lxc` act a little like vagrant. In bash, create an alias for it: `alias vlx="$(pwd)/tests/bin/vlx"

2. set your working directory to the vm directory you'd like to start (eg. `cd "tests/lxd/vanilla"`), then run `vlx up`

3. to access the vm: `vlx shell` or `vlx ssh`. all vm's have the source root mounted at /cloudinabox or /mailinabox, so you can change files locally and they'll be available on the vm for testing

4. to destroy/delete the vm: `vlx destroy`


