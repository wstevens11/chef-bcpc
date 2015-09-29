#
# Cookbook Name:: bcpc-foundation
# Recipe:: deadline-io-scheduler
#
# Copyright 2015, Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

bash "set-deadline-io-scheduler" do
    user "root"
    code <<-EOH
        for i in /sys/block/sd?; do
            echo deadline > $i/queue/scheduler
        done
        echo GRUB_CMDLINE_LINUX_DEFAULT=\\\"\\$GRUB_CMDLINE_LINUX_DEFAULT elevator=deadline\\\" >> /etc/default/grub
        update-grub
    EOH
    not_if "grep 'elevator=deadline' /etc/default/grub"
end

ruby_block "swap-toggle" do
  block do
    rc = Chef::Util::FileEdit.new("/etc/fstab")
    if node['bcpc']['enabled']['swap'] then
      rc.search_file_replace(
        /^#([A-Z].*|\/.*)swap(.*)/,
        '\\1swap\\2'
      )
      rc.write_file
      system 'swapon -a'
    else
      system 'swapoff -a'
      rc.search_file_replace(
        /^([A-Z].*|\/.*)swap(.*)/,
        '#\\1swap\\2'
      )
      rc.write_file
    end
  end
end