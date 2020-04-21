#!/usr/bin/env python2

import argparse
import logging
import sys
import yaml
import json
import requests
import getpass
import warnings
from os import walk
from os import path
from os.path import join, basename

warnings.filterwarnings("ignore")

logging.basicConfig(level=logging.INFO)
# logging.basicConfig(level=logging.DEBUG)

admin_user = ''
api_token = ''
url_base = ''
secrets_dir = ''
crumb_enabled = True

parser = argparse.ArgumentParser(description='Create Jenkins secrets')
parser.set_defaults(delete_all=False)
parser.add_argument('--delete', dest='delete_all', action='store_true',
                    help='Delete all credentials referenced from secrets directory')

parser.add_argument('--server', dest='server', help='URL to Jenkins server')
parser.add_argument('--username', dest='username', help='Jenkins admin username')
parser.add_argument('--secrets-dir', '-d', dest='secrets_dir',
                    help='Directory containing secrets YAML files')

args = parser.parse_args()

def is_secrets_dir_populated(secrets = None):
    if secrets is None:
        secrets = Secrets(secrets_dir).get()

    return len(secrets.keys()) > 0

def main():
    parse_args()
    secrets = Secrets(secrets_dir).get()

    total_secrets = 0

    if not is_secrets_dir_populated(secrets):
        logging.error("No secrets found in {}".format(secrets_dir))
        sys.exit(1)

    for environment in secrets.keys():
        logging.debug('env {}'.format(environment))

        for secret_type in ['userpass', 'secret_text', 'sshuserpass']:

            if secret_type in secrets[environment]:

                for secret in secrets[environment][secret_type]:

                    key_name = secret.keys()[0]
                    credential_id = "{}_{}".format(environment, key_name)
                    credential_description = "{}_{}".format(environment, key_name)
                    credential_scope = 'GLOBAL'

                    logging.info("Using: {} ({})".format(credential_id, secret_type))

                    if secret_type == 'secret_text':
                        credential_text = "{}".format(secret[key_name])

                        form_payload = get_form_payload(secret_type).format(
                            scope=credential_scope,
                            id=credential_id,
                            secret=json.dumps(credential_text),
                            description=json.dumps(credential_description)
                        )

                    elif secret_type == 'userpass':
                        credential_username = "{}".format(secret[key_name]['username'])
                        credential_password = "{}".format(secret[key_name]['password'])

                        form_payload = get_form_payload(secret_type).format(
                            scope=credential_scope,
                            id=credential_id,
                            username=credential_username,
                            password=credential_password,
                            description=credential_description
                        )

                    elif secret_type == 'sshuserpass':
                        credential_username = "{}".format(secret[key_name]['sshusername'])
                        credential_private_key_source = "{}".format(secret[key_name]['privateKeySource'])
                        credential_passphrase = "{}".format(secret[key_name]['passphrase'])

                        form_payload = get_form_payload(secret_type).format(
                            scope=credential_scope,
                            id=credential_id,
                            sshusername=credential_username,
                            privateKeySource=credential_private_key_source,
                            passphrase=credential_passphrase,
                            description=credential_description
                        )

                    logging.debug('deleting {}'.format(credential_id))
                    response = requests.post(
                        '{}/credentials/store/system/domain/_/credential/{}/doDelete'.format(url_base, credential_id),
                        data={'json': form_payload},
                        headers=get_headers(),
                        auth=(admin_user, api_token), verify=False
                    )
                    logging.debug(response.request.headers)
                    check_status_code_is_200_or_404(response)

                    if not args.delete_all:
                        logging.debug(form_payload)
                        response = requests.post(
                            '{}/credentials/store/system/domain/_/createCredentials'.format(url_base),
                            data={'json': form_payload},
                            headers=get_headers(),
                            auth=(admin_user, api_token), verify=False
                        )
                        logging.debug(response.request.headers)
                        check_status_code_is_200(response)

                    total_secrets += 1

    logging.info("Secrets added: %s " % str(total_secrets))


def parse_args():
    global admin_user, api_token, url_base, secrets_dir

    if args.secrets_dir is None:
        secrets_dir = raw_input("Local YAML secrets directory: ")
    else:
        secrets_dir = args.secrets_dir

    if not is_secrets_dir_populated():
        logging.error("No secrets found in {}".format(secrets_dir))
        sys.exit(1)

    if args.server is None:
        url_base = raw_input("Jenkins server (incl. protocol): ")
    else:
        url_base = args.server


    if args.username is None:
        admin_user = raw_input("Jenkins admin username: ")
    else:
        admin_user = args.username

    api_token = getpass.getpass("Jenkins API Token for " + admin_user + ": ")

    logging.info('url_base: {}'.format(url_base))


