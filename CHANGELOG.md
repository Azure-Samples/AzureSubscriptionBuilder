## AzureSubscriptionBuilder Changelog
All notable changes to this project will be documented in this file

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2020-05-20
### Added
- This CHANGELOG file

### Fixed
- Added retry and exponential backoff when creating subscriptions as large volumes of requests were being rate limited
- Added validation when moving subscription under management group to ensure desired state before moving on to blueprint assignment
- made sure all iterations of Start-Sleep cmdlet are consistent


## [1.0.0] - 2020-05-15
### Added
- Initial public version of the project
