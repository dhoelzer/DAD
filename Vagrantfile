# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  config.vm.box = "dhoelzer/debian8"
  config.vm.box_check_update = true
  config.vm.network "private_network", ip: "192.168.155.15"
  config.vm.network "public_network" # Allow the VM to be used to digest real logs.

#  config.vm.provision "chef_solo" do |chef|
#    chef add_recipe "apache"
#  end
  config.vm.provision "shell", path: "./provision.sh"
end
