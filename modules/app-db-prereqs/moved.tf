# Adding count addresses existing artifacts resources. These moves keep an
# already-applied bucket, its public access block, its bucket policy, and its
# lifecycle rule in place when create_artifacts_bucket stays true.
# Encryption and CORS already used count, so their addresses do not change.
# The state bucket's public access block moves the same way when
# enable_public_access_blocks stays true.

moved {
  from = aws_s3_bucket.artifacts
  to   = aws_s3_bucket.artifacts[0]
}

moved {
  from = aws_s3_bucket_public_access_block.artifacts
  to   = aws_s3_bucket_public_access_block.artifacts[0]
}

moved {
  from = aws_s3_bucket_policy.artifacts
  to   = aws_s3_bucket_policy.artifacts[0]
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.artifacts
  to   = aws_s3_bucket_lifecycle_configuration.artifacts[0]
}

moved {
  from = aws_s3_bucket_public_access_block.tofu_state
  to   = aws_s3_bucket_public_access_block.tofu_state[0]
}
