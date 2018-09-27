#!/usr/bin/python
# -*- coding: utf-8 -*-

# When we make a hotfix, we need to reverse integrate our hotfix back into
# master. After commiting to master, this script audits that all tags have been
# reverse integrated.
import subprocess
from distutils.version import LooseVersion
import logging

#logging.basicConfig(level=logging.DEBUG)

def is_on_master():
    output = subprocess.check_output(["git", "rev-parse", "--abbrev-ref", "HEAD"]).strip()
    logging.debug("branch output: %s" % output)
    return output == "master"

def main():
    if not is_on_master():
        # Don't interfere while on a feature or hotfix branch
        logging.debug("not on master branch")
        return

    logging.debug("on master branch")

    unmerged_tags_output = subprocess.check_output(["git", "tag", "--no-merged", "master"])
    unmerged_tags = [line.strip() for line in unmerged_tags_output.split("\n") if len(line) > 0]

    logging.debug("All unmerged tags: %s" % unmerged_tags)

    # Before this point we weren't always reverse integrating our tags.  As we
    # audit old tags, we can ratchet this version number back.
    epoch_tag="2.21.0"

    logging.debug("ignoring tags before epoch_tag: %s" % epoch_tag)

    tags_of_concern = [tag for tag in unmerged_tags if LooseVersion(tag) > LooseVersion(epoch_tag)]

    # Don't reverse integrate tags for adhoc builds
    tags_of_concern = [tag for tag in tags_of_concern if "adhoc" not in tag]

    tags_to_ignore = ['2.29.0.11', '2.29.0.7', '2.29.0.8', '2.29.0.9', '2.23.3.0', '2.23.3.1', '2.26.0.15', '2.26.0.16', '2.26.0.6', '2.26.0.7', '3.0', '3.0.1', '3.0.2', '2.30.0.0', '2.30.0.1']
    tags_of_concern = [tag for tag in tags_of_concern if tag not in tags_to_ignore]

    if len(tags_of_concern) > 0:
        logging.debug("Found unmerged tags newer than epoch: %s" % tags_of_concern)
        raise RuntimeError("💥 Found unmerged tags: %s" % tags_of_concern)
    else:
        logging.debug("No unmerged tags newer than epoch. All good!")

if __name__ == "__main__":
        main()
