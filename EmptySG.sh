# Simple script to query AWS for security groups not assigned to EC2 Instances, ELB, RDS, Groups named Default and email any output

#!/bin/bash

# Define Variables
RegionFile=regions.txt
DATE=$(date +"%d-%m-%Y")
OUTPUTDIR=/
OUTPUTFORMAT=text
FILEFORMAT=txt
Merge1=Merge1-$DATE
Merge2=Merge2-$DATE
Merge3=Merge3-$DATE
Merge4=Merge4-$DATE
 
SecGroupID=SecGroupID-$DATE
InsSecGroupID=InsSecGroupID-$DATE
ElbSecGroupID=ElbSecGroupID-$DATE
RDSSecGroupID=RDSSecGroupID-$DATE
SecGroupIDNonDefault=SecGroupIDNonDefault-$DATE
Email=Email-$DATE
EmailAddress=emailaddress@email.com
 
 
 
for line in $(cat $RegionFile)
do
    echo "$line : Checking for unused security group id's"
    aws ec2 describe-security-groups --region $line --query SecurityGroups[*].[GroupId] --output $OUTPUTFORMAT | tr \t \n | sort > $OUTPUTDIR/$line$SecGroupID.$FILEFORMAT
    # Gathering all EC2 Security Group ID's used by EC2 Instances
 
    aws ec2 describe-instances --region $line --query 'Reservations[*].Instances[*].SecurityGroups[*].[GroupId]' --output $OUTPUTFORMAT | tr '\t' '\n' | sort | uniq > $OUTPUTDIR/$line$InsSecGroupID.$FILEFORMAT
    comm -23 $OUTPUTDIR/$line$SecGroupID.$FILEFORMAT $OUTPUTDIR/$line$InsSecGroupID.$FILEFORMAT | xargs -I {} aws ec2 describe-security-groups --region $line --filters "Name=group-id,Values={}" --query 'SecurityGroups[*].[GroupId]' --output text >> $OUTPUTDIR/$line$Merge1.$FILEFORMAT
 
    # Gathering all EC2 Security Group ID's used against ELB
    aws elb describe-load-balancers --region $line --output json | jq -c -r ".LoadBalancerDescriptions[].SecurityGroups" | tr -d "\"[]\"" | sort | uniq > $OUTPUTDIR/$line$ElbSecGroupID.$FILEFORMAT
    comm -23 $OUTPUTDIR/$line$Merge1.$FILEFORMAT $OUTPUTDIR/$line$ElbSecGroupID.$FILEFORMAT | xargs -I {} aws ec2 describe-security-groups --region $line --filters "Name=group-id,Values={}" --query 'SecurityGroups[*].[GroupId]' --output text >> $OUTPUTDIR/$line$Merge2.$FILEFORMAT
 
    # Gathering all EC2 Security Group ID's used against RDS
    aws rds describe-db-instances --region $line --output json | jq -c -r ".DBInstances[].VpcSecurityGroups[].VpcSecurityGroupId" | sort | uniq > $OUTPUTDIR/$line$RDSSecGroupID.$FILEFORMAT
    comm -23 $OUTPUTDIR/$line$Merge2.$FILEFORMAT $OUTPUTDIR/$line$RDSSecGroupID.$FILEFORMAT | xargs -I {} aws ec2 describe-security-groups --region $line --filters "Name=group-id,Values={}" --query 'SecurityGroups[*].[GroupId]' --output text >> $OUTPUTDIR/$line$Merge3.$FILEFORMAT
 
  # Gathering all Security Groups without a Group Name of default
    aws ec2 describe-security-groups --region $line --query 'SecurityGroups[?GroupName==`default`].[GroupId]' --output $OUTPUTFORMAT | tr \t \n | sort > $OUTPUTDIR/$line$SecGroupIDNonDefault.$FILEFORMAT
    comm -23 $OUTPUTDIR/$line$Merge3.$FILEFORMAT $OUTPUTDIR/$line$SecGroupIDNonDefault.$FILEFORMAT | xargs -I {} aws ec2 describe-security-groups --region $line --filters "Name=group-id,Values={}" --query 'SecurityGroups[*].[GroupId]' --output text >> $OUTPUTDIR/$line$Merge4.$FILEFORMAT
 
    # Send Group ID's for deletion. Skip id's where an error occurs and output to a file.
    # cat $OUTPUTDIR/$Merge4.$FILEFORMAT | xargs -I {} aws ec2 --profile $AdminProfile delete-security-group --group-id {}
 
    # Emailing List of Security Groups to be investigated for deletion
    cat $OUTPUTDIR/$line$Merge4.$FILEFORMAT | xargs -I {} aws ec2 describe-security-groups --region $line --filters "Name=group-id,Values={}" --query 'SecurityGroups[*].[GroupName,GroupId,Description]' --output text >> $OUTPUTDIR/$line$Email.$FILEFORMAT
  if [ `ls -l $OUTPUTDIR/$line$Email.$FILEFORMAT | awk '{print $5}'` -eq 0 ]
    then
        echo "$line : No contents to email"
    else
            cat $OUTPUTDIR/$line$Email.$FILEFORMAT | mail -s "$line Security Group Cleanup" $EmailAddress
    fi
done
