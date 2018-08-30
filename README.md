# ESP32 Toolchain Archiver

This script will scrape the esp-idf documentation pages for URLs linking to
possible toolchains, download them and then archive them to a remote destination
using `rclone`.

## Prerequisites

* rclone
* sqlite3
* Ruby 2.0+

## Installation

```bash
git clone https://github.com/mkroman/esp32-toolchain-archiver esp32-toolchain-archiver
cd esp32-toolchain-archiver
# Modify RCLONE_DESTINATION in scripts/esp32-download-toolchains.rb to fit your remote destination.
ruby scripts/esp32-download-toolchains.rb
```
