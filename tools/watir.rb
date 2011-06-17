#!/usr/bin/ruby

site = ARGV[0]
url = ARGV[1]
src = url.dup
src.sub!(/%26/, '&')

require 'rubygems'
require 'watir-webdriver'

# output_dir = ARGV[2]
# require 'selenium-webdriver'
# profile = Selenium::WebDriver::Firefox::Profile.new
# profile["browser.download.useDownloadDir"] = true
# profile["browser.download.dir"] = "#{output_dir}"
# driver = Selenium::WebDriver.for :firefox, :profile => profile
# browser = Watir::Browser.new(driver)

browser = Watir::Browser.new :firefox
browser.goto "http://#{site}/wiki/index.php?title=#{url}&printable=yes"
# html = browser.html
# File.open("my_file", 'w') {|f| f.write(html) }
# winid = `xdotool search --name \\"#{url}\\"`
winid = `xdotool search --name \\\\"#{src}\\\\"`
puts winid, src
exit 1;
# value = system( "#{cmd}" )
# puts "not good 1" if value
value = %x[ rm -rf ~/Desktop/* && echo "#{url}" && WINID=`xdotool search --name "#{url}"` && xdotool windowactivate --sync $WINID && xdotool key --window $WINID ctrl+s ]
# begin=0;while [[ $(xdotool search --name "Save As") < 1 ]] ; [[ $begin < 5 ]]; do sleep .1; echo 1;let begin=$begin+1;done
puts "not good 2" if value
value = %x[ xdotool search --name "Save As" ]
value = %x[ xdotool key --window $WINID Return && while (($(xdotool search --name "Save As"))); do sleep .1; done ]
puts $?.exitstatus
sleep 0.5
browser.close
