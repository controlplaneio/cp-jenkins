@Grapes([
  @Grab(group = 'org.yaml', module = 'snakeyaml', version = '1.17')
])

import org.yaml.snakeyaml.Yaml
import java.util.logging.Logger
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.CredentialsStore

import com.cloudbees.plugins.credentials.common.*
import com.cloudbees.plugins.credentials.domains.*

import com.cloudbees.plugins.credentials.impl.*;
import com.cloudbees.plugins.credentials.*;
import com.cloudbees.plugins.credentials.domains.*;

import com.cloudbees.jenkins.plugins.sshcredentials.impl.*

import jenkins.model.*
import jenkins.security.*
import hudson.model.*
import hudson.security.*
import hudson.plugins.sshslaves.*;

import hudson.security.SecurityRealm
import hudson.security.AuthorizationStrategy
import org.jenkinsci.plugins.GithubSecurityRealm
import org.jenkinsci.plugins.GithubAuthorizationStrategy

import javaposse.jobdsl.dsl.DslScriptLoader
import javaposse.jobdsl.plugin.JenkinsJobManagement

env = System.getenv()
JENKINS_SETUP_YAML = env['JENKINS_SETUP_YAML'] ?: "${env['JENKINS_CONFIG_HOME']}/setup.yml"
JENKINS_SECRET_YAML = env['JENKINS_SETUP_YAML'] ?: "${env['JENKINS_CONFIG_HOME']}/setup-secret.yml"
Logger logger = Logger.getLogger('setup-master-config.groovy')
def config = new Yaml().load(new File(JENKINS_SETUP_YAML).text)
def secrets = new Yaml().load(new File(JENKINS_SECRET_YAML).text)

config = config + secrets

def firstRun = true

// setup Time Zone
Thread.start {
  TZ = env['JENKINS_TZ'] ?: config.time_zone ?: 'Europe/London'
  System.setProperty('org.apache.commons.jelly.tags.fmt.timeZone', TZ)
}

// setup master executors
Thread.start {
  def JENKINS = Jenkins.getInstance()
  int executors = env['JENKINS_EXECUTORS'] ?: config.executors.master.toInteger() ?: 2
  int current_executors = JENKINS.getNumExecutors()
  if (current_executors != executors) {
    JENKINS.setNumExecutors(executors)
    JENKINS.save()
  }
}

// setup global git config
Thread.start {
  if (Jenkins.instance.pluginManager.activePlugins.find { it.shortName == 'git' } != null) {
    def PLUGIN = 'hudson.plugins.git.GitSCM'
    def globalConfigName = config.git.config.name ?: 'jenkins-bot'
    def globalConfigEmail = config.git.config.email ?: 'jenkins@example.com'

    def descriptor = Jenkins.instance.getDescriptor(PLUGIN)
    if (globalConfigName != descriptor.getGlobalConfigName()) {
      descriptor.setGlobalConfigName(globalConfigName)
    }
    if (globalConfigEmail != descriptor.getGlobalConfigEmail()) {
      descriptor.setGlobalConfigEmail(globalConfigEmail)
    }
    if (!descriptor.equals(Jenkins.instance.getDescriptor(PLUGIN))) {
      descriptor.save()
    }
    logger.info('Configured Git SCM')
  }
}

