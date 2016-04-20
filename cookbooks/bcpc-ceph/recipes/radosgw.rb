#
# Cookbook Name:: bcpc-ceph
# Recipe:: radosgw
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

#RGW Stuff
#Note, currently rgw cannot use Keystone to auth S3 requests, only swift, so for the time being we'll have
#to manually provision accounts for RGW in the radosgw-admin tool

include_recipe "bcpc-apache"
include_recipe "bcpc-ceph"

package "radosgw" do
  default_release 'trusty'  # use Ceph repository instead of UCA
  action :upgrade
end

package "python-boto"

directory "/var/lib/ceph/radosgw/ceph-radosgw.gateway" do
    owner "root"
    group "root"
    mode 0755
    action :create
    recursive true
end

file "/var/lib/ceph/radosgw/ceph-radosgw.gateway/done" do
    owner "root"
    group "root"
    mode "0644"
    action :touch
end

bash "write-client-radosgw-key" do
    code <<-EOH
        RGW_KEY=`ceph --name client.admin --keyring /etc/ceph/ceph.client.admin.keyring auth get-or-create-key client.radosgw.gateway osd 'allow rwx' mon 'allow rw'`
        ceph-authtool "/var/lib/ceph/radosgw/ceph-radosgw.gateway/keyring" \
            --create-keyring \
            --name=client.radosgw.gateway \
            --add-key="$RGW_KEY"
        chmod 644 /var/lib/ceph/radosgw/ceph-radosgw.gateway/keyring
    EOH
    not_if "test -f /var/lib/ceph/radosgw/ceph-radosgw.gateway/keyring"
    notifies :restart, "service[radosgw-all]", :delayed
end

rgw_rule = (node['bcpc']['ceph']['rgw']['type'] == "ssd") ? node['bcpc']['ceph']['ssd']['ruleset'] : node['bcpc']['ceph']['hdd']['ruleset']

ruby_block "rados-pool-wrapper" do
  block do
    rgw_optimal_pg = optimal_pgs_per_node('rgw')
    replicas = [[get_ceph_osd_nodes.length, node['bcpc']['ceph']['rgw']['replicas']].min, 1].max

    %w{.rgw .rgw.control .rgw.gc .rgw.root .users.uid .users.email .users .usage .log .intent-log .rgw.buckets .rgw.buckets.index .rgw.buckets.extra}.each do |pool|
      bash "create-rados-pool-#{pool}" do
        code <<-EOH
          ceph osd pool create #{pool} #{rgw_optimal_pg}
          ceph osd pool set #{pool} crush_ruleset #{rgw_rule}
        EOH
        not_if "rados lspools | grep ^#{pool}$"
        notifies :run, "bash[wait-for-pgs-creating]", :immediately
      end

      bash "set-#{pool}-rados-pool-replicas" do
        code "ceph osd pool set #{pool} size #{replicas}"
        not_if {
          size_cmd = Mixlib::ShellOut.new("ceph osd pool get #{pool} size").run_command
          size_cmd.stdout.strip == "size: #{replicas}"
        }
      end
    end

    # check to see if we should up the number of pg's now for the core buckets pool
    (node['bcpc']['ceph']['pgp_auto_adjust'] ? %w{pg_num pgp_num} : %w{pg_num}).each do |pg|
      bash "update-rgw-buckets-#{pg}" do
        code "ceph osd pool set .rgw.buckets #{pg} #{rgw_optimal_pg}"
        only_if {
          cmd = Mixlib::ShellOut.new("ceph osd pool get .rgw.buckets #{pg} | awk '{print $2}'").run_command
          cmd.stdout.to_i < rgw_optimal_pg
        }
        notifies :run, "bash[wait-for-pgs-creating]", :immediately
      end
    end
  end
end

service "radosgw-all" do
  provider Chef::Provider::Service::Upstart
  action [ :enable, :start ]
end

ruby_block "initialize-radosgw-admin-user" do
  block do
    make_config('radosgw-admin-user', "radosgw")
    make_config('radosgw-admin-access-key', secure_password_alphanum_upper(20))
    make_config('radosgw-admin-secret-key', secure_password(40))

    cmd = Mixlib::ShellOut.new("radosgw-admin user create --display-name='Admin' --uid='radosgw' --access_key=#{get_config('radosgw-admin-access-key')} --secret=#{get_config('radosgw-admin-secret-key')}").run_command
    cmd.error!
  end
  not_if "radosgw-admin user info --uid='radosgw'"
end

ruby_block "initialize-radosgw-test-user" do
  block do
    make_config('radosgw-test-user', "tester")
    make_config('radosgw-test-access-key', secure_password_alphanum_upper(20))
    make_config('radosgw-test-secret-key', secure_password(40))

    cmd = Mixlib::ShellOut.new("radosgw-admin user create --display-name='Tester' --uid='tester' --max-buckets=3 --access_key=#{get_config('radosgw-test-access-key')} --secret=#{get_config('radosgw-test-secret-key')} --caps='usage=read; user=read; bucket=read;'").run_command
    cmd.error!
  end
  not_if "radosgw-admin user info --uid='tester'"
end

template "/usr/local/bin/radosgw_check.py" do
    source "radosgw_check.py.erb"
    mode 0700
    owner "root"
    group "root"
end