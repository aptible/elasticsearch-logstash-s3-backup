# ![](https://gravatar.com/avatar/11d3bc4c3163e3d238d558d5c9d98efe?s=64) aptible/elasticsearch-logstash-s3-backup

An Aptible app that periodically archives older Logstash indexes from an
Elasticsearch database. Indexes named in the standard logstash convention
(`logstash-YYYY.MM.DD`) are archived daily based on their age, keeping a
configurable number of the most recent indexes live. Each index is backed
up over HTTPS and encrypted using AWS server-side encryption to its own
Elasticsearch snapshot in your S3 snapshot repository. 

Added new feature to backup multiple indices, added slack notification feature.

## Installation

Recommended setup for running as an app on Aptible:

 1. Create an S3 bucket for your logs in the same region as your Elasticsearch
    database.

 2. Create an IAM user to run the backup and restore. Give your IAM user
    permission to read/write from the bucket you created in step 2. The
    elasticsearch-cloud-aws plugin documentation has [instructions on setting
    up these permissions](https://github.com/elastic/elasticsearch-cloud-aws/tree/v2.5.1/#recommended-s3-permissions);
    adding the following as an inline custom policy should be sufficient
    (replace `BUCKET_NAME` with the name of your S3 bucket):

    ```
    {
        "Statement": [
            {
                "Action": [
                    "s3:ListBucket",
                    "s3:GetBucketLocation",
                    "s3:ListBucketMultipartUploads",
                    "s3:ListBucketVersions"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::MY_BUCKET_NAME"
                ]
            },
            {
                "Action": [
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:AbortMultipartUpload",
                    "s3:ListMultipartUploadParts"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::MY_BUCKET_NAME/*"
                ]
            }
        ],
        "Version": "2012-10-17"
    }

    ```

 3. Create an app in your Aptible account for the cron. You can do this through
    the [Aptible dashboard](https://dashboard.aptible.com) or using the
    [Aptible CLI](https://github.com/aptible/aptible-cli):

    ```
    aptible apps:create YOUR_APP_HANDLE
    ```

    In the steps that follow, we'll use &lt;YOUR_APP_HANDLE&gt; anywhere that
    you should substitute the actual app handle you've specified in this step.

 4. Set the following environment variables in your app's configuration:

     * `DATABASE_URL`: Your Elasticsearch URL.
     * `S3_BUCKET`: Your S3 Bucket name.
     * `S3_BUCKET_BASE_PATH`: Destination path within bucket (Optional)
     * `S3_ACCESS_KEY_ID`: The access key you generated in step 3.
     * `S3_SECRET_ACCESS_KEY`: The secret key you generated in step 3.
     * `INDEX_ARRAY`: array of indices, INDEX_ARRAY="logstash nginx", separated with white space 
     * `SLACK_HOOK`: slack webhook url (optional)
     * `SLACK_CHANNEL,SLACK_USER,SLACK_EMO`: optional variables for slack configuration

    You may also wish to override any of the following optional environment
    variables:

     * `MAX_DAYS_TO_KEEP`: The number of days of live logstash indexes you'd
       like to keep in your Elasticsearch instance. Any indexes from before this
       point will be archived by the cron. Defaults to 30.
     * `CRON_SCHEDULE`: The schedule for your backups. Defaults to "0 2 * * *",
       which runs nightly at 2 A.M. Make sure to escape any asterisks when
       setting this variable from the command line to avoid shell expansion.
     * `S3_REGION`: The region your Elasticsearch instance and S3 bucket live in.
       Defaults to `us-east-1`.
     * `REPOSITORY_NAME`: The name of your Elasticsearch snapshot repo. This is
       the handle you can use in Elasticsearch to perform operations on your
       snapshot repo. Defaults to "logstash-snapshots".
     * `WAIT_SECONDS`: Number of seconds to wait on an index archive to succeed
       after the request has been made. Defaults to 1800.

    Environment variables can be set using the Aptible CLI, for example:

    ```
    aptible config:set  --app YOUR_APP_HANDLE NAME=VALUE OTHER_NAME=OTHER_VALUE
    ```

 5. Clone this repository and push it to your Aptible app:

    ```
    git clone https://github.com/aptible/elasticsearch-logstash-s3-backup.git
    cd elasticsearch-logstash-s3-backup
    git remote add aptible git@beta.aptible.com:<YOUR_APP_HANDLE>.git
    git push aptible master
    ```

## Notes

The cron run by this app will execute daily and log its progress to stdout.

To test the backup or run it manually, use the Aptible CLI to run the
`backup-all-indexes.sh` script in a container over SSH:

```
aptible ssh --app YOUR_APP_HANDLE ./backup-all-indexes.sh
```

To restore an index, you can use the `restore-index.sh` script included in this
repository with the Aptible CLI. For example, to load the index for July 10, 2015,
run:

```
aptible ssh --app YOUR_APP_HANDLE ./restore-index.sh logstash-2015-07-10
```

This will load the index back into your Elasticsearch instance. Note that if
you load an archived index into the same instance that you are running this
cron against, the index will get removed at the end of the day. Alternatively,
you can load the index into a different Elasticsearch instance by overriding
the `DATABASE_URL` environment variable in an SSH session before you run the
restore script:

```
$ aptible ssh --app YOUR_APP_HANDLE bash
bash-4.3# DATABASE_URL=https://some-other-elasticsearch ./restore-index.sh logstash-2015-07-09
```

## Copyright and License

MIT License, see [LICENSE](LICENSE.md) for details.

Copyright (c) 2015 [Aptible](https://www.aptible.com) and contributors.

[<img src="https://s.gravatar.com/avatar/c386daf18778552e0d2f2442fd82144d?s=60" style="border-radius: 50%;" alt="@aaw" />](https://github.com/aaw)
