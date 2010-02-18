#!/usr/bin/env ruby
require 'rubygems'
require 'erb'
require 'aws'
require 'right_aws'

class Server
  ACCESS_KEY_ID     = "AKIAJBBCS3TU7UNTYZJQ"
  SECRET_ACCESS_KEY = "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"
  SDB_DOMAIN_NAME   = "sumo2"
  AMI32             = "ami-3ecc2e57"
  AVAILABILITY_ZONE = "us-east-1d"
  SSH_USER          = "root"

  def name
  	File.expand_path(File.dirname(__FILE__)).split('/')[-1]
  end

  def hostname
  end

  def ec2
  	@ec2 ||= RightAws::Ec2.new(ACCESS_KEY_ID, SECRET_ACCESS_KEY)
  end
  
  def sdb
    @sdb ||= RightAws::SdbInterface.new(ACCESS_KEY_ID, SECRET_ACCESS_KEY)
    @sdb.create_domain(SDB_DOMAIN_NAME)
    @sdb
  end
  
  def put(instance)
    attrs = [:aws_instance_type, :aws_instance_id, :dns_name, :aws_availability_zone, :aws_state, :aws_image_id]
    new_attrs  = instance.reject { |k,v| !attrs.include?(k) }
    sdb.delete_attributes(SDB_DOMAIN_NAME, name)
    sdb.put_attributes(SDB_DOMAIN_NAME, name, new_attrs)
  end
  
  def get
    sdb.get_attributes(SDB_DOMAIN_NAME, name)[:attributes]
  end
  
  def ssh_key
    # Q: what / where is "sumo" key?
    # A: keypair.pem is PRIVATE KEY, so create_key_pair with this didn't work...?
  	@ssh_key ||= 'keypair.pem'
  end

  def setup
  	ec2.create_key_pair(ssh_key)
  	ec2.create_security_group(name, "#{name} security group")
  	ec2.authorize_security_group_IP_ingress(name, 22, 22,'tcp','0.0.0.0/0')
  	rescue Aws::AwsError
  end

  def start
  	setup
  	instance = ec2.run_instances(AMI32, 1, 1, [name], "sumo", user_data, 'public').first
  	put(instance)
  	
    # poll until dns_name becomes available
  	loop do
  	  instance = ec2.describe_instances(instance[:aws_instance_id]).first rescue {}
  	  break if instance.has_key?(:dns_name) and !instance[:dns_name].empty?
  	  sleep 2
		end
		put(instance)
  end

  def stop(instance_id)
  	put(ec2.terminate_instances(get["aws_instance_id"]).first)
  end
  
  def describe
    puts "----- KEY PAIRS -----"
  	ec2.describe_key_pairs.each { |k| puts k.inspect }
  	puts "\n----- SECURITY GROUPS -----"
    ec2.describe_security_groups.each { |s| puts s.inspect }
    puts "\n----- INSTANCES -----"
  	ec2.describe_instances.each { |i| puts i.inspect }
  	puts "\n----- SDB -----"
    sdb.select("SELECT * FROM #{SDB_DOMAIN_NAME}").each { |r| puts r.inspect }
  end

  def user_data
    @user_data_template ||= File.read('user_data.sh.erb')
    @user_data ||= ERB.new(@user_data_template).result(binding)
    raise "user_data.sh too big" if @user_data.length > 160000
    @user_data
  end

  def ssh
    Kernel.exec "ssh -i id_rsa #{SSH_USER}@#{get['dns_name'].first}"
  end

  def debug
    puts user_data
  end
end

@server = Server.new
action = ARGV.shift
@server.describe if action == "cloud:describe"
@server.start if action == "server:start"
@server.stop(ARGV[0]) if action  == "server:stop"
@server.ssh if action  == "server:ssh"
@server.debug if action == "debug"