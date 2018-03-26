from hamcrest import *
from create_jenkins_secrets import Secrets

secrets_dir = './tests/assets/SingleEnvSimple'
secrets = Secrets(secrets_dir)


def test_sort_creds_simple():
    assert_that(secrets.sort_creds(
        [
            {'ansible_credentials': 'example ansible credential'}
        ]
    ),
        equal_to(
            {
                'secret_text': [
                    {'ansible_credentials': 'example ansible credential'}
                ],
            }

        ))


def test_sort_two_creds_simple():
    assert_that(secrets.sort_creds(
        [
            {'ansible_credentials': 'example ansible credential'},
            {'ansible_credentials_2': 'example ansible credential 2'},
        ]
    ),
        equal_to(
            {
                'secret_text': [
                    {'ansible_credentials': 'example ansible credential'},
                    {'ansible_credentials_2': 'example ansible credential 2'}
                ]
            }

        ))


def test_read_secrets_simple():
    secrets_dir = './tests/assets/SingleEnvSimple'
    secrets = Secrets(secrets_dir)

    assert_that(secrets.get(), equal_to(
        {
            'FirstEnviron': {
                'secret_text': [
                    {
                        'ansible_credentials': 'example ansible credential'
                    }
                ]
            }
        }
    ))


def test_read_secrets_simple_sshuserpass():
    secrets_dir = './tests/assets/SingleEnvSshusername'
    secrets = Secrets(secrets_dir)

    assert_that(secrets.get(), equal_to(
        {
            'FirstEnviron': {
                'sshuserpass': [
                    {'gitlab_jenkins_credentials':
                         {'sshusername': 'git',
                          'privateKeySource': '-----BEGIN RSA PRIVATE KEY-----\\nxxx\\n-----END RSA PRIVATE KEY-----',
                          'passphrase': ''
                          }
                     }
                ],
            }
        }
    ))


def test_read_secrets_single_env():
    secrets_dir = './tests/assets/SingleEnv'
    secrets = Secrets(secrets_dir)

    assert_that(secrets.get(), equal_to(
        {
            'FirstEnviron': {
                'secret_text': [
                    {'ssh_credentials': 'example ssh credential'},
                    {'ansible_credentials': 'example ansible credential'},
                ],
                'userpass': [
                    {'docker_crenentials': {'username': "docker username", 'password': "docker password"}},
                    {'aws_credentials': {'username': "aws username", 'password': "aws password"}}
                ]
            }
        }
    ))


def test_read_secrets_multi_env_first():
    secrets_dir = './tests/assets/MultiEnv'
    secrets = Secrets(secrets_dir)

    assert_that(secrets.get()['FirstEnviron'], equal_to(
        {
            'secret_text': [
                {'ssh_credentials': 'example ssh credential'},
                {'ansible_credentials': 'example ansible credential'},
            ],
            'userpass': [
                {'aws_credentials': {'username': "aws username", 'password': "aws password"}},
                {'docker_crenentials': {'username': "docker username", 'password': "docker password"}}
            ],
            'sshuserpass': [
                {
                    'gitlab_jenkins_credentials': {
                        'sshusername': 'git',
                        'privateKeySource': '-----BEGIN RSA PRIVATE KEY-----\\nxxx\\n-----END RSA PRIVATE KEY-----',
                        'passphrase': ''
                    }
                }
            ],
        }
    ))


def test_read_secrets_multi_env_second():
    secrets_dir = './tests/assets/MultiEnv'
    secrets = Secrets(secrets_dir)

    assert_that(secrets.get()['SecondEnviron'], equal_to(
        {
            'secret_text': [
                {'ssh_credentials': 'example ssh credential for 2nd env'},
                {'ansible_credentials': 'example ansible credential for 2nd env'},
            ],
            'userpass': [
                {'docker_crenentials': {'username': "docker username for 2nd env",
                                        'password': "docker password for 2nd env"}},
                {'aws_credentials': {'username': "aws username for 2nd env",
                                     'password': "aws password for 2nd env"}}
            ]
        }
    ))


def test_read_secrets_multi_env():
    secrets_dir = './tests/assets/MultiEnv'
    secrets = Secrets(secrets_dir)

    assert_that(secrets.get(), equal_to(
        {
            'FirstEnviron': {
                'secret_text': [
                    {'ssh_credentials': 'example ssh credential'},
                    {'ansible_credentials': 'example ansible credential'},
                ],
                'userpass': [
                    {'aws_credentials': {'username': "aws username", 'password': "aws password"}},
                    {'docker_crenentials': {'username': "docker username", 'password': "docker password"}}
                ],
                'sshuserpass': [
                    {
                        'gitlab_jenkins_credentials': {
                            'sshusername': 'git',
                            'privateKeySource': '-----BEGIN RSA PRIVATE KEY-----\\nxxx\\n-----END RSA PRIVATE KEY-----',
                            'passphrase': ''
                        }
                    }
                ],
            },
            'SecondEnviron': {
                'secret_text': [
                    {'ssh_credentials': 'example ssh credential for 2nd env'},
                    {'ansible_credentials': 'example ansible credential for 2nd env'},
                ],
                'userpass': [
                    {'docker_crenentials': {'username': "docker username for 2nd env",
                                            'password': "docker password for 2nd env"}},
                    {'aws_credentials': {'username': "aws username for 2nd env",
                                         'password': "aws password for 2nd env"}}
                ]
            }
        }
    ))
