This 'vendor/' dir contains sources from external git repos

Each <foo>.vendor.hjson specifies an external repo, and specifies
which files are to be copied from that repo.

The Makefile describes how each such resource is created.
Briefly, each resource <foo> is created by:

    $ ../Tools/vendor.py    <foo>

The tool '../Tools/vendor.py' is downloaded from:
    https://github.com/lowRISC/opentitan/blob/master/util/vendor.py

    It is an alternative to using Git sub-modules for external repositories.
