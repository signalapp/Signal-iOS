#!/usr/bin/python2.7
# -*- coding: utf-8 -*-

# When we make a hotfix, we need to reverse integrate our hotfix back into
# master. After commiting to master, this script audits that all tags have been
# reverse integrated.
import subprocess
from distutils.version import LooseVersion
import logging
import argparse

# logging.basicConfig(level=logging.DEBUG)

def is_on_master():
    output = subprocess.check_output(["git", "rev-parse", "--abbrev-ref", "HEAD"]).strip()
    logging.debug("branch output: %s" % output)
    return output == "master"

def main():
    parser = argparse.ArgumentParser(description='Check for unmerged tags.')
    parser.add_argument('--current-branch', action='store_true', help='if unspecified, the check is only run when on the master branch')

    args = parser.parse_args()

    if not is_on_master():
        # Don't interfere while on a feature or hotfix branch
        logging.debug("not on master branch")
        if not args.current_branch:
            return
    else:
        logging.debug("on master branch")

    unmerged_tags_output = subprocess.check_output(["git", "tag", "--no-merged", "HEAD"])
    unmerged_tags = [line.strip() for line in unmerged_tags_output.split("\n") if len(line) > 0]

    logging.debug("All unmerged tags: %s" % unmerged_tags)

    # Before this point we weren't always reverse integrating our tags.  As we
    # audit old tags, we can ratchet this version number back.
    epoch_tag="2.21.0"

    logging.debug("ignoring tags before epoch_tag: %s" % epoch_tag)

    tags_of_concern = [tag for tag in unmerged_tags if LooseVersion(tag) > LooseVersion(epoch_tag)]

    # Don't reverse integrate tags for adhoc builds
    tags_of_concern = [tag for tag in tags_of_concern if "adhoc" not in tag]

    tags_to_ignore = [
        '2.23.3.0',
        '2.23.3.1',
        '2.26.0.6',
        '2.26.0.7',
        '2.26.0.15',
        '2.26.0.16',
        '2.29.0.7',
        '2.29.0.8',
        '2.29.0.9',
        '2.29.0.11',
        '2.30.0.0',
        '2.30.0.1',
        '2.30.2.0',
        '2.46.0.26',
        '3.0',
        '3.0.1',
        '3.0.2',
        '3.3.1.0',
        # These tags were from unmerged branches investigating an issue that only reproduced when installed from TF.
        '2.34.0.10', '2.34.0.11', '2.34.0.12', '2.34.0.13', '2.34.0.15', '2.34.0.16', '2.34.0.17', '2.34.0.18', '2.34.0.19', '2.34.0.20', '2.34.0.6', '2.34.0.7', '2.34.0.8', '2.34.0.9',
        '2.37.3.0',
        '2.37.4.0',
        # these were internal release only tags, now we include "-internal" in the tag name to avoid this
        '2.38.0.2.1',
        '2.38.0.3.1',
        '2.38.0.4.1',
        # the work in these tags was moved to the 2.38.1 release instead
        '2.38.0.12',
        '2.38.0.13',
        '2.38.0.14',
        '2.38.1.3',
        # Looks like this tag was erroneously applied before rebasing.
        # After rebasing, HEAD was retagged with 2.40.0.20
        '2.40.0.19',
        # Looks like this tag was erroneously applied before rebasing.
        # After rebasing, HEAD was retagged with 2.41.0.2
        '2.41.0.1',
        # internal builds, not marked as such
        '2.44.0.0',
        '2.44.0.3',
        '2.42.0.6',
        '2.43.1.0',
        '2.43.1.1',
        '2.44.0.1',
        '2.44.0.2',
        '2.44.1.1',
        '3.4.0.8',
    ]
    tags_of_concern = [tag for tag in tags_of_concern if tag not in tags_to_ignore]

    # Interal Builds
    #
    # If you want to tag a build which is not intended to be reverse
    # integrated, include the text "internal" somewhere in the tag name, such as
    #
    # 1.2.3.4.5-internal
    # 1.2.3.4.5-internal-mkirk
    #
    # NOTE: that if you upload the build to test flight, you still need to give testflight
    # a numeric build number - so tag won't match the build number exactly as they do
    # with production build tags. That's fine.
    #
    # To avoid collision with "production" build numbers, use at least a 5
    # digit build number.
    tags_of_concern = [tag for tag in tags_of_concern if "internal" not in tag]

    if len(tags_of_concern) > 0:
        logging.debug("Found unmerged tags newer than epoch: %s" % tags_of_concern)
        raise RuntimeError("💥 Found unmerged tags: %s" % tags_of_concern)
    else:
        logging.debug("No unmerged tags newer than epoch. All good!")

if __name__ == "__main__":
        main()
