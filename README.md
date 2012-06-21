# EbsSnapper

Take snapshots of EBS volumes and keep them for a period of time.  We use it take nightly snapshots and retain them for a several days before they are purged.



## Installation


    $ gem install ebs_snapper

### Bundler

Add this line to your application's Gemfile:

    gem 'ebs_snapper'

And then execute:

    $ bundle
    
    

## Usage

* Set up the configuration file, see: config/sample.config.yaml
* Tag your volume with the key 'Snapper'
* Setup a cron job to run nightly from a single instance (for example)
  * Once created, the snapshots will be tagged 'Snapper' and contain a timestamp of creation time and the description will also contain the creation time.


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
