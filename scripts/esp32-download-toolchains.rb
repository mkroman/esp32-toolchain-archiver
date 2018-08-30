#!/usr/bin/env ruby
# frozen_string_literal: true

require 'uri'
require 'shellwords'
require 'bundler/inline'

RCLONE_DESTINATION = 'gdrive:Development/ESP32/Toolchains'

gemfile do
  source 'https://rubygems.org'

  gem 'mechanize', '~> 2.7'
  gem 'logging', '~> 2.2'
  gem 'sqlite3', '~> 1.3', require: false
  gem 'sequel', '~> 5.11'
end

TOOLCHAIN_DOC_URLS = {
  'linux' => 'https://docs.espressif.com/projects/esp-idf/en/latest/get-started/linux-setup.html',
  'macos' => 'https://docs.espressif.com/projects/esp-idf/en/latest/get-started/macos-setup.html',
  'windows' => 'https://docs.espressif.com/projects/esp-idf/en/latest/get-started/windows-setup.html'
}

# Make sure our needed subdirectories exists, otherwise create them.
%w[logs/ toolchains/ cache/].each do |subdir|
  Dir.mkdir(subdir) unless Dir.exists?(subdir)
end

# Set up our database and our toolchain dataset.
DB = Sequel.connect('sqlite://cache/database.sqlite3')

DB.create_table? :toolchains do
  primary_key :id

  String   :url
  String   :path, unique: true
  String   :filename, unique: true
  String   :platform
  Bool     :uploaded, default: false
  DateTime :downloaded_at, required: true

  index [:filename, :platform]
end

Toolchain = DB[:toolchains]

# Set up our logger.
layout = Logging.layouts.pattern(
    pattern: '[%d] %-5l %c: %m\n',
    date_pattern: '%Y-%m-%d %H:%M:%S')

# Log to stdout.
Logging.appenders.stdout(layout: layout, level: :debug)

# Log to logs/download.log and roll it monthly.
Logging.appenders.rolling_file('logs/download.log',
                               age: 'monthly',
                               layout: layout)

$logger = Logging.logger['main']
$logger.add_appenders('stdout', 'logs/download.log')

DB.loggers << $logger

agent = Mechanize.new
agent.user_agent_alias = 'Linux Mozilla'
agent.pluggable_parser['application/zip'] = Mechanize::Download
agent.pluggable_parser['application/octet-stream'] = Mechanize::Download

TOOLCHAIN_DOC_URLS.each do |platform, url|
  page = agent.get(url)

  links = page.links_with(css: '.section#toolchain-setup a')
  links = links.select{|link| link.uri.host == 'dl.espressif.com' }

  if links.any?
    $logger.debug(platform) { "Downloadable toolchains for #{platform}: #{links.map{|l| File.basename(l.uri.path) }.join(', ') }" }
  else
    $logger.fatal(platform) { "There were no toolchains found for #{platform}! This script requires an update!" }
    exit 1
  end

  links.each do |link|
    filename = File.basename(link.uri.path)
    platform_dir = File.join('toolchains', platform)
    download_path = File.join(platform_dir, filename)

    unless Dir.exists?(platform_dir)
      Dir.mkdir(platform_dir)
    end

    if File.exists?(download_path)
      $logger.debug(platform) { "Not downloading #{filename} because it already exists" }

      next
    end

    if toolchain = Toolchain[platform: platform, filename: filename]
      $logger.debug(platform) { "Not downloading #{filename} as it was already downloaded at #{toolchain[:downloaded_at]}"}

      next
    else
      $logger.info(platform) { "Downloading #{filename} to #{download_path}" }

      agent.download(link, download_path)

      id = Toolchain.insert(url: link.uri.to_s, filename: filename,
                            path: download_path, platform: platform,
                            downloaded_at: DateTime.now)

      rclone_destination = File.join(RCLONE_DESTINATION, platform)
      rclone_cmd = "rclone copy --no-update-modtime -v #{download_path.shellescape} #{rclone_destination.shellescape}"

      $logger.info("Uploading #{platform}/#{filename} to #{rclone_destination}")
      $logger.debug(rclone_cmd)

      upload = system(rclone_cmd)

      if upload
        Toolchain.where(id: id).update(uploaded: true)
      else
        $logger.error("Upload for #{platform}/#{filename} to #{rclone_destination} failed!")
      end
    end
  end
end
