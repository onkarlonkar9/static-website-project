pipeline {
    agent any

    environment {
        TF_DIR = "terraform"          
        AWS_REGION = "us-east-1"    
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Generate Version') {
            steps {
                script {
                    COMMIT = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()

                    writeFile file: "${TF_DIR}/override.tfvars", text: """
site_ref = "${COMMIT}"
alert_email = "onkar@gmail.com"
"""

                    env.TF_VAR_site_ref = COMMIT
                }
            }
        }

        stage('Terraform Init') {
            steps {
                dir("${TF_DIR}") {
                    sh "terraform init -input=false"
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                dir("${TF_DIR}") {
                    sh "terraform plan -var-file=override.tfvars -out=tfplan -input=false"
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir("${TF_DIR}") {
                    sh "terraform apply -input=false tfplan"
                }
            }
        }

        stage('Validate Deployment') {
            steps {
                script {
                    echo "Validating ASG Deployment..."

                    sh "aws autoscaling describe-auto-scaling-groups --region ${AWS_REGION}"
                    
                    echo 'Checking EC2 Instances...'
                    sh "aws ec2 describe-instances --region ${AWS_REGION} --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress]' --output table"

                    echo 'Deployment successful!'
                }
            }
        }

        stage('Load Test (Optional)') {
            when {
                expression { return false }
            }
            steps {
                script {
                    echo "Run load test AFTER ALB is enabled in AWS."
                }
            }
        }
    }

    post {
        failure {
            echo "Pipeline failed!"
        }
        success {
            echo "Deployment successful!"
        }
    }
}

