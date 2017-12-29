@Grapes([
    @Grab(group='org.yaml', module='snakeyaml', version='1.17')
])

import org.yaml.snakeyaml.Yaml
import java.util.logging.Logger

env = System.getenv()
JENKINS_SETUP_YAML = env['JENKINS_SETUP_YAML'] ?: "${env['JENKINS_CONFIG_HOME']}/setup.yml"
Logger logger = Logger.getLogger('setup-jenkins-job-builder.groovy')
def config = new Yaml().load(new File(JENKINS_SETUP_YAML).text)

Thread.start {
    if (new File('/etc/jenkins_jobs/jenkins_jobs.ini').isFile()) {
        def admin_username = env['JENKINS_ADMIN_USERNAME'] ?: config.admin.username ?: 'admin'
        def admin_password = env['JENKINS_ADMIN_PASSWORD'] ?: config.admin.password ?: 'password'
        def web_port = env['JENKINS_WEB_PORT'] ?: config.web_port ?: 8080
        def jenkins_jobs_ini = """\
        [jenkins]
        user=${admin_username}
        password=${admin_password}
        url=http://127.0.0.1:${web_port}
        query_plugins_info=False
        """.stripIndent()
        new File('/etc/jenkins_jobs').mkdirs()
        new File('/etc/jenkins_jobs/jenkins_jobs.ini').write(jenkins_jobs_ini)
        logger.info('Configured jenkins-job-builder')
    }
}
