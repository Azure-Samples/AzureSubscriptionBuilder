## AzureSubscriptionBuilder Changelog
All notable changes to this project will be documented in this file

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [1.1.1] - 2020-06-01
### Fixed
- Added GUID to Blueprint assignment name to avoid duplicate assignment names
- Updated Network Watcher sample policy to latest

## [1.1.0] - 2020-05-22
### Added
- Replaced static website hosted in Azure Blob Storage with Apache Web Server, deployed via ARM


## [1.0.2] - 2020-05-21
### Fixed
- Expanded use of retry and exponential back off to APIs that are exhibiting race condition issues and/or rate limiting


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