def get_form_payload(secret_type):
    if secret_type == 'secret_text':
        return '''{{
"":"0",
"credentials":{{
"scope":"{scope}",
"id":"{id}",
"secret":{secret},
"description":{description},
"$class":"org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl"
}}
}}'''
    elif secret_type == 'userpass':
        return '''{{
"":"0",
"credentials":{{
"scope":"{scope}",
"id":"{id}",
"username":"{username}",
"password":"{password}",
"description":"{description}",
"$class":"com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl"
}}
}}'''
    elif secret_type == 'sshuserpass':
        return '''{{
"":"0",
"credentials":{{
"scope":"{scope}",
"id":"{id}",
"username":"{sshusername}",
"privateKeySource":{{
"privateKey":"{privateKeySource}",
"stapler-class":"com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey$DirectEntryPrivateKeySource"
}},
"passphrase":"{passphrase}",
"description":"{description}",
"stapler-class":"com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey"
}}
}}'''
    else:
        print('Payload type {} not known'.format(secret_type))
        sys.exit(1)


def get_crumb(url_base):
    global crumb_enabled

    if not crumb_enabled:
        return ""

    response = requests.get(
        "{}/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)".format(url_base),
        auth=(admin_user, api_token), verify=False
    )

    if not check_status_code_is_200(response, tolerate_failure=True):
        logging.debug('Status is not 200 on crumb request')
        crumb_enabled = False
        return ""

    crumb = response.text.split(':')[1]
    logging.debug('crumb: {}'.format(crumb))

    return crumb


def check_status_code_is_200(response, tolerate_failure=False):
    if response.status_code != 200:
        logging.error("Request failed: status code {}".format(response.status_code))
        logging.error(response.text.encode('UTF-8'))
        if tolerate_failure:
            logging.info("Failure tolerated, continuing")
            return False
        sys.exit(1)

    return True


def check_status_code_is_200_or_404(response):
    if response.status_code != 200 and response.status_code != 404:
        logging.error("Request failed: status code {}".format(response.status_code))
        logging.error(response.text.encode('UTF-8'))
        sys.exit(1)

    return True


def get_headers():
    crumb = get_crumb(url_base)
    headers = {
        'Jenkins-Crumb': crumb,
        'Content-Type': 'application/x-www-form-urlencoded'
    }

    return headers


class Secrets(object):
    def __init__(self, directory):
        self.result = {}
        if not path.isdir(directory):
            logging.error("Directory not found at {}. Try going down one level with `../`?".format(directory))
            logging.error("  For example: ../../../2020/cp-secret/environments/")
            sys.exit(1)

        self.directory = directory

    def get(self):
        files = self.get_files_from_dir(self.directory)
        logging.debug(files)

        for this_file in files:
            logging.debug(this_file)
            result = self.get_list(self.parse_yaml(this_file))
            environment_name = basename(this_file).replace('.yaml', '')
            self.result[environment_name] = self.sort_creds(result, this_file)

        logging.debug(self.result)
        return self.result

    def get_files_from_dir(self, source_directory):
        all_files = []
        for (root, dirs, files) in walk(source_directory):
            for file in files:
                new_files = join(source_directory, file)
                all_files.append(new_files)

        return all_files

    def sort_creds(self, credentials, file_name):
        response = {}

        for cred in credentials:
            for key, value in cred.iteritems():
                if isinstance(value, list) and len(value) > 0:
                    logging.debug("Found list: " + key)
                    logging.debug("Found list length: %d" % len(value))

                    try:
                        env_creds = self.list_to_dict(value)
                    except:
                        raise Exception('Malformed credentials block - could not parse list')

                    if env_creds.get('username') is not None \
                        and env_creds.get('password') is not None:
                        if response.get('userpass') is None:
                            response['userpass'] = []
                        response['userpass'].append({key: env_creds})

                    elif env_creds.get('sshusername') is not None \
                        and env_creds.get('privateKeySource') is not None:
                        if response.get('sshuserpass') is None:
                            response['sshuserpass'] = []
                        if env_creds.get('passphrase') is None:
                            env_creds['passphrase'] = ''
                        env_creds['privateKeySource'] = env_creds['privateKeySource'].replace('\n', '\\n')
                        response['sshuserpass'].append({key: env_creds})

                    else:
                        raise Exception('Wanted user or username key, neither found in `%s` of file `%s`' % (key, file_name))
                else:
                    if response.get('secret_text') is None:
                        response['secret_text'] = []
                    response['secret_text'].append({key: value})

        return response

    def list_to_dict(self, value):
        new_value = {}
        new_value.update(value[0])
        new_value.update(value[1])
        return new_value

    def parse_yaml(self, file):
        parsed_yaml = None
        with open(file, 'r') as stream:
            try:
                parsed_yaml = yaml.load(stream)
            except yaml.YAMLError as exc:
                raise exc
        return parsed_yaml

    def get_list(self, dict_to_list):
        list_of_dictionary = []
        for key, value in dict_to_list.iteritems():
            list_of_dictionary.append({key: value})
        return list_of_dictionary


if __name__ == "__main__":
    main()
