locals {
    s3_bucket_id = module.s3-bucket[0].bucket.id # handle invalid reference in storage.location.template parameter reference
}
