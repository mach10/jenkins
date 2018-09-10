#!/usr/bin/env python
import argparse
import errno
import json
import logging
import os
import os.path
import subprocess

logger = logging.basicConfig(level=logging.DEBUG,
                             format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')

LOGGER = logging.getLogger(__name__)

parser = argparse.ArgumentParser(description="Create/Update a release file in m2aci for specified module")
parser.add_argument('--artifact-id', help='The new artifact id we are building (generated by Jenkins)', required=True)
parser.add_argument('--module', help='The module we are building')

args = parser.parse_args()
ARTIFACT_ID = args.artifact_id
MODULE = args.module

M2A_CI_URL = "git@bitbucket.org:m2amedia/m2a-ci.git"


def get_sha(url):
    git_runner = GitRunner('/usr/bin/git', LOGGER)
    return git_runner.get_last_commit(url).split('\t', 1)[0]


def create_common_release(ci_url):
    common_data = {
        "m2a-ci": {
            "sha": get_sha(ci_url)
        },
        "artifact_id": ARTIFACT_ID
    }
    create_release_file(common_data)


def create_module_release(module_url, ci_url):
    modules_data = {
        "sha": get_sha(module_url),
        "m2a-ci": {
            "sha": get_sha(ci_url)
        },
        "artifact_id": ARTIFACT_ID
    }
    create_release_file(modules_data)


def create_release_file(module_data, module_name):
    """

    :param module_data: JSON object with module SHA, m2a-ci SHA and artifact id
    :param module_name: Module we are deploying
    """
    path = "m2a-releases/m2a-ci/{}.json".format(module_name)
    if not os.path.exists(os.path.dirname(path)):
        try:
            os.makedirs(os.path.dirname(path))
        except OSError as exc:
            if exc.errno != errno.EEXIST:
                raise

    with open(path, "w+") as new_file:
        json.dump(module_data, new_file)


class GitRunner:
    def __init__(self, path_to_binary, logger):
        self.path_to_binary = path_to_binary
        self.logger = logger

    def _run_cmd(self, cmd):
        try:
            process = subprocess.Popen(cmd,
                                       shell=False,
                                       stderr=subprocess.STDOUT,
                                       stdout=subprocess.PIPE)
            output, stderr = process.communicate()
            ret_code = process.wait()
            if ret_code == 0:
                return output
            else:
                error_message = "ERROR whilst running cmd {} - error {} ".format(cmd, stderr)
                self.logger.error(error_message)
                raise UserWarning(error_message)
        except Exception as ex:
            self.logger.error("ERROR whilst running cmd {} - error {} ".format(cmd, ex))
            raise ex

    def _create_cmd_for_remote_repo(self, remote_path):
        return [
            self.path_to_binary,
            "ls-remote",
            remote_path,
            "master"
        ]

    def get_last_commit(self, remote_path):
        cmd = self._create_cmd_for_remote_repo(remote_path)
        return self._run_cmd(cmd)


if MODULE:
    m2a_module_url = "git@bitbucket.org:m2amedia/{}.git".format(MODULE)
    create_module_release(m2a_module_url, M2A_CI_URL)
else:
    create_common_release(M2A_CI_URL)

