#
# DO NOT EDIT THIS FILE DIRECTLY - UNLESS YOU KNOW WHAT YOU ARE DOING
#

systemd = true
case node.platform
when "ubuntu"
 if node.platform_version.to_f <= 14.04
    systemd = false
 end
end


service_name="zookeeper"

case node.platform_family
  when "debian"
systemd_script = "/lib/systemd/system/#{service_name}.service"
  when "rhel"
systemd_script = "/usr/lib/systemd/system/#{service_name}.service" 
end


# Pre-Experiment Code

require 'json'

#include_recipe 'build-essential::default'

include_recipe 'java'

kzookeeper  "#{node.kzookeeper.version}" do
  user        node.kzookeeper.user
  mirror      node.kzookeeper.mirror
  checksum    node.kzookeeper.checksum
  install_dir node.kzookeeper.install_dir
  data_dir    node.kzookeeper.config.dataDir
  action      :install
end

zk_ip = private_recipe_ip("kzookeeper", "default")

include_recipe "kzookeeper::config_render"

template "#{node.kzookeeper.home}/bin/zookeeper-start.sh" do
  source "zookeeper-start.sh.erb"
  owner node.kzookeeper.user
  group node.kzookeeper.user
  mode 0770
  variables({ :zk_ip => zk_ip,
              :zk_dir => node.kzookeeper.home
 })
end

template "#{node.kzookeeper.home}/bin/zookeeper-stop.sh" do
  source "zookeeper-stop.sh.erb"
  owner node.kzookeeper.user
  group node.kzookeeper.user
  mode 0770
  variables({ :zk_dir => node.kzookeeper.home
 })
end

template "#{node.kzookeeper.home}/bin/zookeeper-status.sh" do
  source "zookeeper-status.sh.erb"
  owner node.kzookeeper.user
  group node.kzookeeper.user
  mode 0770
  variables({ :zk_dir => node.kzookeeper.home
 })
end


directory "#{node.kzookeeper.home}/data" do
  owner node.kzookeeper.user
  group node.kzookeeper.group
  mode "755"
  action :create
  recursive true
end

config_hash = {
  clientPort: 2181, 
  dataDir: "#{node.kzookeeper.home}/data", 
  tickTime: 2000,
  syncLimit: 3,
  initLimit: 60,
# unlimited number of IO connections, this might be set to a reasonable number
  maxClientCnxns: 0,
  autopurge: {
    snapRetainCount: 1,
    purgeInterval: 1
  }
}


#if node.kzookeeper != nil && node.kzookeeper.default != nil &&  node.kzookeeper.default.private_ips !=  nil

node.kzookeeper[:default][:private_ips].each_with_index do |ipaddress, index|
id=index+1
config_hash["server.#{id}"]="#{ipaddress}:2888:3888"
end
#end

kzookeeper_config "/opt/zookeeper/zookeeper-#{node.kzookeeper.version}/conf/zoo.cfg" do
  config config_hash
  user   node.kzookeeper.user
  action :render
end

template '/etc/default/zookeeper' do
  source 'environment-defaults.erb'
  owner node.kzookeeper.user
  group node.kzookeeper.group
  action :create
  mode '0644'
  notifies :restart, 'service[zookeeper]', :delayed
end

if systemd == false 
  template '/etc/init.d/zookeeper' do
    source 'zookeeper.initd.erb'
    owner 'root'
    group 'root'
    action :create
    mode '0755'
    notifies :restart, 'service[zookeeper]', :delayed
  end

  service 'zookeeper' do
    supports :status => true, :restart => true, :start => true, :stop => true
    provider Chef::Provider::Service::Init::Debian
    action :enable
  end
else
  template systemd_script do
    source 'zookeeper.service.erb'
    owner 'root'
    group 'root'
    action :create
    mode '0755'
    notifies :restart, 'service[zookeeper]', :delayed
  end

  service 'zookeeper' do
    supports :status => true, :restart => true, :start => true, :stop => true
    provider Chef::Provider::Service::Systemd
    action :enable
  end

end

found_id=-1
id=1
my_ip = my_private_ip()

for zk in node.kzookeeper[:default][:private_ips]
  if my_ip.eql? zk
    Chef::Log.info "Found matching IP address in the list of zkd nodes: #{zk}. ID= #{id}"
    found_id = id
  end
  id += 1

end 
Chef::Log.info "Found ID IS: #{found_id}"
if found_id == -1
  raise "Could not find matching IP address #{my_ip} in the list of zkd nodes: " + node.kzookeeper[:default][:private_ips].join(",")
end



template "#{node.kzookeeper.home}/data/myid" do
  source 'zookeeper.id.erb'
  owner node.kzookeeper.user
  group node.kzookeeper.group
  action :create
  mode '0755'
  variables({ :id => found_id })
  notifies :restart, 'service[zookeeper]', :delayed
end

list_zks=node.kzookeeper[:default][:private_ips].join(",")

template "#{node.kzookeeper.home}/bin/zkConnect.sh" do
  source 'zkClient.sh.erb'
  owner node.kzookeeper.user
  group node.kzookeeper.group
  action :create
  mode '0755'
  variables({ :servers => list_zks })
  notifies :restart, 'service[zookeeper]', :delayed
end


link node.kzookeeper.base_dir do
  owner node.kzookeeper.user
  group node.kzookeeper.group
  to node.kzookeeper.home
end


kagent_config service_name do
  service "zookeeper"
  log_file "#{node.kzookeeper.base_dir}/zookeeper.log"
  config_file "#{node.kzookeeper.base_dir}/conf/zoo.cfg"
end
