#!/bin/bash -ex
##
# Command to get path-id: aws --region us-west-2 servicecatalog list-launch-paths --product-id prod-zthu3k3c26ziq
# Command to get provisioning-artifacts-id: aws --region us-west-2 servicecatalog list-provisioning-artifacts --product-id prod-zthu3k3c26ziq
##
PROCESSING_ENVIRONMENT=$1
AWS_DEFAULT_REGION=us-west-2
NAME_SUFFIX=${GIT_COMMIT:0:8}
METRICS_VERSION=$(cat pom.xml | grep \<metrics.version | awk -F '>' '{ print $2 }' | awk -F '<' '{ print $1 }')
EMR_VERSION=emr-1.8.2
APP=bp-features
SHORT_ENVIRONMENT=${PROCESSING_ENVIRONMENT#*-}
PREFIX=bp-features-${SHORT_ENVIRONMENT}
CONF_SUFFIX=${SHORT_ENVIRONMENT#*-}
COMMIT=${GIT_COMMIT:0:8}
PROFILE=${SHORT_ENVIRONMENT}
UI_SG_NAME=bastion-to-emrUI-${PREFIX}
EFS_NAME=efs-emr-checkpoint-${PREFIX}

# I do not like this and I do not want to talk about it
CONFIGURATIONS=$(cat <<-EOF
  [{
    "Classification": "spark",
    "ConfigurationProperties": {
        "spark.ssl.enabled": "true",
        "spark.ssl.protocol" : "TLSv1.2",
        "spark.history.fs.cleaner.maxAge": "2h",
        "spark.history.fs.cleaner.interval": "3h",
        "spark.history.fs.cleaner.enabled": "true"
      }
    }]
EOF
)
CONFIGURATIONS=$(echo ${CONFIGURATIONS} | sed 's/"/\\"/g')

# ====================EMR Scaling====================

DESIRED_EXECUTOR_COUNT=415
NUMBER_OF_EXECUTOR_CORES_STREAM=1
INSTANCE_COUNT=52
EXECUTOR_MEMORY_STREAM=2
STREAMING_SHUFFLE_PARTITIONS=20
INSTANCE_TYPE="m5.2xlarge"

NUMBER_OF_EXECUTOR_CORES_BATCH=4
EXECUTOR_MEMORY_BATCH=10
BATCH_SHUFFLE_PARTITIONS=10

# ====================EMR Scaling====================

if [ "${PROCESSING_ENVIRONMENT}" == "processing-cdo-dev" ]; then
  KEY_PAIR="terraform-example-key"
  VPC_ID=vpc-837e56fa
  EMR_RDS_SG=sg-0bf0bd51cda1f4f4c
  EMR_EFS_SG=sg-07a80b4bbeba29e81
  KAFKA_SSL_TRUSTSTORE_IDPS_ENDPOINT="BletchleyPark-PRE-PRODUCTION-NXUFCU.pd.idps.a.intuit.com"
  KAFKA_SSL_TRUSTSTORE_IDPS_POLICY_ID="p-7fihiwdqbgnk"
  PRODUCT_ID="prod-zthu3k3c26ziq"
  PROVISIONIONG_ARTIFACT_ID="pa-jnycfmbmg6h2o"
  SUBNETS="subnet-092c71e25898eb825,subnet-0065cd8fc12538fc2,subnet-0c6b24a19df350955"
  BOOTSTRAPARGS1="${SHORT_ENVIRONMENT} ${KAFKA_SSL_TRUSTSTORE_IDPS_ENDPOINT} ${KAFKA_SSL_TRUSTSTORE_IDPS_POLICY_ID}"
  BOOTSTRAPARGS4="${METRICS_VERSION} ${PROCESSING_ENVIRONMENT} ${COMMIT}"
elif [ "${PROCESSING_ENVIRONMENT}" == "processing-cdo-qa" ]; then
  KEY_PAIR="terraform-example-key"
  VPC_ID=vpc-bd3631c4
  EMR_RDS_SG=sg-050e4365ad6db4f36
  EMR_EFS_SG=sg-0237bf13b8c9c9ef0
  KAFKA_SSL_TRUSTSTORE_IDPS_ENDPOINT="BletchleyPark-PRE-PRODUCTION-NXUFCU.pd.idps.a.intuit.com"
  KAFKA_SSL_TRUSTSTORE_IDPS_POLICY_ID="p-7fihiwdqbgnk"
  PRODUCT_ID="prod-5q65hnfbnpzji"
  PROVISIONIONG_ARTIFACT_ID="pa-mqndlhvrbpu2q"
  SUBNETS="subnet-09c15b70,subnet-7957d332,subnet-1411634e"
  BOOTSTRAPARGS1="${SHORT_ENVIRONMENT} ${KAFKA_SSL_TRUSTSTORE_IDPS_ENDPOINT} ${KAFKA_SSL_TRUSTSTORE_IDPS_POLICY_ID}"
  BOOTSTRAPARGS4="${METRICS_VERSION} ${PROCESSING_ENVIRONMENT} ${COMMIT}"
elif [ "${PROCESSING_ENVIRONMENT}" == "processing-cdo-e2e" ]; then
  KEY_PAIR="terraform-example-key"
  VPC_ID=vpc-bf3e3fc6
  EMR_RDS_SG=sg-05f0718ab6f5fdc6a
  EMR_EFS_SG=sg-09e60f35587c64646
  KAFKA_SSL_TRUSTSTORE_IDPS_ENDPOINT="BletchleyPark-PRE-PRODUCTION-NXUFCU.pd.idps.a.intuit.com"
  KAFKA_SSL_TRUSTSTORE_IDPS_POLICY_ID="p-7fihiwdqbgnk"
  PRODUCT_ID="prod-3ymh6pazm4y22"
  PROVISIONIONG_ARTIFACT_ID="pa-35n2kwdlfuxt4"
  SUBNETS="subnet-0ceb850b7dc9741ab,subnet-0832e1f6012506019,subnet-01470b35acdb7623f"
  BOOTSTRAPARGS1="${SHORT_ENVIRONMENT} ${KAFKA_SSL_TRUSTSTORE_IDPS_ENDPOINT} ${KAFKA_SSL_TRUSTSTORE_IDPS_POLICY_ID}"
  BOOTSTRAPARGS4="${METRICS_VERSION} ${PROCESSING_ENVIRONMENT} ${COMMIT}"
elif [ "${PROCESSING_ENVIRONMENT}" == "processing-cdo-prd" ]; then
  KEY_PAIR="cdo-prod-emr"
  VPC_ID=vpc-370f274e
  EMR_RDS_SG=sg-04a282b5a32b63089
  EMR_EFS_SG=sg-01e9c85a934511117
  KAFKA_SSL_TRUSTSTORE_IDPS_ENDPOINT="Infostore-PRODUCTION-K0MZEO.pd.idps.a.intuit.com"
  KAFKA_SSL_TRUSTSTORE_IDPS_POLICY_ID="p-uojsu7hciezb"
  PRODUCT_ID="prod-m4fra22raxjgs"
  PROVISIONIONG_ARTIFACT_ID="pa-masuurdoqkvqk"
  SUBNETS="subnet-70d5603b,subnet-8d39b1f4,subnet-c195f89b"
  BOOTSTRAPARGS1="${SHORT_ENVIRONMENT} ${KAFKA_SSL_TRUSTSTORE_IDPS_ENDPOINT} ${KAFKA_SSL_TRUSTSTORE_IDPS_POLICY_ID}"
  BOOTSTRAPARGS4="${METRICS_VERSION} ${PROCESSING_ENVIRONMENT} ${COMMIT}"
fi

EFS_ID=$(aws --profile ${PROFILE} \
          --region ${AWS_DEFAULT_REGION} \
          efs describe-file-systems  | \
          jq -r '.FileSystems[] | "\(.Name) \(.FileSystemId)"' | \
          grep ${EFS_NAME} | cut -d " " -f2)

UI_SG=$(aws --profile ${PROFILE} \
            --region ${AWS_DEFAULT_REGION} \
            ec2 describe-security-groups \
            --filters Name=vpc-id,Values=${VPC_ID} \
            --filters Name=group-name,Values=${UI_SG_NAME} \
            --query "SecurityGroups[0].GroupId" \
            --output text)

PROVISIONING_PARAMS=$( cat <<-EOF
  {
    "Key": "EMRName",
    "Value": "${PREFIX}-${NAME_SUFFIX}"
  },
  {
    "Key": "Application0",
    "Value": "Spark"
  },
  {
    "Key": "EMRS3LogPath",
    "Value": "s3://bpark-emr-logs-us-west-2-${PROCESSING_ENVIRONMENT}"
  },
  {
    "Key": "MasterInstanceType",
    "Value": "m5.xlarge"
  },
  {
    "Key": "CoreInstanceType",
    "Value": "${INSTANCE_TYPE}"
  },
  {
    "Key": "CoreInstanceCount",
    "Value": "${INSTANCE_COUNT}"
  },
  {
    "Key": "EMRInstanceKey",
    "Value": "${KEY_PAIR}"
  },
  {
    "Key": "MasterEbsVolumeSizeGB",
    "Value": "1000"
  },
  {
    "Key": "CoreEbsVolumeSizeGB",
    "Value": "1000"
  },
  {
    "Key": "EMRApplicationRole",
    "Value": "emr-ec2-profile-bpark-${PROCESSING_ENVIRONMENT}"
  },
  {
    "Key": "BootstrapPath1",
    "Value": "s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/scripts/generate_jks.sh"
  },
  {
    "Key": "BootstrapArgs1",
    "Value": "${BOOTSTRAPARGS1}"
  },
  {
    "Key": "BootstrapPath2",
    "Value": "s3://idl-sched-uw2-${PROCESSING_ENVIRONMENT}/artifacts/emr/${EMR_VERSION}/scripts/bash/revert_ssh_restriction.sh"
  },
  {
    "Key": "BootstrapPath3",
    "Value": "s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/scripts/mount_efs.sh"
  },
  {
    "Key": "BootstrapArgs3",
    "Value": "${EFS_ID}"
  },
  {
    "Key": "BootstrapPath4",
    "Value": "s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/scripts/copy_metrics_jar_local.sh"
  },
  {
    "Key": "BootstrapArgs4",
    "Value": "${BOOTSTRAPARGS4}"
  },
  {
    "Key": "MasterSecurityGroup1",
    "Value": "${EMR_RDS_SG}"
  },
  {
    "Key": "SlaveSecurityGroup1",
    "Value": "${EMR_RDS_SG}"
  },
  {
    "Key": "MasterSecurityGroup2",
    "Value": "${EMR_EFS_SG}"
  },
  {
    "Key": "SlaveSecurityGroup2",
    "Value": "${EMR_EFS_SG}"
  },
  {
    "Key": "MasterSecurityGroup3",
    "Value": "${UI_SG}"
  },
  {
    "Key": "SlaveSecurityGroup3",
    "Value": "${UI_SG}"
  },
  {
    "Key": "CustomSubnetId",
    "Value": "${SUBNETS}"
  },
  {
    "Key": "CustomVPNSubnetId",
    "Value": "${SUBNETS}"
  },
  {
    "Key": "Configurations",
    "Value": "${CONFIGURATIONS}"
  },
  {
    "Key": "MonitoringEnabled",
    "Value": "True"
  }  
EOF
)

TAGS=$( cat <<-EOF
  {
    "Key": "Name",
    "Value": "${PREFIX}"
  },
  {
    "Key": "env",
    "Value": "${SHORT_ENVIRONMENT}"
  },
  {
    "Key": "emr_version",
    "Value": "${EMR_VERSION}"
  },
  {
    "Key": "bu",
    "Value": "cdo"
  },
  {
    "Key": "app",
    "Value": "${APP}"
  },
  {
    "Key": "commitId",
    "Value": "${COMMIT}"
  }
EOF
)

EMR_FP_COMMAND="aws servicecatalog provision-product \
                  --profile ${PROFILE} \
                  --product-id ${PRODUCT_ID} \
                  --provisioning-artifact-id ${PROVISIONIONG_ARTIFACT_ID} \
                  --region ${AWS_DEFAULT_REGION} \
                  --provisioned-product-name ${PREFIX}-${NAME_SUFFIX} \
                  --provision-token ${PREFIX}-${NAME_SUFFIX} \
                  --tags '[${TAGS}]' \
                  --provisioning-parameters '[${PROVISIONING_PARAMS}]'"

echo $EMR_FP_COMMAND

echo "Going into loop to check EMR Feature Processor cluster deployment status"
while [ "$(eval ${EMR_FP_COMMAND} | jq '.RecordDetail.Status')" != "\"SUCCEEDED\"" ]; do
  if [ "$(eval ${EMR_FP_COMMAND} | jq '.RecordDetail.Status')" == "\"FAILED\"" ]; then
    echo "EMR Feature Processor Deploy Status failed check EMR console for reason"
    exit 1
  fi
  echo "Status is neither Success nor Failure, sleeping for 30 seconds and looping."
  sleep 30
done

EMR_FP_CLUSTER_ID=$(aws --profile ${PROFILE} emr list-clusters | jq -r '.Clusters[] | "\(.Name) \(.Id)"' | grep ${PREFIX}-${NAME_SUFFIX} | cut -d " " -f2)
echo "Successfully deployed EMR Feature Processor Cluster ID: ${EMR_FP_CLUSTER_ID}"

#Create CloudWatch Alarm
Alarm=`aws cloudwatch put-metric-alarm --alarm-name "EMR_appsFailed" --alarm-description "The default example alarm" --namespace "AWS/Elastic­Map­Reduce" --metric-name Apps­Failed --statistic Average --period 60 --evaluation-periods 5 --threshold 50 --comparison-operator GreaterThanOrEqualToThreshold --dimensions  Name=JobFlowId,Value=${EMR_FP_CLUSTER_ID --alarm-actions <sns-topic-id> --unit Percent`


# Call clean up scripts
./scripts/cleanup_cf_stacks.sh "$PROFILE" "$PREFIX" "$NAME_SUFFIX"

echo "Running add-steps for feature processor cluster"
if [ "${PROCESSING_ENVIRONMENT}" == "processing-cdo-dev" ]; then
  ADD_STEPS=$(aws --profile ${PROFILE} emr add-steps \
    --cluster-id ${EMR_FP_CLUSTER_ID} \
    --steps Type=spark,Name=BletchleyPark-ATO-Batch-App,MainClass=com.intuit.aiml.bpark.app.DriverApp,Args=[--master,yarn,--deploy-mode,cluster,--driver-memory,10g,--num-executors,${DESIRED_EXECUTOR_COUNT},--executor-cores,${NUMBER_OF_EXECUTOR_CORES_BATCH},--executor-memory,${EXECUTOR_MEMORY_BATCH}g,--packages,org.apache.spark:spark-sql-kafka-0-10_2.11:2.3.0,--class,com.intuit.aiml.bpark.app.DriverApp,--files,"s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/emr-jars/ato-metrics-confs/${COMMIT}/metrics-batch-${CONF_SUFFIX}.conf\\,s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/emr-jars/ato-metrics-confs/${COMMIT}/metrics-kafka-${CONF_SUFFIX}.conf",--conf,"spark.sql.shuffle.partitions=${BATCH_SHUFFLE_PARTITIONS}",--conf,"spark.metrics.conf=metrics-batch-${CONF_SUFFIX}.conf",--conf,"spark.executor.extraClassPath=/opt/spark-metrics.jar",--conf,"spark.sql.streaming.metricsEnabled=true",--conf,"spark.metrics.namespace=ato-batch-${CONF_SUFFIX}",--conf,"spark.driver.maxResultSize=4g",--conf,"spark.executor.extraJavaOptions=-Denv=cdo-dev -XX:+UseG1GC -XX:+PrintFlagsFinal -XX:+PrintReferenceGC -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintAdaptiveSizePolicy -XX:+UnlockDiagnosticVMOptions -XX:+G1SummarizeConcMark -XX:InitiatingHeapOccupancyPercent=35 -XX:ConcGCThreads=5",--conf,"spark.driver.extraJavaOptions=-Denv=cdo-dev -XX:+UseG1GC -XX:+PrintFlagsFinal -XX:+PrintReferenceGC -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintAdaptiveSizePolicy -XX:+UnlockDiagnosticVMOptions -XX:+G1SummarizeConcMark -XX:InitiatingHeapOccupancyPercent=35 -XX:ConcGCThreads=5",s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/emr-jars/bletchleypark-features-${COMMIT}.jar,--mode,incremental,--appConf,ato-batch-dev.conf,--featureConf,ato-features.conf],ActionOnFailure=CANCEL_AND_WAIT \
    Type=spark,Name=BletchleyPark-ATO-Stream-App,MainClass=com.intuit.aiml.bpark.app.DriverApp,Args=[--master,yarn,--deploy-mode,cluster,--driver-memory,10g,--num-executors,${DESIRED_EXECUTOR_COUNT},--executor-cores,${NUMBER_OF_EXECUTOR_CORES_STREAM},--executor-memory,${EXECUTOR_MEMORY_STREAM}g,--packages,org.apache.spark:spark-sql-kafka-0-10_2.11:2.3.0,--class,com.intuit.aiml.bpark.app.DriverApp,--files,"s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/emr-jars/ato-metrics-confs/${COMMIT}/metrics-stream-${CONF_SUFFIX}.conf\\,s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/emr-jars/ato-metrics-confs/${COMMIT}/metrics-kafka-${CONF_SUFFIX}.conf",--conf,"spark.sql.shuffle.partitions=${STREAMING_SHUFFLE_PARTITIONS}",--conf,"spark.metrics.conf=metrics-stream-${CONF_SUFFIX}.conf",--conf,"spark.executor.extraClassPath=/opt/spark-metrics.jar",--conf,"spark.sql.streaming.metricsEnabled=true",--conf,"spark.metrics.namespace=ato-stream-${CONF_SUFFIX}",--conf,"spark.driver.maxResultSize=4g",--conf,"spark.executor.extraJavaOptions=-Denv=cdo-dev -XX:+UseG1GC -XX:+PrintFlagsFinal -XX:+PrintReferenceGC -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintAdaptiveSizePolicy -XX:+UnlockDiagnosticVMOptions -XX:+G1SummarizeConcMark -XX:InitiatingHeapOccupancyPercent=35 -XX:ConcGCThreads=5",--conf,"spark.driver.extraJavaOptions=-Denv=cdo-dev -XX:+UseG1GC -XX:+PrintFlagsFinal -XX:+PrintReferenceGC -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintAdaptiveSizePolicy -XX:+UnlockDiagnosticVMOptions -XX:+G1SummarizeConcMark -XX:InitiatingHeapOccupancyPercent=35 -XX:ConcGCThreads=5",s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/emr-jars/bletchleypark-features-${COMMIT}.jar,--mode,stream,--appConf,ato-stream-dev.conf,--featureConf,ato-features.conf],ActionOnFailure=CANCEL_AND_WAIT | jq -r ".StepIds[0]")
elif [ "${PROCESSING_ENVIRONMENT}" == "processing-cdo-qa" ]; then
  ADD_STEPS=$(aws --profile ${PROFILE} emr add-steps \
    --cluster-id ${EMR_FP_CLUSTER_ID} \
    --steps Type=spark,Name=BletchleyPark-ATO-Stream-App,MainClass=com.intuit.aiml.bpark.app.DriverApp,Args=[--master,yarn,--deploy-mode,cluster,--driver-memory,10g,--num-executors,${DESIRED_EXECUTOR_COUNT},--executor-cores,${NUMBER_OF_EXECUTOR_CORES_STREAM},--executor-memory,${EXECUTOR_MEMORY_STREAM}g,--packages,org.apache.spark:spark-sql-kafka-0-10_2.11:2.3.0,--class,com.intuit.aiml.bpark.app.DriverApp,--files,"s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/emr-jars/ato-metrics-confs/${COMMIT}/metrics-stream-${CONF_SUFFIX}.conf\\,s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/emr-jars/ato-metrics-confs/${COMMIT}/metrics-kafka-${CONF_SUFFIX}.conf",--conf,"spark.sql.shuffle.partitions=${STREAMING_SHUFFLE_PARTITIONS}",--conf,"spark.metrics.conf=metrics-stream-${CONF_SUFFIX}.conf",--conf,"spark.executor.extraClassPath=/opt/spark-metrics.jar",--conf,"spark.sql.streaming.metricsEnabled=true",--conf,"spark.metrics.namespace=ato-stream-${CONF_SUFFIX}",--conf,"spark.driver.maxResultSize=4g",--conf,"spark.executor.extraJavaOptions=-Denv=cdo-qa -XX:+UseG1GC -XX:+PrintFlagsFinal -XX:+PrintReferenceGC -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintAdaptiveSizePolicy -XX:+UnlockDiagnosticVMOptions -XX:+G1SummarizeConcMark -XX:InitiatingHeapOccupancyPercent=35 -XX:ConcGCThreads=5",--conf,"spark.driver.extraJavaOptions=-Denv=cdo-qa -XX:+UseG1GC -XX:+PrintFlagsFinal -XX:+PrintReferenceGC -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintAdaptiveSizePolicy -XX:+UnlockDiagnosticVMOptions -XX:+G1SummarizeConcMark -XX:InitiatingHeapOccupancyPercent=35 -XX:ConcGCThreads=5",s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/emr-jars/bletchleypark-features-${COMMIT}.jar,--mode,stream,--appConf,ato-stream-qa.conf,--featureConf,ato-features.conf],ActionOnFailure=CANCEL_AND_WAIT | jq -r ".StepIds[0]")
elif [ "${PROCESSING_ENVIRONMENT}" == "processing-cdo-e2e" ]; then
  ADD_STEPS=$(aws --profile ${PROFILE} emr add-steps \
    --cluster-id ${EMR_FP_CLUSTER_ID} \
    --steps Type=spark,Name=BletchleyPark-ATO-Stream-App,MainClass=com.intuit.aiml.bpark.app.DriverApp,Args=[--master,yarn,--deploy-mode,cluster,--driver-memory,10g,--num-executors,${DESIRED_EXECUTOR_COUNT},--executor-cores,${NUMBER_OF_EXECUTOR_CORES_STREAM},--executor-memory,${EXECUTOR_MEMORY_STREAM}g,--packages,org.apache.spark:spark-sql-kafka-0-10_2.11:2.3.0,--class,com.intuit.aiml.bpark.app.DriverApp,--files,"s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/emr-jars/ato-metrics-confs/${COMMIT}/metrics-stream-${CONF_SUFFIX}.conf\\,s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/emr-jars/ato-metrics-confs/${COMMIT}/metrics-kafka-${CONF_SUFFIX}.conf",--conf,"spark.sql.shuffle.partitions=${STREAMING_SHUFFLE_PARTITIONS}",--conf,"spark.metrics.conf=metrics-stream-${CONF_SUFFIX}.conf",--conf,"spark.executor.extraClassPath=/opt/spark-metrics.jar",--conf,"spark.sql.streaming.metricsEnabled=true",--conf,"spark.metrics.namespace=ato-stream-${CONF_SUFFIX}",--conf,"spark.driver.maxResultSize=4g",--conf,"spark.executor.extraJavaOptions=-Denv=cdo-e2e -XX:+UseG1GC -XX:+PrintFlagsFinal -XX:+PrintReferenceGC -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintAdaptiveSizePolicy -XX:+UnlockDiagnosticVMOptions -XX:+G1SummarizeConcMark -XX:InitiatingHeapOccupancyPercent=35 -XX:ConcGCThreads=5",--conf,"spark.driver.extraJavaOptions=-Denv=cdo-e2e -XX:+UseG1GC -XX:+PrintFlagsFinal -XX:+PrintReferenceGC -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintAdaptiveSizePolicy -XX:+UnlockDiagnosticVMOptions -XX:+G1SummarizeConcMark -XX:InitiatingHeapOccupancyPercent=35 -XX:ConcGCThreads=5",s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/emr-jars/bletchleypark-features-${COMMIT}.jar,--mode,stream,--appConf,ato-stream-e2e.conf,--featureConf,ato-features.conf],ActionOnFailure=CANCEL_AND_WAIT | jq -r ".StepIds[0]")
elif [ "${PROCESSING_ENVIRONMENT}" == "processing-cdo-prd" ]; then
  ADD_STEPS=$(aws --profile ${PROFILE} emr add-steps \
    --cluster-id ${EMR_FP_CLUSTER_ID} \
    --steps Type=spark,Name=BletchleyPark-ATO-Stream-App,MainClass=com.intuit.aiml.bpark.app.DriverApp,Args=[--master,yarn,--deploy-mode,cluster,--driver-memory,10g,--num-executors,${DESIRED_EXECUTOR_COUNT},--executor-cores,${NUMBER_OF_EXECUTOR_CORES_STREAM},--executor-memory,${EXECUTOR_MEMORY_STREAM}g,--packages,org.apache.spark:spark-sql-kafka-0-10_2.11:2.3.0,--class,com.intuit.aiml.bpark.app.DriverApp,--files,"s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/emr-jars/ato-metrics-confs/${COMMIT}/metrics-stream-${CONF_SUFFIX}.conf\\,s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/emr-jars/ato-metrics-confs/${COMMIT}/metrics-kafka-${CONF_SUFFIX}.conf",--conf,"spark.sql.shuffle.partitions=${STREAMING_SHUFFLE_PARTITIONS}",--conf,"spark.metrics.conf=metrics-stream-${CONF_SUFFIX}.conf",--conf,"spark.executor.extraClassPath=/opt/spark-metrics.jar",--conf,"spark.sql.streaming.metricsEnabled=true",--conf,"spark.metrics.namespace=ato-stream-${CONF_SUFFIX}",--conf,"spark.driver.maxResultSize=4g",--conf,"spark.executor.extraJavaOptions=-Denv=cdo-prd -XX:+UseG1GC -XX:+PrintFlagsFinal -XX:+PrintReferenceGC -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintAdaptiveSizePolicy -XX:+UnlockDiagnosticVMOptions -XX:+G1SummarizeConcMark -XX:InitiatingHeapOccupancyPercent=35 -XX:ConcGCThreads=5",--conf,"spark.driver.extraJavaOptions=-Denv=cdo-prd -XX:+UseG1GC -XX:+PrintFlagsFinal -XX:+PrintReferenceGC -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintAdaptiveSizePolicy -XX:+UnlockDiagnosticVMOptions -XX:+G1SummarizeConcMark -XX:InitiatingHeapOccupancyPercent=35 -XX:ConcGCThreads=5",s3://ssh-bpark-us-west-2-${PROCESSING_ENVIRONMENT}/emr-jars/bletchleypark-features-${COMMIT}.jar,--mode,stream,--appConf,ato-stream-prd.conf,--featureConf,ato-features.conf],ActionOnFailure=CANCEL_AND_WAIT | jq -r ".StepIds[0]")
fi
echo "Submitted step at ${ADD_STEPS}"