// setup Jenkins generics
Thread.start {
  def JENKINS = Jenkins.getInstance()

  def PLUGIN_LOCATION = 'jenkins.model.JenkinsLocationConfiguration'
  def descriptorLocation = JENKINS.getDescriptor(PLUGIN_LOCATION)
  def HOSTNAME = env['HOSTNAME'].toString()
  def JENKINS_LOC_URL = "${config.web_proto}://${HOSTNAME}:${config.web_port}"

  if (JENKINS_LOC_URL != descriptorLocation.getUrl()) {
    descriptorLocation.setUrl(JENKINS_LOC_URL)
  }
  if (config.admin.email != descriptorLocation.getAdminAddress()) {
    descriptorLocation.setAdminAddress(config.admin.email)
  } else {
    firstRun = false
  }
  if (!descriptorLocation.equals(Jenkins.instance.getDescriptor(PLUGIN_LOCATION))) {
    descriptorLocation.save()
  }
  logger.info('Configured Admin Address')


  if (!firstRun) {
    logger.info('NOT FIRST RUN - done')


  } else {
    logger.info('FIRST RUN - configuring auth')

    // setup seed job
    WORKSPACE_BASE = "${env['JENKINS_HOME']}/workspace"
    def workspace = new File("${WORKSPACE_BASE}")

    def seedJobDsl = config.seed_jobdsl
    logger.info(seedJobDsl)

    def jobManagement = new JenkinsJobManagement(System.out, [:], workspace)
    new DslScriptLoader(jobManagement).runScript(seedJobDsl)
    logger.info('Created seed job')

    sleep 1000

    // setup global credentials
//    Thread.start {
//      def PLUGIN_SYS_CRED = 'com.cloudbees.plugins.credentials.SystemCredentialsProvider'
//      credentials_store = JENKINS.getExtensionList(PLUGIN_SYS_CRED)[0].getStore()
//
//      config.credentials.each {
//        it.global.each {
//          Credentials credentials = (Credentials) new UsernamePasswordCredentialsImpl(CredentialsScope.USER,
//            it.id, it.description, it.username, it.password)
//
//          credentials_store.addCredentials(Domain.global(), credentials)
//        }
//      }
//      logger.info('Configured Global Credentials')
//    }

    // setup master ssh key
    Thread.start {
      def globalConfigName = config.git.config.name ?: 'jenkins-bot'
      logger.info("starting ssh key load for ${globalConfigName}")

      def JENKINS_SSH_KEY = env['JENKINS_HOME'] + '/.ssh/id_rsa'
      if (Jenkins.instance.pluginManager.activePlugins.find { it.shortName == 'ssh-credentials' } != null) {

        // adds SSHUserPrivateKey From the Jenkins master ${HOME}/.ssh
        def PLUGIN_SYS_CRED = 'com.cloudbees.plugins.credentials.SystemCredentialsProvider'
        credentials_store = Jenkins.instance.getExtensionList(PLUGIN_SYS_CRED)[0].getStore()

        // signature Scope, Id, Username, Keysource, Passphrase, Description
        try {
          credentials = new BasicSSHUserPrivateKey(
            CredentialsScope.GLOBAL,
            "ssh-key-${globalConfigName}",
            globalConfigName,
            new BasicSSHUserPrivateKey.DirectEntryPrivateKeySource(
              new File(JENKINS_SSH_KEY).getText('UTF-8')
            ),
            '',
            'Autogenerated during bootstrap'
          )

          credentials_store.addCredentials(Domain.global(), credentials)
          logger.info("Configured SSH Credentials from ${JENKINS_SSH_KEY} for ${globalConfigName}")
        } catch (Exception e) {
          logger.info("No ssh key found at ${JENKINS_SSH_KEY} for ${globalConfigName}")
        }
//        } else {
//          logger.info("No ssh key found at ${JENKINS_SSH_KEY} for ${globalConfigName}")
//        }
      } else {
        logger.info("ssh-credentials plugin not found")
      }
    }

    // setup matrix-auth configuration
    Thread.start {
      if (JENKINS.pluginManager.activePlugins.find { it.shortName == 'matrix-auth' } != null) {
        def hudson_realm = new HudsonPrivateSecurityRealm(false)
        def admin_username = env['JENKINS_ADMIN_USERNAME'] ?: config.admin.username ?: 'admin'
        def admin_password = env['JENKINS_ADMIN_PASSWORD'] ?: config.admin.password ?: 'password'
        hudson_realm.createAccount(admin_username, admin_password)

        JENKINS.setSecurityRealm(hudson_realm)

        def strategy = new hudson.security.GlobalMatrixAuthorizationStrategy()
        //  Setting Anonymous Permissions
        strategy.add(hudson.model.Hudson.READ, 'anonymous')
        strategy.add(hudson.model.Item.BUILD, 'anonymous')
        strategy.add(hudson.model.Item.CANCEL, 'anonymous')
        strategy.add(hudson.model.Item.DISCOVER, 'anonymous')
        strategy.add(hudson.model.Item.READ, 'anonymous')
        // Setting Admin Permissions
        strategy.add(Jenkins.ADMINISTER, 'admin')
        // Setting easy settings for local development
        if (env['BUILD_ENV'] == 'local') {
          //  Overall Permissions
          strategy.add(hudson.model.Hudson.ADMINISTER, 'anonymous')
          strategy.add(hudson.PluginManager.CONFIGURE_UPDATECENTER, 'anonymous')
          strategy.add(hudson.model.Hudson.READ, 'anonymous')
          strategy.add(hudson.model.Hudson.RUN_SCRIPTS, 'anonymous')
          strategy.add(hudson.PluginManager.UPLOAD_PLUGINS, 'anonymous')
        }

        if (!hudson_realm.equals(Jenkins.instance.getSecurityRealm())) {
          // Jenkins.instance.setSecurityRealm(hudson_realm)
          // Jenkins.instance.save()
          JENKINS.setAuthorizationStrategy(strategy)
          JENKINS.save()
        }
        logger.info('Configured AuthorizationStrategy')
      }
    }

    // setup Mailer configuration
    Thread.start {
      def PLUGIN_MAILER = 'hudson.tasks.Mailer'
      def descriptorMailer = JENKINS.getDescriptor(PLUGIN_MAILER)
      def smtpEmail = env['SMTP_EMAIL'] ?: config.mailer.smtp_email ?: ''
      def smtpHost = env['SMTP_HOST'] ?: config.mailer.smtp_host ?: 'smtp.gmail.com'
      def smtpAuthPasswordSecret = env['SMTP_PASSWORD'] ?: config.mailer.smtp_password ?: ''

      descriptorMailer.setSmtpAuth(smtpEmail, "${smtpAuthPasswordSecret}")
      descriptorMailer.setReplyToAddress(smtpEmail)
      descriptorMailer.setSmtpHost(smtpHost)
      descriptorMailer.setUseSsl(true)
      descriptorMailer.setSmtpPort('465')
      descriptorMailer.setCharset('UTF-8')

      descriptorMailer.save()

      logger.info('Configured Mailer')
    }

    // setup master-slave security
    Thread.start {
      if (config.set_master_kill_switch != null) {
        def master_slave_security = {
          instance = 'Jenkins.instance',
          home = env['JENKINS_HOME'],
          disabled = config.set_master_kill_switch ->

          new File(home + 'secrets/filepath-filters.d').mkdirs()
          new File(home + 'secrets/filepath-filters.d/50-gui.conf').createNewFile()
          new File(home + 'secrets/whitelisted-callables.d').mkdirs()
          new File(home + 'secrets/whitelisted-callables.d/gui.conf').createNewFile()

          instance.getInjector().getInstance(jenkins.security.s2m.AdminWhitelistRule.class).setMasterKillSwitch(disabled)
        }
        logger.info('Enabled Master -> Slave Security')
      }
    }

    Thread.start {
      logger.info('--> setting agent port for jnlp')
      def env = System.getenv()
      int port = config.jnlp_port ?: env['JENKINS_SLAVE_AGENT_PORT'].toInteger() ?: 5001
      Jenkins.instance.setSlaveAgentPort(port)
      logger.info('--> setting agent port for jnlp... done')
    }

    Thread.start {
      sleep 5000
      if (Jenkins.instance.pluginManager.activePlugins.find { it.shortName == 'github-oauth' } != null) {

        String githubWebUri = env['GITHUB_WEB_URI'] ?: config.github.oauth.web_uri ?: 'https://github.com'
        String githubApiUri = env['GITHUB_API_URI'] ?: config.github.oauth.api_uri ?: 'https://api.github.com'
        String clientID = env['GITHUB_CLIENT_ID'] ?: config.github.oauth.client_id ?: 'someid'
        String clientSecret = env['GITHUB_CLIENT_SECRET'] ?: config.github.oauth.client_secret ?: 'somesecret'
        String oauthScopes = 'read:org'

        SecurityRealm github_realm = new GithubSecurityRealm(githubWebUri, githubApiUri, clientID, clientSecret, oauthScopes)
        //check for equality, no need to modify the runtime if no settings changed
        if (!github_realm.equals(Jenkins.instance.getSecurityRealm())) {
          Jenkins.instance.setSecurityRealm(github_realm)
          Jenkins.instance.save()
        }

        //----

        //permissions are ordered similar to web UI
        //Admin User Names
        String adminUserNames = env['JENKINS_ADMIN_USERNAME'] ?: config.admin.username ?: 'admin'
        //Participant in Organization
        String organizationNames = env['GITHUB_ORG'] ?: config.github.orgname ?: ''
        //Use Github repository permissions
        boolean useRepositoryPermissions = true
        //Grant READ permissions to all Authenticated Users
        boolean authenticatedUserReadPermission = false
        //Grant CREATE Job permissions to all Authenticated Users
        boolean authenticatedUserCreateJobPermission = false
        //Grant READ permissions for /github-webhook
        boolean allowGithubWebHookPermission = false
        //Grant READ permissions for /cc.xml
        boolean allowCcTrayPermission = false
        //Grant READ permissions for Anonymous Users
        boolean allowAnonymousReadPermission = false
        //Grant ViewStatus permissions for Anonymous Users
        boolean allowAnonymousJobStatusPermission = false

        AuthorizationStrategy github_authorization = new GithubAuthorizationStrategy(adminUserNames,
          authenticatedUserReadPermission,
          useRepositoryPermissions,
          authenticatedUserCreateJobPermission,
          organizationNames,
          allowGithubWebHookPermission,
          allowCcTrayPermission,
          allowAnonymousReadPermission,
          allowAnonymousJobStatusPermission)

        //check for equality, no need to modify the runtime if no settings changed
        if (!github_authorization.equals(Jenkins.instance.getAuthorizationStrategy())) {
          Jenkins.instance.setAuthorizationStrategy(github_authorization)
          logger.info('Saving Github authorisation strategy')

          Jenkins.instance.save()
        } else {
          logger.info('Github oauth plugin not found')
        }
      }
    }
  }
}
