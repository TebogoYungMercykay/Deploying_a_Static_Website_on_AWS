# AWS Website Hosting (CloudFront + S3)

A complete solution for hosting static websites on Amazon S3 with automated deployment using CloudFormation and security policies.

![Cloud Hosting](./docs/images/cloud-hosting.png)

## Project Structure

```
.
├── aws-infrastructure/
│   ├── cloudformation/
│   │   └── s3-bucket-template.json   # CloudFormation S3 bucket
│   ├── policies/
│   │   ├── s3-bucket-policy.json     # Bucket deletion policy
│   │   └── s3-object-policy.json     # Object deletion policy
│   └── scripts/
│       └── deploy.sh                 # Deployment script
├── docs/
│   ├── images/
│   │   └── cloud-hosting.png         # Documentation images
│   └── manual.pdf                    # Detailed setup manual
├── src/                              # Static website files
│   ├── css/                          # Stylesheets
│   ├── img/                          # Website images
│   ├── vendor/                       # Third-party libraries
│   └── index.html                    # Main website file
└── README.md
```

## Prerequisites

- AWS CLI configured with appropriate permissions
- Bash shell (Linux/macOS/WSL)
- Active AWS account

## What's Included

- **Static Website**: Responsive blog template with Bootstrap and FontAwesome
- **CloudFormation Template**: Infrastructure as code for S3 bucket creation
- **Security Policies**: Bucket and object deletion protection
- **Deployment Script**: Automated deployment with validation and error handling

## For a Detailed Guide

See the [manual.pdf](docs/manual.pdf) file in the docs directory for comprehensive setup instructions and configuration options.

## License

This project is licensed under the terms described in the [LICENSE](./LICENSE) file.

---