terraform {
  backend "s3" {
    bucket = "tap-terraform-state-999" # This must match your actual state bucket name
    key    = "production/terraform.tfstate"
    region = "eu-north-1" # Based on your error, the bucket is here
  }
}

provider "aws" {
  region = "us-east-1"
}

# 1. Create the S3 Bucket
resource "aws_s3_bucket" "podcast_website" {
  bucket = "african-perspective-web-89234" # Change this number to make it unique to you
}

# 2. Configure the bucket to act as a website
resource "aws_s3_bucket_website_configuration" "podcast_website_config" {
  bucket = aws_s3_bucket.podcast_website.id

  index_document {
    suffix = "index.html"
  }
}

# 3. Turn off the default "Block Public Access" security lock
resource "aws_s3_bucket_public_access_block" "podcast_public_access" {
  bucket = aws_s3_bucket.podcast_website.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 4. Attach a policy that allows anyone on the internet to read the website files
resource "aws_s3_bucket_policy" "allow_public_read" {
  bucket = aws_s3_bucket.podcast_website.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.podcast_website.arn}/*"
      },
    ]
  })
  
  # Ensure the public access block is removed BEFORE applying this policy
  depends_on = [aws_s3_bucket_public_access_block.podcast_public_access]
}

# 5. Upload the HTML file to the S3 bucket
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.podcast_website.id
  key          = "index.html"
  source       = "../website/index.html"
  content_type = "text/html"
}

# 6. Output the live website URL in the terminal
output "website_url" {
  description = "Click this link to see your live podcast website!"
  value       = aws_s3_bucket_website_configuration.podcast_website_config.website_endpoint
}

# 7. Create a CloudFront CDN to serve the website over HTTPS
resource "aws_cloudfront_distribution" "podcast_cdn" {
  origin {
    # We point CloudFront to the HTTP website endpoint of your bucket
    domain_name = aws_s3_bucket_website_configuration.podcast_website_config.website_endpoint
    origin_id   = "S3-Website-${aws_s3_bucket.podcast_website.id}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-Website-${aws_s3_bucket.podcast_website.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    # This is the magic line that forces HTTPS
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# 8. Output the secure CloudFront URL
output "secure_website_url" {
  description = "Your secure HTTPS podcast website!"
  value       = "https://${aws_cloudfront_distribution.podcast_cdn.domain_name}"
}