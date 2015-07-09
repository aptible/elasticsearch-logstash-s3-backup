# ![](https://gravatar.com/avatar/11d3bc4c3163e3d238d558d5c9d98efe?s=64) aptible/elasticsearch-logstash-s3-backup

An Aptible app that periodically archives older Logstash indexes from an
Elasticsearch database. Indexes named in the standard logstash convention
(`logstash-YYYY.MM.DD`) are archived daily based on their age, keeping a
configurable number of the most recent indexes live. Each index is backed
up over HTTPS and encrypted using AWS server-side encryption to its own
Elasticsearch snapshot in your S3 snapshot repository.

## Installation

Recommended setup for running as an app on Aptible:

 1. Create an S3 bucket for your logs in the same region as your Elasticsearch
    database.

 2. Create an IAM user to run the backup and restore. Give your IAM user
    permission to read/write from the bucket you created in step 1. The
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

 3. Create an app in your [Aptible dashboard](https://dashboard.aptible.com) for
    the cron. In the steps that follow, we'll use &lt;YOUR_APP_HANDLE&gt;
    anywhere that you should substitute the actual app handle the results from
    this step in the instructions.

 4. Use the [Aptible CLI](https://github.com/aptible/aptible-cli) to set the
    following environment variables in your app:

     * `DATABASE_URL`: Your Elasticsearch URL.
     * `S3_BUCKET`: Your S3 Bucket name.
     * `S3_ACCESS_KEY_ID`: The access key you generated in step 2.
     * `S3_SECRET_ACCESS_KEY`: The secret key you generated in step 2.

    In addition, the following environment variables are optional:

     * `MAX_DAYS_TO_KEEP`: The number of days of live logstash indexes you'd
       like to keep in your Elasticsearch instance. Any indexes from before this
       point will be archived by the cron. Defaults to 30.
     * `S3_REGION`: The region your Elasticsearch instance and S3 bucket live in.
       Defaults to `us-east-1`.
     * `REPOSITORY_NAME`: The name of your Elasticsearch snapshot repo. This is
       the handle you can use in Elasticsearch to perform operations on your
       snapshot repo. Defaults to "logstash-snapshots".
     * `WAIT_SECONDS`: Number of seconds to wait on an index archive to succeed
       after the request has been made. Defaults to 1800.

    Environment variables can be set using the Aptible CLI, for example:

    ```
    aptible config:set NAME=VALUE --app YOUR_APP_HANDLE
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

To restore an index, you can use the `restore-index.sh` script included in this
repository. Just use the Aptible CLI to SSH into an app container:

```
aptible ssh --app YOUR_APP_HANDLE
```

And, from there, run `restore-index.sh` with the name of the index you want to
restore, for example:

```
# /bin/bash /opt/scripts/restore-index.sh logstash-2015-07-09
```

This will load the index back into your Elasticsearch instance. Note that if
you load an archived index into the same instance that you are running this
cron against, the index will get removed at the end of the day. Alternatively,
you can load the index into a different Elasticsearch instance by overriding
the `DATABASE_URL` environment variable:

```
# DATABASE_URL=https://some-other-elasticsearch /bin/bash /opt/scripts/restory-index.sh logstash-2015-07-09
```

## Copyright and License

MIT License, see [LICENSE](LICENSE.md) for details.

Copyright (c) 2015 [Aptible](https://www.aptible.com) and contributors.

[<img src="https://s.gravatar.com/avatar/c386daf18778552e0d2f2442fd82144d?s=60" style="border-radius: 50%;" alt="@aaw" />](https://github.com/aaw)
