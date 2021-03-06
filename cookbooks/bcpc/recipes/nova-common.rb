#
# Cookbook Name:: bcpc
# Recipe:: nova-common
#
# Copyright 2013, Bloomberg Finance L.P.
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
require 'ipaddr'

include_recipe "bcpc::openstack"

ruby_block "initialize-nova-config" do
    block do
        require 'openssl'
        require 'net/ssh'
        key = OpenSSL::PKey::RSA.new 2048;
        pubkey = "#{key.ssh_type} #{[key.to_blob].pack('m0')}"
        make_config('ssh-nova-private-key', key.to_pem)
        make_config('ssh-nova-public-key', pubkey)
        make_config('mysql-nova-user', "nova")
        make_config('mysql-nova-password', secure_password)
        make_config('mysql-nova-api-user', "nova_api")
        make_config('mysql-nova-api-password', secure_password)
        make_config('glance-cloudpipe-uuid', %x[uuidgen -r].strip)
    end
end

package "nova-common" do
  action :upgrade
end

package "qemu-system-common" do
  action :upgrade
end

template "/etc/nova/nova.conf" do
    source "nova.conf.erb"
    owner "nova"
    group "nova"
    mode 00600
    variables(
      lazy {
        {
          :servers => get_head_nodes
        }
      }
    )
end

template "/etc/nova/api-paste.ini" do
    source "nova.#{node['bcpc']['openstack_release']}.api-paste.ini.erb"
    owner "nova"
    group "nova"
    mode 00600
end

template "/etc/nova/policy.json" do
    source "nova-policy.json.erb"
    owner "nova"
    group "nova"
    mode 00600
    variables(:policy => JSON.pretty_generate(node['bcpc']['nova']['policy']))
end
