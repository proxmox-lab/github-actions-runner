#cloud-config
output: { all: "| tee -a /var/log/cloud-init-output.log" }
preserve_hostname: false
manage_etc_hosts: false
fqdn: ${hostname}.${domain}
package_update: true
write_files:
  - path: /etc/amazon/ssm/seelog.xml
    encoding: text/plain
    owner: root:root
    permissions: '0644'
    content: |
      <!--amazon-ssm-agent uses seelog logging -->
      <!--Seelog has github wiki pages, which contain detailed how-tos references: https://github.com/cihub/seelog/wiki -->
      <!--Seelog examples can be found here: https://github.com/cihub/seelog-examples -->
      <seelog type="adaptive" mininterval="2000000" maxinterval="100000000" critmsgcount="500" minlevel="info">
          <exceptions>
              <exception filepattern="test*" minlevel="error"/>
          </exceptions>
          <outputs formatid="fmtinfo">
              <console formatid="fmtinfo"/>
              <rollingfile type="size" filename="/var/log/amazon/ssm/amazon-ssm-agent.log" maxsize="30000000" maxrolls="5"/>
              <filter levels="error,critical" formatid="fmterror">
                  <rollingfile type="size" filename="/var/log/amazon/ssm/errors.log" maxsize="10000000" maxrolls="5"/>
              </filter>
          </outputs>
          <formats>
              <format id="fmterror" format="%Date %Time %LEVEL [%FuncShort @ %File.%Line] %Msg%n"/>
              <format id="fmtdebug" format="%Date %Time %LEVEL [%FuncShort @ %File.%Line] %Msg%n"/>
              <format id="fmtinfo" format="%Date %Time %LEVEL %Msg%n"/>
          </formats>
      </seelog>
  - path: /opt/aws/amazon-cloudwatch-agent/etc/common-config.toml
    encoding: text/plain
    owner: root:root
    permissions: '0644'
    content: |
      [credentials]
      shared_credential_profile = "default"
      shared_credential_file = "/root/.aws/credentials"
  - path: /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
    encoding: text/plain
    owner: root:root
    permissions: '0644'
    content: |
      {
        "metrics": {
          "namespace": "MANAGED-INSTANCE-EXAMPLE",
          "metrics_collected": {
            "cpu": {
              "resources": [
                "*"
              ],
              "measurement": [
                "cpu_usage_idle",
                "cpu_usage_nice",
                "cpu_usage_guest"
              ],
              "metrics_collection_interval": 10
            },
            "netstat": {
              "measurement": [
                "tcp_established",
                "tcp_syn_sent",
                "tcp_close"
              ],
              "metrics_collection_interval": 60
            },
            "disk": {
              "measurement": [
                "used_percent"
              ],
              "resources": [
                "*"
              ]
            },
            "processes": {
              "measurement": [
                "blocked",
                "dead",
                "idle",
                "paging",
                "stopped",
                "total",
                "total_threads",
                "wait",
                "zombies",
                "running",
                "sleeping"
              ],
              "metrics_collection_interval": 10
            }
          }
        },
        "logs": {
          "logs_collected": {
            "files": {
              "collect_list": [
                {
                  "file_path": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
                  "log_group_name": "${log_group_name}",
                  "log_stream_name": "amazon-cloudwatch-agent.log"
                },
                {
                  "file_path": "/var/log/messages",
                  "log_group_name": "${log_group_name}",
                  "log_stream_name": "syslog"
                }
              ]
            }
          },
          "force_flush_interval": 15
        }
      }
  - path: /root/ca.crt
    encoding: text/plain
    owner: root:root
    permissions: '0600'
    content: |
      ${tlscacert}
  - path: /root/server.crt
    encoding: text/plain
    owner: root:root
    permissions: '0600'
    content: |
      ${tlscert}
  - path: /root/server.key
    encoding: text/plain
    owner: root:root
    permissions: '0600'
    content: |
      ${tlskey}
salt_minion:
  pkg_name: 'salt-minion'
  service_name: 'salt-minion'
  config_dir: '/etc/salt'
  conf:
    master: ${saltmaster}
    id: ${hostname}
    startup_states: highstate
    log_level: info
    log_level_logfile: info
    saltenv: ${salt_environment}
    pillarenv_from_saltenv: True
  grains:
    roles:
      - github-actions-runner
      - docker
runcmd:
  - echo "*******************************************************************************"
  - echo "Configuring the AWS CLI..."
  - echo "*******************************************************************************"
  - aws configure set region ${region}
  - aws configure set aws_access_key_id ${aws_access_key_id}
  - aws configure set aws_secret_access_key ${aws_secret_access_key}
  - aws configure set aws_session_token ${aws_session_token}
  - echo "*******************************************************************************"
  - echo "Configuring the AWS SSM Agent..."
  - echo "*******************************************************************************"
  - systemctl stop amazon-ssm-agent
  - read activation_id activation_code <<<$(echo $(aws ssm create-activation --default-instance-name "${hostname}" --description "${description}" --iam-role ${role} --registration-limit 1 --region ${region} --tags ${tags} | jq -r '.ActivationId, .ActivationCode'))
  - amazon-ssm-agent -register -code $activation_code -id $activation_id -region ${region}
  - systemctl start amazon-ssm-agent
  - echo "*******************************************************************************"
  - echo "Restart the AWS CloudWatch Agent..."
  - echo "*******************************************************************************"
  - systemctl restart amazon-cloudwatch-agent
  - echo "*******************************************************************************"
  - echo "User Data Script Execution Complete"
  - echo "*******************************************************************************"
