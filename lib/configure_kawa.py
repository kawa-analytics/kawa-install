#!/usr/bin/env python3
"""
Post-install configuration of KAWA, using the kywy python client.

Reads its parameters from the environment (sourced from
/etc/kawa/kawa.config by kawa-configure.sh) and applies the KAWA
Configuration objects through the commands API:

  - Features + email provider  (StandaloneApiServerConfiguration)
  - SMTP server                (SmtpConfig)
  - OIDC / SSO                 (OAuth2ClientConfiguration)
  - Workflow engine            (WorkflowConfiguration)
  - AI                         (OpenAiConfiguration - kept deactivated)
  - Admin password             (AdminChangeUserPassword)

The secrets stay in the environment and are NOT sent through this
script: KAWA_SMTP_USERNAME / KAWA_SMTP_PASSWORD, KAWA_OAUTH2_CLIENT_SECRET,
and the HTTPS certificate (see /etc/kawa/kawa.env).

Idempotent: re-run it at any time after editing /etc/kawa/kawa.config,
then restart the kawa service.
"""

import os
import sys

from kywy.client.kawa_client import KawaClient

SETUP_ADMIN = 'setup-admin@kawa.io'
DEFAULT_ADMIN_PASSWORD = 'changeme'


def env(name, default=''):
    return os.environ.get(name, default).strip()


def main():
    port = env('LISTEN_PORT', '8080')
    scheme = 'https' if env('USE_HTTPS') == 'true' else 'http'
    url = '{}://localhost:{}'.format(scheme, port)

    admin_password = ''
    admin_password_file = env('ADMIN_PASSWORD_FILE', '/etc/kawa/admin.pwd')
    if os.path.isfile(admin_password_file):
        with open(admin_password_file) as f:
            admin_password = f.read().strip()

    print('Connecting to KAWA on {}'.format(url))
    kawa = KawaClient(kawa_api_url=url)

    # Login with the configured admin password. On a fresh install the
    # password is still the default one: log in with it, and change it
    # at the end of this script.
    password_needs_change = False
    try:
        kawa.login_with_credential(login=SETUP_ADMIN, password=admin_password or DEFAULT_ADMIN_PASSWORD)
    except Exception:
        kawa.login_with_credential(login=SETUP_ADMIN, password=DEFAULT_ADMIN_PASSWORD)
        password_needs_change = bool(admin_password)

    cmd = kawa.commands

    # Features + email provider.
    # In docker mode the server always listens on 8080 inside its
    # container (SERVER_INTERNAL_PORT), whatever the exposed port is.
    features = [f.strip() for f in env('ENABLED_FEATURES').split(',') if f.strip()]
    provider = env('COMMUNICATION_PROVIDER_TYPE', 'LOG')
    cmd.replace_configuration('StandaloneApiServerConfiguration', {
        'port': int(env('SERVER_INTERNAL_PORT') or port),
        'communicationProviderType': provider,
        'enabledFeatures': features,
    })
    print('- Enabled features: {}'.format(', '.join(features) or 'none'))
    print('- Email provider: {}'.format(provider))

    # SMTP server. The credentials stay in the environment
    # (KAWA_SMTP_USERNAME / KAWA_SMTP_PASSWORD in kawa.env).
    # The workflow engine needs no SMTP configuration of its own:
    # all emails are sent by the KAWA server.
    if provider == 'SMTP':
        cmd.replace_configuration('SmtpConfig', {
            'host': env('SMTP_HOST'),
            'port': int(env('SMTP_PORT', '465')),
            'sslEnabled': env('SMTP_SSL') == 'true',
            'startTlsEnabled': env('SMTP_START_TLS') == 'true',
            'authenticationEnabled': env('SMTP_AUTHENTICATION') == 'true',
        })
        print('- SMTP server: {}:{}'.format(env('SMTP_HOST'), env('SMTP_PORT')))

    # OIDC / SSO. The client secret stays in the environment
    # (KAWA_OAUTH2_CLIENT_SECRET in kawa.env).
    if env('USE_OIDC') == 'true':
        cmd.replace_configuration('OAuth2ClientConfiguration', {
            'clientId': env('OIDC_CLIENT_ID'),
            'openidIssuer': env('OIDC_ISSUER'),
            'clientHost': env('OIDC_CLIENT_HOST') or env('KAWA_EXTERNAL_URL'),
        })
        print('- OIDC enabled against: {}'.format(env('OIDC_ISSUER')))

    # Workflow engine. In docker mode the engine is reached through
    # the compose network (WORKFLOW_URL=http://kawa-workflow:8088).
    workflow_url = env('WORKFLOW_URL') or 'http://localhost:{}'.format(env('WORKFLOW_PORT', '8088'))
    cmd.replace_configuration('WorkflowConfiguration', {
        'enabled': True,
        'baseUrl': workflow_url,
    })
    print('- Workflow engine enabled on {}'.format(workflow_url))

    # AI is completely disabled
    cmd.replace_configuration('OpenAiConfiguration', {
        'activated': False,
    })
    print('- AI: disabled')

    # Admin password
    if password_needs_change:
        cmd.change_user_password(SETUP_ADMIN, admin_password)
        print('- Admin password updated')
    elif not admin_password:
        print('! The admin password is still the default one.')
        print('  Set it in {} and re-run kawa-configure.sh'.format(admin_password_file))

    print('Configuration applied. Restart the KAWA server to take it into account.')


if __name__ == '__main__':
    sys.exit(main())
