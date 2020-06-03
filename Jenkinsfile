pipeline {
    agent any

    environment {
        LANG = "en_US.UTF-8"
        LANGUAGE = "en_US.UTF-8"
        LC_ALL = "en_US.UTF-8"
        PATH = "PATH=$HOME/.rbenv/bin:$HOME/.rbenv/shims:/usr/local/bin/:$PATH"
    }

    stages {
        stage('env setup') {
            steps {
                script {
                    // CHANGE_ID is set only for pull requests, so it is safe to access the pullRequest global variable
                    if (env.CHANGE_ID) {
                        currentBuild.displayName = "PR #${pullRequest.number}: ${pullRequest.title}"
                    }
                }
                sh 'make setup'
            }
        }
        stage('build dependencies') {
            steps {
                sh 'make dependencies'
            }
        }
        stage('test') {
            steps {
                ansiColor('xterm') {
                    sh 'make test'
                }
            }
        }
    }

    post {
        success {
            script {
                // CHANGE_ID is set only for pull requests, so it is safe to access the pullRequest global variable
                if (env.CHANGE_ID) {
                    def comment = pullRequest.comment("👍 Build PASSED commit: ${pullRequest.head}\nbuild: ${currentBuild.absoluteUrl}")
                }
            }
        }

        failure {
            script {
                // CHANGE_ID is set only for pull requests, so it is safe to access the pullRequest global variable
                if (env.CHANGE_ID) {
                    def comment = pullRequest.comment("💥 Build FAILED commit: ${pullRequest.head}\nbuild: ${currentBuild.absoluteUrl}")
                }
            }
        }
    }
}
